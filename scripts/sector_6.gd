extends "res://scripts/sector.gd"
## SECTOR 6: SHOWROOM.
##
## Rooms full of identical mannequins. Most are props. Some are the
## Replacement: 1 in Explorer (it creeps but never catches you), 2 in
## Survivor, 3 in Nightmare. You can't tell which until one has moved.
## LIGHT FREEZES THEM: in a lit room they can't move at all. In a dark room
## they move whenever you look away.
##
## The power board in the main hall has four circuits (WEST showroom, EAST
## showroom, STOCKROOM, ELEVATOR) and can only carry TWO at once. A circuit
## lights its room and powers its shutter. Switch on a third and the board
## overloads: everything goes dark and an alarm goes off.
##
## The escape route:
##   1. EAST + STOCKROOM: through the east showroom into the stockroom for the
##      elevator key.
##   2. Back at the board: WEST + ELEVATOR, through the west showroom to the
##      elevator. Every time you switch, the room you leave goes dark and its
##      mannequins wake up. The main hall only has emergency lighting.

## Map legend (on top of the base's):
##  Z  power board     e/s/w  shutters on the EAST / STOCKROOM / WEST circuit
##  q  mannequin (always a prop)   m  mannequin (may be the Replacement)
##  u  elevator key
const MAP_6 := [
	"###############################",
	"#....#########.q....q...f#....#",
	"#.P..#########...q.....q.#....#",
	"#....#########.....m.q...s..u.#",
	"#i...#########..q.....q..#....#",
	"#....#########....q......#...f#",
	"##D################e###########",
	"#....L....Z...................#",
	"#....................M........#",
	"#.............i............L..#",
	"#######w################D######",
	"#f....q......m..####..........#",
	"#.q......q....q.#..#.........L#",
	"#..........q....XE.#.....i....#",
	"#....q..m.......#..#..........#",
	"#..q........q...####L.........#",
	"###############################",
]

const ROOMS_6 := [
	["ARRIVAL", Rect2i(1, 1, 4, 5)],
	["EAST SHOWROOM", Rect2i(14, 1, 11, 5)],
	["STOCKROOM", Rect2i(26, 1, 4, 5)],
	["MAIN HALL", Rect2i(1, 7, 29, 3)],
	["WEST SHOWROOM", Rect2i(1, 11, 15, 5)],
	["ELEVATOR", Rect2i(17, 12, 2, 3)],
	["SERVICE ROOM", Rect2i(20, 11, 10, 5)],
]

const CIRCUITS := ["WEST", "EAST", "STOCKROOM", "ELEVATOR"]
const CAPACITY := 2
## Which room each circuit lights, and which shutter it powers.
const CIRCUIT_ROOM := {"WEST": "WEST SHOWROOM", "EAST": "EAST SHOWROOM", "STOCKROOM": "STOCKROOM", "ELEVATOR": "ELEVATOR"}
const SHUTTER_CIRCUIT := {"w": "WEST", "e": "EAST", "s": "STOCKROOM"}

const FRAGMENT_TEXT_6 := [
	"\"We made forty mannequins for the showroom. This morning I counted forty-one.\"",
	"\"It doesn't move in the light. So we left the lights on. Then the power started failing.\"",
	"\"If one of them is facing you, and you don't remember it facing you, leave.\"",
]

const Replacement2 := preload("res://scripts/replacement.gd")

var power: Dictionary = {"WEST": false, "EAST": false, "STOCKROOM": false, "ELEVATOR": false}
var switch_lamps: Dictionary = {}     # circuit -> material
var zone_doors: Dictionary = {}       # door -> circuit
var mannequins: Array = []            # active Replacements
var _r_spots: Array[Vector2i] = []
var has_key := false
var _blackout_board := 0.0
## Which circuit each switch on the board (1-4, left to right) is wired to.
## The labels fell off: it's different every game, and you find out by trying.
var board_order: Array = CIRCUITS.duplicate()
var circuit_known: Dictionary = {}     # circuit -> true once you've seen what it powers
var _switch_labels: Dictionary = {}    # circuit -> Label3D under its switch


