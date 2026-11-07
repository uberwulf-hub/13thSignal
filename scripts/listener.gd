extends Node3D
## THE LISTENER. It can't see you, but it hears everything.
##
## It wanders, goes to check out noises, and hunts you while you keep making
## noise close by. It LEARNS: hide in lockers too often and it starts checking
## them (hold your breath!); run too often and it sets tripwire chimes in the
## halls you run through.

enum State { WANDER, INVESTIGATE, LISTEN, HUNT, CHECK_LOCKER }

const WANDER_SPEED := 1.6
const INVESTIGATE_SPEED := 2.9
const HUNT_SPEED := 4.3

var sector: Node
var state := State.WANDER
var path: Array[Vector2i] = []
var last_heard := Vector3.ZERO
var _wait := 0.0
var _hunt_t := 0.0
var _repath_t := 0.0
var _click_t := 0.0
var _locker_queue: Array = []
var _checking: Node = null
var _audio: AudioStreamPlayer3D
var _breath: AudioStreamPlayer3D
var _body: Node3D
var _torso: Node3D
var _head: Node3D
var _arms: Array = []
var _legs: Array = []
var _ear_mat: StandardMaterial3D
var _rasp: AudioStreamPlayer3D
var _stride := 0.0
var _twitch_t := 0.0
var _head_target := Vector3.ZERO
var _last_pos := Vector3.ZERO
var _time := 0.0


func setup(s: Node) -> void:
	sector = s
	_build_body()
	_audio = AudioStreamPlayer3D.new()
	_audio.stream = Sound.stream("listener_click")
	_audio.unit_size = 7.0
	_audio.max_distance = 40.0
	_audio.position.y = 2.0
	add_child(_audio)
	_breath = AudioStreamPlayer3D.new()
	_breath.stream = Sound.stream("listener_breath")
	_breath.unit_size = 3.0
	_breath.max_distance = 14.0
	_breath.position.y = 2.0
	add_child(_breath)
	# A wet, rasping breath you hear before you see it.
	_rasp = AudioStreamPlayer3D.new()
	_rasp.stream = Sound.stream("listener_rasp")
	_rasp.unit_size = 2.5
	_rasp.max_distance = 16.0
	_rasp.position.y = 2.2
	_rasp.volume_db = -14.0 if Game.is_explorer() else -4.0
	add_child(_rasp)
	_rasp.play()


func _build_body() -> void:
	# Tall, starved and eyeless. It has no face, just rows of ear-slits that
	# glow when it clicks. Long arms that nearly drag on the floor.
	_body = Node3D.new()
	add_child(_body)
	var skin := StandardMaterial3D.new()
	skin.albedo_color = Color(0.07, 0.065, 0.07)
	skin.roughness = 0.25
	skin.metallic = 0.15
	skin.rim_enabled = true
	skin.rim = 0.8
	skin.rim_tint = 0.2
	_ear_mat = StandardMaterial3D.new()
	var ear_color := Color(0.35, 0.55, 1.0) if Game.is_explorer() else Color(1.0, 0.18, 0.08)
	_ear_mat.albedo_color = ear_color
	_ear_mat.emission_enabled = true
	_ear_mat.emission = ear_color
	_ear_mat.emission_energy_multiplier = 0.6

	# Legs: thigh forward, shin bending backwards like a bird's.
	for side in [-1.0, 1.0]:
		var hip := Node3D.new()
		hip.position = Vector3(0.16 * side, 1.35, 0)
		_body.add_child(hip)
		_limb(hip, 0.07, 0.75, Vector3(0, -0.3, 0.12), -0.35, skin)
		var knee := Node3D.new()
		knee.position = Vector3(0, -0.66, 0.24)
		hip.add_child(knee)
		_limb(knee, 0.055, 0.8, Vector3(0, -0.34, -0.12), 0.35, skin)
		_legs.append(hip)

	# Torso on a pivot so it can hunch forward when it hunts.
	_torso = Node3D.new()
	_torso.position.y = 1.35
	_body.add_child(_torso)
	_limb(_torso, 0.17, 1.05, Vector3(0, 0.5, 0), 0.0, skin)
	for i in 6:   # ribs
		var rib := MeshInstance3D.new()
		var rm := BoxMesh.new()
		rm.size = Vector3(0.34 - i * 0.02, 0.025, 0.24)
		rib.mesh = rm
		rib.material_override = skin
		rib.position = Vector3(0, 0.45 + i * 0.09, 0.03)
		_torso.add_child(rib)

	# Long neck and an eyeless, stretched head.
	_head = Node3D.new()
	_head.position = Vector3(0, 1.08, 0.04)
	_torso.add_child(_head)
	_limb(_head, 0.05, 0.36, Vector3(0, 0.12, 0), 0.0, skin)
	var skull := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.17
	sm.height = 0.62
	skull.mesh = sm
	skull.material_override = skin
	skull.position = Vector3(0, 0.42, 0.06)
	skull.rotation.x = 0.35
	_head.add_child(skull)
	for side in [-1.0, 1.0]:      # ear-slits down each side of the head
		for j in 4:
			_slit(Vector3(0.15 * side, 0.3 + j * 0.08, 0.06 + j * 0.02), Vector3(0.012, 0.05, 0.06))
	for j in 3:                    # and where a face should be
		_slit(Vector3(0, 0.3 + j * 0.09, 0.22 + j * 0.02), Vector3(0.09 - j * 0.02, 0.012, 0.02))

	# Arms on shoulder pivots, with long fingers.
	for side in [-1.0, 1.0]:
		var shoulder := Node3D.new()
		shoulder.position = Vector3(0.24 * side, 0.98, 0)
		_torso.add_child(shoulder)
		_limb(shoulder, 0.045, 0.9, Vector3(0.04 * side, -0.42, 0), 0.08 * side, skin)
		var elbow := Node3D.new()
		elbow.position = Vector3(0.08 * side, -0.85, 0)
		shoulder.add_child(elbow)
		_limb(elbow, 0.038, 0.85, Vector3(0, -0.4, 0.04), -0.1, skin)
		for f in 4:
			_limb(elbow, 0.012, 0.38, Vector3((f - 1.5) * 0.03, -0.98, 0.06 + f * 0.01), (f - 1.5) * 0.12, skin)
		_arms.append(shoulder)

	var wisps := CPUParticles3D.new()
	wisps.amount = 18
	wisps.lifetime = 1.8
	wisps.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	wisps.emission_sphere_radius = 0.4
	wisps.direction = Vector3.UP
	wisps.spread = 40.0
	wisps.initial_velocity_min = 0.05
	wisps.initial_velocity_max = 0.25
	wisps.gravity = Vector3.ZERO
	wisps.scale_amount_min = 0.2
	wisps.scale_amount_max = 0.5
	var wm := SphereMesh.new()
	wm.radius = 0.25
	wm.height = 0.5
	wisps.mesh = wm
	var wmat := StandardMaterial3D.new()
	wmat.albedo_color = Color(0, 0, 0, 0.35)
	wmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wisps.material_override = wmat
	wisps.position.y = 0.3
	_body.add_child(wisps)


