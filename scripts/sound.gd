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
func play_at(sound_name: String, pos: Vector3, vol_db := 0.0, pitch := 1.0) -> void:
	var s: AudioStream = pick(sound_name)
	var scene := get_tree().current_scene
	if s == null or scene == null:
		return
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
	_set_variants("hit_metal", 3, func(): return _step_metal(0.8))
	_set_variants("hit_glass", 3, func(): return _glass_smash())
	_set_variants("hit_soft", 3, func(): return _step_concrete(0.8))

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
