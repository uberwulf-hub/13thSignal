extends CharacterBody3D
## You. First-person movement, the flashlight, hiding in lockers and holding
## your breath. Everything you do makes some amount of NOISE, and the Listener
## hunts by noise.

const WALK := 3.2
const SPRINT := 5.6
const CROUCH := 1.6
const STAND_H := 1.8
const CROUCH_H := 1.0

var sector: Node
var cam: Camera3D
var flashlight: SpotLight3D
var ray: RayCast3D
var capsule: CapsuleShape3D
var shape: CollisionShape3D

var yaw := 0.0
var pitch := 0.0
var crouching := false
var sprinting := false
var stamina := 100.0
var battery := 100.0
var breath := 100.0
var holding_breath := false
var hidden_in: Node = null
var carrying: Node = null   # a relay you're holding (Sector 3)

# --- Inventory: six slots; the selected item is in your right hand ---
const Items := preload("res://scripts/items.gd")
const WorldItem := preload("res://scripts/world_item.gd")
const SLOTS := 6
var inventory: Array = []   # [{"id": String, "count": int}], at most SLOTS
var selected := 0
var _hand: Node3D           # holds the selected item's model
var _hand_id := ""
var frozen := false
var noise := 0.0           # how loud you are right now (metres the sound carries)
var _gasp_lock := 0.0
var _step_t := 0.0
var _noise_t := 0.0
var _bob := 0.0
var _eye := 1.6
var _exhausted := false


func _ready() -> void:
	collision_layer = 4
	collision_mask = 1
	floor_snap_length = 0.3
	capsule = CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = STAND_H
	shape = CollisionShape3D.new()
	shape.shape = capsule
	shape.position.y = STAND_H / 2.0
	add_child(shape)
	cam = Camera3D.new()
	cam.fov = 75.0
	cam.near = 0.05
	cam.position.y = _eye
	add_child(cam)
	flashlight = SpotLight3D.new()
	flashlight.spot_range = 20.0
	flashlight.spot_angle = 26.0
	flashlight.spot_attenuation = 0.8
	flashlight.light_energy = 3.0
	flashlight.light_color = Color(1.0, 0.95, 0.85)
	flashlight.shadow_enabled = Game.gfx() >= 1
	# The flashlight is in your left hand.
	var torch := Node3D.new()
	torch.position = Vector3(-0.45, -0.36, -0.6)
	torch.rotation = Vector3(0.05, 0.08, 0)
	cam.add_child(torch)
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.32, 0.33, 0.35)   # brushed grey metal
	body_mat.roughness = 0.3
	body_mat.metallic = 0.7
	var tube := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 0.024
	tm.bottom_radius = 0.02
	tm.height = 0.24
	tube.mesh = tm
	tube.material_override = body_mat
	tube.rotation.x = PI / 2.0
	torch.add_child(tube)
	var head := MeshInstance3D.new()
	var hm := CylinderMesh.new()
	hm.top_radius = 0.034
	hm.bottom_radius = 0.026
	hm.height = 0.06
	head.mesh = hm
	head.material_override = body_mat
	head.rotation.x = PI / 2.0
	head.position.z = -0.14
	torch.add_child(head)
	flashlight.position = Vector3(-0.45, -0.36, -0.76)
	cam.add_child(flashlight)
	# Your right hand holds the selected item.
	_hand = Node3D.new()
	_hand.position = Vector3(0.52, -0.34, -0.6)
	_hand.rotation = Vector3(0.25, -0.35, 0)
	cam.add_child(_hand)
	# A little light spilling back from the flashlight, so you can see your hands.
	var spill := OmniLight3D.new()
	spill.light_energy = 0.35
	spill.omni_range = 1.1
	spill.light_color = Color(1.0, 0.95, 0.85)
	spill.position = Vector3(0, -0.2, -0.35)
	cam.add_child(spill)
	ray = RayCast3D.new()
	ray.target_position = Vector3(0, 0, -2.4)
	ray.collision_mask = 3
	ray.exclude_parent = true
	cam.add_child(ray)


func look_at_yaw(y: float) -> void:
	yaw = y
	pitch = 0.0
	_apply_look()


func _apply_look() -> void:
	rotation.y = yaw
	cam.rotation.x = pitch


