extends StaticBody3D
## A sliding facility door. The player opens it with E (which makes noise);
## monsters open doors just by walking up to them. Doors close by themselves.
## kind: "door", "keycard" (needs the keycard) or "exit" (needs power + the code).

const S := 3.0
const H := 3.2

var sector: Node
var cell := Vector2i.ZERO
var kind := "door"
var is_open := false
var unlocked := false   # keycard/exit doors, once you've got past them
var stay_open := false
var panel: MeshInstance3D
var shape: CollisionShape3D
var display: Label3D    # the exit door's code-order screen
var vault_letter := ""  # "A", "B" or "C" for vault doors
var _close_t := 0.0
var _opened_by_player := false
var _tween: Tween
var _leaves: Array = []   # the elevator's two sliding doors
var _arrow: Label3D       # the lit "going down" arrow above the elevator
var _lamp: Array = []     # the work lamp over the elevator doors


## Put the elevator's lamp on the hall side (1 = +z, -1 = -z).
func set_hall_side(side: float) -> void:
	for n in _lamp:
		(n as Node3D).position.z = absf((n as Node3D).position.z) * side


const LEAF_H := 2.3


func setup(s: Node, c: Vector2i, along_x: bool, k: String) -> void:
	sector = s
	cell = c
	kind = k
	collision_layer = 3
	collision_mask = 0
	set_meta("surface", "metal")
	if not along_x:
		rotation.y = PI / 2.0
	if kind == "exit":
		_build_elevator_door()
	else:
		_build_panel()
	shape = CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(S, H, 0.3)
	shape.shape = box
	shape.position.y = H / 2.0
	add_child(shape)


func _build_panel() -> void:
	var colors := {"door": Color(0.22, 0.26, 0.3), "keycard": Color(0.35, 0.22, 0.12), "exit": Color(0.32, 0.3, 0.12), "vault": Color(0.2, 0.24, 0.22), "gate": Color(0.22, 0.18, 0.3)}
	var mat: StandardMaterial3D = Game.tex_mat("door", 0.5, colors[kind].lightened(0.55), 0.5)
	if mat == null:
		mat = StandardMaterial3D.new()
		mat.albedo_color = colors[kind]
		mat.metallic = 0.6
		mat.roughness = 0.45
	panel = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(S, H, 0.3)
	panel.mesh = bm
	panel.material_override = mat
	panel.position.y = H / 2.0
	add_child(panel)
	# A glowing stripe so doors are easy to spot in the dark.
	var stripe := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(S * 0.9, 0.08, 0.34)
	stripe.mesh = sm
	var smat := StandardMaterial3D.new()
	var glow := {"door": Color(0.3, 0.7, 1.0), "keycard": Color(1.0, 0.55, 0.1), "exit": Color(1.0, 0.9, 0.2), "vault": Color(0.4, 1.0, 0.6), "gate": Color(0.75, 0.45, 1.0)}
	smat.albedo_color = glow[kind]
	smat.emission_enabled = true
	smat.emission = glow[kind]
	smat.emission_energy_multiplier = 1.5
	stripe.material_override = smat
	stripe.position.y = 0.4
	panel.add_child(stripe)
	if kind != "door":
		var door_sign := Label3D.new()
		door_sign.text = {"keycard": "SECURITY\nKEYCARD ONLY", "exit": "SERVICE ELEVATOR", "vault": "VAULT " + vault_letter, "gate": "SIGNAL GATE"}[kind]
		door_sign.font_size = 48
		door_sign.pixel_size = 0.004
		door_sign.modulate = glow[kind]
		door_sign.position = Vector3(0, 0.75, 0.17)
		panel.add_child(door_sign)
		var back := door_sign.duplicate()
		back.position.z = -0.17
		back.rotation.y = PI
		panel.add_child(back)
	if kind == "exit":
		display = Label3D.new()
		display.font_size = 56
		display.pixel_size = 0.0045
		display.position = Vector3(0, -0.45, 0.17)
		display.modulate = Color(0.4, 0.4, 0.4)
		display.text = "- NO POWER -"
		panel.add_child(display)
		var display_back: Label3D = display.duplicate()
		display_back.position.z = -0.17
		display_back.rotation.y = PI
		panel.add_child(display_back)
		display.set_meta("twin", display_back)


