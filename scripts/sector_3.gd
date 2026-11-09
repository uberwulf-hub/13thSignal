extends "res://scripts/sector.gd"
## SECTOR 3: RELAY STATION.
##
## Signal-relay puzzles. Transmitters shoot a beam of signal in a straight
## line. Carry relays (E), put them down (E) and turn them (R): a beam that
## reaches a relay goes back out the way its arrow points. Point the beams into
## the receivers. Beams pass through glass; you can't. Each receiver wants its
## own colour, and a relay hit by two colours jams.
##
##   RELAY LAB 1: one relay, one corner (it teaches you).
##   RELAY LAB 2: three relays, a pillar, and a receiver behind glass.
##   RELAY LAB 3: two colours, two receivers, four relays.
## Each lab opens the signal gate to the next; Lab 3 opens the elevator.
##
## The labs are SHIELDED: ECHO can't follow you inside. It waits at the door.
## In Explorer, no monster comes into a lab at all.

## Map legend (on top of the base's):
##  Q  transmitter    O  receiver    r  relay (starts here)
##  w  glass wall     G  signal gate
const MAP_3 := [
	"###############################",
	"#.....#.......f#Q.....w..#...f#",
	"#.P...#Q.......#......w..#....#",
	"#i....#........#..#...w.O#....#",
	"#.....#..r.....#......w..#....#",
	"#.....#......O.#.r.r.rw..#...L#",
	"###D######D#########G######D###",
	"#....L.....ggg.i..............#",
	"#..........ggg.M..............#",
	"#..........ggg........L.......#",
	"######G##########D########D####",
	"#Q...........#.......###....###",
	"#....rrrr...##.......#.#....#.#",
	"#O..........O#.i.....V.#....XE#",
	"##...........#......L#f#....#.#",
	"#...........Q#.......###L...###",
	"###############################",
]

const ROOMS_3 := [
	["ARRIVAL", Rect2i(1, 1, 5, 5)],
	["RELAY LAB 1", Rect2i(7, 1, 8, 5)],
	["RELAY LAB 2", Rect2i(16, 1, 9, 5)],
	["STOREROOM", Rect2i(26, 1, 4, 5)],
	["MAIN HALL", Rect2i(1, 7, 29, 3)],
	["RELAY LAB 3", Rect2i(1, 11, 12, 5)],
	["SERVICE ROOM", Rect2i(14, 11, 7, 5)],
	["CRAWLSPACE", Rect2i(22, 12, 1, 3)],
	["ELEVATOR HALL", Rect2i(24, 11, 4, 5)],
	["ELEVATOR", Rect2i(29, 12, 1, 3)],
]

const LABS := ["RELAY LAB 1", "RELAY LAB 2", "RELAY LAB 3"]
## Which gate each lab opens (the last one opens the elevator).
const LAB_GATES := {"RELAY LAB 1": Vector2i(20, 6), "RELAY LAB 2": Vector2i(6, 10)}

const RED := Color(1.0, 0.25, 0.2)
const BLUE := Color(0.25, 0.55, 1.0)
## Transmitters: cell -> [direction, colour].
const EMITTERS := {
	Vector2i(7, 2): [Vector2i(1, 0), RED],
	Vector2i(16, 1): [Vector2i(0, 1), RED],
	Vector2i(1, 11): [Vector2i(1, 0), RED],
	Vector2i(12, 15): [Vector2i(-1, 0), BLUE],
}
## Receivers: cell -> the colour they need.
const RECEIVERS := {
	Vector2i(13, 5): RED,
	Vector2i(24, 3): RED,
	Vector2i(12, 13): RED,
	Vector2i(1, 13): BLUE,
}

const FRAGMENT_TEXT_3 := [
	"\"Every relay in the station points the same way. Down. Toward a sector we never built.\"",
	"\"The 13th signal isn't a message. It's a voice learning how to be every voice.\"",
	"\"If you can hear this, it can hear you. Keep moving.\"",
]

const Relay := preload("res://scripts/relay.gd")

var relays: Array = []
var solved: Dictionary = {}       # lab name -> true
var gates: Dictionary = {}        # cell -> door
var receiver_lamps: Dictionary = {}   # cell -> material
var powered: Dictionary = {}      # receiver cell -> colour reaching it
var _beam_root: Node3D
var _player_room := ""


