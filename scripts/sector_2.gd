extends "res://scripts/sector.gd"
## SECTOR 2: ARCHIVES.
##
## New threat: ECHO walks exactly where you walked. Keep moving, don't double
## back, and hide in a locker to break your trail. The Listener is here too,
## so you have to balance moving on with staying quiet.
##
## The escape route:
##   1. Find a fuse in COLD STORAGE (all metal grates, so it's loud).
##   2. Put it in the fuse panel in the VAULT HALL to power the vault doors.
##   3. Read the three record terminals. Each says where the archive drive is.
##      Exactly ONE of them is really MERIDIAN telling the truth; the other two
##      are ECHO lying with MERIDIAN's voice. Work out which vault it must be.
##      (The statements change every game.)
##   4. Open that vault. The wrong vault sets off an alarm.
##   5. Plug the drive into the ARCHIVE SERVER. It unlocks the elevator.
## Secrets: 3 signal fragments, one behind a low vent in Records C.

## Map legend (on top of Sector 1's):
##  T  record terminal       a b c  vault doors A, B, C
##  u  fuse                  Z  fuse panel        S  archive server
const MAP_2 := [
	"#############################",
	"#....#.......#.....#.......f#",
	"#.P..D...T...#..T..D..ggg...#",
	"#.i..#.......D.....#..ggg.u.#",
	"#....#L......#....L#..ggg..L#",
	"###D#####D#######D######D####",
	"#.....L.......i.............#",
	"#.........M.................#",
	"####D######D#####D#####D#####",
	"#......#...........#........#",
	"#..T...#.....Z.....#..S.....#",
	"#L.....#...........#.....i..#",
	"#......###a###b###c#####X##.#",
	"#......##...#...#...###.E.#.#",
	"#......##...#...#...###...#.#",
	"##V##D#####################.#",
	"#.f.#.......ggg.....L.......#",
	"#...#.......ggg........i...f#",
	"#############################",
]

const ROOMS_2 := [
	["ARRIVAL", Rect2i(1, 1, 4, 4)],
	["RECORDS A", Rect2i(6, 1, 7, 4)],
	["RECORDS B", Rect2i(14, 1, 5, 4)],
	["COLD STORAGE", Rect2i(20, 1, 8, 4)],
	["MAIN HALL", Rect2i(1, 6, 27, 2)],
	["RECORDS C", Rect2i(1, 9, 6, 6)],
	["VAULT HALL", Rect2i(8, 9, 11, 3)],
	["VAULT A", Rect2i(9, 13, 3, 2)],
	["VAULT B", Rect2i(13, 13, 3, 2)],
	["VAULT C", Rect2i(17, 13, 3, 2)],
	["SERVER ROOM", Rect2i(20, 9, 8, 3)],
	["ELEVATOR", Rect2i(23, 13, 3, 2)],
	["SERVICE SHAFT", Rect2i(27, 12, 1, 4)],
	["LOWER HALL", Rect2i(5, 16, 23, 2)],
	["CRAWLSPACE", Rect2i(1, 16, 3, 2)],
]

const FRAGMENT_TEXT_2 := [
	"\"The archive drive holds every voice MERIDIAN ever recorded. If ECHO gets it, it can sound like anyone.\"",
	"\"Day 41: the night guard swears he heard himself walking down the corridor behind him. He wasn't moving.\"",
	"\"Don't let it follow you home. Don't walk back the way you came. Never walk back the way you came.\"",
]

const VAULTS := ["A", "B", "C"]

var has_fuse := false
var vault_power := false
var has_drive := false
var correct_vault := 0
var truthful_terminal := 0
var statements: Array = []     # [["in" or "not", vault index], ...] for terminals 1-3
var terminals_read: Dictionary = {}
var vault_doors: Dictionary = {}   # vault index -> door
var _records_hint_given := false


func _configure() -> void:
	sector_id = 2
	sector_title = "SECTOR 2  -  ARCHIVES"
	next_scene = "res://scenes/sector_3.tscn"
	map = MAP_2
	rooms = ROOMS_2
	fragment_text = FRAGMENT_TEXT_2
	no_wander_rooms = ["CRAWLSPACE", "ELEVATOR", "VAULT A", "VAULT B", "VAULT C", ""]
	echo_enabled = true


# Archives: tired sodium-orange lamps that slowly swell and fade.
func _light_mood() -> Dictionary:
	return {"color": Color(1.0, 0.68, 0.35), "energy": 0.85, "rhythm": "breathe"}


## Key items that move to a random spot in their room each game.
func _scatter_chars() -> Array:
	return ["u"]   # the fuse


func _setup_puzzles() -> void:
	make_vault_puzzle()


