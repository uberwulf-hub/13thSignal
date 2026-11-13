extends StaticBody3D
## A portable signal jammer (Sector 4). Pick it up with E and put it down with
## E. While it's ON THE FLOOR it jams everything on its own square and the 8
## squares around it (the glowing purple square shows the area):
##   - laser grids switch off, so you can walk through,
##   - security cameras go dark,
##   - your footsteps make no sound,
##   - ECHO can't step into it.
## While you're carrying it, it does nothing. You can walk over it.

var sector: Node
var item_name := "jammer"
var cell := Vector2i.ZERO
var home_cell := Vector2i.ZERO
var _field: MeshInstance3D
var _field_mat: StandardMaterial3D
var _led_mat: StandardMaterial3D
var _shape: CollisionShape3D
var _hum: AudioStreamPlayer3D
var _carried := false
var _t := 0.0


func setup(s: Node, c: Vector2i) -> void:
	sector = s
	cell = c
	home_cell = c
	# Layer 2 only: you can aim at it to pick it up, but you walk straight over it.
	collision_layer = 2
	collision_mask = 0
	set_meta("surface", "metal")
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.18, 0.16, 0.22)
	body_mat.metallic = 0.6
	body_mat.roughness = 0.4
	var case := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.5, 0.3, 0.4)
	case.mesh = bm
	case.material_override = body_mat
	case.position.y = 0.15
	add_child(case)
	var antenna := MeshInstance3D.new()
	var am := CylinderMesh.new()
	am.top_radius = 0.015
	am.bottom_radius = 0.025
	am.height = 0.7
	antenna.mesh = am
	antenna.material_override = body_mat
	antenna.position = Vector3(0.15, 0.65, 0.1)
	add_child(antenna)
	_led_mat = StandardMaterial3D.new()
	_led_mat.albedo_color = Color(0.75, 0.4, 1.0)
	_led_mat.emission_enabled = true
	_led_mat.emission = Color(0.75, 0.4, 1.0)
	var led := MeshInstance3D.new()
	var lm := SphereMesh.new()
	lm.radius = 0.05
	lm.height = 0.1
	led.mesh = lm
	led.material_override = _led_mat
	led.position = Vector3(0.15, 1.02, 0.1)
	add_child(led)
	# The area it jams: its square and the 8 around it.
	_field = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(9.0, 9.0)
	_field.mesh = pm
	_field_mat = StandardMaterial3D.new()
	_field_mat.albedo_color = Color(0.6, 0.3, 1.0, 0.12)
	_field_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_field_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_field_mat.emission_enabled = true
	_field_mat.emission = Color(0.6, 0.3, 1.0)
	_field.material_override = _field_mat
	_field.position.y = 0.05
	add_child(_field)
	_shape = CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.7, 1.1, 0.7)
	_shape.shape = box
	_shape.position.y = 0.55
	add_child(_shape)
	_hum = AudioStreamPlayer3D.new()
	_hum.stream = Sound.stream("jam_hum")
	_hum.unit_size = 1.5
	_hum.max_distance = 10.0
	_hum.volume_db = -10.0
	_hum.bus = Sound.WORLD
	add_child(_hum)
	_hum.play()


func is_on() -> bool:
	return not _carried


func prompt() -> String:
	return "Pick up jammer"


func interact(_player: Node) -> void:
	sector.pick_up(self)


func set_carried(on: bool) -> void:
	_carried = on
	_shape.set_deferred("disabled", on)
	_field.visible = not on
	if on:
		_hum.stop()
	else:
		_hum.play()


func _process(delta: float) -> void:
	_t += delta
	var pulse := 0.5 + 0.5 * sin(_t * 4.0)
	_led_mat.emission_energy_multiplier = (1.0 + pulse * 3.0) if not _carried else 0.3
	_field_mat.albedo_color.a = 0.08 + pulse * 0.08