func _configure() -> void:
	sector_id = 3
	sector_title = "SECTOR 3  -  RELAY STATION"
	next_scene = "res://scenes/sector_4.tscn"
	map = MAP_3
	rooms = ROOMS_3
	fragment_text = FRAGMENT_TEXT_3
	no_wander_rooms = ["CRAWLSPACE", "ELEVATOR", ""]
	if Game.is_explorer():
		no_wander_rooms += LABS
	echo_enabled = true


func _setup_puzzles() -> void:
	pass


func _solid_chars() -> Array:
	return ["#", "V", "K", "X", "G", "Q", "O", "w"]


func _build_grid() -> void:
	super._build_grid()
	# Explorer: the labs are safe rooms. No monster can walk into them.
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
		"Q":
			_spawn_emitter(cell)
		"O":
			_spawn_receiver(cell)
		"r":
			var rl := Relay.new()
			add_child(rl)
			rl.position = p
			rl.setup(self, cell)
			relays.append(rl)
			carryables.append(rl)
		"w":
			var glass := StandardMaterial3D.new()
			glass.albedo_color = Color(0.6, 0.85, 1.0, 0.12)
			glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			glass.roughness = 0.05
			glass.metallic = 0.3
			_box(Vector3(0.12, WALL_H, S), p + Vector3(0, WALL_H / 2.0, 0), glass)
			_box(Vector3(0.16, 0.08, S), p + Vector3(0, 0.04, 0), _mat(Color(0.3, 0.3, 0.32), 0.4, 0.8))
			var body := StaticBody3D.new()
			body.collision_layer = 1
			body.collision_mask = 0
			add_child(body)
			_shape(body, Vector3(0.12, WALL_H, S), p + Vector3(0, WALL_H / 2.0, 0))
		"G":
			var d := Door.new()
			d.position = p
			add_child(d)
			d.setup(self, cell, ch(cell + Vector2i(-1, 0)) == "#" and ch(cell + Vector2i(1, 0)) == "#", "gate")
			doors[cell] = d
			gates[cell] = d


func _spawn_emitter(cell: Vector2i) -> void:
	var info: Array = EMITTERS[cell]
	var d: Vector2i = info[0]
	var color: Color = info[1]
	var p := cell_to_world(cell)
	var housing := _box(Vector3(0.9, 1.1, 0.9), p + Vector3(0, 0.55, 0), _mat(Color(0.2, 0.22, 0.25), 0.5, 0.6))
	housing.rotation.y = atan2(float(d.x), float(d.y))
	var lens := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.18
	cm.bottom_radius = 0.18
	cm.height = 0.12
	lens.mesh = cm
	lens.material_override = _glow(color, 3.0)
	lens.rotation.x = PI / 2.0
	lens.position = Vector3(0, 0.45, 0.47)
	housing.add_child(lens)
	var l := OmniLight3D.new()
	l.light_color = color
	l.light_energy = 0.5
	l.omni_range = 3.0
	l.position = p + Vector3(d.x, 0, d.y) * 0.8 + Vector3(0, 1.0, 0)
	add_child(l)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	add_child(body)
	_shape(body, Vector3(0.9, 1.1, 0.9), p + Vector3(0, 0.55, 0))


func _spawn_receiver(cell: Vector2i) -> void:
	var color: Color = RECEIVERS[cell]
	var p := cell_to_world(cell)
	_box(Vector3(0.8, 0.9, 0.8), p + Vector3(0, 0.45, 0), _mat(Color(0.2, 0.22, 0.25), 0.5, 0.6))
	var lamp_mat := _glow(Color(color.r * 0.25, color.g * 0.25, color.b * 0.25), 0.6)
	var orb := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.32
	sm.height = 0.64
	orb.mesh = sm
	orb.material_override = lamp_mat
	orb.position = p + Vector3(0, 1.1, 0)
	add_child(orb)
	receiver_lamps[cell] = lamp_mat
	# A coloured ring around the base says which colour it wants.
	var ring := MeshInstance3D.new()
	var rm := TorusMesh.new()
	rm.inner_radius = 0.42
	rm.outer_radius = 0.5
	ring.mesh = rm
	ring.material_override = _glow(color, 1.5)
	ring.position = p + Vector3(0, 0.92, 0)
	add_child(ring)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	add_child(body)
	_shape(body, Vector3(0.8, 1.4, 0.8), p + Vector3(0, 0.7, 0))


