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
var _torch: Node3D          # the flashlight in your left hand
var _spill: OmniLight3D
var body: Node3D            # you, as other people would see you (only in cutscenes)
var _hand_id := ""
var frozen := false
var noise := 0.0           # how loud you are right now (metres the sound carries)
var _gasp_lock := 0.0
var _step_t := 0.0
var _noise_t := 0.0
var _bob := 0.0
var _breath_t := 0.0
var _outer: SpotLight3D      # the flashlight's faint outer spill
var _eye := 1.6
var _exhausted := false


func _ready() -> void:
	collision_layer = 4
	collision_mask = 1 | 8      # walls, and mannequins: you can't walk through them
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
	flashlight.spot_angle_attenuation = 4.0   # a bright centre that fades softly at the edges
	# A wide, faint outer spill around the beam (a child, so it switches with it).
	_outer = SpotLight3D.new()
	_outer.spot_angle = 50.0
	_outer.spot_range = 9.0
	_outer.spot_angle_attenuation = 2.0
	_outer.light_energy = 0.3
	_outer.light_color = Color(1.0, 0.95, 0.85)
	flashlight.add_child(_outer)
	flashlight.light_energy = 3.0
	flashlight.light_color = Color(1.0, 0.95, 0.85)
	flashlight.shadow_enabled = Game.gfx() >= 1
	# The flashlight is in your left hand.
	var torch := Node3D.new()
	_torch = torch
	torch.position = Vector3(-0.45, -0.36, -0.6)
	torch.rotation = Vector3(0.05, 0.08, 0)
	cam.add_child(torch)
	# A real flashlight model (Poly Haven, CC0), lens pointing forward.
	var torch_model := Items.real_model("small_plastic_torch", Vector3(0, PI, 0))
	if torch_model:
		torch_model.position = Vector3(0, -0.03, 0.04)
		torch.add_child(torch_model)
	flashlight.position = Vector3(-0.45, -0.36, -0.76)
	cam.add_child(flashlight)
	# Aim the beam (and the flashlight in your hand) at the crosshair, about
	# 10 m ahead, instead of straight out from your hand.
	var aim := (Vector3(0, 0, -10.0) - flashlight.position).normalized()
	flashlight.basis = Basis.looking_at(aim, Vector3.UP)
	torch.basis = Basis.looking_at((Vector3(0, 0, -10.0) - torch.position).normalized(), Vector3.UP)
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
	_spill = spill
	body = _build_body()
	body.visible = false
	add_child(body)
	ray = RayCast3D.new()
	ray.target_position = Vector3(0, 0, -2.4)
	ray.collision_mask = 3
	ray.exclude_parent = true
	cam.add_child(ray)