func _limb(parent: Node3D, radius: float, length: float, pos: Vector3, tilt: float, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = radius
	cm.height = maxf(length, radius * 2.0)
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	mi.rotation.z = tilt
	parent.add_child(mi)


func _slit(pos: Vector3, size: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _ear_mat
	mi.position = pos
	_head.add_child(mi)


## Arms, legs, hunch and the twitchy head. Runs every frame.
func _animate(delta: float, moving: bool, speed: float) -> void:
	var hunting := state == State.HUNT
	var listening := state == State.LISTEN or state == State.CHECK_LOCKER
	_stride += delta * speed * 2.6 if moving else 0.0
	var swing := sin(_stride) * (0.55 if moving else 0.0)
	for i in _legs.size():
		var leg: Node3D = _legs[i]
		leg.rotation.x = lerpf(leg.rotation.x, swing * (1.0 if i == 0 else -1.0), minf(delta * 10.0, 1.0))
	var hunch := 0.55 if hunting else (0.25 if listening else 0.12)
	_torso.rotation.x = lerpf(_torso.rotation.x, hunch, minf(delta * 4.0, 1.0))
	for i in _arms.size():
		var arm: Node3D = _arms[i]
		var reach := -1.1 if hunting else (-0.35 if listening else 0.0)
		var want := reach + (-swing * 0.6 if i == 0 else swing * 0.6) * (0.4 if hunting else 1.0)
		if hunting:
			want += sin(_time * 9.0 + i) * 0.12   # fingers-out grasping twitch
		arm.rotation.x = lerpf(arm.rotation.x, want, minf(delta * 8.0, 1.0))
	# The head jerks: it holds still, then SNAPS to a new angle.
	_twitch_t -= delta
	if _twitch_t <= 0.0:
		_twitch_t = randf_range(0.15, 0.5) if (hunting or listening) else randf_range(0.6, 1.8)
		var tilt := 0.7 if listening else 0.35
		_head_target = Vector3(randf_range(-0.3, 0.25), randf_range(-0.6, 0.6), randf_range(-tilt, tilt))
	_head.rotation = _head.rotation.lerp(_head_target, minf(delta * 22.0, 1.0))
	# The ear-slits flare with each click, then fade.
	_ear_mat.emission_energy_multiplier = maxf(_ear_mat.emission_energy_multiplier - delta * 6.0, 0.6)
	_body.position.y = sin(_time * 2.1) * 0.03


func reset_to(pos: Vector3) -> void:
	global_position = pos
	state = State.WANDER
	path.clear()
	_wait = 3.0
	_checking = null
	_locker_queue.clear()


## A noise happened. Can I hear it?
func hear(pos: Vector3, radius: float, from_player: bool) -> void:
	var m := Game.mode_data()
	var d := global_position.distance_to(pos)
	if d > radius * float(m["hearing"]):
		return
	last_heard = pos
	if state == State.CHECK_LOCKER and not from_player:
		return
	if from_player and d < 8.0 and not sector.player.hidden_in:
		if state != State.HUNT:
			sector.on_hunt_started()
		state = State.HUNT
		_hunt_t = 2.8
		return
	if state != State.HUNT:
		state = State.INVESTIGATE
		_go_to(pos)


func _go_to(pos: Vector3) -> void:
	path = sector.find_path(global_position, pos)


func _physics_process(delta: float) -> void:
	if sector == null or sector.paused_world:
		return
	_time += delta
	var m := Game.mode_data()
	var mult := float(m["listener_speed"])
	var player: Node = sector.player

	match state:
		State.WANDER:
			if path.is_empty():
				_wait -= delta
				if _wait <= 0.0:
					path = sector.find_path(global_position, sector.random_floor_pos())
					_wait = randf_range(1.0, 3.0)
			_follow(WANDER_SPEED * mult, delta)
		State.INVESTIGATE:
			_follow(INVESTIGATE_SPEED * mult, delta)
			if path.is_empty():
				state = State.LISTEN
				_wait = randf_range(2.0, 3.5)
				_breath.play()
		State.LISTEN:
			_wait -= delta
			if _wait <= 0.0:
				_after_listen()
		State.HUNT:
			_hunt_t -= delta
			_repath_t -= delta
			if player.hidden_in:
				# You vanished into a locker: go to where it last heard you.
				state = State.INVESTIGATE
				_go_to(last_heard)
			elif _hunt_t <= 0.0:
				state = State.INVESTIGATE
				_go_to(last_heard)
			else:
				if _repath_t <= 0.0:
					_repath_t = 0.4
					last_heard = player.global_position
					_go_to(player.global_position)
				_follow(HUNT_SPEED * mult, delta)
		State.CHECK_LOCKER:
			if not path.is_empty():
				_follow(INVESTIGATE_SPEED * mult, delta)
			else:
				_face(_checking.global_position, delta)
				_wait -= delta
				if player.hidden_in == _checking and not player.holding_breath:
					sector.on_caught("listener")
					return
				if _wait <= 0.0:
					_checking = null
					_next_locker()

	# Echolocation clicks: faster when it's on to you.
	_click_t -= delta
	if _click_t <= 0.0:
		var gap := {State.WANDER: 1.4, State.INVESTIGATE: 0.8, State.LISTEN: 0.6, State.HUNT: 0.32, State.CHECK_LOCKER: 0.5}
		_click_t = float(gap[state]) * randf_range(0.8, 1.2)
		_audio.pitch_scale = randf_range(0.9, 1.15)
		_audio.play()
		_ear_mat.emission_energy_multiplier = 4.0 if state == State.HUNT else 2.5

	var moved := global_position.distance_to(_last_pos)
	_last_pos = global_position
	_animate(delta, moved > 0.0005, moved / maxf(delta, 0.0001))

	# Caught?
	if not player.hidden_in and not player.frozen:
		var flat := Vector2(global_position.x - player.global_position.x, global_position.z - player.global_position.z)
		if flat.length() < 1.15:
			sector.on_caught("listener")


func _after_listen() -> void:
	if Game.learned_lockers:
		_locker_queue = sector.lockers_near(global_position, 10.0, 2)
		_next_locker()
	else:
		state = State.WANDER
		_wait = randf_range(0.5, 2.0)


func _next_locker() -> void:
	if _locker_queue.is_empty():
		state = State.WANDER
		_wait = 1.0
		return
	_checking = _locker_queue.pop_front()
	state = State.CHECK_LOCKER
	_wait = 3.2
	_go_to(_checking.front_pos())
	sector.on_locker_checked(_checking)


func _follow(speed: float, delta: float) -> void:
	if path.is_empty():
		return
	var target: Vector3 = sector.cell_to_world(path[0])
	var to := target - global_position
	to.y = 0.0
	var step := speed * delta
	if to.length() <= step:
		global_position = Vector3(target.x, global_position.y, target.z)
		path.remove_at(0)
		if not path.is_empty():
			sector.monster_entering(path[0])
		elif state == State.CHECK_LOCKER and _checking:
			_checking.rattle()
		return
	global_position += to.normalized() * step
	_face(target, delta)


func _face(target: Vector3, delta: float) -> void:
	var to := target - global_position
	if Vector2(to.x, to.z).length() < 0.01:
		return
	var want := atan2(to.x, to.z)
	rotation.y = lerp_angle(rotation.y, want, minf(delta * 6.0, 1.0))