# =================================================================== beams

func _relay_at(cell: Vector2i) -> Node:
	var item := _carryable_at(cell)
	return item if item in relays else null


## Does a beam stop at this cell (before entering it)?
func _beam_blocked(cell: Vector2i) -> bool:
	var k := ch(cell)
	if k == "#" or k == "Q" or k == "V":
		return true
	if doors.has(cell) and not doors[cell].is_open:
		return true
	return false


## Follow every beam through the relays. Relays that are hit by two
## different colours jam and send nothing. Recomputed whenever a relay moves.
func update_beams() -> void:
	if _beam_root:
		_beam_root.queue_free()
	_beam_root = Node3D.new()
	add_child(_beam_root)
	powered.clear()
	# Work out what colour reaches each relay (repeat until it settles,
	# because one relay can feed another).
	var inputs: Dictionary = {}   # relay -> Array of colours
	for pass_i in 8:
		var new_inputs: Dictionary = {}
		var sources := _sources(inputs)
		for src in sources:
			_trace(src[0], src[1], src[2], new_inputs, false)
		if _same_inputs(inputs, new_inputs):
			break
		inputs = new_inputs
	# Draw the final beams and light up receivers.
	powered.clear()
	for src in _sources(inputs):
		_trace(src[0], src[1], src[2], {}, true)
	for rl in relays:
		var cols_in: Array = inputs.get(rl, [])
		rl.show_signal(cols_in[0] if cols_in.size() == 1 else Color.BLACK, cols_in.size() > 1)
	for cell in receiver_lamps:
		var want: Color = RECEIVERS[cell]
		var lamp: StandardMaterial3D = receiver_lamps[cell]
		var lit: bool = powered.get(cell, Color.BLACK) == want
		lamp.emission = want if lit else Color(want.r * 0.25, want.g * 0.25, want.b * 0.25)
		lamp.emission_energy_multiplier = 4.0 if lit else 0.6
	_check_labs()


func _sources(inputs: Dictionary) -> Array:
	var out: Array = []
	for cell in EMITTERS:
		out.append([cell, EMITTERS[cell][0], EMITTERS[cell][1]])
	for rl in inputs:
		var cols_in: Array = inputs[rl]
		if cols_in.size() == 1 and is_instance_valid(rl):
			out.append([rl.cell, rl.dir(), cols_in[0]])
	return out


func _same_inputs(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for k in a:
		if not b.has(k) or a[k] != b[k]:
			return false
	return true


func _trace(from: Vector2i, d: Vector2i, color: Color, inputs: Dictionary, draw: bool) -> void:
	var cell := from
	var start := cell_to_world(from)
	for n in 60:
		var next := cell + d
		if _beam_blocked(next):
			if draw:
				_beam(start, cell_to_world(cell) + Vector3(d.x, 0, d.y) * (S / 2.0), color)
			return
		cell = next
		if RECEIVERS.has(cell):
			if draw:
				_beam(start, cell_to_world(cell), color)
				powered[cell] = color if not powered.has(cell) or powered[cell] == color else Color.WHITE
			return
		var rl := _relay_at(cell)
		if rl:
			if draw:
				_beam(start, cell_to_world(cell), color)
			var arr: Array = inputs.get(rl, [])
			if not color in arr:
				arr.append(color)
			inputs[rl] = arr
			return


func _beam(a: Vector3, b: Vector3, color: Color) -> void:
	var length := a.distance_to(b)
	if length < 0.05:
		return
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.07, 0.07, length)
	mi.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 3.0
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = m
	_beam_root.add_child(mi)
	var mid := (a + b) / 2.0
	mi.global_position = Vector3(mid.x, 1.0, mid.z)
	var dir := b - a
	mi.rotation.y = atan2(dir.x, dir.z)


func _check_labs() -> void:
	for lab in LABS:
		if solved.has(lab):
			continue
		var all_lit := true
		for cell in RECEIVERS:
			if room_at(cell) == lab and powered.get(cell, Color.BLACK) != RECEIVERS[cell]:
				all_lit = false
		if all_lit:
			solved[lab] = true
			_lab_solved(lab)


