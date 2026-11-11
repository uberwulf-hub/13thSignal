extends Node3D
## THE REPLACEMENT. Looks like an ordinary scientist mannequin.
## It only moves when you can't see it. Keep your light on it.
## (In Explorer mode it creeps closer but never catches you.)

const SPEED := 5.0

var sector: Node
var active := false
var path: Array[Vector2i] = []
var _repath_t := 0.0
var _creak_t := 0.0
var _home := Vector3.ZERO


## The mannequin itself. Also used for one scripted scare.
## A real mannequin model, if one has been added to the project (any
## CC0 glTF/GLB of a human figure). Otherwise a mannequin is built from shapes.
const MODEL_PATH := "res://assets/models/mannequin.glb"
const HEIGHT := 1.85


static func _plastic() -> StandardMaterial3D:
	# Glossy, slightly yellowed store-mannequin plastic.
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.78, 0.75, 0.7)
	m.roughness = 0.28
	m.clearcoat_enabled = true
	m.clearcoat = 0.6
	m.clearcoat_roughness = 0.25
	m.rim_enabled = true
	m.rim = 0.25
	return m


static func build_model() -> Node3D:
	if ResourceLoader.exists(MODEL_PATH):
		return _imported_model()
	return _shape_model()


## The imported mannequin, scaled to a person's height and given the plastic look.
static func _imported_model() -> Node3D:
	var root := Node3D.new()
	var scene: Node3D = (load(MODEL_PATH) as PackedScene).instantiate()
	root.add_child(scene)
	var plastic := _plastic()
	var box := AABB()
	var first := true
	for mi in scene.find_children("*", "MeshInstance3D", true, false):
		var m: MeshInstance3D = mi
		m.material_override = plastic
		var b: AABB = m.get_aabb()
		b = m.transform * b
		box = b if first else box.merge(b)
		first = false
	if box.size.y > 0.01:
		var k := HEIGHT / box.size.y
		scene.scale = Vector3.ONE * k
		scene.position.y = -box.position.y * k
	root.set_meta("arms", [])
	root.set_meta("head", null)
	root.set_meta("body", scene)
	return root


## A faceless store mannequin built from smooth shapes, with joints for posing.
static func _shape_model() -> Node3D:
	var root := Node3D.new()
	var plastic := _plastic()
	var seam := StandardMaterial3D.new()
	seam.albedo_color = Color(0.45, 0.43, 0.4)
	seam.roughness = 0.5
	# Legs: thigh, knee joint, shin, foot.
	for side in [-1.0, 1.0]:
		var x: float = 0.11 * side
		root.add_child(_shape("capsule", Vector3(0.085, 0.5, 0.085), Vector3(x, 0.74, 0), Vector3(0, 0, 0.03 * side), plastic))
		root.add_child(_shape("sphere", Vector3(0.068, 0.068, 0.068), Vector3(x, 0.5, 0.01), Vector3.ZERO, seam))
		root.add_child(_shape("capsule", Vector3(0.062, 0.46, 0.062), Vector3(x, 0.27, 0), Vector3.ZERO, plastic))
		root.add_child(_shape("sphere", Vector3(0.06, 0.04, 0.13), Vector3(x, 0.035, 0.05), Vector3.ZERO, plastic))
	# Hips, waist, chest and shoulders.
	root.add_child(_shape("sphere", Vector3(0.2, 0.14, 0.13), Vector3(0, 0.98, 0), Vector3.ZERO, plastic))
	root.add_child(_shape("capsule", Vector3(0.14, 0.32, 0.1), Vector3(0, 1.14, 0), Vector3.ZERO, plastic))
	root.add_child(_shape("sphere", Vector3(0.21, 0.2, 0.13), Vector3(0, 1.36, 0.01), Vector3.ZERO, plastic))
	root.add_child(_shape("capsule", Vector3(0.07, 0.48, 0.07), Vector3(0, 1.47, 0), Vector3(0, 0, PI / 2.0), plastic))
	# Arms on shoulder pivots, with an elbow joint and flat hands, so it can
	# be found in a different pose every time you look back.
	var arms: Array = []
	for side in [-1.0, 1.0]:
		var shoulder := Node3D.new()
		shoulder.position = Vector3(0.25 * side, 1.47, 0)
		root.add_child(shoulder)
		shoulder.add_child(_shape("sphere", Vector3(0.06, 0.06, 0.06), Vector3.ZERO, Vector3.ZERO, seam))
		shoulder.add_child(_shape("capsule", Vector3(0.05, 0.32, 0.05), Vector3(0.02 * side, -0.17, 0), Vector3(0, 0, 0.06 * side), plastic))
		shoulder.add_child(_shape("sphere", Vector3(0.045, 0.045, 0.045), Vector3(0.03 * side, -0.33, 0), Vector3.ZERO, seam))
		shoulder.add_child(_shape("capsule", Vector3(0.042, 0.3, 0.042), Vector3(0.035 * side, -0.49, 0.01), Vector3.ZERO, plastic))
		shoulder.add_child(_shape("sphere", Vector3(0.045, 0.09, 0.022), Vector3(0.035 * side, -0.69, 0.01), Vector3.ZERO, plastic))
		arms.append(shoulder)
	# Neck and a smooth, egg-shaped head with no face at all. Just a hint of a
	# nose and brow, the way store mannequins have.
	var neck := Node3D.new()
	neck.position = Vector3(0, 1.56, 0)
	root.add_child(neck)
	neck.add_child(_shape("capsule", Vector3(0.045, 0.14, 0.045), Vector3(0, 0.04, 0), Vector3.ZERO, plastic))
	neck.add_child(_shape("sphere", Vector3(0.095, 0.125, 0.11), Vector3(0, 0.2, 0.01), Vector3(-0.12, 0, 0), plastic))
	neck.add_child(_shape("sphere", Vector3(0.016, 0.03, 0.02), Vector3(0, 0.19, 0.115), Vector3(-0.3, 0, 0), plastic))
	neck.add_child(_shape("capsule", Vector3(0.012, 0.11, 0.012), Vector3(0, 0.235, 0.098), Vector3(0, 0, PI / 2.0), plastic))
	root.set_meta("arms", arms)
	root.set_meta("head", neck)
	return root