## The service elevator: two brushed-steel doors that part in the middle,
## set in a heavy frame, with the sign, the code screen and a floor arrow
## in the header above them.
func _build_elevator_door() -> void:
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.58, 0.6, 0.62)
	steel.metallic = 0.9
	steel.roughness = 0.32
	steel.anisotropy_enabled = true
	steel.anisotropy = 0.6
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.12, 0.12, 0.13)
	dark.metallic = 0.6
	dark.roughness = 0.5
	var grime := Game.tex_mat("metal", 1.0, Color(0.5, 0.5, 0.48), 0.6)
	if grime == null:
		grime = dark
	# panel: a holder for the doors (left in place so other code can find it).
	panel = MeshInstance3D.new()
	add_child(panel)
	for side in [-1.0, 1.0]:
		var leaf := Node3D.new()
		leaf.position = Vector3(side * S / 4.0, 0, 0)
		panel.add_child(leaf)
		var slab := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(S / 2.0 - 0.02, LEAF_H, 0.12)
		slab.mesh = bm
		slab.material_override = steel
		slab.position.y = LEAF_H / 2.0
		leaf.add_child(slab)
		# Scuffed kick plate and a dirty seam where the doors meet.
		var kick := MeshInstance3D.new()
		var km := BoxMesh.new()
		km.size = Vector3(S / 2.0 - 0.06, 0.35, 0.14)
		kick.mesh = km
		kick.material_override = grime
		kick.position.y = 0.2
		leaf.add_child(kick)
		var seam := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(0.025, LEAF_H, 0.13)
		seam.mesh = sm
		seam.material_override = dark
		seam.position = Vector3(-side * (S / 4.0 - 0.02), LEAF_H / 2.0, 0)
		leaf.add_child(seam)
		_leaves.append(leaf)
	# The frame: posts, sill and the header above the doors.
	var frame: Array = [
		[Vector3(0.14, LEAF_H, 0.36), Vector3(-S / 2.0 + 0.07, LEAF_H / 2.0, 0)],
		[Vector3(0.14, LEAF_H, 0.36), Vector3(S / 2.0 - 0.07, LEAF_H / 2.0, 0)],
		[Vector3(S, H - LEAF_H, 0.36), Vector3(0, LEAF_H + (H - LEAF_H) / 2.0, 0)],
		[Vector3(S, 0.03, 0.4), Vector3(0, 0.015, 0)],
	]
	for f in frame:
		var mi := MeshInstance3D.new()
		var bm2 := BoxMesh.new()
		bm2.size = f[0]
		mi.mesh = bm2
		mi.material_override = grime if f[0].y > 0.5 else dark
		mi.position = f[1]
		add_child(mi)
	var hy := LEAF_H + (H - LEAF_H) / 2.0
	for face in [1.0, -1.0]:
		var sign := Label3D.new()
		sign.text = "SERVICE ELEVATOR"
		sign.font_size = 40
		sign.pixel_size = 0.0035
		sign.modulate = Color(1.0, 0.85, 0.3)
		sign.position = Vector3(0, hy + 0.33, 0.185 * face)
		sign.rotation.y = 0.0 if face > 0 else PI
		add_child(sign)
		var arrow := Label3D.new()
		arrow.text = "v"
		arrow.font_size = 90
		arrow.pixel_size = 0.004
		arrow.modulate = Color(0.25, 0.08, 0.05)
		arrow.position = Vector3(1.2 if face > 0 else -1.2, hy + 0.05, 0.185 * face)
		arrow.rotation.y = 0.0 if face > 0 else PI
		add_child(arrow)
		if face > 0:
			_arrow = arrow
		else:
			_arrow.set_meta("twin", arrow)
	# A caged work lamp over the doors, on the hall side, so you can find it.
	var lamp_light := OmniLight3D.new()
	lamp_light.light_color = Color(1.0, 0.75, 0.45)
	lamp_light.light_energy = 0.9
	lamp_light.omni_range = 5.5
	lamp_light.position = Vector3(-1.2, H - 0.1, 0.55)
	add_child(lamp_light)
	var bulb := MeshInstance3D.new()
	var bsm := SphereMesh.new()
	bsm.radius = 0.06
	bsm.height = 0.12
	bulb.mesh = bsm
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(1.0, 0.8, 0.5)
	bmat.emission_enabled = true
	bmat.emission = Color(1.0, 0.75, 0.45)
	bmat.emission_energy_multiplier = 4.0
	bulb.material_override = bmat
	bulb.position = Vector3(-1.2, H - 0.12, 0.3)
	add_child(bulb)
	var cage := MeshInstance3D.new()
	var ctm := TorusMesh.new()
	ctm.inner_radius = 0.075
	ctm.outer_radius = 0.09
	cage.mesh = ctm
	cage.material_override = dark
	cage.position = bulb.position
	cage.rotation.x = PI / 2.0
	add_child(cage)
	_lamp = [lamp_light, bulb, cage]
	display = Label3D.new()
	display.font_size = 52
	display.pixel_size = 0.0026
	display.position = Vector3(0, hy - 0.07, 0.185)
	display.modulate = Color(0.4, 0.4, 0.4)
	display.text = "- NO POWER -"
	add_child(display)
	var display_back: Label3D = display.duplicate()
	display_back.position = Vector3(0, hy - 0.07, -0.185)
	display_back.rotation.y = PI
	add_child(display_back)
	display.set_meta("twin", display_back)


