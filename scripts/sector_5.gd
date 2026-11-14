extends "res://scripts/sector.gd"
## SECTOR 5: PLAYBACK LAB.
##
## Recorder booths. Press E at a booth to start recording, then move around and
## press R to stop. A green hologram copy of you replays exactly what you did,
## then stays standing where you finished. Its weight holds down PRESSURE
## PLATES, and each plate holds a door open. Only one copy exists at a time:
## a new recording replaces the old one.
##
##   PLAYBACK LAB 1: the plate is too far from its door to hold both yourself.
##   PLAYBACK LAB 2: two doors in a row, two plates. Your copy must stand on
##      the first plate long enough for you to get through, then move to the
##      second. (Timing!)
##   CONTROL ROOM: your copy must cross a field of loud grates to hold the
##      elevator's plate. Your copy makes YOUR noise: walk normally while
##      recording and the Listener will hear it, find it and erase it. Crouch.
##      (In Explorer the Listener leaves copies alone.)
## The labs are shielded: ECHO can't follow you in.

## Map legend (on top of the base's):
##  W  recorder booth   p  pressure plate   Y  plate door   H  shutter
const MAP_5 := [
	"################################",
	"#....#W.......#W...#############",
	"#.P..#........Y....Y.....Y.....#",
	"#i...#........#....###########.#",
	"#....#f......p#.p.p###########.#",
	"###D#####D####################.#",
	"#....L........i..............#.#",
	"#...................M........#.#",
	"#...................L........#.#",
	"########D###############H#####.#",
	"#............#..##...gggggg....#",
	"#............XE.##...gggggg....#",
	"#L...........#..##p..gggggg...L#",
	"#######V##########...gggggg....#",
	"######...#########...gggggg...W#",
	"######..f#########f..gggggg..i.#",
	"################################",
]

const ROOMS_5 := [
	["ARRIVAL", Rect2i(1, 1, 4, 4)],
	["PLAYBACK LAB 1", Rect2i(6, 1, 8, 4)],
	["PLAYBACK LAB 2", Rect2i(15, 1, 4, 4)],
	["LAB 2 CORRIDOR", Rect2i(20, 2, 10, 1)],
	["SERVICE SHAFT", Rect2i(30, 2, 1, 8)],
	["MAIN HALL", Rect2i(1, 6, 28, 3)],
	["CONTROL ROOM", Rect2i(18, 10, 13, 6)],
	["ELEVATOR WING", Rect2i(1, 10, 12, 3)],
	["ELEVATOR", Rect2i(14, 10, 2, 3)],
	["CRAWLSPACE", Rect2i(6, 14, 3, 2)],
]

const SHIELDED := ["PLAYBACK LAB 1", "PLAYBACK LAB 2", "LAB 2 CORRIDOR", "SERVICE SHAFT", "CONTROL ROOM"]
const LABS := ["PLAYBACK LAB 1", "PLAYBACK LAB 2", "LAB 2 CORRIDOR"]

## Each plate holds one door open: plate cell -> [door cell, colour name, colour].
const PLATES := {
	Vector2i(13, 4): [Vector2i(14, 2), "CYAN", Color(0.3, 0.9, 1.0)],
	Vector2i(16, 4): [Vector2i(19, 2), "ORANGE", Color(1.0, 0.55, 0.15)],
	Vector2i(18, 4): [Vector2i(25, 2), "YELLOW", Color(1.0, 0.9, 0.2)],
	Vector2i(18, 12): [Vector2i(13, 11), "GREEN", Color(0.3, 1.0, 0.45)],
}

const MAX_RECORDING := 40.0
const FRAME := 0.1

const FRAGMENT_TEXT_5 := [
	"\"The recorders were meant for training. Then the recordings started walking on their own.\"",
	"\"A recording of you is still you, for as long as it lasts. ECHO is what happens when it never stops.\"",
	"\"If you meet yourself down here, don't ask it which one of you is real.\"",
]

