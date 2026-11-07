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
	var parts := [
		[Vector2(0.09, 0.9), Vector3(-0.12, 0.45, 0), 0.0],
		[Vector2(0.09, 0.9), Vector3(0.12, 0.45, 0), 0.0],
		[Vector2(0.2, 0.75), Vector3(0, 1.25, 0), 0.0],
		[Vector2(0.06, 0.7), Vector3(-0.3, 1.2, 0), 0.12],
		[Vector2(0.06, 0.7), Vector3(0.3, 1.2, 0), -0.12],
	]
	for p in parts:
		var mi := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = p[0].x
		cm.height = p[0].y
		mi.mesh = cm
		mi.material_override = mat
		mi.position = p[1]
		mi.rotation.z = p[2]
		root.add_child(mi)
	var head := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.14
	sm.height = 0.3
	head.mesh = sm
	head.material_override = mat
	head.position.y = 1.78
	root.add_child(head)
	return root


## Lose your trail and fade away; come back after `delay` seconds and start
## copying you again from wherever you are then.
func lose_trail(delay: float) -> void:
	if visible:
		Sound.play_at("static", global_position + Vector3(0, 1, 0), -10.0, 1.4)
	active = false
	visible = false
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
			if not _appeared_once:
				_appeared_once = true
				sector.on_echo_appeared()
		return

	# Follow your footsteps, oldest first.
	var target: Vector3 = player.global_position if _idx >= trail.size() else trail[_idx]
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

	# It copies MERIDIAN's voice, and it wants you to turn around.
	var dist: float = global_position.distance_to(player.global_position)
	_voice_t -= delta
	if _voice_t <= 0.0 and dist < 18.0:
		_voice_t = randf_range(25.0, 45.0)
		sector.hud.say("echo", VOICE_LINES[randi() % VOICE_LINES.size()])

	# Caught up with you?
	if dist < 1.1 and not player.hidden_in and not player.frozen:
		if Game.mode_data()["echo_catches"]:
			sector.on_caught("echo")
		else:
			sector.hud.toast("ECHO caught up with you and glitched away. It will be back. Keep moving!", 4.0)
			lose_trail(float(Game.mode_data()["echo_delay"]))
