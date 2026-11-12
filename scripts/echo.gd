extends Node3D
## ECHO. It copies you.
##
## A while after you arrive, a figure made of TV static steps out where you
## started and walks EXACTLY where you walked, step for step, a little slower
## than you walk. Stop for too long and it catches up. Double back and you
## walk right into it. Hiding in a locker breaks your trail and it fades away
## for a while. It also copies voices: it sounds like MERIDIAN, and it wants
## you to go back the way you came.
##
## In Explorer it never catches you: if it reaches you it just glitches away.

## Lines in YOUR voice. It has been listening to you.
const YOUR_LINES := [
	"Wait for me...",
	"Is someone there?",
	"I'm right behind you.",
	"Why are you running from me?",
	"Turn around. It's only me.",
]

const VOICE_LINES := [
	"Go back the way you came. It's safer.",
	"Stop. Wait right there. I'm coming to help.",
	"You dropped something back there. Go back for it.",
	"Don't hide. Hiding makes it worse.",
	"I can see you on the cameras. Turn around.",
]

var sector: Node
var active := false
var _wait := 0.0
var _idx := 0
var _step_t := 0.0
var _voice_t := 20.0
var _glitch_t := 0.0
var _model: Node3D
var _light: OmniLight3D
var _appeared_once := false
var _head: Node3D
var _mouth: MeshInstance3D
var _arms: Array = []
var _whisper: AudioStreamPlayer3D
var _was_shielded := false
var _time := 0.0


func setup(s: Node) -> void:
	sector = s
	_model = _build_model()
	add_child(_model)
	_light = OmniLight3D.new()
	_light.light_color = Color(0.5, 0.8, 1.0)
	_light.light_energy = 0.35
	_light.omni_range = 3.5
	_light.position.y = 1.3
	add_child(_light)
	_whisper = AudioStreamPlayer3D.new()
	_whisper.stream = Sound.stream("echo_whisper")
	_whisper.unit_size = 2.5
	_whisper.max_distance = 18.0
	_whisper.position.y = 1.7
	_whisper.volume_db = -16.0 if Game.is_explorer() else -6.0
	_whisper.bus = Sound.WORLD
	add_child(_whisper)
	visible = false
	_wait = float(Game.mode_data()["echo_delay"])