var plates: Dictionary = PLATES.duplicate()   # plate cell -> [door, name, colour]; they move each game
var plate_doors: Dictionary = {}    # door cell -> door
var plate_pads: Dictionary = {}     # plate cell -> material
var plate_down: Dictionary = {}     # plate cell -> bool
var recording := false
var rec_frames: Array = []          # [position, yaw, crouching, noise]
var rec_t := 0.0
var _rec_sample := 0.0
var copy: Node3D = null
var copy_frames: Array = []
var copy_t := 0.0
var _copy_noise_t := 0.0
var _copy_step_t := 0.0
var shutter: Node


func _configure() -> void:
	sector_id = 5
	sector_title = "SECTOR 5  -  PLAYBACK LAB"
	next_scene = "res://scenes/sector_6.tscn"
	map = MAP_5
	rooms = ROOMS_5
	fragment_text = FRAGMENT_TEXT_5
	no_wander_rooms = ["CRAWLSPACE", "ELEVATOR", ""]
	if Game.is_explorer():
		no_wander_rooms += LABS
	echo_enabled = true


## Key items that move to a random spot in their room each game.
func _scatter_chars() -> Array:
	return []   # the plates move in _setup_puzzles (each must stay far from its door)


## Each game the plates move to new spots in their rooms. A plate always
## stays at least 3 squares from the door it holds (so you can't hold it
## yourself), and the control room's plate stays across the grates from the
## recorder (so your copy still has to cross them quietly).
func _setup_puzzles() -> void:
	if Game.fixed_layout:
		return
	var moved: Dictionary = {}
	for plate in plates:
		var door: Vector2i = plates[plate][0]
		var room := room_at(plate)
		var rect := room_rect(room)
		var grate_x := 999
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				if ch(Vector2i(x, y)) == "g":
					grate_x = mini(grate_x, x)
		var spots: Array = []
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				var c := Vector2i(x, y)
				if c != plate and (ch(c) != "." or not _scatter_ok(c)):
					continue
				if absi(c.x - door.x) + absi(c.y - door.y) < 3 or c.x >= grate_x:
					continue
				spots.append(c)
		var to: Vector2i = spots[randi() % spots.size()] if not spots.is_empty() else plate
		_set_ch(plate, ".")
		_set_ch(to, "p")
		moved[to] = plates[plate]
	plates = moved


func _solid_chars() -> Array:
	return ["#", "V", "K", "X", "Y", "H", "W"]


func _build_grid() -> void:
	super._build_grid()
	if Game.is_explorer():
		for r in rows:
			for c in cols:
				var cell := Vector2i(c, r)
				if room_at(cell) in LABS:
					grid.set_point_solid(cell, true)


# ================================================================= objects

func _custom_cell(k: String, cell: Vector2i) -> void:
	var p := cell_to_world(cell)
	match k:
		"W":
			_spawn_booth(cell)
		"p":
			_spawn_plate(cell)
		"Y":
			var d := Door.new()
			d.position = p
			add_child(d)
			d.setup(self, cell, ch(cell + Vector2i(-1, 0)) == "#" and ch(cell + Vector2i(1, 0)) == "#", "gate")
			doors[cell] = d
			plate_doors[cell] = d
			_door_colour_sign(d, cell)
		"H":
			var d := Door.new()
			d.position = p
			add_child(d)
			d.setup(self, cell, true, "gate")
			doors[cell] = d
			shutter = d


func _door_colour_sign(d: Node, cell: Vector2i) -> void:
	for plate in plates:
		if plates[plate][0] == cell:
			var col: Color = plates[plate][2]
			var l := Label3D.new()
			l.text = "HELD OPEN BY THE\n%s PLATE" % plates[plate][1]
			l.font_size = 40
			l.pixel_size = 0.004
			l.modulate = col
			l.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
			l.position = Vector3(0, WALL_H - 0.35, 0)
			d.add_child(l)