func _lab_solved(lab: String) -> void:
	Sound.play("key_ok", -2.0)
	Sound.play("power_on", -6.0, 1.4)
	if LAB_GATES.has(lab):
		var gate: Node = gates[LAB_GATES[lab]]
		gate.unlocked = true
		gate.stay_open = true
		unlock_cell(gate.cell)
		gate.open(true)
		hud.toast("%s SOLVED. A signal gate opened." % lab, 4.0)
		if lab == "RELAY LAB 1":
			hud.set_objective("Solve RELAY LAB 2 (its gate is open now, off the main hall).")
			hud.say("ai", "Good. The next lab is open. Remember: the signal goes through glass. You don't.")
		else:
			hud.set_objective("Solve RELAY LAB 3 (its gate is open now, off the main hall).")
			hud.say("ai", "Two colours in the last lab. Each receiver wants its own colour, and a relay hit by both colours jams.")
	else:
		exit_open = true
		exit_door.unlocked = true
		exit_door.stay_open = true
		unlock_cell(exit_door.cell)
		exit_door.open(true)
		hud.toast("%s SOLVED. The elevator is open." % lab, 4.0)
		hud.set_objective("Get to the elevator (elevator hall, bottom right).")
		hud.say("ai", "Every relay is lined up. The station is transmitting.")
		hud.say("unknown", "thank you. now everyone will hear it.")


## A relay moved, was picked up or turned: re-trace the beams.
func _on_carry_changed() -> void:
	update_beams()


func trail_shielded() -> bool:
	return room_at(world_to_cell(player.global_position)) in LABS


func gate_prompt(_door: Node) -> String:
	return "Signal gate: solve the open relay lab to power it"


func gate_interact(door: Node) -> void:
	Sound.play_at("locked", door.global_position, -2.0)
	hud.toast("This gate opens when the signal reaches the receiver in the previous lab.")


func exit_prompt(door: Node) -> String:
	return "" if door.unlocked else "Elevator: needs the signal from RELAY LAB 3"


func exit_interact(door: Node) -> void:
	Sound.play_at("locked", door.global_position, -2.0)
	hud.toast("The elevator runs on the station's signal. Solve all three relay labs.")


func _check_clues() -> void:
	pass


# =================================================================== story

func _intro() -> void:
	update_beams()
	hud.set_objective("Solve RELAY LAB 1 (next door).")
	hud.add_clue("Relays: E picks up and puts down, R turns. A beam leaves a relay the way its arrow points.")
	hud.add_clue("Beams go through glass. Each receiver needs its own colour. A relay hit by two colours jams.")
	await get_tree().create_timer(1.6).timeout
	hud.say("ai", "Sector 3: the relay station. Every signal in the facility is routed through here.")
	hud.say("ai", "Each relay lab opens the next. Point the signal beam into the receiver.")
	hud.say("ai", "Pick up a relay with E, put it down with E, and turn it with R. The beam leaves the way the arrow points.")
	hud.say("ai", "The labs are shielded. ECHO cannot follow you inside.")


func _process(delta: float) -> void:
	super._process(delta)
	if ended or player == null:
		return
	var room := room_at(world_to_cell(player.global_position))
	if room != _player_room:
		_player_room = room
		if room in LABS and echo and echo.visible and not visited.has("shield_" + room):
			visited["shield_" + room] = true
			hud.toast("Shielded lab: ECHO can't follow you in. It's waiting outside.", 3.5)


func _entered_room(room: String) -> void:
	match room:
		"MAIN HALL":
			listener.set_physics_process(true)
			hud.say("ai", "The hall is not shielded. Move with purpose.")
		"RELAY LAB 2":
			hud.say("ai", "The receiver is behind the glass. You can't reach it, but the signal can.")
		"RELAY LAB 3":
			hud.say("ai", "Red goes to red. Blue goes to blue. Don't let one relay catch both.")
		"CRAWLSPACE":
			hud.toast("A secret room!", 2.5)


func _end_story() -> String:
	return ("Every relay in the station lit up at once and pointed the same way: down.\n"
		+ "Somewhere below, something answered. It used your voice.\n\nSector 4 is waiting below.")