func _configure() -> void:
	sector_id = 6
	sector_title = "SECTOR 6  -  SHOWROOM"
	next_scene = "res://scenes/sector_7.tscn"
	map = MAP_6
	rooms = ROOMS_6
	fragment_text = FRAGMENT_TEXT_6
	no_wander_rooms = ["ELEVATOR", ""]
	echo_enabled = false


# Showroom: warm, sickly light that dies for a moment now and then.
func _light_mood() -> Dictionary:
	return {"color": Color(1.0, 0.85, 0.55), "energy": 1.0, "rhythm": "cutout"}


## Key items that move to a random spot in their room each game.
## (The power board's wiring is shuffled too: see _spawn_board.)
func _scatter_chars() -> Array:
	return ["u"]   # the elevator key


func _setup_puzzles() -> void:
	pass


func _solid_chars() -> Array:
	return ["#", "V", "K", "X", "e", "s", "w", "Z"]


# ================================================================= objects

func _custom_cell(k: String, cell: Vector2i) -> void:
	var p := cell_to_world(cell)
	match k:
		"q":
			var m := Replacement2.build_model()
			add_child(m)
			m.position = p + Vector3(randf_range(-0.5, 0.5), 0, randf_range(-0.5, 0.5))
			m.rotation.y = randf() * TAU
			Replacement2.random_pose(m, false)
		"m":
			_r_spots.append(cell)
		"e", "s", "w":
			var d := Door.new()
			d.position = p
			add_child(d)
			d.setup(self, cell, ch(cell + Vector2i(-1, 0)) == "#" and ch(cell + Vector2i(1, 0)) == "#", "gate")
			doors[cell] = d
			zone_doors[d] = SHUTTER_CIRCUIT[k]
		"Z":
			_spawn_board(cell)
		"u":
			_spawn_key(cell)


func _spawn_board(cell: Vector2i) -> void:
	var wp := wall_point(cell, 1.5)
	var p: Vector3 = wp[0]
	var n: Vector3 = wp[1]
	var right := (-n).cross(Vector3.UP)
	var panel := _box(Vector3(2.6, 1.4, 0.12), p + n * 0.06, _mat(Color(0.22, 0.24, 0.22), 0.6, 0.5))
	panel.rotation.y = atan2(n.x, n.z)
	_label("POWER BOARD  -  MAX %d CIRCUITS" % CAPACITY, p + n * 0.14 + Vector3(0, 0.55, 0), n, 30, Color(1.0, 0.8, 0.3), 0.004)
	if Game.fixed_layout:
		for c in CIRCUITS:
			circuit_known[c] = true
	else:
		board_order.shuffle()
		_label("(labels missing - someone's written them in as they found out)", p + n * 0.14 + Vector3(0, 0.42, 0), n, 18, Color(0.75, 0.7, 0.6), 0.004)
	for i in board_order.size():
		var circuit: String = board_order[i]
		var sp := p + n * 0.14 + right * ((i - 1.5) * 0.6)
		_switch_labels[circuit] = _label(_switch_text(circuit), sp + Vector3(0, -0.42, 0), n, 22, Color(0.85, 0.9, 1.0), 0.004)
		var lamp_mat := _glow(Color(0.25, 0.05, 0.05), 1.0)
		_box(Vector3(0.12, 0.12, 0.04), sp + Vector3(0, 0.25, 0), lamp_mat)
		switch_lamps[circuit] = lamp_mat
		var it := Interactable.new()
		it.position = sp
		add_child(it)
		_box(Vector3(0.14, 0.32, 0.1), Vector3.ZERO, _mat(Color(0.6, 0.6, 0.62), 0.4, 0.8), it)
		_shape_for(it, Vector3(0.45, 0.6, 0.3))
		it.prompt_text = "Flip switch %d" % (i + 1)
		it.set_meta("circuit", circuit)
		it.on_use = func():
			flip(circuit)
			it.prompt_text = "Flip switch %d  (%s)" % [i + 1, circuit] if circuit_known.has(circuit) else "Flip switch %d" % (i + 1)
		if circuit_known.has(circuit):
			it.prompt_text = "Flip switch %d  (%s)" % [i + 1, circuit]


func _switch_text(circuit: String) -> String:
	var num := board_order.find(circuit) + 1
	return "%d  %s" % [num, circuit] if circuit_known.has(circuit) else "%d  ????" % num