func _unhandled_input(event: InputEvent) -> void:
	if frozen or (Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not Game.use_touch()):
		return
	if event is InputEventMouseMotion and not Game.use_touch():
		var inv := -1.0 if Game.invert_y else 1.0
		yaw -= event.relative.x * Game.mouse_sensitivity * 0.01
		pitch -= event.relative.y * Game.mouse_sensitivity * 0.01 * inv
		pitch = clampf(pitch, -1.45, 1.45)
		_apply_look()
	elif event.is_action_pressed("flashlight"):
		if battery > 1.0:
			flashlight.visible = not flashlight.visible
			Sound.play("click", -12.0)
	elif event.is_action_pressed("interact"):
		if hidden_in:
			leave_locker()
		elif carrying:
			sector.try_place()
		else:
			var hit := ray.get_collider()
			if hit and hit.has_method("interact"):
				hit.interact(self)
	elif event.is_action_pressed("use_item") and not hidden_in and not carrying:
		use_item()
	elif event.is_action_pressed("drop_item") and not hidden_in:
		drop_item()
	elif event.is_action_pressed("item_next"):
		select_slot((selected + 1) % SLOTS)
	elif event.is_action_pressed("item_prev"):
		select_slot((selected + SLOTS - 1) % SLOTS)
	elif _slot_pressed(event) >= 0:
		select_slot(_slot_pressed(event))
	elif event.is_action_pressed("rotate"):
		if sector.on_rotate_pressed():
			pass
		elif carrying:
			sector.turn_carried()
		else:
			var hit := ray.get_collider()
			if hit and hit.has_method("turn"):
				hit.turn()


func _physics_process(delta: float) -> void:
	if frozen:
		noise = 0.0
		return
	_gamepad_look(delta)
	_update_battery(delta)
	if hidden_in:
		_update_breath(delta)
		noise = 0.0
		sector.hud.set_prompt("Leave locker" if not holding_breath else "")
		return
	breath = minf(breath + 30.0 * delta, 100.0)

	# Crouch (hold). You stay crouched if there's no room to stand up (vents).
	var want_crouch := Input.is_action_pressed("crouch")
	if want_crouch != crouching:
		if want_crouch or not test_move(global_transform, Vector3(0, STAND_H - CROUCH_H + 0.05, 0)):
			crouching = want_crouch
			capsule.height = CROUCH_H if crouching else STAND_H
			shape.position.y = capsule.height / 2.0

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var moving_input := input.length() > 0.1
	if stamina <= 0.0:
		_exhausted = true
	elif stamina > 30.0:
		_exhausted = false
	sprinting = Input.is_action_pressed("sprint") and moving_input and not crouching and not _exhausted
	var speed := CROUCH if crouching else (SPRINT if sprinting else WALK)
	var dir := (transform.basis * Vector3(input.x, 0, input.y))
	dir.y = 0.0
	if dir.length() > 1.0:
		dir = dir.normalized()
	var target := dir * speed
	var accel := 14.0 if moving_input else 18.0
	velocity.x = move_toward(velocity.x, target.x, accel * delta * speed)
	velocity.z = move_toward(velocity.z, target.z, accel * delta * speed)
	if not is_on_floor():
		velocity.y -= 20.0 * delta
	else:
		velocity.y = -0.5
	move_and_slide()

	# Stamina.
	if sprinting:
		stamina = maxf(stamina - 20.0 * delta, 0.0)
		Game.sprint_time += delta
		sector.note_sprint(global_position, delta)
	else:
		stamina = minf(stamina + 13.0 * delta, 100.0)

	# Noise: how far your footsteps carry.
	var hspeed := Vector2(velocity.x, velocity.z).length()
	var on_grate: bool = sector.is_grate(global_position)
	var loud := 0.0
	if hspeed > 0.6:
		if crouching:
			# Crouching is quieter, not silent. Once the Listener has learned
			# to hear you crawl, it's twice as loud.
			loud = 4.5 if on_grate else 2.2
			if Game.learned_crouch:
				loud *= 2.0
			Game.crouch_time += delta
			sector.note_crouch()
		elif sprinting:
			loud = 20.0 if on_grate else 12.0
		else:
			loud = 10.0 if on_grate else 4.5
	if loud > 0.0 and sector.noise_muffled(global_position):
		loud = 0.0   # inside a jammer's field: silent
	noise = lerpf(noise, loud, minf(delta * 8.0, 1.0))
	_noise_t -= delta
	if loud > 0.0 and _noise_t <= 0.0:
		_noise_t = 0.35
		sector.emit_noise(global_position, loud, true)

	# Footstep sounds and head bob.
	if hspeed > 0.6 and is_on_floor():
		_step_t -= delta * hspeed
		_bob += delta * hspeed * 2.4
		if _step_t <= 0.0:
			_step_t = 2.1
			var kind := "_soft" if crouching else ("_run" if sprinting else "")
			var vol := -12.0 if crouching else (-3.0 if sprinting else -8.0)
			Sound.play(("step_grate" if on_grate else "step") + kind, vol, randf_range(0.92, 1.08), true)
	var eye_target := 0.85 if crouching else 1.6
	_eye = lerpf(_eye, eye_target, minf(delta * 10.0, 1.0))
	var bob_amt := 0.05 if sprinting else 0.025
	cam.position.y = _eye + sin(_bob) * bob_amt * minf(hspeed, 1.0)

	# What am I looking at?
	if carrying:
		sector.hud.set_prompt(sector.carry_prompt())
		return
	var hit := ray.get_collider()
	if hit and hit.has_method("prompt"):
		sector.hud.set_prompt(hit.prompt())
	else:
		sector.hud.set_prompt("")