func _spawn_plate(cell: Vector2i) -> void:
	var info: Array = plates[cell]
	var col: Color = info[2]
	var p := cell_to_world(cell)
	_box(Vector3(2.2, 0.08, 2.2), p + Vector3(0, 0.04, 0), _mat(Color(0.25, 0.26, 0.28), 0.4, 0.8))
	var pad_mat := _glow(Color(col.r * 0.3, col.g * 0.3, col.b * 0.3), 0.8)
	_box(Vector3(1.8, 0.1, 1.8), p + Vector3(0, 0.07, 0), pad_mat)
	plate_pads[cell] = pad_mat
	plate_down[cell] = false
	var l := Label3D.new()
	l.text = info[1] + " PLATE"
	l.font_size = 64
	l.pixel_size = 0.005
	l.modulate = col
	l.rotation.x = -PI / 2.0
	l.position = p + Vector3(0, 0.14, 0)
	add_child(l)


func _spawn_booth(cell: Vector2i) -> void:
	var p := cell_to_world(cell)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.set_meta("surface", "metal")
	add_child(body)
	_shape(body, Vector3(1.2, 2.2, 1.2), p + Vector3(0, 1.1, 0))
	_box(Vector3(1.2, 2.2, 1.2), p + Vector3(0, 1.1, 0), _mat(Color(0.2, 0.22, 0.25), 0.5, 0.6))
	var lamp := _box(Vector3(0.3, 0.3, 0.3), p + Vector3(0, 2.4, 0), _glow(Color(1.0, 0.15, 0.1), 2.0))
	for n in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
		_label("RECORDER", p + n * 0.62 + Vector3(0, 1.6, 0), n, 40, Color(1.0, 0.4, 0.35), 0.004)
	var it := Interactable.new()
	it.position = p + Vector3(0, 1.1, 0)
	add_child(it)
	_shape_for(it, Vector3(1.4, 2.2, 1.4))
	it.prompt_text = "Start recording"
	it.on_use = func(): start_recording(lamp)


# =============================================================== recording

func start_recording(lamp: Node = null) -> void:
	if recording:
		return
	erase_copy(false)
	recording = true
	rec_frames.clear()
	rec_t = 0.0
	_rec_sample = 0.0
	Sound.play("key_ok", -6.0, 1.4)
	hud.toast("RECORDING. Everything you do now, your copy will do. Press R to stop.", 4.0)
	_sample_frame()


func _sample_frame() -> void:
	rec_frames.append([player.global_position, player.yaw, player.crouching, player.noise])


func stop_recording() -> void:
	if not recording:
		return
	recording = false
	_sample_frame()
	hud.set_status("")
	Sound.play("key_ok", -6.0, 0.9)
	if rec_frames.size() < 3:
		hud.toast("That recording was too short.", 2.5)
		return
	copy_frames = rec_frames.duplicate()
	copy_t = 0.0
	copy = _build_copy()
	add_child(copy)
	copy.global_position = copy_frames[0][0]
	Sound.play_at("static", copy.global_position + Vector3(0, 1, 0), -12.0, 1.6)
	hud.toast("Playing back. Your copy will stay where you stopped.", 3.0)


func on_rotate_pressed() -> bool:
	if recording:
		stop_recording()
		return true
	return false


## Remove the copy (a new recording, or the Listener found it).
func erase_copy(by_listener: bool) -> void:
	if copy == null:
		return
	Sound.play_at("static", copy.global_position + Vector3(0, 1, 0), -6.0 if by_listener else -14.0, 1.2)
	copy.queue_free()
	copy = null
	copy_frames.clear()
	if by_listener:
		hud.toast("The Listener found your recording and tore it apart. Record it again - quietly.", 5.0)


