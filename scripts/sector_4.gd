extends "res://scripts/sector.gd"
## SECTOR 4: SECURITY WING.
##
## Portable signal jammers. Put one down (E) and it jams its square and the 8
## around it: laser grids switch off, cameras go dark, your footsteps go
## silent, and ECHO can't step in. Carrying it, it does nothing.
##
## The escape route:
##   1. CHECKPOINT: a laser grid blocks the corridor north of the main hall.
##      The jammer in the hall, set down next to it, gets you into the ARMORY.
##   2. ARMORY: a second jammer, and a button that opens a shutter back to the
##      hall (so you can go back for the first jammer).
##   3. CAMERA HALL: a sweeping camera. Duck behind the pillars between sweeps,
##      or jam it. If a camera spots you, an alarm brings the Listener.
##   4. ELEVATOR WING: a laser grid watched by a second camera. One jammer can't
##      cover both, so you need both jammers here at once.
## Secrets: 3 signal fragments, one behind a low vent in the office.

## Map legend (on top of the base's):
##  j  jammer (starts here)   z  laser grid   C  security camera
##  H  shutter                y  shutter release button
const MAP_4 := [
	"###############################",
	"#....#.......#.......L.########",
	"#.P..#j.....y#.........#.....##",
	"#.i..#f......#....i....V....f##",
	"#....###.##H##.........#.....##",
	"#....###z##.##.........########",
	"##D#####.##.######D############",
	"#........gg.L.......i.........#",
	"#.....j..ggg............M.....#",
	"#........ggg.............L....#",
	"###############D###############",
	"##############.......#.......##",
	"##############....#.....#...C##",
	"##############L......#......f##",
	"###########################D###",
	"##############.EX...z........##",
	"##############..#...z.L..i..C##",
	"###############################",
]

const ROOMS_4 := [
	["ARRIVAL", Rect2i(1, 1, 4, 5)],
	["ARMORY", Rect2i(6, 1, 7, 3)],
	["CHECKPOINT", Rect2i(8, 4, 1, 3)],
	["OFFICE", Rect2i(14, 1, 9, 5)],
	["CRAWLSPACE", Rect2i(24, 2, 5, 3)],
	["MAIN HALL", Rect2i(1, 7, 29, 3)],
	["CAMERA HALL", Rect2i(14, 11, 15, 3)],
	["ELEVATOR WING", Rect2i(17, 15, 12, 2)],
	["ELEVATOR", Rect2i(14, 15, 2, 2)],
]

const FRAGMENT_TEXT_4 := [
	"\"The jammers were built to stop the signal. They only slow it down. Nothing stops it.\"",
	"\"Camera 7 recorded someone walking the halls at 3 a.m. Facial match: the person watching the footage.\"",
	"\"Thirteen sectors. Twelve on the map. The thirteenth is where the signal sleeps.\"",
]

const Jammer := preload("res://scripts/jammer.gd")

var jammers: Array = []
var lasers: Dictionary = {}     # cell -> {"body", "beams": Node3D, "on": bool}
var cameras: Array = []         # [{cell, pos, normal, pivot, spot, led, phase, amp, seen, cooldown, on}]
var shutter: Node
var _spotted_warned := false


func _configure() -> void:
	sector_id = 4
	sector_title = "SECTOR 4  -  SECURITY WING"
	next_scene = "res://scenes/sector_5.tscn"
	map = MAP_4
	rooms = ROOMS_4
	fragment_text = FRAGMENT_TEXT_4
	no_wander_rooms = ["CRAWLSPACE", "ELEVATOR", ""]
	echo_enabled = true


func _setup_puzzles() -> void:
	pass


func _solid_chars() -> Array:
	return ["#", "V", "K", "X", "z", "H"]


# ================================================================= objects

func _custom_cell(k: String, cell: Vector2i) -> void:
	var p := cell_to_world(cell)
	match k:
		"j":
			var jm := Jammer.new()
			add_child(jm)
			jm.position = p
			jm.setup(self, cell)
			jammers.append(jm)
			carryables.append(jm)
		"z":
			_spawn_laser(cell)
		"C":
			_spawn_camera(cell)
		"H":
			var d := Door.new()
			d.position = p
			add_child(d)
			d.setup(self, cell, true, "gate")
			doors[cell] = d
			shutter = d
		"y":
			_spawn_button(cell)