## Slide the elevator's doors apart (open) or together. Also lights the arrow.
func _slide_leaves(open_it: bool, secs: float) -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	for i in _leaves.size():
		var side := -1.0 if i == 0 else 1.0
		var x := side * (S / 4.0 + (S / 2.0 - 0.18) if open_it else S / 4.0)
		_tween.tween_property(_leaves[i], "position:x", x, secs).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	var c := Color(1.0, 0.3, 0.15) if open_it else Color(0.25, 0.08, 0.05)
	_arrow.modulate = c
	_arrow.get_meta("twin").modulate = c


## The doors closing behind you at the end (the cutscene). Slow and heavy.
func close_elevator(secs: float) -> void:
	stay_open = true
	is_open = false
	Sound.play_at("elevator_doors", global_position + Vector3(0, 1.2, 0), -2.0)
	_slide_leaves(false, secs)


func set_display(text: String, color: Color) -> void:
	if display == null:
		return
	display.text = text
	display.modulate = color
	var twin: Label3D = display.get_meta("twin")
	twin.text = text
	twin.modulate = color


func prompt() -> String:
	if is_open:
		return ""
	match kind:
		"keycard":
			return "Open security door" if (unlocked or sector.has_keycard) else "Locked: security keycard needed"
		"exit":
			return sector.exit_prompt(self)
		"vault":
			return sector.vault_prompt(self)
		"gate":
			return sector.gate_prompt(self)
	return "Open door"


func interact(_player: Node) -> void:
	if is_open:
		return
	match kind:
		"keycard":
			if not unlocked:
				if not sector.has_keycard:
					Sound.play_at("locked", global_position, -2.0)
					sector.hud.toast("You need a security keycard.")
					return
				unlocked = true
				sector.unlock_cell(cell)
				Sound.play("pickup", -10.0)
		"exit":
			if not unlocked:
				sector.exit_interact(self)
				return
		"vault":
			if not unlocked:
				sector.vault_interact(self)
				return
		"gate":
			if not unlocked:
				sector.gate_interact(self)
				return
	open(true)


func open(noisy: bool) -> void:
	_close_t = 5.0
	if is_open:
		return
	is_open = true
	Sound.play_at("door", global_position, -4.0)
	if noisy:
		# Heavy blast doors: opening one is a loud bang the Listener can hear.
		_opened_by_player = true
		Sound.play_at("bang", global_position + Vector3(0, 2, 0), -6.0, 1.4)
		sector.emit_noise(global_position, float(Game.mode_data()["door_noise"]), true)
	shape.set_deferred("disabled", true)
	if kind == "exit":
		Sound.play_at("elevator_ding", global_position + Vector3(0, 2.6, 0), -6.0)
		_slide_leaves(true, 1.6)
		return
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(panel, "position:y", H * 1.45, 0.6).set_trans(Tween.TRANS_SINE)


func close() -> void:
	if not is_open or stay_open:
		return
	is_open = false
	Sound.play_at("door", global_position, -8.0, 0.9)
	if _opened_by_player:
		# The clank as it shuts gives away where you just were.
		_opened_by_player = false
		sector.emit_noise(global_position, 9.0, false)
	shape.set_deferred("disabled", false)
	if kind == "exit":
		_slide_leaves(false, 1.4)
		return
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(panel, "position:y", H / 2.0, 0.6).set_trans(Tween.TRANS_SINE)


## Monsters open doors just by being next to them.
func monster_near() -> void:
	if kind == "door" or unlocked:
		open(false)


func _process(delta: float) -> void:
	if not is_open or stay_open:
		return
	_close_t -= delta
	if _close_t <= 0.0:
		if sector.anyone_near(global_position, 2.2):
			_close_t = 1.0
		else:
			close()