func _build_copy() -> Node3D:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
void fragment() {
	float scan = 0.6 + 0.4 * step(0.5, fract(SCREEN_UV.y * 120.0 - TIME * 2.0));
	float rim = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.0);
	ALBEDO = vec3(0.3, 1.0, 0.55);
	ALPHA = (0.18 + rim * 0.6) * scan;
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	var root := Node3D.new()
	for part in [[Vector2(0.09, 0.9), Vector3(-0.12, 0.45, 0)], [Vector2(0.09, 0.9), Vector3(0.12, 0.45, 0)],
			[Vector2(0.2, 0.75), Vector3(0, 1.25, 0)], [Vector2(0.06, 0.7), Vector3(-0.3, 1.22, 0)],
			[Vector2(0.06, 0.7), Vector3(0.3, 1.22, 0)]]:
		var mi := MeshInstance3D.new()
		var cm := CapsuleMesh.new()
		cm.radius = part[0].x
		cm.height = part[0].y
		mi.mesh = cm
		mi.material_override = mat
		mi.position = part[1]
		root.add_child(mi)
	var head := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.14
	sm.height = 0.3
	head.mesh = sm
	head.material_override = mat
	head.position.y = 1.78
	root.add_child(head)
	var light := OmniLight3D.new()
	light.light_color = Color(0.3, 1.0, 0.55)
	light.light_energy = 0.5
	light.omni_range = 3.0
	light.position.y = 1.2
	root.add_child(light)
	var tag := Label3D.new()
	tag.text = "YOUR RECORDING"
	tag.font_size = 28
	tag.pixel_size = 0.004
	tag.modulate = Color(0.3, 1.0, 0.55)
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.position.y = 2.15
	root.add_child(tag)
	return root


func copy_cell() -> Vector2i:
	return world_to_cell(copy.global_position) if copy else Vector2i(-99, -99)


func _update_recording(delta: float) -> void:
	if recording:
		if catching or player.frozen:
			recording = false
			hud.set_status("")
			return
		rec_t += delta
		_rec_sample += delta
		if _rec_sample >= FRAME:
			_rec_sample -= FRAME
			_sample_frame()
		hud.set_status("REC  %d:%02d / 0:40      [R] stop" % [int(rec_t) / 60, int(rec_t) % 60])
		if rec_t >= MAX_RECORDING:
			stop_recording()
	if copy == null:
		return
	# Play the copy back.
	copy_t += delta
	var f := copy_t / FRAME
	var i := mini(int(f), copy_frames.size() - 1)
	var j := mini(i + 1, copy_frames.size() - 1)
	var a: Array = copy_frames[i]
	var b: Array = copy_frames[j]
	var w := clampf(f - i, 0.0, 1.0)
	var before := copy.global_position
	copy.global_position = (a[0] as Vector3).lerp(b[0], w)
	copy.rotation.y = lerp_angle(a[1], b[1], w)
	copy.scale.y = 0.6 if a[2] else 1.0
	var moving := copy.global_position.distance_to(before) > 0.002
	var noise: float = a[3]
	# Its footsteps make your noise: the Listener can hear it.
	if moving and noise > 0.5:
		_copy_noise_t -= delta
		if _copy_noise_t <= 0.0:
			_copy_noise_t = 0.35
			emit_noise(copy.global_position, noise, false)
		_copy_step_t -= delta
		if _copy_step_t <= 0.0:
			_copy_step_t = 0.5
			var grate := is_grate(copy.global_position)
			Sound.play_at("step_grate" if grate else "step", copy.global_position, -6.0 if noise > 3.0 else -16.0)
	# The Listener tears recordings apart (not in Explorer).
	if not Game.is_explorer() and listener.is_physics_processing():
		var d := Vector2(listener.global_position.x - copy.global_position.x, listener.global_position.z - copy.global_position.z).length()
		if d < 1.3:
			erase_copy(true)


# ============================================================ plates & doors

