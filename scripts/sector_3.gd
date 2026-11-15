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
var receivers: Dictionary = RECEIVERS.duplicate()   # cell -> colour (they move each game)
var _sol_cells: Dictionary = {}     # squares the last solution's beams cross
var beam_solution: Dictionary = {}   # lab -> [[cell, facing], ...]: proof each lab can be solved
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


func _no_spawn_rooms() -> Array:
	return no_wander_rooms + LABS


## Key items that move to a random spot in their room each game.
func _scatter_chars() -> Array:
	return []   # the relays and receivers move in _setup_puzzles


## Each game the receivers move to new spots, so every lab needs a different
## answer. A layout is only used if the solver below can solve it with the
## lab's relays (and it isn't too easy). The relays start scattered around
## the part of the lab you can walk in.
const LAB_RELAYS := {"RELAY LAB 1": [1, 1], "RELAY LAB 2": [2, 3], "RELAY LAB 3": [2, 4]}   # [fewest, most]
const DIRS4 := [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]


func _setup_puzzles() -> void:
	if Game.fixed_layout:
		return
	for lab in LABS:
		_randomize_lab(lab)


func _randomize_lab(lab: String) -> void:
	var original_map: Array = map.duplicate()
	var lab_receivers: Array = []
	for c in receivers:
		if room_at(c) == lab:
			lab_receivers.append(c)
	var lab_relay_count := 0
	for r in rows:
		for c in cols:
			if ch(Vector2i(c, r)) == "r" and room_at(Vector2i(c, r)) == lab:
				lab_relay_count += 1
	for attempt in 300:
		map = original_map.duplicate()
		# Lift the relays and receivers out, then put the receivers somewhere new.
		var new_recv: Dictionary = {}
		for r in rows:
			for c in cols:
				var cell := Vector2i(c, r)
				if room_at(cell) == lab and ch(cell) in ["r", "O"]:
					_set_ch(cell, ".")
		var ok := true
		for old in lab_receivers:
			var spots := _receiver_spots(lab, old)
			if spots.is_empty():
				ok = false
				break
			var to: Vector2i = spots[randi() % spots.size()]
			_set_ch(to, "O")
			new_recv[to] = receivers[old]
		if not ok:
			continue
		var usable := _lab_reachable(lab)
		if usable.is_empty() or not _fragments_reachable(lab, usable):
			continue
		var sol = _solve_lab(lab, new_recv, usable)
		if sol == null:
			continue
		# It works: keep it. Scatter the relays where you can reach them, but
		# not in a transmitter's beam (so nothing lights up by itself).
		for old in lab_receivers:
			receivers.erase(old)
		for c in new_recv:
			receivers[c] = new_recv[c]
		beam_solution[lab] = sol
		var in_beam := _emitter_lines(lab)
		var free: Array = []
		for c in usable:
			if ch(c) == "." and not in_beam.has(c) and not _sol_cells.has(c):
				free.append(c)
		free.shuffle()
		for i in mini(lab_relay_count, free.size()):
			_set_ch(free[i], "r")
		return
	map = original_map   # no luck: the hand-made layout


## Where a receiver can go: plain floor in the lab, on the same side of any
## glass as it was, and not right next to a door, a transmitter or another receiver.
func _receiver_spots(lab: String, old: Vector2i) -> Array:
	var rect := room_rect(lab)
	var behind_glass := _behind_glass(lab, old)
	var out: Array = []
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var c := Vector2i(x, y)
			if ch(c) != "." or _behind_glass(lab, c) != behind_glass:
				continue
			var crowded := false
			for d in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
				if ch(c + d) in ["D", "G", "Q", "O", "f"]:
					crowded = true
			if not crowded:
				out.append(c)
	return out


## Is this square on the far side of the lab's glass wall (where you can't go)?
func _behind_glass(lab: String, c: Vector2i) -> bool:
	var rect := room_rect(lab)
	for x in range(rect.position.x, c.x):
		if ch(Vector2i(x, c.y)) == "w":
			return true
	return false


## The squares of the lab you can walk to from its entrance.
func _lab_reachable(lab: String) -> Dictionary:
	var rect := room_rect(lab)
	var todo: Array[Vector2i] = []
	var seen: Dictionary = {}
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var c := Vector2i(x, y)
			for d in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
				if ch(c + d) in ["D", "G"] and not rect.has_point(c + d) and _walkable(c):
					seen[c] = true
					todo.append(c)
	while not todo.is_empty():
		var c: Vector2i = todo.pop_back()
		for d in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
			var n: Vector2i = c + d
			if rect.has_point(n) and not seen.has(n) and _walkable(n):
				seen[n] = true
				todo.append(n)
	return seen


