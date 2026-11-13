extends StaticBody3D
## A signal relay (Sector 3). Pick it up with E, put it down with E, and turn
## it with R. Any signal beam that reaches it goes back out the way its arrow
## points. If two different colours reach it at once, it jams.

const DIRS := [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]  # E, S, W, N

var sector: Node
var item_name := "relay"
var cell := Vector2i.ZERO
var home_cell := Vector2i.ZERO
var facing := 0              # index into DIRS
var _ring_mat: StandardMaterial3D
var _arrow: Node3D
var _shape: CollisionShape3D


func setup(s: Node, c: Vector2i) -> void:
	sector = s
	cell = c
	home_cell = c
	collision_layer = 3
	collision_mask = 0
	set_meta("surface", "metal")
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.55, 0.57, 0.6)
	metal.metallic = 0.7
	metal.roughness = 0.35
	var base := MeshInstance3D.new()
	var bm := CylinderMesh.new()
	bm.top_radius = 0.25
	bm.bottom_radius = 0.32
	bm.height = 0.15
	base.mesh = bm
	base.material_override = metal
	base.position.y = 0.075
	add_child(base)
	var pole := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.04
	pm.bottom_radius = 0.04
	pm.height = 0.8
	pole.mesh = pm
	pole.material_override = metal
	pole.position.y = 0.5
	add_child(pole)
	# The arrow (and dish) point where the signal will go.
	_arrow = Node3D.new()
	_arrow.position.y = 1.0
	add_child(_arrow)
	var dish := MeshInstance3D.new()
	var dm := SphereMesh.new()
	dm.radius = 0.3
	dm.height = 0.25
	dish.mesh = dm
	dish.material_override = metal
	dish.rotation.x = PI / 2.0
	dish.position.z = -0.05
	_arrow.add_child(dish)
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.albedo_color = Color(0.2, 0.2, 0.25)
	_ring_mat.emission_enabled = true
	_ring_mat.emission = Color(0.2, 0.2, 0.25)
	var ring := MeshInstance3D.new()
	var rm := TorusMesh.new()
	rm.inner_radius = 0.24
	rm.outer_radius = 0.3
	ring.mesh = rm
	ring.material_override = _ring_mat
	ring.rotation.x = PI / 2.0
	ring.position.z = 0.02
	_arrow.add_child(ring)
	var tip := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.1
	cone.height = 0.3
	tip.mesh = cone
	var tip_mat := StandardMaterial3D.new()
	tip_mat.albedo_color = Color(1.0, 0.85, 0.3)
	tip_mat.emission_enabled = true
	tip_mat.emission = Color(1.0, 0.85, 0.3)
	tip_mat.emission_energy_multiplier = 1.5
	tip.mesh = cone
	tip.material_override = tip_mat
	tip.rotation.x = PI / 2.0
	tip.position.z = 0.32
	_arrow.add_child(tip)
	_shape = CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.6, 1.3, 0.6)
	_shape.shape = box
	_shape.position.y = 0.65
	add_child(_shape)
	_apply_facing()


func dir() -> Vector2i:
	return DIRS[facing]


func set_facing(i: int) -> void:
	facing = posmod(i, 4)
	_apply_facing()


func _apply_facing() -> void:
	var d: Vector2i = DIRS[facing]
	_arrow.rotation.y = atan2(float(d.x), float(d.y))


## Show which colour is going through it (or that it's jammed).
func show_signal(color: Color, jammed: bool) -> void:
	var c := Color(1.0, 0.3, 0.9) if jammed else color
	_ring_mat.albedo_color = c
	_ring_mat.emission = c
	_ring_mat.emission_energy_multiplier = 2.5 if color != Color.BLACK or jammed else 0.3


func prompt() -> String:
	return "Pick up relay      [R] turn it"


func interact(_player: Node) -> void:
	sector.pick_up(self)


func turn() -> void:
	set_facing(facing + 1)
	Sound.play_at("click", global_position, -4.0)
	sector._on_carry_changed()


func set_carried(on: bool) -> void:
	_shape.set_deferred("disabled", on)