## Looking around by dragging a finger (touch screens).
func touch_look(rel: Vector2) -> void:
	if frozen:
		return
	var inv := -1.0 if Game.invert_y else 1.0
	yaw -= rel.x * Game.mouse_sensitivity * 0.012
	pitch -= rel.y * Game.mouse_sensitivity * 0.012 * inv
	pitch = clampf(pitch, -1.45, 1.45)
	_apply_look()


func _gamepad_look(delta: float) -> void:
	var look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if look.length() < 0.05:
		return
	var inv := -1.0 if Game.invert_y else 1.0
	yaw -= look.x * delta * 3.0 * Game.mouse_sensitivity * 4.0
	pitch -= look.y * delta * 2.2 * Game.mouse_sensitivity * 4.0 * inv
	pitch = clampf(pitch, -1.45, 1.45)
	_apply_look()


func _update_battery(delta: float) -> void:
	var m := Game.mode_data()
	if flashlight.visible:
		battery = maxf(battery - float(m["battery_drain"]) * delta, 0.0)
		if battery <= 0.0:
			flashlight.visible = false
		flashlight.light_energy = 3.0 if battery > 15.0 else (3.0 if randf() > 0.1 else 0.4)
	else:
		battery = minf(battery + 0.9 * delta, 100.0)


func _update_breath(delta: float) -> void:
	_gasp_lock = maxf(_gasp_lock - delta, 0.0)
	holding_breath = Input.is_action_pressed("hold_breath") and _gasp_lock <= 0.0 and breath > 0.0
	if holding_breath:
		breath = maxf(breath - float(Game.mode_data()["breath_drain"]) * delta, 0.0)
		if breath <= 0.0:
			# Ran out of air: a loud gasp the Listener can hear.
			holding_breath = false
			_gasp_lock = 2.0
			Sound.play("gasp", -2.0)
			sector.emit_noise(global_position, 9.0, true)
	else:
		breath = minf(breath + 22.0 * delta, 100.0)


# ------------------------------------------------------------------ lockers

func enter_locker(locker: Node) -> void:
	if carrying:
		sector.hud.toast("Put the relay down first.", 2.0)
		return
	hidden_in = locker
	locker.set_occupied(true)
	shape.set_deferred("disabled", true)
	velocity = Vector3.ZERO
	crouching = false
	capsule.height = STAND_H
	shape.position.y = STAND_H / 2.0
	global_position = locker.inside_pos()
	look_at_yaw(atan2(-locker.facing.x, -locker.facing.z))
	_eye = 1.6
	cam.position.y = _eye
	breath = 100.0
	Sound.play("locker", -6.0)
	sector.on_player_hid(locker)
	sector.hud.show_locker(true)


func leave_locker() -> void:
	if hidden_in == null:
		return
	var locker := hidden_in
	hidden_in = null
	holding_breath = false
	locker.set_occupied(false)
	global_position = locker.front_pos()
	shape.set_deferred("disabled", false)
	Sound.play("locker", -6.0)
	sector.emit_noise(global_position, 3.0, true)
	sector.hud.show_locker(false)


# ------------------------------------------------------------------- sight