func _walkable(c: Vector2i) -> bool:
	return ch(c) in [".", "r", "f", "i", "L"]


func _fragments_reachable(lab: String, usable: Dictionary) -> bool:
	var rect := room_rect(lab)
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if ch(Vector2i(x, y)) == "f" and not usable.has(Vector2i(x, y)):
				return false
	return true


## Squares a transmitter's beam crosses before it hits anything.
func _emitter_lines(lab: String) -> Dictionary:
	var out: Dictionary = {}
	for e in EMITTERS:
		if room_at(e) != lab:
			continue
		var d: Vector2i = EMITTERS[e][0]
		var c: Vector2i = e + d
		while room_at(c) == lab and not _solve_blocked(c, lab):
			out[c] = true
			c += d
	return out


## Solve a lab: relays (cell, facing) that light every receiver, using between
## the lab's fewest and most relays. null if it can't be done that way.
func _solve_lab(lab: String, recv: Dictionary, usable: Dictionary):
	var limits: Array = LAB_RELAYS[lab]
	var emitters: Array = []
	for e in EMITTERS:
		if room_at(e) == lab:
			emitters.append(e)
	var all_relays: Array = []
	_sol_cells.clear()
	var avoid_pass: Dictionary = {}
	var avoid_relay: Dictionary = {}
	for e in emitters:
		var want: Color = EMITTERS[e][1]
		var target := Vector2i(-1, -1)
		for c in recv:
			if recv[c] == want:
				target = c
		if target.x < 0:
			return null
		var res = _solve_beam(e, EMITTERS[e][0], target, lab, usable, avoid_pass, avoid_relay, int(limits[1]) - all_relays.size())
		if res == null or (res["relays"] as Array).is_empty():
			return null   # every beam needs at least one relay
		for r in res["relays"]:
			all_relays.append(r)
			avoid_pass[r[0]] = true
			avoid_relay[r[0]] = true
		for c in res["cells"]:
			avoid_relay[c] = true
			_sol_cells[c] = true
	if all_relays.size() < int(limits[0]) or all_relays.size() > int(limits[1]):
		return null
	var out: Array = []
	for r in all_relays:
		out.append([r[0], DIRS4.find(r[1])])
	return out


func _solve_blocked(c: Vector2i, lab: String) -> bool:
	return room_at(c) != lab or ch(c) in ["#", "Q", "V", "D", "G", "X"]


## Fewest relays that bring a beam from a transmitter into the target:
## {"relays": [[cell, dir]...], "cells": every square the beam crosses}, or null.
## The beam can't cross avoid_pass (another beam's relays would grab it) and
## no relay may go on avoid_relay (another beam's path).
func _solve_beam(from: Vector2i, d: Vector2i, target: Vector2i, lab: String, usable: Dictionary, avoid_pass: Dictionary, avoid_relay: Dictionary, max_relays: int):
	var frontier: Array = [[from, d, [], []]]   # start, dir, relays, cells crossed
	var seen: Dictionary = {}
	for turns in max_relays + 1:
		var nxt: Array = []
		frontier.shuffle()   # different answers on different tries
		for st in frontier:
			var c: Vector2i = st[0]
			var dir: Vector2i = st[1]
			var used: Array = st[2]
			var crossed: Array = (st[3] as Array).duplicate()
			for n in 60:
				var nx: Vector2i = c + dir
				if _solve_blocked(nx, lab) or avoid_pass.has(nx):
					break
				if nx == target:
					crossed.append(nx)
					return {"relays": used, "cells": crossed}
				if ch(nx) == "O":
					break   # another receiver stops it
				var hits_own := false
				for u in used:
					if u[0] == nx:
						hits_own = true
				if hits_own:
					break
				c = nx
				crossed.append(c)
				if turns < max_relays and usable.has(c) and ch(c) == "." and not avoid_relay.has(c) and crossed.count(c) == 1:
					for nd in DIRS4:
						if nd == dir or nd == -dir:
							continue
						var key := [c, nd]
						if seen.has(key):
							continue
						seen[key] = true
						var u2: Array = used.duplicate()
						u2.append([c, nd])
						nxt.append([c, nd, u2, crossed.duplicate()])
		frontier = nxt
	return null


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
			body.set_meta("surface", "glass")
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
	body.set_meta("surface", "metal")
	add_child(body)
	_shape(body, Vector3(0.9, 1.1, 0.9), p + Vector3(0, 0.55, 0))


func _spawn_receiver(cell: Vector2i) -> void:
	var color: Color = receivers[cell]
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
	body.set_meta("surface", "metal")
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
		var want: Color = receivers[cell]
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
		if receivers.has(cell):
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
		for cell in receivers:
			if room_at(cell) == lab and powered.get(cell, Color.BLACK) != receivers[cell]:
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