func _build_model() -> Node3D:
	# Shaped like a person - like you - but made of moving static.
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform float alpha = 0.75;
float rnd(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void fragment() {
	vec2 px = floor(SCREEN_UV * vec2(320.0, 180.0));
	float f = floor(TIME * 24.0);
	float n = rnd(px + vec2(f * 3.1, f * 1.7));
	float band = 0.55 + 0.45 * step(0.5, fract(SCREEN_UV.y * 90.0 + TIME * 4.0));
	ALBEDO = mix(vec3(0.45, 0.75, 1.0), vec3(1.0), n) * (0.4 + 0.6 * n);
	ALPHA = alpha * band * (0.35 + 0.65 * n);
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	var root := Node3D.new()
	for p in [[Vector2(0.09, 0.9), Vector3(-0.12, 0.45, 0)], [Vector2(0.09, 0.9), Vector3(0.12, 0.45, 0)],
			[Vector2(0.2, 0.75), Vector3(0, 1.25, 0)]]:
		root.add_child(_capsule(p[0], p[1], mat))
	# Arms on shoulder pivots, so it can reach for you.
	for side in [-1.0, 1.0]:
		var shoulder := Node3D.new()
		shoulder.position = Vector3(0.28 * side, 1.55, 0)
		shoulder.rotation.z = 0.12 * -side
		root.add_child(shoulder)
		shoulder.add_child(_capsule(Vector2(0.06, 0.78), Vector3(0, -0.36, 0), mat))
		_arms.append(shoulder)
	# A head on a neck pivot, with a face: empty black eyes and a mouth.
	_head = Node3D.new()
	_head.position.y = 1.66
	root.add_child(_head)
	var skull := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.14
	sm.height = 0.32
	skull.mesh = sm
	skull.material_override = mat
	skull.position.y = 0.12
	skull.scale = Vector3(1.0, 1.15, 0.9)
	_head.add_child(skull)
	var void_mat := StandardMaterial3D.new()
	void_mat.albedo_color = Color(0, 0, 0)
	void_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var em := SphereMesh.new()
		em.radius = 0.04
		em.height = 0.06
		eye.mesh = em
		eye.material_override = void_mat
		eye.position = Vector3(0.055 * side, 0.16, 0.125)
		eye.scale = Vector3(1.0, 1.0, 0.4)
		_head.add_child(eye)
	_mouth = MeshInstance3D.new()
	var mm := SphereMesh.new()
	mm.radius = 0.035
	mm.height = 0.05
	_mouth.mesh = mm
	_mouth.material_override = void_mat
	_mouth.position = Vector3(0, 0.05, 0.13)
	_head.add_child(_mouth)
	return root


## Lose your trail and fade away; come back after `delay` seconds and start
## copying you again from wherever you are then.
func _capsule(dims: Vector2, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = dims.x
	cm.height = dims.y
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	return mi


func lose_trail(delay: float) -> void:
	if visible:
		Sound.play_at("static", global_position + Vector3(0, 1, 0), -10.0, 1.4)
	active = false
	visible = false
	_whisper.stop()
	_wait = delay
	_idx = 0
	sector.on_trail_broken()


func _physics_process(delta: float) -> void:
	if sector == null or sector.paused_world:
		return
	var trail: Array[Vector3] = sector.trail
	var player: Node = sector.player
	if not active:
		_wait -= delta
		if _wait <= 0.0 and trail.size() > 3:
			active = true
			visible = true
			_idx = 0
			global_position = trail[0]
			Sound.play_at("static", global_position + Vector3(0, 1, 0), -6.0, 0.8)
			_whisper.play()
			if not _appeared_once:
				_appeared_once = true
				sector.on_echo_appeared()
		return

	_time += delta
	var dist: float = global_position.distance_to(player.global_position)
	var scary := not Game.is_explorer()
	_animate_body(delta, dist, scary, player)

	# You're in a shielded room: it can't follow you in. It waits at the
	# edge and stares. When you come out, it loses you for a while.
	var shielded: bool = sector.trail_shielded()
	if shielded:
		_was_shielded = true
		if _idx < trail.size():
			# Walk the rest of your trail up to the door, then wait there.
			var t2: Vector3 = trail[_idx]
			var d2 := t2 - global_position
			d2.y = 0.0
			var st := float(Game.mode_data()["echo_speed"]) * delta
			if d2.length() <= st:
				global_position = Vector3(t2.x, 0.0, t2.z)
				_idx += 1
			else:
				global_position += d2.normalized() * st
		var look: Vector3 = player.global_position - global_position
		rotation.y = lerp_angle(rotation.y, atan2(look.x, look.z), minf(delta * 4.0, 1.0))
		return
	if _was_shielded:
		_was_shielded = false
		lose_trail(float(Game.mode_data()["echo_delay"]) * 0.5)
		return

	# Now and then it lurches forward along your trail (not in Explorer).
	if scary and dist > 10.0 and _idx < trail.size() - 8:
		var lurch := 0.12 if Game.mode == Game.Mode.NIGHTMARE else 0.06
		if randf() < lurch * delta:
			_idx += 6
			global_position = trail[_idx]
			Sound.play_at("static", global_position + Vector3(0, 1, 0), -8.0, 1.6)

	# Follow your footsteps, oldest first.
	var target: Vector3 = player.global_position if _idx >= trail.size() else trail[_idx]
	if sector.echo_blocked(target) or sector.echo_blocked(global_position + (target - global_position).normalized() * 1.2):
		# A jammer's field is in the way. It can't step into it: it waits and stares.
		var look: Vector3 = player.global_position - global_position
		rotation.y = lerp_angle(rotation.y, atan2(look.x, look.z), minf(delta * 4.0, 1.0))
		return
	var to := target - global_position
	to.y = 0.0
	var step := float(Game.mode_data()["echo_speed"]) * delta
	var before: Vector2i = sector.world_to_cell(global_position)
	if to.length() <= step:
		global_position = Vector3(target.x, 0.0, target.z)
		if _idx < trail.size():
			_idx += 1
	else:
		global_position += to.normalized() * step
		rotation.y = lerp_angle(rotation.y, atan2(to.x, to.z), minf(delta * 8.0, 1.0))
	var after: Vector2i = sector.world_to_cell(global_position)
	if after != before:
		sector.monster_entering(after)
	# Forget the part of the trail it has already walked.
	if _idx > 200:
		trail.assign(trail.slice(_idx))
		_idx = 0

	# It copies your footsteps too: soft on concrete, loud on the grates.
	_step_t -= delta
	if _step_t <= 0.0:
		_step_t = 0.6
		var grate: bool = sector.is_grate(global_position)
		Sound.play_at("step_grate" if grate else "step", global_position, -8.0, randf_range(0.8, 0.95))

	# Glitch: it jumps a little and flickers.
	_glitch_t -= delta
	if _glitch_t <= 0.0:
		_glitch_t = randf_range(0.05, 0.6)
		_model.position = Vector3(randf_range(-0.12, 0.12), 0, randf_range(-0.12, 0.12)) if randf() < 0.3 else Vector3.ZERO
		_model.visible = randf() > 0.08

	# It copies MERIDIAN's voice - and yours - and it wants you to turn around.
	_voice_t -= delta
	if _voice_t <= 0.0 and dist < 18.0:
		_voice_t = randf_range(25.0, 45.0)
		if randf() < 0.5:
			sector.hud.say("you", YOUR_LINES[randi() % YOUR_LINES.size()])
		else:
			sector.hud.say("echo", VOICE_LINES[randi() % VOICE_LINES.size()])

	# Caught up with you?
	if dist < 1.1 and not player.hidden_in and not player.frozen:
		if Game.mode_data()["echo_catches"]:
			sector.on_caught("echo")
		else:
			sector.hud.toast("ECHO caught up with you and glitched away. It will be back. Keep moving!", 4.0)
			lose_trail(float(Game.mode_data()["echo_delay"]))


## Head snaps to stare at you; up close it stretches taller, its mouth opens
## and it reaches for you (the stretch and reach are not in Explorer).
func _animate_body(delta: float, dist: float, scary: bool, player: Node) -> void:
	var close := clampf(1.0 - (dist - 1.5) / 6.0, 0.0, 1.0)
	if dist < 9.0:
		var to: Vector3 = player.global_position - global_position
		var want := atan2(to.x, to.z) - rotation.y
		want = wrapf(want, -PI, PI)
		_head.rotation.y = clampf(want, -1.6, 1.6) if randf() > 0.02 else _head.rotation.y + randf_range(-0.5, 0.5)
		_head.rotation.z = sin(_time * 3.0) * 0.1 + (0.3 if scary else 0.1) * close
	else:
		_head.rotation.y = lerpf(_head.rotation.y, 0.0, minf(delta * 3.0, 1.0))
	_mouth.scale = Vector3(1.0, 1.0 + close * (2.2 if scary else 1.0), 1.0)
	var stretch := 1.0 + (0.18 * close if scary else 0.0)
	_model.scale.y = lerpf(_model.scale.y, stretch, minf(delta * 4.0, 1.0))
	for i in _arms.size():
		var arm: Node3D = _arms[i]
		var reach := (-1.3 * close if scary else 0.0) + sin(_time * 2.0 + i) * 0.08
		arm.rotation.x = lerpf(arm.rotation.x, reach, minf(delta * 5.0, 1.0))