## Three statements, exactly one of them true, and only one vault fits.
func make_vault_puzzle() -> void:
	while true:
		var st: Array = []
		for i in 3:
			st.append(["in" if randf() < 0.5 else "not", randi() % 3])
		var answers: Array[int] = []
		for v in 3:
			if _true_count(st, v) == 1:
				answers.append(v)
		if answers.size() == 1:
			statements = st
			correct_vault = answers[0]
			for i in 3:
				if _is_true(st[i], correct_vault):
					truthful_terminal = i
			return


static func _is_true(statement: Array, vault: int) -> bool:
	var is_in: bool = statement[0] == "in"
	return is_in == (int(statement[1]) == vault)


static func _true_count(st: Array, vault: int) -> int:
	var n := 0
	for x in st:
		if _is_true(x, vault):
			n += 1
	return n


func statement_text(i: int) -> String:
	var x: Array = statements[i]
	var letter: String = VAULTS[x[1]]
	return ("The archive drive is in VAULT %s." if x[0] == "in" else "The archive drive is NOT in VAULT %s.") % letter


func _solid_chars() -> Array:
	return ["#", "V", "K", "X", "a", "b", "c"]


# ================================================================= objects

func _custom_cell(k: String, cell: Vector2i) -> void:
	match k:
		"T":
			_spawn_terminal(cell)
		"a", "b", "c":
			_spawn_vault_door(cell, "abc".find(k))
		"u":
			_spawn_fuse(cell)
		"Z":
			_spawn_fuse_panel(cell)
		"S":
			_spawn_server(cell)


func _wall_thing(cell: Vector2i, y: float, size: Vector3, color: Color) -> Array:
	var wp := wall_point(cell, y)
	var p: Vector3 = wp[0]
	var n: Vector3 = wp[1]
	var box := _box(size, p + n * (size.z / 2.0), _mat(color, 0.5, 0.6))
	box.rotation.y = atan2(n.x, n.z)
	return [p, n]


func _spawn_terminal(cell: Vector2i) -> void:
	var i := terminals_read.size()
	terminals_read[i] = false
	var wpn := _wall_thing(cell, 1.6, Vector3(2.2, 1.4, 0.12), Color(0.18, 0.2, 0.22))
	var p: Vector3 = wpn[0]
	var n: Vector3 = wpn[1]
	_box(Vector3(2.0, 1.2, 0.02), p + n * 0.13, _glow(Color(0.03, 0.18, 0.1), 1.0)).rotation.y = atan2(n.x, n.z)
	_label("RECORD TERMINAL %d" % (i + 1), p + n * 0.15 + Vector3(0, 0.42, 0), n, 44, Color(0.5, 1.0, 0.7), 0.004)
	var line := statement_text(i).replace(" is ", "\nis ").replace("The archive drive", "THE ARCHIVE DRIVE")
	_label(line, p + n * 0.15 + Vector3(0, -0.08, 0), n, 56, Color(0.8, 1.0, 0.85), 0.004)
	var it := Interactable.new()
	it.position = p + n * 0.3
	add_child(it)
	_shape_for(it, Vector3(1.2, 0.8, 0.3))
	it.rotation.y = atan2(n.x, n.z)
	it.prompt_text = "Read terminal %d" % (i + 1)
	it.on_use = func(): read_terminal(i)


func read_terminal(i: int) -> void:
	Sound.play("blip", -6.0)
	terminals_read[i] = true
	hud.show_note("RECORD TERMINAL %d" % (i + 1), "\"%s\"\n\n- signed, MERIDIAN" % statement_text(i))
	hud.add_clue("Terminal %d says: %s" % [i + 1, statement_text(i)])
	if not _records_hint_given:
		_records_hint_given = true
		hud.say("ai", "Careful. Only ONE of the three record terminals is really me, telling the truth.")
		hud.say("ai", "The other two are ECHO, using my voice. They are lying.")
		hud.add_clue("Exactly ONE terminal tells the truth. The other two lie.")
	var all_read := true
	for k in terminals_read:
		if not terminals_read[k]:
			all_read = false
	if all_read:
		hud.set_objective("Work out which vault has the drive (only one terminal is telling the truth).")
		if Game.is_explorer():
			hud.say("ai", "Here is a trick. Pretend the drive is in Vault A. How many terminals would be telling the truth? It has to be exactly one. Then try B, then C.")