## Can you see this point? Used by the Replacement (it only moves when you can't).
func can_see(point: Vector3) -> bool:
	if not cam.is_position_in_frustum(point):
		return false
	var from := cam.global_position
	var dist := from.distance_to(point)
	if dist > 26.0:
		return false
	var lit: bool = (flashlight.visible and dist < 20.0) or (sector.power_on and dist < 14.0) or dist < 5.0
	if not lit:
		return false
	var q := PhysicsRayQueryParameters3D.create(from, point, 1)
	q.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func eye_position() -> Vector3:
	return cam.global_position


# ================================================================ inventory

func _slot_pressed(event: InputEvent) -> int:
	for i in SLOTS:
		if event.is_action_pressed("slot_%d" % (i + 1)):
			return i
	return -1


## Put an item in your inventory (stacking with the same kind). False if full.
func add_item(id: String) -> bool:
	var info := Items.info(id)
	for slot in inventory:
		if slot["id"] == id and slot["count"] < int(info.get("stack", 1)):
			slot["count"] += 1
			_inventory_changed()
			sector.hud.toast("Picked up: " + info["name"], 1.8)
			return true
	if inventory.size() >= SLOTS:
		sector.hud.toast("Your pockets are full. Drop something (G) first.", 2.5)
		return false
	inventory.append({"id": id, "count": 1})
	if inventory.size() == 1:
		selected = 0
	_inventory_changed()
	sector.hud.toast("Picked up: %s   (%d to select it)" % [info["name"], inventory.size()], 2.5)
	return true


func selected_id() -> String:
	return inventory[selected]["id"] if selected < inventory.size() else ""


func select_slot(i: int) -> void:
	selected = clampi(i, 0, SLOTS - 1)
	Sound.play("click", -16.0, 1.3)
	_inventory_changed()


func _take_one() -> void:
	var slot: Dictionary = inventory[selected]
	slot["count"] -= 1
	if slot["count"] <= 0:
		inventory.remove_at(selected)
		selected = mini(selected, maxi(inventory.size() - 1, 0))
	_inventory_changed()


func _inventory_changed() -> void:
	sector.hud.set_hotbar(inventory, selected)
	var id := selected_id()
	if id == _hand_id:
		return
	_hand_id = id
	for c in _hand.get_children():
		c.queue_free()
	if id != "":
		var m := Items.model(id)
		m.scale = Vector3.ONE * 1.1
		_hand.add_child(m)


## Use the item in your hand: a battery goes in the flashlight, a glow stick
## is cracked and tossed, anything else is thrown (to make a noise somewhere
## else), and a photo or badge is looked at.
func use_item() -> void:
	var id := selected_id()
	if id == "" or frozen:
		return
	var info := Items.info(id)
	match info["kind"]:
		"battery":
			if battery >= 99.0:
				sector.hud.toast("Your flashlight is already full.", 1.8)
				return
			battery = minf(battery + 60.0, 100.0)
			Sound.play("battery_click", -6.0)
			sector.hud.toast("New battery in. Flashlight recharged.", 2.0)
			_take_one()
		"glow":
			Sound.play("glow_crack", -4.0)
			_throw(id, 5.0, true)
			_take_one()
		"throw":
			Sound.play("throw_whoosh", -8.0, randf_range(0.9, 1.1))
			_throw(id, 13.0, false)
			_take_one()
		"read":
			sector.hud.show_note(info["name"].to_upper(), info["text"])
			sector.hud.add_clue(info["name"] + ": " + info["text"])


## Drop the item in your hand at your feet (quietly).
func drop_item() -> void:
	var id := selected_id()
	if id == "":
		return
	var w := WorldItem.new()
	sector.add_child(w)
	w.setup(sector, id)
	var fwd := -global_transform.basis.z
	w.global_position = global_position + Vector3(fwd.x, 0, fwd.z).normalized() * 0.7 + Vector3(0, 0.3, 0)
	_take_one()


func _throw(id: String, speed: float, lit: bool) -> void:
	var w := WorldItem.new()
	sector.add_child(w)
	w.setup(sector, id, lit)
	w.thrown = true
	var fwd := -cam.global_transform.basis.z
	w.global_position = cam.global_position + fwd * 0.5 + cam.global_transform.basis.x * 0.2
	w.linear_velocity = fwd * speed + Vector3(0, 2.0, 0) + velocity * 0.5
	w.angular_velocity = Vector3(randf_range(-8, 8), randf_range(-8, 8), randf_range(-8, 8))