func _spawn_laser(cell: Vector2i) -> void:
	# Lasers run across the passage.
	var across_x := ch(cell + Vector2i(-1, 0)) == "#" or ch(cell + Vector2i(1, 0)) == "#"
	var p := cell_to_world(cell)
	var beams := Node3D.new()
	beams.position = p
	if not across_x:
		beams.rotation.y = PI / 2.0
	add_child(beams)
	var red := _glow(Color(1.0, 0.1, 0.08), 4.0)
	for i in 6:
		_box(Vector3(S, 0.025, 0.025), Vector3(0, 0.25 + i * 0.32, 0), red, beams)
	for x in [-S / 2.0 + 0.08, S / 2.0 - 0.08]:
		_box(Vector3(0.12, 2.1, 0.12), Vector3(x, 1.05, 0), _mat(Color(0.25, 0.25, 0.28), 0.4, 0.8), beams)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.15, 0.1)
	light.light_energy = 0.6
	light.omni_range = 3.0
	light.position.y = 1.0
	beams.add_child(light)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = p
	body.rotation.y = beams.rotation.y
	add_child(body)
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(S, WALL_H, 0.3)
	cs.shape = b
	cs.position.y = WALL_H / 2.0
	body.add_child(cs)
	lasers[cell] = {"shape": cs, "beams": beams, "on": true}


func _spawn_camera(cell: Vector2i) -> void:
	var wp := wall_point(cell, 2.7)
	var p: Vector3 = wp[0]
	var n: Vector3 = wp[1]
	var pivot := Node3D.new()
	pivot.position = p + n * 0.25
	pivot.rotation.y = atan2(n.x, n.z)
	add_child(pivot)
	_box(Vector3(0.12, 0.12, 0.3), p + n * 0.12, _mat(Color(0.3, 0.3, 0.32), 0.4, 0.8)).rotation.y = atan2(n.x, n.z)
	_box(Vector3(0.28, 0.24, 0.5), Vector3(0, 0, 0.1), _mat(Color(0.8, 0.8, 0.78), 0.4, 0.3), pivot)
	var lens := MeshInstance3D.new()
	var lm := CylinderMesh.new()
	lm.top_radius = 0.07
	lm.bottom_radius = 0.07
	lm.height = 0.05
	lens.mesh = lm
	lens.material_override = _glow(Color(0.05, 0.05, 0.08), 0.2)
	lens.rotation.x = PI / 2.0
	lens.position = Vector3(0, 0, 0.36)
	pivot.add_child(lens)
	var led_mat := _glow(Color(1.0, 0.1, 0.1), 3.0)
	_box(Vector3(0.04, 0.04, 0.04), Vector3(0.1, 0.1, 0.3), led_mat, pivot)
	var spot := SpotLight3D.new()
	spot.light_color = Color(1.0, 0.45, 0.3)
	spot.light_energy = 4.0
	spot.spot_range = 18.0
	spot.spot_angle = 16.0
	spot.position = Vector3(0, 0, 0.4)
	spot.rotation.y = PI          # SpotLight shines along -Z; turn it to face +Z
	pivot.add_child(spot)
	# A faint visible cone, so you can see where it's looking and time your run.
	var cone := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = tan(deg_to_rad(16.0)) * 12.0
	cm.bottom_radius = 0.02
	cm.height = 12.0
	cm.radial_segments = 24
	cone.mesh = cm
	var cone_mat := StandardMaterial3D.new()
	cone_mat.albedo_color = Color(1.0, 0.35, 0.25, 0.07)
	cone_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cone_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	cone_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cone_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	cone_mat.no_depth_test = false
	cone.material_override = cone_mat
	cone.rotation.x = PI / 2.0
	cone.position = Vector3(0, 0, 6.3)
	pivot.add_child(cone)
	cameras.append({"cell": cell, "pivot": pivot, "spot": spot, "cone": cone, "cone_mat": cone_mat, "led": led_mat, "base": atan2(n.x, n.z),
		"phase": randf() * TAU, "amp": 0.75 if room_at(cell) == "CAMERA HALL" else 0.35,
		"seen": 0.0, "cooldown": 0.0, "on": true, "beep": 0.0})