## A smooth ellipsoid ("sphere") or capsule, stretched to `size` (radii).
static func _shape(kind: String, size: Vector3, pos: Vector3, rot: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	if kind == "sphere":
		var sm := SphereMesh.new()
		sm.radius = 1.0
		sm.height = 2.0
		mi.mesh = sm
		mi.scale = size
	else:
		var c := CapsuleMesh.new()
		c.radius = size.x
		c.height = size.y
		mi.mesh = c
		mi.scale = Vector3(1, 1, size.z / size.x)
	mi.position = pos
	mi.rotation = rot
	mi.material_override = mat
	return mi


static func _part(kind: String, dims: Vector2, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	if kind == "sphere":
		var sm := SphereMesh.new()
		sm.radius = dims.x
		sm.height = dims.y
		mi.mesh = sm
	else:
		var c := CapsuleMesh.new()
		c.radius = dims.x
		c.height = dims.y
		mi.mesh = c
	mi.position = pos
	mi.material_override = mat
	return mi


## Poses it can be found in: [left arm (x, z), right arm (x, z), head (x, y, z)].
const POSES := [
	[Vector2(0, 0), Vector2(0, 0), Vector3(0, 0, 0.45)],                 # head tilted
	[Vector2(0, 0), Vector2(0, 0), Vector3(0.2, 0, -0.5)],
	[Vector2(-1.5, 0), Vector2(-1.5, 0), Vector3(-0.15, 0, 0)],          # both arms reaching for you
	[Vector2(-1.5, 0.15), Vector2(0, 0), Vector3(0, 0, 0.6)],            # one arm reaching, head tilted
	[Vector2(0, 0), Vector2(-2.8, 0), Vector3(0, 0, 0)],                 # one arm raised high
	[Vector2(-0.4, 0), Vector2(-0.4, 0), Vector3(0, 1.4, 0)],            # head turned to the side
	[Vector2(-1.2, -0.6), Vector2(-1.2, 0.6), Vector3(0.45, 0, 0)],      # arms spread, head bowed
]

var _model: Node3D
var _unseen := false


func setup(s: Node) -> void:
	sector = s
	_model = build_model()
	add_child(_model)
	_home = global_position


func reset_to(pos: Vector3) -> void:
	global_position = pos
	path.clear()


func _physics_process(delta: float) -> void:
	if not active or sector == null or sector.paused_world:
		return
	var player: Node = sector.player
	if player.frozen:
		return
	var head := global_position + Vector3(0, 1.6, 0)
	var chest := global_position + Vector3(0, 1.0, 0)
	if player.can_see(head) or player.can_see(chest):
		_unseen = false
		return   # Frozen while watched.
	if not _unseen:
		# You looked away: when you look back, it won't be standing the same way.
		_unseen = true
		_new_pose()
	var hunts: bool = Game.mode_data()["replacement_hunts"]
	var to_player: Vector3 = player.global_position - global_position
	to_player.y = 0.0
	var dist := to_player.length()
	# Always turn to face you when you're not looking.
	rotation.y = atan2(to_player.x, to_player.z)
	if not hunts and dist < 5.0:
		return   # Explorer: it only creeps closer, it never catches you.
	_repath_t -= delta
	if _repath_t <= 0.0 or path.is_empty():
		_repath_t = 0.6
		path = sector.find_path(global_position, player.global_position)
	if path.is_empty():
		return
	var speed := SPEED * float(Game.mode_data()["listener_speed"])
	var target: Vector3 = sector.cell_to_world(path[0])
	if path.size() == 1:
		target = player.global_position
	var to := target - global_position
	to.y = 0.0
	var step := speed * delta
	if to.length() <= step:
		global_position = Vector3(target.x, global_position.y, target.z)
		path.remove_at(0)
		if not path.is_empty():
			sector.monster_entering(path[0])
	else:
		global_position += to.normalized() * step
	_creak_t -= delta
	if _creak_t <= 0.0 and dist < 16.0:
		_creak_t = randf_range(0.6, 1.2)
		Sound.play_at("creak", global_position + Vector3(0, 1, 0), -2.0, randf_range(0.8, 1.2))
	if hunts and dist < 1.25 and not player.hidden_in:
		sector.on_caught("replacement")


func _new_pose() -> void:
	# Explorer only ever gets the gentle head tilts.
	var choices := 2 if Game.is_explorer() else POSES.size()
	var pose: Array = POSES[randi() % choices]
	var arms: Array = _model.get_meta("arms")
	if arms.is_empty():
		# An imported model can't bend: it leans and turns a little instead.
		var body: Node3D = _model.get_meta("body")
		body.rotation = Vector3(randf_range(-0.12, 0.12), randf_range(-0.6, 0.6), randf_range(-0.15, 0.15))
		return
	for i in 2:
		var arm: Node3D = arms[i]
		var r: Vector2 = pose[i]
		arm.rotation = Vector3(r.x, 0, r.y)
	var head: Node3D = _model.get_meta("head")
	head.rotation = pose[2]