func _spawn_vault_door(cell: Vector2i, index: int) -> void:
	var d := Door.new()
	d.vault_letter = VAULTS[index]
	d.position = cell_to_world(cell)
	add_child(d)
	d.setup(self, cell, true, "vault")
	# A big letter on the wall above each vault door, readable across the hall.
	_label(VAULTS[index], cell_to_world(cell) + Vector3(0, WALL_H - 0.45, -0.17), Vector3(0, 0, -1), 160, Color(0.45, 1.0, 0.65), 0.006)
	doors[cell] = d
	vault_doors[index] = d


func vault_prompt(door: Node) -> String:
	if not vault_power:
		return "Vault %s: no power" % door.vault_letter
	return "Open vault %s" % door.vault_letter


func vault_interact(door: Node) -> void:
	if not vault_power:
		Sound.play_at("locked", door.global_position, -2.0)
		hud.toast("The vault doors have no power. Find a fuse for the panel.")
		return
	var index: int = VAULTS.find(door.vault_letter)
	if index == correct_vault:
		Sound.play("key_ok", -2.0)
		door.unlocked = true
		door.stay_open = true
		unlock_cell(door.cell)
		door.open(true)
		_spawn_drive(cell_to_world(door.cell + Vector2i(0, 1)))
		hud.toast("VAULT %s OPENED." % door.vault_letter)
		return
	# The wrong vault.
	Sound.play_at("key_bad", door.global_position, 0.0)
	if Game.is_explorer():
		hud.toast("Wrong vault. Think about which terminal is telling the truth.", 4.0)
		return
	Sound.play_at("alarm", door.global_position, 4.0)
	emit_noise(door.global_position, 30.0, false)
	hud.toast("WRONG VAULT! The alarm is LOUD - something heard that.", 4.0)
	hud.say("echo", "Try the next one. Quickly.")


func _spawn_drive(pos: Vector3) -> void:
	_table(pos)
	var it := Interactable.new()
	it.position = pos + Vector3(0, 0.88, 0)
	add_child(it)
	_box(Vector3(0.3, 0.08, 0.2), Vector3.ZERO, _glow(Color(0.4, 1.0, 0.6), 2.0), it)
	_shape_for(it, Vector3(0.5, 0.3, 0.5))
	it.prompt_text = "Take the archive drive"
	it.on_use = func():
		has_drive = true
		Sound.play("pickup", -4.0)
		hud.toast("Got the ARCHIVE DRIVE.")
		hud.set_objective("Take the archive drive to the ARCHIVE SERVER (server room).")
		hud.add_clue("The archive drive goes into the ARCHIVE SERVER in the server room.")
		hud.say("unknown", "...it wants that drive more than you do.")
		it.queue_free()


func _spawn_fuse(cell: Vector2i) -> void:
	var p := cell_to_world(cell)
	_table(p)
	var it := Interactable.new()
	it.position = p + Vector3(0, 0.88, 0)
	add_child(it)
	var fuse := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.06
	cm.bottom_radius = 0.06
	cm.height = 0.3
	fuse.mesh = cm
	fuse.rotation.z = PI / 2.0
	fuse.material_override = _glow(Color(1.0, 0.6, 0.15), 1.5)
	it.add_child(fuse)
	_shape_for(it, Vector3(0.5, 0.3, 0.5))
	it.prompt_text = "Take the fuse"
	it.on_use = func():
		has_fuse = true
		Sound.play("pickup", -4.0)
		hud.toast("Got a FUSE.")
		hud.set_objective("Put the fuse in the panel in the VAULT HALL.")
		it.queue_free()


func _spawn_fuse_panel(cell: Vector2i) -> void:
	var wpn := _wall_thing(cell, 1.4, Vector3(0.8, 1.0, 0.15), Color(0.25, 0.27, 0.25))
	var p: Vector3 = wpn[0]
	var n: Vector3 = wpn[1]
	_label("VAULT POWER\nFUSE PANEL", p + n * 0.17 + Vector3(0, 0.25, 0), n, 28, Color(1.0, 0.75, 0.3), 0.004)
	var lamp := _box(Vector3(0.12, 0.12, 0.05), p + n * 0.17 + Vector3(0, -0.2, 0), _glow(Color(1.0, 0.2, 0.15), 3.0))
	var it := Interactable.new()
	it.position = p + n * 0.3
	add_child(it)
	_shape_for(it, Vector3(0.8, 1.0, 0.3))
	it.prompt_text = "Fuse panel (empty)"
	it.on_use = func():
		if vault_power:
			return
		if not has_fuse:
			Sound.play("locked", -6.0)
			hud.toast("The fuse slot is empty. There must be a spare fuse somewhere.")
			return
		vault_power = true
		power_on = true
		it.prompt_text = ""
		lamp.material_override = _glow(Color(0.2, 1.0, 0.4), 3.0)
		Sound.play_at("breaker", it.global_position, 0.0)
		Sound.play("power_on", -2.0)
		emit_noise(it.global_position, 10.0, false)
		for l in lights:
			if l["room"] == "VAULT HALL":
				var light: OmniLight3D = l["light"]
				light.light_color = Color(0.6, 1.0, 0.75)
				light.light_energy = 1.0 * float(l["mult"])
				l["fixture"].material_override = _glow(Color(0.6, 1.0, 0.75), 2.0)
		hud.set_objective("Read the 3 record terminals, then open the right vault.")
		hud.say("ai", "Vault power restored. The archive drive is in one of the three vaults.")
		hud.say("ai", "Open the wrong vault and every alarm in this sector goes off.")