## You, from the outside: a kid in a hoodie and jeans with a flashlight.
## Faceless from behind the hood. Only seen in the elevator cutscene.
func _build_body() -> Node3D:
	var root := Node3D.new()
	var hoodie := Items._m(Color(0.16, 0.2, 0.17), 0.9)
	var jeans := Items._m(Color(0.12, 0.15, 0.24), 0.85)
	var shoe := Items._m(Color(0.75, 0.75, 0.72), 0.7)
	var skin := Items._m(Color(0.78, 0.6, 0.48), 0.6)
	var dark := Items._m(Color(0.03, 0.03, 0.03), 0.9)
	for side in [-1.0, 1.0]:
		root.add_child(_cap(0.085, 0.85, jeans, Vector3(0.1 * side, 0.47, 0)))
		root.add_child(Items._box(Vector3(0.11, 0.08, 0.26), shoe, Vector3(0.1 * side, 0.04, -0.04)))
	root.add_child(_cap(0.2, 0.68, hoodie, Vector3(0, 1.17, 0), Vector3(0.75, 1.0, 0.6)))
	# Arms: the left holds the flashlight, pointing forward and down.
	var l_arm := Node3D.new()
	l_arm.position = Vector3(-0.22, 1.4, 0)
	l_arm.rotation = Vector3(0.9, 0, -0.1)
	root.add_child(l_arm)
	l_arm.add_child(_cap(0.06, 0.6, hoodie, Vector3(0, -0.27, 0)))
	l_arm.add_child(_cap(0.045, 0.1, skin, Vector3(0, -0.58, 0)))
	var lamp := Items.real_model("small_plastic_torch", Vector3(-PI / 2.0, 0, 0))
	if lamp:
		lamp.position = Vector3(0, -0.66, -0.02)
		l_arm.add_child(lamp)
	var r_arm := Node3D.new()
	r_arm.position = Vector3(0.22, 1.4, 0)
	r_arm.rotation = Vector3(0.15, 0, 0.12)
	root.add_child(r_arm)
	r_arm.add_child(_cap(0.06, 0.6, hoodie, Vector3(0, -0.27, 0)))
	r_arm.add_child(_cap(0.045, 0.1, skin, Vector3(0, -0.58, 0)))
	# Head in a hood: a face in shadow.
	var head := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = 0.11
	hm.height = 0.25
	head.mesh = hm
	head.material_override = skin
	head.position = Vector3(0, 1.64, -0.02)
	root.add_child(head)
	var hood := MeshInstance3D.new()
	var hd := SphereMesh.new()
	hd.radius = 0.145
	hd.height = 0.32
	hood.mesh = hd
	hood.material_override = hoodie
	hood.position = Vector3(0, 1.66, 0.035)
	hood.scale = Vector3(1.0, 1.0, 0.95)
	root.add_child(hood)
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var em := SphereMesh.new()
		em.radius = 0.013
		em.height = 0.02
		eye.mesh = em
		eye.material_override = dark
		eye.position = Vector3(0.04 * side, 1.66, -0.12)
		root.add_child(eye)
	return root


func _cap(r: float, h: float, mat: Material, pos: Vector3, scl := Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = r
	cm.height = h
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	mi.scale = scl
	return mi


## Hide (or bring back) your hands and flashlight, but stay in first person.
func set_view_only(on: bool) -> void:
	_torch.visible = not on
	_hand.visible = not on
	_spill.visible = not on
	if on:
		flashlight.visible = false


## Put the camera back at eye height, level, after a catch scene.
func reset_view() -> void:
	_eye = 1.6
	cam.position = Vector3(0, _eye, 0)
	cam.rotation = Vector3.ZERO
	cam.h_offset = 0.0
	cam.v_offset = 0.0
	flashlight.visible = battery > 1.0
	_apply_look()


## Cutscene: hide your first-person hands and show your body instead.
func set_cutscene(on: bool) -> void:
	_torch.visible = not on
	_hand.visible = not on
	_spill.visible = not on
	flashlight.visible = false if on else flashlight.visible
	body.visible = on


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
	# Standing still, you breathe: a slow rise and fall, and a slight lean.
	_breath_t += delta * (1.6 if stamina > 60.0 else 2.6)
	var still := 1.0 - minf(hspeed / 0.6, 1.0)
	cam.position.y += sin(_breath_t) * 0.008 * still
	cam.rotation.z = sin(_breath_t * 0.5) * 0.004 * still

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
		# A weak battery means a shorter, dimmer, yellower beam, and below 20%
		# it starts to waver and drop out for a moment now and then.
		var charge := clampf(battery / 60.0, 0.0, 1.0)
		var energy := lerpf(1.5, 3.0, charge)
		flashlight.spot_range = lerpf(11.0, 20.0, charge)
		flashlight.light_color = Color(1.0, 0.95, 0.85).lerp(Color(1.0, 0.78, 0.5), 1.0 - charge)
		if battery < 20.0:
			energy *= 0.85 + 0.15 * sin(Time.get_ticks_msec() * 0.023)
			if randf() < 0.05 * delta * 60.0 * (1.0 - battery / 20.0):
				energy *= 0.2
		flashlight.light_energy = energy
		_outer.light_energy = energy * 0.1
		_outer.light_color = flashlight.light_color
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