func _spawn_button(cell: Vector2i) -> void:
	var wp := wall_point(cell, 1.3)
	var p: Vector3 = wp[0]
	var n: Vector3 = wp[1]
	_box(Vector3(0.5, 0.6, 0.1), p + n * 0.05, _mat(Color(0.25, 0.25, 0.27), 0.5, 0.6)).rotation.y = atan2(n.x, n.z)
	var knob := _box(Vector3(0.2, 0.2, 0.08), p + n * 0.14, _glow(Color(1.0, 0.55, 0.1), 2.0))
	_label("SHUTTER", p + n * 0.12 + Vector3(0, 0.38, 0), n, 28, Color(1.0, 0.75, 0.3), 0.004)
	var it := Interactable.new()
	it.position = p + n * 0.25
	add_child(it)
	_shape_for(it, Vector3(0.6, 0.7, 0.3))
	it.prompt_text = "Open the shutter"
	it.on_use = func():
		if shutter.unlocked:
			return
		shutter.unlocked = true
		shutter.stay_open = true
		unlock_cell(shutter.cell)
		shutter.open(true)
		it.prompt_text = ""
		knob.material_override = _glow(Color(0.2, 1.0, 0.4), 2.0)
		Sound.play("key_ok", -4.0)
		hud.toast("The shutter to the main hall is open. Now you can go back for the other jammer.", 4.0)


# ================================================================= jamming

func _jammed(cell: Vector2i) -> bool:
	for jm in jammers:
		if jm.is_on() and maxi(absi(jm.cell.x - cell.x), absi(jm.cell.y - cell.y)) <= 1:
			return true
	return false


func noise_muffled(pos: Vector3) -> bool:
	return _jammed(world_to_cell(pos))


func echo_blocked(pos: Vector3) -> bool:
	return _jammed(world_to_cell(pos))


func _on_carry_changed() -> void:
	_update_jamming()


func _update_jamming() -> void:
	var pcell := world_to_cell(player.global_position) if player else Vector2i(-1, -1)
	for cell in lasers:
		var l: Dictionary = lasers[cell]
		var want_on := not _jammed(cell)
		if want_on == l["on"]:
			continue
		if want_on and cell == pcell:
			continue   # never switch a laser back on while you're standing in it
		l["on"] = want_on
		l["beams"].visible = want_on
		l["shape"].set_deferred("disabled", not want_on)
		grid.set_point_solid(cell, want_on)
		Sound.play_at("click" if want_on else "breaker", cell_to_world(cell) + Vector3(0, 1, 0), -6.0, 0.7 if want_on else 1.5)
	for cam in cameras:
		var on := not _jammed(cam["cell"])
		if on != cam["on"]:
			cam["on"] = on
			cam["spot"].visible = on
			cam["cone"].visible = on
			cam["led"].emission_energy_multiplier = 3.0 if on else 0.0
			cam["seen"] = 0.0


func _update_cameras(delta: float) -> void:
	var need: float = [1.8, 0.9, 0.6][Game.mode]
	for cam in cameras:
		cam["cooldown"] = maxf(cam["cooldown"] - delta, 0.0)
		if not cam["on"]:
			continue
		cam["phase"] += delta * 0.6
		var yaw: float = cam["base"] + sin(cam["phase"]) * cam["amp"]
		var pivot: Node3D = cam["pivot"]
		pivot.rotation = Vector3(0.28, yaw, 0)   # tilted to look down at the floor
		if _camera_sees_player(cam, yaw):
			cam["seen"] += delta
			cam["beep"] -= delta
			if cam["beep"] <= 0.0:
				cam["beep"] = 0.22
				Sound.play_at("cam_beep", pivot.global_position, -4.0, 1.0 + cam["seen"])
			cam["spot"].light_energy = 4.0 + cam["seen"] * 8.0
			cam["cone_mat"].albedo_color.a = 0.07 + cam["seen"] * 0.15
			if not _spotted_warned:
				_spotted_warned = true
				hud.toast("A CAMERA IS SPOTTING YOU! Get out of its light!", 3.0)
			if cam["seen"] >= need and cam["cooldown"] <= 0.0:
				_alarm(cam)
		else:
			cam["seen"] = maxf(cam["seen"] - delta * 2.0, 0.0)
			cam["spot"].light_energy = 4.0
			cam["cone_mat"].albedo_color.a = 0.07