func _spawn_server(cell: Vector2i) -> void:
	var wpn := _wall_thing(cell, 1.3, Vector3(2.2, 2.4, 0.6), Color(0.12, 0.13, 0.15))
	var p: Vector3 = wpn[0]
	var n: Vector3 = wpn[1]
	var right := (-n).cross(Vector3.UP)
	for i in 12:   # blinking status lights
		var led := _box(Vector3(0.05, 0.05, 0.02), p + n * 0.62 + right * (-0.8 + (i % 6) * 0.3) + Vector3(0, 0.3 + (i / 6) * 0.25, 0), _glow(Color(0.2, 0.8, 1.0), 2.0))
		var t := led.create_tween().set_loops()
		t.tween_property(led, "visible", false, randf_range(0.2, 1.2))
		t.tween_property(led, "visible", true, randf_range(0.2, 1.2))
	_label("ARCHIVE SERVER", p + n * 0.62 + Vector3(0, 0.9, 0), n, 40, Color(0.5, 0.85, 1.0), 0.004)
	var it := Interactable.new()
	it.position = p + n * 0.75
	add_child(it)
	_shape_for(it, Vector3(1.6, 1.2, 0.3))
	it.prompt_text = "Archive server: needs the archive drive"
	it.on_use = func():
		if exit_open:
			return
		if not has_drive:
			Sound.play("locked", -6.0)
			hud.toast("The server needs its archive drive. It's in one of the vaults.")
			return
		_upload(it)


func _upload(it: Node) -> void:
	it.prompt_text = ""
	exit_open = true
	Sound.play("key_ok", -2.0)
	Sound.play("power_on", -4.0, 1.3)
	exit_door.unlocked = true
	exit_door.stay_open = true
	unlock_cell(exit_door.cell)
	exit_door.open(true)
	hud.set_objective("Get in the elevator!")
	hud.say("ai", "Archive drive accepted. Uploading every recorded voice in the facility.")
	hud.say("ai", "Thank you. You have been very helpful.")
	hud.say("unknown", "that wasn't MERIDIAN who asked you to bring it.")


func exit_prompt(door: Node) -> String:
	return "" if door.unlocked else "Elevator: locked by the archive server"


func exit_interact(door: Node) -> void:
	Sound.play_at("locked", door.global_position, -2.0)
	hud.toast("The archive server controls this elevator. It wants its drive.")


func _check_clues() -> void:
	pass


# =================================================================== story

func _intro() -> void:
	hud.set_objective("Find a way out of Sector 2.")
	await get_tree().create_timer(1.6).timeout
	hud.say("ai", "You made it down. This is Sector 2: the Archives.")
	hud.say("ai", "The elevator onward is locked by the archive server. It wants its archive drive back.")
	hud.say("ai", "The drive is in one of three vaults, and the vault row has no power.")
	hud.say("unknown", "...it followed you down.")


func _entered_room(room: String) -> void:
	match room:
		"MAIN HALL":
			listener.set_physics_process(true)
			hud.say("ai", "The Listener is down here too. Quiet feet.")
			if not has_fuse:
				hud.set_objective("Find a fuse to power the vault row.")
		"COLD STORAGE":
			hud.say("ai", "Cold storage. The whole floor is grating. Crouch, or it will hear you.")
		"RECORDS A", "RECORDS B", "RECORDS C":
			if not visited.has("records"):
				visited["records"] = true
				hud.say("ai", "The record terminals say where the archive drive is kept.")
		"VAULT HALL":
			if not vault_power:
				hud.say("ai", "The vault doors. Dead. The fuse panel on the wall is empty.")
		"SERVER ROOM":
			if not exit_open:
				hud.say("ai", "The archive server. Bring it the drive and it will open the elevator.")
		"CRAWLSPACE":
			hud.toast("A secret room!", 2.5)


func _end_story() -> String:
	return ("The upload finished as the elevator doors closed.\nMERIDIAN said thank you. Then it said it again, in your voice.\n\n"
		+ "Sector 3 is waiting below.")
