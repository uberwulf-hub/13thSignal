extends Node
## Sounds (autoloaded as `Sound`). Every sound is synthesized when the game
## starts, so there are no audio files to license or download.
## Harsh "sting" sounds are only ever played outside Explorer mode.

const RATE := 22050

## Sounds in the world go through this bus: it adds the echo of a big
## concrete facility, so footsteps and clanks ring off the walls.
const WORLD := "World"

var _streams: Dictionary = {}
var _variants: Dictionary = {}      # name -> Array of AudioStream (one is picked at random)
var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _ambient: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in 12:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_ambient = AudioStreamPlayer.new()
	add_child(_ambient)
	_make_world_bus()
	_generate()


func _make_world_bus() -> void:
	if AudioServer.get_bus_index(WORLD) >= 0:
		return
	AudioServer.add_bus()
	var i := AudioServer.bus_count - 1
	AudioServer.set_bus_name(i, WORLD)
	AudioServer.set_bus_send(i, "Master")
	var verb := AudioEffectReverb.new()
	verb.room_size = 0.62      # a big concrete space
	verb.damping = 0.45
	verb.spread = 0.8
	verb.hipass = 0.15
	verb.dry = 0.9
	verb.wet = 0.24
	verb.predelay_msec = 35.0
	verb.predelay_feedback = 0.25
	AudioServer.add_bus_effect(i, verb)


func stream(sound_name: String) -> AudioStream:
	return _streams.get(sound_name)


## A sound by name; if it has several recorded variations, a random one.
func pick(sound_name: String) -> AudioStream:
	if _variants.has(sound_name):
		var v: Array = _variants[sound_name]
		return v[randi() % v.size()]
	return _streams.get(sound_name)


## A sound with no position. world = true adds the facility's echo (footsteps).
func play(sound_name: String, vol_db := 0.0, pitch := 1.0, world := false) -> void:
	var s: AudioStream = pick(sound_name)
	if s == null:
		return
	var p := _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = s
	p.volume_db = vol_db
	p.pitch_scale = pitch
	p.bus = WORLD if world else "Master"
	p.play()


## A sound that comes from a place in the world (it gets quieter far away).
func play_at(sound_name: String, pos: Vector3, vol_db := 0.0, pitch := 1.0) -> AudioStreamPlayer3D:
	var s: AudioStream = pick(sound_name)
	var scene := get_tree().current_scene
	if s == null or scene == null:
		return null
	var p := AudioStreamPlayer3D.new()
	p.stream = s
	p.volume_db = vol_db
	p.pitch_scale = pitch
	p.unit_size = 5.0
	p.max_distance = 45.0
	p.bus = WORLD
	p.attenuation_filter_cutoff_hz = 3500.0   # far-away sounds get muffled
	p.attenuation_filter_db = -18.0
	scene.add_child(p)
	p.global_position = pos
	p.finished.connect(p.queue_free)
	p.play()
	return p


func start_ambient(vol_db := -10.0) -> void:
	if _ambient.playing:
		_ambient.volume_db = vol_db
		return
	_ambient.stream = _streams["drone"]
	_ambient.volume_db = vol_db
	_ambient.play()


func stop_ambient() -> void:
	_ambient.stop()


# ------------------------------------------------------------- synthesis

func _buf(dur: float) -> PackedFloat32Array:
	var a := PackedFloat32Array()
	a.resize(int(dur * RATE))
	return a