func _camera_sees_player(cam: Dictionary, yaw: float) -> bool:
	if player.hidden_in or player.frozen or catching:
		return false
	var pcell := world_to_cell(player.global_position)
	var ccell: Vector2i = cam["cell"]
	if maxi(absi(pcell.x - ccell.x), absi(pcell.y - ccell.y)) <= 1:
		return false   # right underneath it: a blind spot
	var from: Vector3 = cam["pivot"].global_position
	var to: Vector3 = player.eye_position() - from
	if to.length() > 18.0:
		return false
	var look := Vector3(sin(yaw), 0, cos(yaw))
	var flat := Vector3(to.x, 0, to.z).normalized()
	if look.angle_to(flat) > deg_to_rad(16.0):
		return false
	var q := PhysicsRayQueryParameters3D.create(from + to.normalized() * 0.4, player.eye_position(), 1)
	q.exclude = [player.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _alarm(cam: Dictionary) -> void:
	cam["cooldown"] = 8.0
	cam["seen"] = 0.0
	Sound.play_at("alarm", cam["pivot"].global_position, 4.0)
	emit_noise(player.global_position, 14.0 if Game.is_explorer() else 30.0, false)
	hud.toast("SPOTTED! The alarm is going off - something is coming.", 4.0)
	if not Game.is_explorer():
		hud.say("echo", "There you are.")


# ================================================================= doors

func gate_prompt(_door: Node) -> String:
	return "Shutter: opened from inside the armory"


func gate_interact(door: Node) -> void:
	Sound.play_at("locked", door.global_position, -2.0)
	hud.toast("The shutter's release button is on the other side.")


func exit_prompt(door: Node) -> String:
	return "" if door.unlocked else "Open the elevator"


func exit_interact(door: Node) -> void:
	exit_open = true
	door.unlocked = true
	door.stay_open = true
	unlock_cell(door.cell)
	door.open(true)
	hud.set_objective("Get in the elevator!")
	hud.say("ai", "You made it through the security wing. I could not have done that.")
	hud.say("unknown", "neither could it. but it learned how, watching you.")


func _check_clues() -> void:
	pass


# =================================================================== story

func _intro() -> void:
	_update_jamming()
	hud.set_objective("Find a way through the security checkpoint (north of the main hall).")
	hud.add_clue("Jammers: put one down (E) and it switches off lasers and cameras on its square and the 8 around it.")
	hud.add_clue("Inside a jammer's field your footsteps are silent, and ECHO can't step in.")
	await get_tree().create_timer(1.6).timeout
	hud.say("ai", "Sector 4: the security wing. Laser grids, and cameras that sound the alarm.")
	hud.say("ai", "There are portable signal jammers down here. Set one down and it shuts off anything electronic right next to it.")
	hud.say("ai", "Its field also deadens sound, and ECHO cannot walk into it. While you carry it, it does nothing.")
	hud.say("unknown", "...it knows where you're going now.")


func _process(delta: float) -> void:
	super._process(delta)
	if ended or player == null:
		return
	_update_jamming()
	_update_cameras(delta)


func _entered_room(room: String) -> void:
	match room:
		"MAIN HALL":
			listener.set_physics_process(true)
			hud.say("ai", "The checkpoint is north of the hall. There is a jammer on the floor here.")
		"ARMORY":
			hud.set_objective("Take the second jammer. Open the shutter so you can fetch the first one.")
			hud.say("ai", "The armory. Another jammer, and the release for the shutter.")
		"CAMERA HALL":
			hud.set_objective("Get past the camera (bottom right door). Hide behind the pillars, or jam it.")
			hud.say("ai", "That camera sweeps the whole hall. Stay behind the pillars while it looks your way.")
		"ELEVATOR WING":
			hud.set_objective("A laser grid AND a camera guard the elevator. You need both jammers here.")
			hud.say("ai", "A grid and a camera. One jammer cannot cover both.")
		"CRAWLSPACE":
			hud.toast("A secret room!", 2.5)


func _end_story() -> String:
	return ("The jammers went quiet as the elevator dropped. For a moment, so did the signal.\n"
		+ "Then it came back louder, counting down from thirteen.\n\nSector 5 is waiting below.")