func _spawn_key(cell: Vector2i) -> void:
	var p := cell_to_world(cell)
	_table(p)
	var it := Interactable.new()
	it.position = p + Vector3(0, 0.86, 0)
	add_child(it)
	_box(Vector3(0.22, 0.01, 0.14), Vector3.ZERO, _glow(Color(1.0, 0.85, 0.2), 2.0), it)
	_shape_for(it, Vector3(0.5, 0.3, 0.5))
	it.prompt_text = "Take the elevator key"
	it.on_use = func():
		has_key = true
		Sound.play("pickup", -4.0)
		hud.toast("Got the ELEVATOR KEY.")
		hud.set_objective("Get to the elevator: through the WEST showroom. It needs the ELEVATOR circuit.")
		hud.say("ai", "The elevator is past the west showroom. You'll need its circuit, and the west lights.")
		hud.say("unknown", "...you left the east lights on. or did you.")
		it.queue_free()


func _spawn_actors() -> void:
	super._spawn_actors()
	# Some of the mannequins are the Replacement. Which ones is random.
	var count: int = [1, 2, 3][Game.mode]
	_r_spots.shuffle()
	for i in _r_spots.size():
		var cell: Vector2i = _r_spots[i]
		if i < count:
			var r := Replacement2.new()
			add_child(r)
			r.global_position = cell_to_world(cell)
			r.setup(self)
			r.set_meta("home", cell_to_world(cell))
			r.rotation.y = randf() * TAU
			r.active = true
			mannequins.append(r)
		else:
			var m := Replacement2.build_model()
			add_child(m)
			m.position = cell_to_world(cell)
			m.rotation.y = randf() * TAU
			Replacement2.random_pose(m, false)


func _on_respawn() -> void:
	for r in mannequins:
		r.reset_to(r.get_meta("home"))


# ================================================================== power

func flip(circuit: String) -> void:
	if _blackout_board > 0.0:
		hud.toast("The board is still resetting...", 2.0)
		return
	if power[circuit]:
		power[circuit] = false
		Sound.play_at("breaker", player.global_position, -2.0, 0.8)
	else:
		var on := 0
		for c in power:
			if power[c]:
				on += 1
		if on >= CAPACITY:
			_overload()
			return
		power[circuit] = true
		Sound.play_at("breaker", player.global_position, -2.0, 1.2)
		Sound.play("power_on", -10.0, 1.6)
		if not circuit_known.has(circuit):
			# Now you know what this switch does: write it on the board.
			circuit_known[circuit] = true
			var num := board_order.find(circuit) + 1
			(_switch_labels[circuit] as Label3D).text = _switch_text(circuit)
			hud.toast("Switch %d powers the %s." % [num, circuit if circuit == "ELEVATOR" else CIRCUIT_ROOM[circuit]], 3.0)
			hud.add_clue("Power board: switch %d = %s" % [num, circuit])
	_apply_power()


func _overload() -> void:
	for c in power:
		power[c] = false
	_blackout_board = 4.0
	Sound.play("alarm", 2.0)
	emit_noise(player.global_position, 30.0, false)
	hud.toast("OVERLOAD! Too many circuits. Everything just went dark - and that alarm was loud.", 4.5)
	hud.say("echo", "Turn them all on. Quickly.")
	_apply_power()


func _apply_power() -> void:
	for c in switch_lamps:
		var lamp: StandardMaterial3D = switch_lamps[c]
		lamp.albedo_color = Color(0.2, 1.0, 0.4) if power[c] else Color(0.25, 0.05, 0.05)
		lamp.emission = lamp.albedo_color
		lamp.emission_energy_multiplier = 3.0 if power[c] else 1.0
	for l in lights:
		var room: String = l["room"]
		var light: OmniLight3D = l["light"]
		var fx: MeshInstance3D = l["fixture"]
		var circuit := _circuit_of(room)
		if circuit == "":
			if room == "MAIN HALL":
				# Emergency lighting only: dim red.
				light.light_color = Color(1.0, 0.25, 0.2)
				light.light_energy = 0.35 * float(l["mult"])
				fx.material_override = _glow(Color(1.0, 0.2, 0.15), 1.0)
			continue
		var lit: bool = power[circuit] and _blackout_board <= 0.0
		l["off"] = not lit
		light.visible = lit
		light.light_color = Color(1.0, 0.95, 0.85)
		light.light_energy = 1.2 * float(l["mult"])
		light.omni_range = 9.0
		fx.material_override = _glow(Color(1.0, 0.95, 0.85), 2.5) if lit else _glow(Color(0.1, 0.1, 0.1), 0.2)
	if power["ELEVATOR"] and has_key and exit_door and not exit_door.unlocked:
		exit_door.unlocked = true
		exit_door.stay_open = true
		exit_open = true
		unlock_cell(exit_door.cell)
		exit_door.open(true)
		hud.set_objective("Get in the elevator!")