func _update_plates() -> void:
	var pcell := world_to_cell(player.global_position)
	var ccell := copy_cell()
	for plate in plates:
		var down: bool = (pcell == plate and not player.hidden_in) or ccell == plate
		if down != plate_down[plate]:
			plate_down[plate] = down
			var col: Color = plates[plate][2]
			var pad: StandardMaterial3D = plate_pads[plate]
			pad.emission = col if down else Color(col.r * 0.3, col.g * 0.3, col.b * 0.3)
			pad.emission_energy_multiplier = 3.0 if down else 0.8
			Sound.play_at("breaker", cell_to_world(plate), -12.0, 1.8 if down else 1.2)
	for plate in plates:
		var door_cell: Vector2i = plates[plate][0]
		var door: Node = doors.get(door_cell)
		if door == null:
			continue
		var want: bool = plate_down[plate]
		if want and not door.stay_open:
			door.unlocked = true
			door.stay_open = true
			unlock_cell(door_cell)
			door.open(false)
			if door == exit_door:
				exit_open = true
		elif not want and door.stay_open:
			if pcell == door_cell or ccell == door_cell:
				continue   # never shut a door on someone standing in it
			door.stay_open = false
			door.unlocked = false
			door.close()
			grid.set_point_solid(door_cell, true)
			if door == exit_door:
				exit_open = false


func gate_prompt(door: Node) -> String:
	if door == shutter:
		return "Shutter: jammed shut"
	return "Held open by a pressure plate"


func gate_interact(door: Node) -> void:
	Sound.play_at("locked", door.global_position, -2.0)
	hud.toast("This door only opens while its pressure plate is pressed down." if door != shutter else "It won't budge from this side.")


func exit_prompt(door: Node) -> String:
	return "" if door.is_open else "Elevator: held open by the GREEN plate (control room)"


func exit_interact(door: Node) -> void:
	Sound.play_at("locked", door.global_position, -2.0)
	hud.toast("The elevator opens while something stands on the GREEN plate in the control room.")


func trail_shielded() -> bool:
	return room_at(world_to_cell(player.global_position)) in SHIELDED


func _check_clues() -> void:
	pass


# =================================================================== story

func _intro() -> void:
	hud.set_objective("Find the recorders (Playback Lab 1, next door).")
	hud.add_clue("Recorders: E at a booth starts recording, R stops. Your copy replays it and stays where you stopped.")
	hud.add_clue("Plates hold doors open while something stands on them. One copy at a time.")
	await get_tree().create_timer(1.6).timeout
	hud.say("ai", "Sector 5: the playback lab. They used the recorders for training.")
	hud.say("ai", "Step up to a recorder and press E. Everything you do is recorded until you press R.")
	hud.say("ai", "Then a copy of you does it all again, and stays where you stopped. It is heavy enough to hold a pressure plate.")
	hud.say("unknown", "...two of you now. only one of them is helping.")


func _process(delta: float) -> void:
	super._process(delta)
	if ended or player == null:
		return
	_update_recording(delta)
	_update_plates()


func _entered_room(room: String) -> void:
	match room:
		"MAIN HALL":
			listener.set_physics_process(true)
			hud.say("ai", "The hall is not shielded. Keep moving.")
		"PLAYBACK LAB 1":
			hud.set_objective("Get your copy to hold the CYAN plate while you go through its door.")
		"PLAYBACK LAB 2":
			hud.set_objective("Two doors in a row. Your copy must hold ORANGE until you're through, then move to YELLOW.")
			hud.say("ai", "Two plates, two doors. Your copy can only stand in one place at a time. Timing matters.")
		"CONTROL ROOM":
			hud.set_objective("Get your copy onto the GREEN plate to hold the elevator open. Then get out through the shutter.")
			hud.say("ai", "The GREEN plate holds the elevator open. Your copy will have to cross the grates to reach it.")
			hud.say("ai", "Your copy makes your noise. If you stomp while you record, the Listener will hear it.")
			_open_shutter()
		"CRAWLSPACE":
			hud.toast("A secret room!", 2.5)


func _open_shutter() -> void:
	if shutter == null or shutter.unlocked:
		return
	shutter.unlocked = true
	shutter.stay_open = true
	unlock_cell(shutter.cell)
	shutter.open(true)
	emit_noise(shutter.global_position, 18.0, false)
	hud.toast("The shutter to the main hall rattled open. That was loud.", 4.0)


func _end_story() -> String:
	return ("Your copy waved as the elevator doors closed. You hadn't recorded that.\n"
		+ "It was still standing there, on the plate, when the lights went out.\n\nSector 6 is waiting below.")