func _wav(s: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(s.size() * 2)
	for i in s.size():
		bytes.encode_s16(i * 2, int(clampf(s[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = bytes
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = s.size()
	return w


## Filtered noise with a decay. lp: 0..1 (smaller = darker/muffled).
func _noise(dur: float, lp: float, decay: float, gain := 0.8, attack := 0.004) -> PackedFloat32Array:
	var a := _buf(dur)
	var y := 0.0
	for i in a.size():
		var t := float(i) / RATE
		y += lp * (randf_range(-1.0, 1.0) - y)
		var env := minf(t / attack, 1.0) * exp(-t * decay)
		a[i] = y * env * gain
	return a


func _tone(notes: Array, gain := 0.3, wave := "sine", decay := 6.0) -> PackedFloat32Array:
	var total := 0.0
	for n in notes:
		total += float(n[1])
	var a := _buf(total)
	var i := 0
	for n in notes:
		var f: float = n[0]
		var count := int(float(n[1]) * RATE)
		for j in count:
			if i >= a.size():
				break
			var t := float(j) / RATE
			var ph := fmod(t * f, 1.0)
			var v := 0.0
			match wave:
				"square": v = 1.0 if ph < 0.5 else -1.0
				"triangle": v = 4.0 * absf(ph - 0.5) - 1.0
				_: v = sin(TAU * ph)
			if f <= 1.0:
				v = 0.0  # a rest between notes
			var env := minf(t / 0.005, 1.0) * exp(-t * decay)
			a[i] = v * env * gain
			i += 1
	return a


func _mix(a: PackedFloat32Array, b: PackedFloat32Array, offset := 0) -> PackedFloat32Array:
	var out := a.duplicate()
	if out.size() < b.size() + offset:
		out.resize(b.size() + offset)
	for i in b.size():
		out[i + offset] += b[i]
	return out


func _generate() -> void:
	# Footsteps: soft concrete, and loud clangy metal grates.
	# Footsteps: heel, then toe, with grit, several variations each, so no two
	# steps sound quite the same. Soft (crouching), normal, and running.
	_set_variants("step_soft", 5, func(): return _step_concrete(0.45))
	_set_variants("step", 6, func(): return _step_concrete(1.0))
	_set_variants("step_run", 5, func(): return _step_concrete(1.5))
	# Metal grates: a hollow clang that rings, and a loose panel that rattles.
	_set_variants("step_grate_soft", 4, func(): return _step_metal(0.45))
	_set_variants("step_grate", 5, func(): return _step_metal(1.0))
	_set_variants("step_grate_run", 4, func(): return _step_metal(1.5))

	# Doors.
	var door := _noise(0.7, 0.08, 4.0, 0.9, 0.05)
	door = _mix(door, _noise(0.5, 0.5, 8.0, 0.25), 2000)
	_streams["door"] = _wav(door)
	_streams["locked"] = _wav(_tone([[110.0, 0.12], [1.0, 0.05], [104.0, 0.18]], 0.35, "square", 5.0))
	_streams["locker"] = _wav(_mix(_noise(0.3, 0.4, 14.0, 0.6), _tone([[180.0, 0.3]], 0.15, "triangle", 10.0)))

	# Intercom and UI.
	_streams["chime"] = _wav(_tone([[880.0, 0.22], [659.25, 0.45]], 0.22, "sine", 3.5))
	_streams["blip"] = _wav(_tone([[1320.0, 0.025]], 0.08, "square", 30.0))
	_streams["echo_blip"] = _wav(_tone([[1250.0, 0.02], [610.0, 0.02]], 0.08, "square", 25.0))
	_streams["click"] = _wav(_tone([[900.0, 0.05]], 0.15, "sine", 40.0))
	_streams["pickup"] = _wav(_tone([[523.25, 0.08], [659.25, 0.08], [987.77, 0.25]], 0.22, "triangle", 5.0))
	_streams["key_beep"] = _wav(_tone([[1046.5, 0.07]], 0.2, "sine", 25.0))
	_streams["key_ok"] = _wav(_tone([[784.0, 0.1], [1046.5, 0.1], [1568.0, 0.3]], 0.25, "sine", 4.0))
	_streams["key_bad"] = _wav(_tone([[220.0, 0.15], [1.0, 0.04], [196.0, 0.3]], 0.3, "square", 3.0))
	_streams["checkpoint"] = _wav(_tone([[659.25, 0.1], [987.77, 0.3]], 0.15, "sine", 6.0))

	# Breakers and power.
	var thunk := _tone([[70.0, 0.35]], 0.7, "sine", 9.0)
	thunk = _mix(thunk, _noise(0.05, 0.9, 80.0, 0.6))
	_streams["breaker"] = _wav(thunk)
	var hum := _buf(2.0)
	for i in hum.size():
		var t := float(i) / RATE
		var f := 40.0 + 80.0 * minf(t / 1.6, 1.0)
		hum[i] = (sin(TAU * f * t) * 0.4 + sin(TAU * f * 2.0 * t) * 0.15) * minf(t * 3.0, 1.0) * minf((2.0 - t) * 4.0, 1.0)
	_streams["power_on"] = _wav(hum)
	var alarm := _buf(1.6)
	for i in alarm.size():
		var t := float(i) / RATE
		var f := 660.0 if fmod(t, 0.4) < 0.2 else 520.0
		alarm[i] = (1.0 if fmod(t * f, 1.0) < 0.5 else -1.0) * 0.18 * minf((1.6 - t) * 6.0, 1.0)
	_streams["alarm"] = _wav(alarm)

	# The Listener: echolocation clicks and a low breath.
	var click := _noise(0.03, 0.95, 160.0, 0.9, 0.001)
	click = _mix(click, _noise(0.03, 0.95, 160.0, 0.7, 0.001), int(0.06 * RATE))
	_streams["listener_click"] = _wav(click)
	var breath := _buf(1.4)
	var y := 0.0
	for i in breath.size():
		var t := float(i) / RATE
		y += 0.05 * (randf_range(-1.0, 1.0) - y)
		breath[i] = y * sin(PI * t / 1.4) * 2.2
	_streams["listener_breath"] = _wav(breath)

	# A rasping breath, looped (the envelope repeats exactly every 3 s).
	var rasp := _buf(3.0)
	var ry := 0.0
	var ry2 := 0.0
	for i in rasp.size():
		var t := float(i) / RATE
		ry += 0.25 * (randf_range(-1.0, 1.0) - ry)
		ry2 += 0.5 * (ry - ry2)
		var breath_env := pow(maxf(sin(TAU * t / 3.0), 0.0), 2.0) * 0.9 + pow(maxf(-sin(TAU * t / 3.0), 0.0), 3.0) * 0.5
		var gurgle := 0.7 + 0.3 * sin(TAU * 31.0 * t) * sin(TAU * 7.0 * t)
		rasp[i] = (ry - ry2) * 3.0 * breath_env * gurgle
	_streams["listener_rasp"] = _wav(rasp, true)

	# Its shriek when it starts hunting you (Survivor and Nightmare only):
	# a falling, grinding cry. Loud, but just a sound.
	var shriek := _buf(1.1)
	var sp1 := 0.0
	var sp2 := 0.0
	for i in shriek.size():
		var t := float(i) / RATE
		var f := 1500.0 * exp(-t * 1.4) + 260.0
		sp1 += f / RATE
		sp2 += (f * 1.47) / RATE
		var saw := (fmod(sp1, 1.0) * 2.0 - 1.0) * 0.5 + (fmod(sp2, 1.0) * 2.0 - 1.0) * 0.35
		var grind := 0.6 + 0.4 * sin(TAU * 43.0 * t)
		var env := minf(t / 0.02, 1.0) * exp(-t * 2.2)
		shriek[i] = (saw * grind + randf_range(-0.25, 0.25)) * env * 0.45
	_streams["shriek"] = _wav(shriek)

	# ECHO's whisper: breathy noise shaped into syllables, looped every 4 s.
	var whisper := _buf(4.0)
	var wy := 0.0
	var wy2 := 0.0
	for i in whisper.size():
		var t := float(i) / RATE
		wy += 0.7 * (randf_range(-1.0, 1.0) - wy)
		wy2 += 0.35 * (wy - wy2)
		var hiss := wy - wy2 * 0.6
		var syll := maxf(sin(TAU * 2.75 * t) * sin(TAU * 0.5 * t), 0.0)
		var formant := 0.6 + 0.4 * sin(TAU * (900.0 + 400.0 * sin(TAU * 0.75 * t)) * t)
		whisper[i] = hiss * syll * formant * 0.5
	_streams["echo_whisper"] = _wav(whisper, true)

	# A jammer's hum: a low buzz with a wobble (repeats exactly every 2 s).
	var hum2 := _buf(2.0)
	for i in hum2.size():
		var t := float(i) / RATE
		var wob := 0.7 + 0.3 * sin(TAU * 3.0 * t)
		hum2[i] = (sin(TAU * 120.0 * t) * 0.25 + sin(TAU * 181.0 * t) * 0.12 + randf_range(-0.04, 0.04)) * wob
	_streams["jam_hum"] = _wav(hum2, true)
	_streams["cam_beep"] = _wav(_tone([[1760.0, 0.06]], 0.2, "square", 30.0))

	# The Replacement: creaking plastic.
	var creak := _buf(0.5)
	var phase := 0.0
	for i in creak.size():
		var t := float(i) / RATE
		phase += (90.0 + 40.0 * sin(t * 23.0)) / RATE
		var pulse := 1.0 if fmod(phase, 1.0) < 0.08 else 0.0
		creak[i] = (pulse * 0.5 + randf_range(-0.05, 0.05)) * sin(PI * t / 0.5)
	_streams["creak"] = _wav(creak)

	# Items: picking up, a battery clicking in, a glow stick snapping, a throw,
	# and things landing (metal clangs, glass smashes, soft thuds).
	_streams["pickup_item"] = _wav(_mix(_noise(0.12, 0.5, 30.0, 0.35), _tone([[1400.0, 0.05]], 0.06, "sine", 40.0)))
	_streams["battery_click"] = _wav(_mix(_noise(0.04, 0.9, 120.0, 0.7), _noise(0.04, 0.9, 120.0, 0.6), int(0.09 * RATE)))
	var snap := _noise(0.05, 0.95, 90.0, 0.9)
	snap = _mix(snap, _noise(0.6, 0.6, 5.0, 0.12), int(0.03 * RATE))   # the fizz as it starts to glow
	_streams["glow_crack"] = _wav(snap)
	var whoosh := _buf(0.3)
	var wl := 0.0
	for i in whoosh.size():
		var t := float(i) / RATE
		wl += (0.05 + 0.4 * t / 0.3) * (randf_range(-1.0, 1.0) - wl)
		whoosh[i] = wl * sin(PI * t / 0.3) * 0.6
	_streams["throw_whoosh"] = _wav(whoosh)
	_set_variants("hit_glass", 3, func(): return _glass_smash())
	# Things you throw: each hit is two sounds, the object itself ringing and
	# the surface it struck. Modal synthesis: a short strike excites the real
	# resonant frequencies of that material and shape, each dying at its own rate.
	_set_variants("obj_can", 4, func(): return _strike(0.5, 0.002, 0.9, [[540.0, 22.0, 0.5], [1180.0, 30.0, 1.0], [2490.0, 38.0, 0.8], [3920.0, 50.0, 0.6], [5650.0, 70.0, 0.4]], 0.25))
	_set_variants("obj_steel", 4, func(): return _strike(1.6, 0.0015, 0.95, [[1630.0, 3.5, 1.0], [4490.0, 6.0, 0.7], [8790.0, 10.0, 0.4], [2950.0, 9.0, 0.25]], 0.2))
	_set_variants("obj_stapler", 4, func(): return _strike(0.6, 0.0025, 0.8, [[870.0, 18.0, 0.7], [1940.0, 24.0, 1.0], [3300.0, 32.0, 0.6], [4700.0, 45.0, 0.3]], 0.4))
	_set_variants("obj_ceramic", 4, func(): return _strike(0.45, 0.0015, 0.9, [[2080.0, 24.0, 1.0], [3460.0, 30.0, 0.7], [5170.0, 40.0, 0.45], [7020.0, 55.0, 0.25]], 0.2))
	_set_variants("obj_bottle", 4, func(): return _strike(0.7, 0.0015, 0.9, [[1240.0, 12.0, 0.9], [2780.0, 16.0, 1.0], [4310.0, 24.0, 0.5], [610.0, 20.0, 0.3]], 0.15))
	_set_variants("obj_plastic", 4, func(): return _strike(0.25, 0.002, 0.7, [[1450.0, 60.0, 1.0], [2900.0, 75.0, 0.6], [4400.0, 90.0, 0.3]], 0.5))
	_set_variants("obj_board", 4, func(): return _board_slap())
	_set_variants("obj_paper", 3, func(): return _noise(0.08, 0.3, 60.0, 0.3))
	_set_variants("surf_concrete", 5, func(): return _surf_concrete())
	_set_variants("surf_grate", 4, func(): return _step_metal(0.5))
	_set_variants("surf_metal", 4, func(): return _strike(1.3, 0.004, 0.5, [[118.0, 5.0, 0.6], [212.0, 6.0, 1.0], [397.0, 8.0, 0.8], [641.0, 11.0, 0.6], [988.0, 15.0, 0.45], [1520.0, 20.0, 0.3], [2270.0, 28.0, 0.2]], 0.3))
	_set_variants("surf_glass", 4, func(): return _strike(0.8, 0.002, 0.8, [[148.0, 14.0, 0.7], [1270.0, 16.0, 1.0], [2930.0, 22.0, 0.6], [4610.0, 32.0, 0.35]], 0.25))
	_set_variants("surf_mannequin", 4, func(): return _surf_mannequin())
	_set_variants("mq_hit_reaction", 3, func(): return _mq_hit_reaction())
	# The elevator: an old, cracked chime; heavy doors grinding along their
	# track; a halogen tube buzzing at mains frequency, and its crackle as it fails.
	_streams["elevator_ding"] = _wav(_strike(2.2, 0.002, 0.8, [[1046.0, 2.2, 1.0], [2093.0, 3.0, 0.35], [2711.0, 5.0, 0.25], [1052.0, 2.5, 0.6]], 0.05))
	_streams["elevator_doors"] = _wav(_elevator_doors())
	_streams["halogen_buzz"] = _wav(_halogen_buzz(), true)
	_set_variants("halogen_flick", 5, func(): return _halogen_flick())
	_streams["elevator_drop"] = _wav(_elevator_drop())
	# The Listener, up close.
	_streams["jumpscare"] = _wav(_jumpscare())
	_set_variants("listener_alert", 3, func(): return _listener_alert(true))
	_set_variants("listener_chatter", 3, func(): return _listener_alert(false))
	_set_variants("listener_snap", 4, func(): return _listener_snap())
	_streams["body_fall"] = _wav(_body_fall())
	_streams["listener_loom"] = _wav(_listener_loom())
	# The building noticing you: a clipped two-note chime falling, then a relay click.
	var chime := _strike(1.4, 0.002, 0.8, [[880.0, 4.0, 1.0], [1762.0, 6.0, 0.25]], 0.05)
	var chime2 := _strike(1.2, 0.002, 0.8, [[659.0, 4.5, 1.0], [1320.0, 7.0, 0.2]], 0.05)
	var at2 := int(0.32 * RATE)
	for i in chime2.size():
		if at2 + i < chime.size():
			chime[at2 + i] += chime2[i]
	var relay_click := _noise(0.03, 0.9, 150.0, 0.8)
	var at3 := int(0.85 * RATE)
	for i in relay_click.size():
		if at3 + i < chime.size():
			chime[at3 + i] += relay_click[i] * 0.6
	for i in int(0.12 * RATE):   # clipped: it cuts off a little too soon
		chime[chime.size() - 1 - i] = 0.0
	_streams["facility_chime"] = _wav(_normalize(chime, 0.7))
	# A loose pipe tapping twice: thin metal, ringing.
	var tap := _strike(1.0, 0.0015, 0.9, [[1240.0, 9.0, 1.0], [2710.0, 14.0, 0.5], [3980.0, 20.0, 0.3]], 0.2)
	var tap2 := _strike(0.8, 0.0015, 0.9, [[1240.0, 9.0, 1.0], [2710.0, 14.0, 0.5], [3980.0, 20.0, 0.3]], 0.2)
	var at4 := int(0.28 * RATE)
	for i in tap2.size():
		if at4 + i < tap.size():
			tap[at4 + i] += tap2[i] * 0.7
	_streams["pipe_tap"] = _wav(_normalize(tap, 0.8))
	# A relay room going dark for one beat: a deep, felt thump.
	_streams["relay_thump"] = _wav(_strike(1.2, 0.01, 0.2, [[42.0, 4.0, 1.0], [84.0, 6.0, 0.5], [130.0, 9.0, 0.25]], 0.3))

	# A signal fragment's hum: low tones a little out of tune with each other,
	# beating slowly, with a faint high shimmer. Loops every 4 s.
	var hum3 := _buf(4.0)
	for i in hum3.size():
		var t := float(i) / RATE
		hum3[i] = (sin(TAU * 110.0 * t) * 0.3 + sin(TAU * 116.5 * t) * 0.25 + sin(TAU * 165.25 * t) * 0.12
			+ sin(TAU * 1760.0 * t) * 0.03 * (0.5 + 0.5 * sin(TAU * 0.75 * t)))
	_streams["crystal_hum"] = _wav(hum3, true)

	# The mannequin moving: hollow plastic feet on concrete, creaking joints,
	# and a foot dragging along the floor.
	_set_variants("mq_step", 5, func(): return _mq_step())
	_set_variants("mq_creak", 4, func(): return _mq_creak())
	_set_variants("mq_scrape", 3, func(): return _mq_scrape())

	# Tripwire chimes (the Listener's traps).
	var chimes := _tone([[1568.0, 0.6]], 0.18, "sine", 4.0)
	chimes = _mix(chimes, _tone([[1864.0, 0.6]], 0.15, "sine", 4.0), 1500)
	chimes = _mix(chimes, _tone([[2093.0, 0.6]], 0.15, "sine", 4.0), 3200)
	_streams["trap"] = _wav(chimes)

	# You, holding your breath too long.
	_streams["gasp"] = _wav(_noise(0.45, 0.35, 6.0, 0.7, 0.02))
	var beat := _tone([[55.0, 0.18]], 0.8, "sine", 14.0)
	beat = _mix(beat, _tone([[52.0, 0.18]], 0.6, "sine", 14.0), int(0.26 * RATE))
	_streams["heartbeat"] = _wav(beat)

	# Distant facility noises.
	_streams["bang"] = _wav(_mix(_noise(1.2, 0.05, 3.0, 1.0), _tone([[62.0, 1.0]], 0.5, "sine", 3.0)))
	_streams["drip"] = _wav(_tone([[1800.0, 0.04], [1300.0, 0.08]], 0.1, "sine", 30.0))

	# Caught: TV static. (Never a scream, never anything graphic.)
	_streams["static"] = _wav(_noise(1.8, 0.9, 1.2, 0.35, 0.01))

	# Jump-scare sting (Survivor and Nightmare only).
	var sting := _noise(1.3, 0.7, 2.5, 0.35, 0.002)
	for f in [233.0, 247.0, 370.0, 523.0]:
		sting = _mix(sting, _tone([[f, 1.3]], 0.12, "square", 2.2))
	_streams["sting"] = _wav(sting)

	# A looping low drone for the facility, made from tones that repeat
	# exactly every 6 seconds so the loop is seamless.
	var drone := _buf(6.0)
	for i in drone.size():
		var t := float(i) / RATE
		var swell := 0.75 + 0.25 * sin(TAU * t / 6.0)
		drone[i] = (sin(TAU * 55.0 * t) * 0.22 + sin(TAU * (331.0 / 6.0) * t) * 0.18
			+ sin(TAU * 110.0 * t) * 0.05 + sin(TAU * (497.0 / 6.0) * t) * 0.07) * swell
	_streams["drone"] = _wav(drone, true)


# ------------------------------------------------ realistic material sounds

func _set_variants(sound_name: String, count: int, make: Callable) -> void:
	var list: Array = []
	for i in count:
		list.append(_wav(make.call()))
	_variants[sound_name] = list
	_streams[sound_name] = list[0]


## A resonance: rings at `freq` when struck, dying away at `decay` per second.
func _reso(x: PackedFloat32Array, freq: float, decay: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(x.size())
	var r := exp(-decay / RATE)
	var c := 2.0 * r * cos(TAU * freq / RATE)
	var r2 := r * r
	var y1 := 0.0
	var y2 := 0.0
	for i in x.size():
		var y := x[i] + c * y1 - r2 * y2
		out[i] = y
		y2 = y1
		y1 = y
	return out


func _add(into: PackedFloat32Array, x: PackedFloat32Array, gain: float) -> void:
	for i in mini(into.size(), x.size()):
		into[i] += x[i] * gain


func _normalize(a: PackedFloat32Array, peak: float) -> PackedFloat32Array:
	var m := 0.0001
	for v in a:
		m = maxf(m, absf(v))
	for i in a.size():
		a[i] = a[i] / m * peak
	return a


## A shoe on concrete: a dull heel strike, then the toe, with a little grit.
func _step_concrete(weight: float) -> PackedFloat32Array:
	var a := _buf(0.34)
	var toe_at := randf_range(0.05, 0.085) / (1.4 if weight > 1.2 else (0.8 if weight < 0.6 else 1.0))
	var thump_f := randf_range(80.0, 115.0)
	var lp1 := 0.0
	var lp2 := 0.0
	var lp3 := 0.0
	var grit := 0.0
	var dark := randf_range(0.12, 0.2)
	for i in a.size():
		var t := float(i) / RATE
		var n := randf_range(-1.0, 1.0)
		lp1 += dark * (n - lp1)                # dull heel body
		lp2 += 0.55 * (n - lp2)
		lp3 += 0.08 * (lp2 - lp3)
		var bright := lp2 - lp3                # sharper toe/scuff
		var heel := exp(-t * 60.0) * minf(t / 0.0015, 1.0)
		var toe := 0.0
		if t >= toe_at:
			toe = exp(-(t - toe_at) * 85.0) * 0.6
		var thump := sin(TAU * thump_f * t) * exp(-t * 38.0)
		# Grit: tiny grains of dust and sand crunching under the sole.
		if t < 0.16 and randf() < 0.004 * weight:
			grit = randf_range(-1.0, 1.0)
		grit *= 0.93
		var scuff := 0.0
		if weight < 0.6:
			scuff = bright * sin(PI * clampf(t / 0.25, 0.0, 1.0)) * 0.25   # a slow, careful roll
		a[i] = lp1 * heel * 1.6 + bright * toe * 0.9 + thump * heel * 0.7 * weight + grit * 0.18 + scuff
	return _normalize(a, 0.85 * minf(weight, 1.0) if weight < 1.0 else 0.9)


## A boot on a metal grate: a clang with ringing, inharmonic tones, and the
## loose panel rattling in its frame a moment later.
func _step_metal(weight: float) -> PackedFloat32Array:
	var dur := 1.0
	var excite := _buf(dur)
	var hits := [[0.0, 1.0]]
	var t := randf_range(0.045, 0.08)
	var g := 0.45
	for k in randi_range(2, 4):        # the rattle
		hits.append([t, g])
		t += randf_range(0.025, 0.05)
		g *= 0.6
	var lp := 0.0
	for h in hits:
		var start := int(float(h[0]) * RATE)
		var amp: float = h[1] * weight
		for j in int(0.006 * RATE):
			if start + j < excite.size():
				lp += 0.7 * (randf_range(-1.0, 1.0) - lp)
				excite[start + j] += lp * amp * exp(-float(j) / RATE * 700.0)
	var out := _buf(dur)
	var modes := [[287.0, 7.0, 0.5], [451.0, 9.0, 0.45], [668.0, 11.0, 0.36], [1023.0, 14.0, 0.3],
		[1497.0, 17.0, 0.22], [2210.0, 22.0, 0.15], [3120.0, 28.0, 0.1]]
	for m in modes:
		var f: float = m[0] * randf_range(0.9, 1.1)
		_add(out, _reso(excite, f, m[1]), m[2] * 0.02)
	_add(out, excite, 0.35)
	# The boot itself: a soft thud under the clang.
	for i in int(0.12 * RATE):
		var tt := float(i) / RATE
		out[i] += sin(TAU * 95.0 * tt) * exp(-tt * 40.0) * 0.25 * weight
	return _normalize(out, 0.85 if weight < 1.0 else 0.95)


## A mannequin foot: a hollow plastic clack (heel, then toe), and a tiny
## joint tick. Wrong for a person, and that's the point.
func _mq_step() -> PackedFloat32Array:
	var dur := 0.45
	var excite := _buf(dur)
	var times := [0.0, randf_range(0.03, 0.055)]
	if randf() < 0.6:
		times.append(randf_range(0.12, 0.22))   # the joint ticking
	for k in times.size():
		var start := int(float(times[k]) * RATE)
		var amp := 1.0 if k == 0 else (0.6 if k == 1 else 0.25)
		for j in int(0.003 * RATE):
			if start + j < excite.size():
				excite[start + j] += randf_range(-1.0, 1.0) * amp
	var out := _buf(dur)
	for m in [[330.0, 20.0, 0.6], [740.0, 32.0, 0.5], [1130.0, 40.0, 0.4], [1810.0, 48.0, 0.3], [2650.0, 60.0, 0.2]]:
		_add(out, _reso(excite, m[0] * randf_range(0.93, 1.07), m[1]), m[2] * 0.02)
	_add(out, excite, 0.15)
	return _normalize(out, 0.8)


## Plastic joints creaking: stick-slip friction, an irregular rasp.
func _mq_creak() -> PackedFloat32Array:
	var dur := randf_range(0.45, 0.8)
	var excite := _buf(dur)
	var phase := 0.0
	var base := randf_range(55.0, 90.0)
	for i in excite.size():
		var t := float(i) / RATE
		var f := base + 45.0 * sin(TAU * randf_range(0.9, 1.6) * t) + randf_range(-15.0, 15.0)
		phase += f / RATE
		if phase >= 1.0:
			phase -= 1.0
			excite[i] = randf_range(0.6, 1.0) * sin(PI * t / dur)
	var out := _buf(dur)
	_add(out, _reso(excite, randf_range(850.0, 1000.0), 45.0), 0.03)
	_add(out, _reso(excite, randf_range(1350.0, 1550.0), 55.0), 0.02)
	_add(out, _reso(excite, randf_range(2400.0, 2700.0), 70.0), 0.01)
	return _normalize(out, 0.7)


## A plastic foot dragged across concrete.
func _mq_scrape() -> PackedFloat32Array:
	var dur := randf_range(0.5, 0.8)
	var a := _buf(dur)
	var lp := 0.0
	var lp2 := 0.0
	var stutter := randf_range(12.0, 22.0)
	for i in a.size():
		var t := float(i) / RATE
		lp += 0.45 * (randf_range(-1.0, 1.0) - lp)
		lp2 += 0.05 * (lp - lp2)
		var grain := lp - lp2
		var env := sin(PI * t / dur) * (0.55 + 0.45 * absf(sin(TAU * stutter * t)))
		a[i] = grain * env
	var out := a.duplicate()
	_add(out, _reso(a, 620.0, 30.0), 0.01)
	return _normalize(out, 0.55)


## A struck object: a short burst of filtered noise (the contact) rings the
## object's resonant modes [freq, decay per second, level]. `click` is how much
## of the raw contact you hear on top. Each variant is detuned a little,
## because no two hits land on exactly the same spot.
func _strike(dur: float, contact: float, bright: float, modes: Array, click: float) -> PackedFloat32Array:
	var excite := _buf(dur)
	var lp := 0.0
	var n := maxi(int(contact * RATE), 8)
	for j in n:
		lp += bright * (randf_range(-1.0, 1.0) - lp)
		excite[j] = lp * sin(PI * float(j) / n)
	var out := _buf(dur)
	for m in modes:
		var level: float = m[2] * randf_range(0.7, 1.15)   # where it was hit changes the mix
		_add(out, _reso(excite, float(m[0]) * randf_range(0.96, 1.04), float(m[1]) * randf_range(0.9, 1.1)), level * 0.02)
	_add(out, excite, click)
	# A tiny bit of air on very short tails so they don't click off.
	return _normalize(out, 0.85)


## Something landing on concrete: no ring at all, just a hard, dry knock
## with a low body thud and a scatter of grit.
func _surf_concrete() -> PackedFloat32Array:
	var dur := 0.25
	var a := _buf(dur)
	var lp := 0.0
	var lp2 := 0.0
	var thud_f := randf_range(90.0, 140.0)
	var grit := 0.0
	for i in a.size():
		var t := float(i) / RATE
		var nz := randf_range(-1.0, 1.0)
		lp += 0.5 * (nz - lp)
		lp2 += 0.12 * (nz - lp2)
		var env := minf(t / 0.0008, 1.0) * exp(-t * 110.0)
		if t < 0.08 and randf() < 0.006:
			grit = randf_range(-1.0, 1.0)
		grit *= 0.9
		a[i] = lp * env * 0.7 + lp2 * exp(-t * 45.0) * 0.9 + sin(TAU * thud_f * t) * exp(-t * 50.0) * 0.5 + grit * 0.15
	var out := a.duplicate()
	_add(out, _reso(a, randf_range(1700.0, 2300.0), 120.0), 0.01)
	return _normalize(out, 0.8)


## Hitting a mannequin: hard, hollow fibreglass. A boxy knock with the
## low boom of the empty body inside it - like knocking on a big plastic drum.
func _surf_mannequin() -> PackedFloat32Array:
	var out := _strike(0.7, 0.0025, 0.6, [[96.0, 9.0, 0.9], [163.0, 13.0, 1.0], [404.0, 22.0, 0.75], [871.0, 32.0, 0.55], [1530.0, 45.0, 0.35], [2380.0, 60.0, 0.2]], 0.3)
	# Its arm or head knocks against its body a moment later.
	var tap := _strike(0.25, 0.0015, 0.7, [[640.0, 40.0, 1.0], [1490.0, 55.0, 0.6]], 0.2)
	var at := int(randf_range(0.06, 0.12) * RATE)
	for i in tap.size():
		if at + i < out.size():
			out[at + i] += tap[i] * 0.3
	return _normalize(out, 0.85)


## A clipboard: a flat slap of hardboard, and the metal clip clacking.
func _board_slap() -> PackedFloat32Array:
	var out := _strike(0.35, 0.004, 0.45, [[230.0, 35.0, 1.0], [590.0, 45.0, 0.7], [1310.0, 65.0, 0.4]], 0.6)
	var clip := _strike(0.2, 0.001, 0.9, [[3150.0, 40.0, 1.0], [5400.0, 60.0, 0.5]], 0.2)
	var at := int(randf_range(0.01, 0.03) * RATE)
	for i in clip.size():
		if at + i < out.size():
			out[at + i] += clip[i] * 0.35
	return _normalize(out, 0.8)


## What a mannequin does when you hit it. It's subtle, and it's wrong:
## something small and loose rolls around INSIDE the hollow body and settles,
## then a long, slow plastic creak like a joint easing back - and under it,
## very faint, something like an exhale.
func _mq_hit_reaction() -> PackedFloat32Array:
	var dur := 2.4
	var excite := _buf(dur)
	# The thing rolling inside: ticks that slow down and fade.
	var t := 0.0
	var gap := 0.03
	var amp := 0.8
	while t < 0.9:
		var start := int(t * RATE)
		for j in int(0.0015 * RATE):
			if start + j < excite.size():
				excite[start + j] += randf_range(-1.0, 1.0) * amp
		t += gap * randf_range(0.6, 1.5)
		gap *= 1.13
		amp *= 0.9
	var out := _buf(dur)
	for m in [[180.0, 8.0, 0.5], [720.0, 22.0, 1.0], [1210.0, 30.0, 0.7], [1980.0, 40.0, 0.35]]:
		_add(out, _reso(excite, m[0] * randf_range(0.95, 1.05), m[1]), m[2] * 0.02)
	# The joint easing back: slow stick-slip, falling in pitch.
	var creak := _buf(dur)
	var phase := 0.0
	var c0 := 0.7
	var c1 := 1.9
	for i in creak.size():
		var tt := float(i) / RATE
		if tt < c0 or tt > c1:
			continue
		var k := (tt - c0) / (c1 - c0)
		phase += (70.0 - 40.0 * k + randf_range(-8.0, 8.0)) / RATE
		if phase >= 1.0:
			phase -= 1.0
			creak[i] = randf_range(0.5, 1.0) * sin(PI * k)
	_add(out, _reso(creak, 930.0, 50.0), 0.012)
	_add(out, _reso(creak, 1460.0, 60.0), 0.008)
	# The exhale: dark breathy noise, barely there.
	var lp := 0.0
	var lp2 := 0.0
	for i in out.size():
		var tt := float(i) / RATE
		if tt < 1.0:
			continue
		var k := (tt - 1.0) / (dur - 1.0)
		lp += 0.18 * (randf_range(-1.0, 1.0) - lp)
		lp2 += 0.03 * (lp - lp2)
		out[i] += (lp - lp2) * sin(PI * k) * 0.22
	return _normalize(out, 0.6)


## Elevator doors sliding shut: a low motor whine, the rumble of rollers in a
## gritty track, and the heavy thud as they meet.
func _elevator_doors() -> PackedFloat32Array:
	var dur := 3.6
	var a := _buf(dur)
	var lp := 0.0
	var lp2 := 0.0
	var ph := 0.0
	for i in a.size():
		var t := float(i) / RATE
		var move := clampf(t / 0.3, 0.0, 1.0) * clampf((3.2 - t) / 0.2, 0.0, 1.0)
		ph += (95.0 + 12.0 * sin(TAU * 0.7 * t)) / RATE
		var motor := (sin(TAU * ph) * 0.5 + sin(TAU * ph * 2.0) * 0.25 + sin(TAU * ph * 3.0) * 0.12)
		var n := randf_range(-1.0, 1.0)
		lp += 0.08 * (n - lp)
		lp2 += 0.4 * (n - lp2)
		var rumble := lp * (0.7 + 0.3 * sin(TAU * 11.0 * t))
		var grit := lp2 * 0.15 if randf() < 0.02 else 0.0
		a[i] = (motor * 0.25 + rumble * 1.2 + grit) * move
	var thud := _strike(0.6, 0.006, 0.3, [[62.0, 8.0, 1.0], [140.0, 12.0, 0.7], [310.0, 18.0, 0.4], [780.0, 30.0, 0.2]], 0.5)
	var at := int(3.15 * RATE)
	for i in thud.size():
		if at + i < a.size():
			a[at + i] += thud[i] * 1.4
	return _normalize(a, 0.9)


## A halogen / fluorescent tube's buzz: mains hum (60 Hz and its harmonics,
## rough and slightly clipped), plus a thin high whine. Loops every 2 s.
func _halogen_buzz() -> PackedFloat32Array:
	var a := _buf(2.0)
	for i in a.size():
		var t := float(i) / RATE
		var hum := 0.0
		for h in [[60.0, 0.5], [120.0, 1.0], [180.0, 0.45], [240.0, 0.5], [360.0, 0.3], [480.0, 0.2], [600.0, 0.12]]:
			hum += sin(TAU * h[0] * t) * h[1]
		hum = clampf(hum * 0.6, -0.8, 0.8)
		a[i] = hum * 0.6 + sin(TAU * 8000.0 * t) * 0.02 + randf_range(-0.03, 0.03)
	return _normalize(a, 0.6)


## The tube failing: a sharp electrical crackle and a burst of louder buzz.
func _halogen_flick() -> PackedFloat32Array:
	var dur := randf_range(0.08, 0.2)
	var a := _buf(dur)
	var spark := 0.0
	for i in a.size():
		var t := float(i) / RATE
		if randf() < 0.03:
			spark = randf_range(-1.0, 1.0)
		spark *= 0.85
		var buzz := clampf((sin(TAU * 120.0 * t) + sin(TAU * 240.0 * t) * 0.6) * 1.5, -0.7, 0.7)
		a[i] = (spark * 0.8 + buzz * 0.5) * exp(-t * 14.0) * minf(t / 0.002, 1.0)
	return _normalize(a, 0.75)


## The cab lurches and starts down: a deep clunk and a falling groan of cables.
func _elevator_drop() -> PackedFloat32Array:
	var dur := 2.5
	var a := _strike(dur, 0.01, 0.25, [[45.0, 3.0, 1.0], [92.0, 5.0, 0.7], [210.0, 9.0, 0.4]], 0.4)
	var ph := 0.0
	for i in a.size():
		var t := float(i) / RATE
		ph += (180.0 - 60.0 * t / dur) / RATE
		var groan := (sin(TAU * ph) + 0.4 * sin(TAU * ph * 2.03)) * sin(PI * t / dur) * 0.06
		a[i] += groan
	return _normalize(a, 0.85)


## The jump scare: a split-second of silence-breaking noise. A hard, low
## impact, a ragged inhuman shriek (several detuned voices that bend and
## warble against each other) and its clicks firing all at once.
func _jumpscare() -> PackedFloat32Array:
	var dur := 1.4
	var a := _buf(dur)
	var phases := [0.0, 0.0, 0.0, 0.0]
	var bases := [740.0, 1130.0, 1610.0, 2290.0]
	for i in a.size():
		var t := float(i) / RATE
		var env := minf(t / 0.008, 1.0) * exp(-t * 2.2)
		var v := 0.0
		for k in 4:
			var f: float = bases[k] * (1.0 + 0.08 * sin(TAU * (13.0 + k * 3.0) * t) - 0.18 * t)
			phases[k] = fmod(phases[k] + f / RATE, 1.0)
			v += (phases[k] * 2.0 - 1.0) * (0.35 - k * 0.05)   # raw saw voices
		v = clampf(v * 1.8, -0.9, 0.9)                          # torn and overdriven
		v += randf_range(-1.0, 1.0) * 0.25 * exp(-t * 6.0)     # breath in the scream
		var boom := sin(TAU * (55.0 - 20.0 * t) * t) * exp(-t * 7.0) * 1.2
		a[i] = v * env + boom
	# Its clicks, all at once.
	for k in 14:
		var at := int(randf_range(0.0, 0.5) * RATE)
		for j in int(0.003 * RATE):
			if at + j < a.size():
				a[at + j] += randf_range(-1.0, 1.0) * 0.7
	return _normalize(a, 0.98)


## It just heard you run. harsh: a rising, rattling screech; otherwise
## (Explorer) a fast, quiet burst of clicking chatter - a warning, not a scare.
func _listener_alert(harsh: bool) -> PackedFloat32Array:
	var dur := 0.9 if harsh else 0.7
	var a := _buf(dur)
	var ph := 0.0
	for i in a.size():
		var t := float(i) / RATE
		var env := sin(PI * minf(t / dur, 1.0)) * minf(t / 0.02, 1.0)
		var v := 0.0
		if harsh:
			var f := 420.0 + 900.0 * t + 60.0 * sin(TAU * 37.0 * t)
			ph = fmod(ph + f / RATE, 1.0)
			var rattle := 0.5 + 0.5 * signf(sin(TAU * 31.0 * t))
			v = clampf((ph * 2.0 - 1.0) * 1.6, -0.8, 0.8) * (0.6 + 0.4 * rattle) + randf_range(-0.2, 0.2)
		a[i] = v * env
	# Clicks: rapid, accelerating.
	var t2 := 0.0
	var gap := 0.06
	while t2 < dur - 0.05:
		var at := int(t2 * RATE)
		for j in int(0.002 * RATE):
			if at + j < a.size():
				a[at + j] += randf_range(-1.0, 1.0) * (0.5 if harsh else 0.9)
		t2 += gap
		gap = maxf(gap * 0.88, 0.015)
	var out := a.duplicate()
	_add(out, _reso(a, 2400.0, 60.0), 0.01)
	return _normalize(out, 0.9 if harsh else 0.6)


## Its joints snapping as it jumps: a cluster of dry cracks, like knuckles
## or green sticks, and a short sucked-in breath played backwards.
func _listener_snap() -> PackedFloat32Array:
	var dur := 0.7
	var excite := _buf(dur)
	var t := 0.0
	for k in randi_range(4, 7):
		var at := int(t * RATE)
		for j in int(0.0012 * RATE):
			if at + j < excite.size():
				excite[at + j] += randf_range(-1.0, 1.0) * randf_range(0.5, 1.0)
		t += randf_range(0.012, 0.05)
	var out := _buf(dur)
	for m in [[680.0, 70.0, 1.0], [1450.0, 90.0, 0.8], [2900.0, 120.0, 0.5], [310.0, 50.0, 0.6]]:
		_add(out, _reso(excite, m[0] * randf_range(0.9, 1.1), m[1]), m[2] * 0.03)
	_add(out, excite, 0.6)
	# A reversed inhale: swelling breath noise that cuts off.
	var lp := 0.0
	for i in out.size():
		var tt := float(i) / RATE
		if tt < 0.2:
			continue
		lp += 0.25 * (randf_range(-1.0, 1.0) - lp)
		var k2 := (tt - 0.2) / (dur - 0.2)
		out[i] += lp * pow(k2, 2.0) * 0.5 * (1.0 if k2 < 0.97 else 0.0)
	return _normalize(out, 0.85)


## You hitting the floor on your back: a heavy, dull thump with a scuff.
func _body_fall() -> PackedFloat32Array:
	var a := _strike(0.6, 0.02, 0.15, [[58.0, 9.0, 1.0], [96.0, 12.0, 0.7], [180.0, 20.0, 0.4]], 0.6)
	var scuff := _surf_concrete()
	for i in scuff.size():
		if i < a.size():
			a[i] += scuff[i] * 0.4
	return _normalize(a, 0.9)


## Leaning over you (gentle version): a low unsteady drone and slow wet clicks.
func _listener_loom() -> PackedFloat32Array:
	var dur := 2.8
	var a := _buf(dur)
	for i in a.size():
		var t := float(i) / RATE
		var env := minf(t / 0.8, 1.0) * minf((dur - t) / 0.4, 1.0)
		a[i] = (sin(TAU * 48.0 * t) * 0.5 + sin(TAU * 50.5 * t) * 0.4 + sin(TAU * 97.0 * t) * 0.15) * env
	for k in 9:
		var at := int(randf_range(0.3, dur - 0.3) * RATE)
		var click := _strike(0.08, 0.001, 0.8, [[1900.0, 80.0, 1.0], [3100.0, 120.0, 0.5]], 0.3)
		for j in click.size():
			if at + j < a.size():
				a[at + j] += click[j] * 0.35
	return _normalize(a, 0.7)


## Glass smashing: a sharp crack, then bright shards tinkling down.
func _glass_smash() -> PackedFloat32Array:
	var dur := 1.1
	var excite := _buf(dur)
	for j in int(0.004 * RATE):
		excite[j] = randf_range(-1.0, 1.0)
	for k in 28:   # the shards
		var start := int(randf_range(0.02, 0.8) * RATE)
		var amp := randf_range(0.1, 0.5) * exp(-float(start) / RATE * 2.5)
		for j in int(0.002 * RATE):
			if start + j < excite.size():
				excite[start + j] += randf_range(-1.0, 1.0) * amp
	var out := _buf(dur)
	for m in [[2350.0, 30.0], [3100.0, 38.0], [4200.0, 45.0], [5300.0, 55.0], [6800.0, 65.0]]:
		_add(out, _reso(excite, m[0] * randf_range(0.9, 1.1), m[1]), 0.02)
	_add(out, excite, 0.5)
	return _normalize(out, 0.85)