func _circuit_of(room: String) -> String:
	for c in CIRCUIT_ROOM:
		if CIRCUIT_ROOM[c] == room:
			return c
	return ""


func lit_at(pos: Vector3) -> bool:
	var circuit := _circuit_of(room_at(world_to_cell(pos)))
	return circuit != "" and power[circuit] and _blackout_board <= 0.0


func replacement_frozen(pos: Vector3) -> bool:
	return lit_at(pos)


func _update_shutters() -> void:
	var pcell := world_to_cell(player.global_position)
	for d in zone_doors:
		var want: bool = power[zone_doors[d]] and _blackout_board <= 0.0
		if want and not d.stay_open:
			d.unlocked = true
			d.stay_open = true
			unlock_cell(d.cell)
			d.open(true)
		elif not want and d.stay_open:
			if pcell == d.cell:
				continue   # never shut on you
			d.stay_open = false
			d.unlocked = false
			d.close()
			grid.set_point_solid(d.cell, true)


func gate_prompt(door: Node) -> String:
	var circuit: String = zone_doors.get(door, "")
	return "Shutter: needs the %s circuit (power board, main hall)" % circuit


func gate_interact(door: Node) -> void:
	Sound.play_at("locked", door.global_position, -2.0)
	hud.toast("No power. Switch on its circuit at the power board in the main hall.")


func exit_prompt(door: Node) -> String:
	if door.unlocked:
		return ""
	if not has_key:
		return "Elevator: locked (needs the key from the stockroom)"
	return "Elevator: needs the ELEVATOR circuit"


func exit_interact(door: Node) -> void:
	Sound.play_at("locked", door.global_position, -2.0)
	hud.toast("The elevator needs its key AND its circuit switched on." if not has_key else "Switch on the ELEVATOR circuit at the power board.")


func _check_clues() -> void:
	pass


# =================================================================== story

func _intro() -> void:
	_apply_power()
	hud.set_objective("Find the power board in the main hall.")
	hud.add_clue("The power board carries only 2 circuits at once. A third overloads it.")
	hud.add_clue("Mannequins can't move in a lit room. In the dark, they move when you look away.")
	await get_tree().create_timer(1.6).timeout
	hud.say("ai", "Sector 6: the showroom. This is where they tested the Replacement.")
	hud.say("ai", "There are dozens of mannequins down here. Most of them are only mannequins.")
	hud.say("ai", "They cannot move in the light. The power board can carry two circuits at a time. Choose carefully.")
	hud.say("unknown", "...which one of us moved?")


func _process(delta: float) -> void:
	super._process(delta)
	if ended or player == null:
		return
	if _blackout_board > 0.0:
		_blackout_board -= delta
		if _blackout_board <= 0.0:
			hud.toast("The board has reset. Switch your circuits back on.", 3.0)
			_apply_power()
	_update_shutters()


func _entered_room(room: String) -> void:
	match room:
		"MAIN HALL":
			listener.set_physics_process(true)
			hud.set_objective("Use the power board: EAST + STOCKROOM gets you to the elevator key." if Game.fixed_layout
				else "Power board: switch on the EAST showroom and STOCKROOM for the elevator key. The switches lost their labels - find out which is which.")
			hud.say("ai", "Only emergency lights in the hall. Something here hunts by sound, as always.")
		"EAST SHOWROOM":
			if not power["EAST"]:
				hud.say("ai", "It's dark in here. Keep your light on them.")
		"WEST SHOWROOM":
			hud.say("unknown", "they're all facing the door now.")


func _end_story() -> String:
	return ("As the elevator doors closed, every mannequin in the showroom was facing you.\n"
		+ "You hadn't seen a single one of them move.\n\nSector 7 is waiting below.")
