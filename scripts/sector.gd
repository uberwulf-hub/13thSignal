extends Node3D
## SECTOR 1: INTAKE, and the shared base for every sector.
##
## The base builds a facility from a text map and runs everything sectors
## share: monsters (the Listener, the Replacement, ECHO), lockers, noise,
## checkpoints, scares, catching and the end screen. Later sectors extend this
## script and override the hooks marked "SECTOR HOOK" (map, rooms, puzzles,
## story). Sector 1's own puzzles live in this file too.
##
## The escape route:
##   1. Find the maintenance note (Break Room): the breaker order.
##   2. Find the security keycard (Office), open SECURITY off the main hall.
##   3. Flip the three breakers in the right order -> power comes back on.
##      (A voice that sounds like MERIDIAN lies to you about the order.)
##   4. The elevator door shows a colour order. Find the 4 painted numbers
##      (red, blue, green, yellow) around the sector and type in the code.
##   5. Get in the elevator.
## Secrets: 3 signal fragments, one behind a low vent you must crouch through.

const Player := preload("res://scripts/player.gd")
const Listener := preload("res://scripts/listener.gd")
const Replacement := preload("res://scripts/replacement.gd")
const Hud := preload("res://scripts/hud.gd")
const Door := preload("res://scripts/door.gd")
const Locker := preload("res://scripts/locker.gd")
const Interactable := preload("res://scripts/interactable.gd")
const Echo := preload("res://scripts/echo.gd")
const TouchControls := preload("res://scripts/touch_controls.gd")

const S := 3.0         # one map cell is 3 x 3 metres
const WALL_H := 3.2
const VENT_H := 1.15
const CHUNK := 5       # floors, ceilings and walls are built in 5 x 5 cell pieces

## Map legend:
##  #  wall           .  floor          P  you start here
##  D  door           K  keycard door   X  elevator door (power + code)
##  E  elevator       V  low vent (crouch)
##  L  locker         g  metal grate (LOUD to walk on)
##  i  intercom (checkpoint)            n  maintenance note
##  k  keycard        B  breaker panel  f  signal fragment (secret)
##  1-4  painted numbers for the exit code
##  M  the Listener starts here         R  the Replacement stands here
const MAP := [
	"###########################",
	"#.....#.L...L.#.....#.....#",
	"#.P...D...n...#..1..#..R..#",
	"#..i..#.......#.....D.....#",
	"#.....#.......#.L...#..f..#",
	"###D######D######D####D####",
	"#...L...ggg.......ggg..L..#",
	"#.......ggg...i...ggg.....#",
	"#.......ggg.......ggg.....#",
	"###D######D######K####D####",
	"#.....#.......#.....#....f#",
	"#..k..#...2...#..B..#..4..#",
	"#.....#.......#.....#....L#",
	"#L....#...M...#..3..#.....#",
	"###V####D############D#####",
	"#...#..........i.......#..#",
	"#.f.#..................X.E#",
	"#...#....L.......L.....#..#",
	"###########################",
]

const ROOMS := [
	["MED BAY", Rect2i(1, 1, 5, 4)],
	["BREAK ROOM", Rect2i(7, 1, 7, 4)],
	["RECORDS", Rect2i(15, 1, 5, 4)],
	["LAB 2", Rect2i(21, 1, 5, 4)],
	["MAIN HALL", Rect2i(1, 6, 25, 3)],
	["OFFICE", Rect2i(1, 10, 5, 4)],
	["STORAGE", Rect2i(7, 10, 7, 4)],
	["SECURITY", Rect2i(15, 10, 5, 4)],
	["PUMP ROOM", Rect2i(21, 10, 5, 4)],
	["LOWER HALL", Rect2i(5, 15, 18, 3)],
	["CRAWLSPACE", Rect2i(1, 15, 3, 3)],
	["ELEVATOR", Rect2i(24, 15, 2, 3)],
]

const CODE_COLORS := [
	["RED", Color(1.0, 0.25, 0.2)],
	["BLUE", Color(0.3, 0.55, 1.0)],
	["GREEN", Color(0.3, 0.95, 0.4)],
	["YELLOW", Color(1.0, 0.9, 0.2)],
]

const BREAKER_ORDER := ["RIGHT", "MIDDLE", "LEFT"]   # the hand-made order (tests)

const FRAGMENT_TEXT := [
	"\"Sector 13 isn't on any map because we never built it. So who is broadcasting from down there?\"",
	"\"MERIDIAN says it hears a second voice on its own channel. The second voice sounds exactly like MERIDIAN.\"",
	"\"Whatever you do, don't answer the signal. It learns your voice.\"",
]

# --- What this sector is (later sectors change these) ---
var sector_id := 1
var sector_title := "SECTOR 1  -  INTAKE"
var next_scene := "res://scenes/sector_2.tscn"
var map: Array = MAP
var rooms: Array = ROOMS
var fragment_text: Array = FRAGMENT_TEXT
var no_wander_rooms: Array = ["CRAWLSPACE", "ELEVATOR", ""]
var has_replacement := false
var echo_enabled := false

var rows := 0
var cols := 0
var grid := AStarGrid2D.new()
var player: Player
var listener: Listener
var replacement: Replacement
var hud: Hud
var echo: Echo
var trail: Array[Vector3] = []   # where you've walked, for ECHO to copy
var _trail_t := 0.0

var doors: Dictionary = {}       # Vector2i -> door
var lockers: Array = []
var grates: Dictionary = {}      # Vector2i -> true
var wander_cells: Array[Vector2i] = []
var lights: Array = []           # [{light, fixture, flicker}]
var intercoms: Array = []        # [{cell, lamp}]
var traps: Array = []
var glows: Array = []            # lit glow sticks

var start_cell := Vector2i.ZERO
var listener_home := Vector3.ZERO
var replacement_home := Vector3.ZERO
var checkpoint := Vector3.ZERO
var checkpoint_yaw := 0.0

# Puzzle state.
var has_keycard := false
var power_on := false
var exit_open := false
var breaker_seq: Array[String] = []
var breaker_order: Array = BREAKER_ORDER.duplicate()   # random each game
var breaker_clues: Array = []          # the note's two lines that pin it down
var digit_colors: Array = [0, 1, 2, 3] # which colour each painted number is
var levers: Dictionary = {}      # "LEFT"/"MIDDLE"/"RIGHT" -> lever mesh
var code_digits: Array[int] = []    # one digit per colour in CODE_COLORS
var code_order: Array[int] = []     # colour indexes in the order the elevator wants
var exit_code := ""
var digit_spots: Array = []      # [{pos, color, room, found}]
var exit_door: Node
var order_seen := false

# Run state.
var paused_world := false
var ended := false
var catching := false
var catches := 0
var fragments := 0
var fragment_total := 0
var run_time := 0.0
var visited: Dictionary = {}
var _env: Environment
var _event_t := 0.0
var _ambient_t := 0.0
var _clue_t := 0.0
var _last_cell := Vector2i(-1, -1)
var _hunt_warnings := 0
var _blackout_t := 0.0
var _hid_recently := 0.0


func _ready() -> void:
	Game.reset_run()
	_configure()
	rows = map.size()
	cols = String(map[0]).length()
	# Every game is different: key items move to a random spot in their own
	# room (so the order you solve things in still works). Tests can turn
	# this off to check the hand-made layouts.
	map = map.duplicate()
	if not Game.fixed_layout:
		_scatter_in_room(_scatter_chars())
		_place_monsters()
	_setup_puzzles()
	_build_environment()
	_build_level()
	_build_grid()
	hud = Hud.new()
	hud.sector = self
	add_child(hud)
	_spawn_actors()
	_spawn_loot()
	# Whatever you carried out of the last sector comes with you.
	var carried: Array = Game.carried_for(sector_id)
	if not carried.is_empty():
		player.inventory = carried
		player.selected = 0
		player._hand_id = "-"
		player._inventory_changed()
	if Game.use_touch():
		add_child(TouchControls.new().setup(self))
	hud.set_fragments(0, fragment_total)
	Game.capture_mouse()
	Sound.start_ambient(-11.0)
	var gap: Vector2 = Game.mode_data()["scare_gap"]
	_event_t = randf_range(gap.x, gap.y)
	_ambient_t = randf_range(8.0, 16.0)
	_intro()


## SECTOR HOOK: set sector_id, map, rooms, etc. (Sector 1 uses the defaults.)
func _configure() -> void:
	pass


## SECTOR HOOK: prepare random puzzle answers before the level is built.
func _setup_puzzles() -> void:
	_make_code()
	_make_breakers()


## A new breaker order every game, and two clues for the maintenance note
## that together pin it down (but neither does on its own).
func _make_breakers() -> void:
	if Game.fixed_layout:
		breaker_order = BREAKER_ORDER.duplicate()
		breaker_clues = ["NEVER start with the MIDDLE breaker.", "The LEFT breaker always goes LAST."]
		return
	digit_colors.shuffle()
	var sides := ["LEFT", "MIDDLE", "RIGHT"]
	var perms: Array = []
	for a in sides:
		for b in sides:
			for c in sides:
				if a != b and b != c and a != c:
					perms.append([a, b, c])
	breaker_order = perms[randi() % perms.size()]
	var clues := _breaker_clue_pool()
	var truths: Array = []
	for cl in clues:
		if cl[1].call(breaker_order):
			truths.append(cl)
	truths.shuffle()
	for i in truths.size():
		for j in range(i + 1, truths.size()):
			var fits := 0
			var alone_i := 0
			var alone_j := 0
			for p in perms:
				var ti: bool = truths[i][1].call(p)
				var tj: bool = truths[j][1].call(p)
				fits += 1 if ti and tj else 0
				alone_i += 1 if ti else 0
				alone_j += 1 if tj else 0
			if fits == 1 and alone_i > 1 and alone_j > 1:
				breaker_clues = [truths[i][0], truths[j][0]]
				return
	breaker_clues = ["The %s breaker goes FIRST." % breaker_order[0], "The %s breaker goes LAST." % breaker_order[2]]


## Things the maintenance note might say: [text, does it hold for this order?].
func _breaker_clue_pool() -> Array:
	var pool: Array = []
	for s in ["LEFT", "MIDDLE", "RIGHT"]:
		pool.append(["NEVER start with the %s breaker." % s, func(o): return o[0] != s])
		pool.append(["The %s breaker always goes LAST." % s, func(o): return o[2] == s])
		pool.append(["The %s breaker never goes last." % s, func(o): return o[2] != s])
		pool.append(["Start with the %s breaker." % s, func(o): return o[0] == s])
		pool.append(["The %s breaker goes second." % s, func(o): return o[1] == s])
		for t in ["LEFT", "MIDDLE", "RIGHT"]:
			if t != s:
				pool.append(["Flip %s straight after %s." % [s, t], func(o): return o.find(s) == o.find(t) + 1])
				pool.append(["%s comes before %s." % [s, t], func(o): return o.find(s) < o.find(t)])
	return pool


## SECTOR HOOK: map characters (key items) that move to a random spot in
## their own room each game.
func _scatter_chars() -> Array:
	return ["k", "n"]


## Move each of these map characters to a random free floor square in the
## same room: not next to a door or another object, not where you start.
func _scatter_in_room(chars: Array) -> void:
	var taken: Dictionary = {}
	for r in rows:
		for c in cols:
			var cell := Vector2i(c, r)
			var k := ch(cell)
			if not k in chars:
				continue
			var room := room_at(cell)
			if room == "":
				continue
			var spots: Array[Vector2i] = []
			var rect: Rect2i = room_rect(room)
			for y in range(rect.position.y, rect.end.y):
				for x in range(rect.position.x, rect.end.x):
					var s := Vector2i(x, y)
					if s != cell and (not ch(s) in [".", "g"] or taken.has(s) or not _scatter_ok(s)):
						continue
					spots.append(s)
			if spots.is_empty():
				continue
			var to: Vector2i = spots[randi() % spots.size()]
			taken[to] = true
			var under := ch(to)
			_set_ch(cell, under)   # swap, so a grate floor stays a grate floor
			_set_ch(to, k)


## SECTOR HOOK: rooms a monster must never start in (safe rooms, labs).
func _no_spawn_rooms() -> Array:
	return no_wander_rooms


## The monsters start somewhere different every game: the Listener (M) and
## the Replacement (R) each pick a random square they could walk to you
## from, far from where you start (14+ squares' walk for the Listener, 10+
## for the Replacement), never in your starting room, a safe room or a lab,
## and not in the same room as each other.
func _place_monsters() -> void:
	var start := Vector2i(-1, -1)
	for r in rows:
		for c in cols:
			if ch(Vector2i(c, r)) == "P":
				start = Vector2i(c, r)
	if start.x < 0:
		return
	var solid := _solid_chars()
	var dist: Dictionary = {start: 0}
	var todo: Array[Vector2i] = [start]
	var i := 0
	while i < todo.size():
		var cur: Vector2i = todo[i]
		i += 1
		for d in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
			var n: Vector2i = cur + d
			if dist.has(n) or n.x < 0 or n.y < 0 or n.y >= rows or n.x >= cols:
				continue
			var k := ch(n)
			if k in solid and k != "D":
				continue
			dist[n] = dist[cur] + 1
			todo.append(n)
	var start_room := room_at(start)
	var banned := _no_spawn_rooms()
	var used_room := ""
	for pair in [["M", 14], ["R", 10]]:
		var who: String = pair[0]
		var old := Vector2i(-1, -1)
		for r in rows:
			for c in cols:
				if ch(Vector2i(c, r)) == who:
					old = Vector2i(c, r)
		if old.x < 0:
			continue
		var spots: Array = []
		for cell in dist:
			var room := room_at(cell)
			if ch(cell) == "." and int(dist[cell]) >= int(pair[1]) and room != start_room and room != used_room \
					and not room in banned and _scatter_ok(cell):
				spots.append(cell)
		if spots.is_empty():
			continue
		var to: Vector2i = spots[randi() % spots.size()]
		_set_ch(old, ".")
		_set_ch(to, who)
		used_room = room_at(to)


## A free spot: its four neighbours are plain floor, walls, grates or lockers
## (nothing that would block a door or crowd another object).
func _scatter_ok(s: Vector2i) -> bool:
	for d in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
		if not ch(s + d) in [".", "#", "g", "L"]:
			return false
	return true


func _set_ch(c: Vector2i, k: String) -> void:
	var row: String = map[c.y]
	map[c.y] = row.substr(0, c.x) + k + row.substr(c.x + 1)


## SECTOR HOOK: a map character the base doesn't know about.
func _custom_cell(_k: String, _cell: Vector2i) -> void:
	pass


## SECTOR HOOK: map characters that monsters can't path through (at the start).
func _solid_chars() -> Array:
	return ["#", "V", "K", "X"]


## SECTOR HOOK: the story text on the end screen.
func _end_story() -> String:
	return "The elevator goes down, not up.\nSomewhere below, a 13th sector that isn't on any map is still broadcasting."


func _intro() -> void:
	hud.set_objective("Find a way out of Sector 1.")
	await get_tree().create_timer(1.6).timeout
	hud.say("ai", "Good morning. You are awake eleven hours ahead of schedule.")
	hud.say("ai", "I am MERIDIAN, the facility assistant. Please remain calm.")
	hud.say("ai", "Sector 1 is sealed. The service elevator is the only way out. It has no power.")


# ===================================================================== map

func ch(c: Vector2i) -> String:
	if c.x < 0 or c.y < 0 or c.x >= cols or c.y >= rows:
		return "#"
	return String(map[c.y])[c.x]


func cell_to_world(c: Vector2i) -> Vector3:
	return Vector3(c.x * S, 0.0, c.y * S)


func world_to_cell(p: Vector3) -> Vector2i:
	return Vector2i(roundi(p.x / S), roundi(p.z / S))


func room_at(c: Vector2i) -> String:
	for r in rooms:
		var rect: Rect2i = r[1]
		if rect.has_point(c):
			return r[0]
	return ""


## The nearest wall in a straight line from this cell: [normal pointing into
## the room, distance in cells]. Checks west, east, north, south.
func nearest_wall(c: Vector2i) -> Array:
	var best: Array = [Vector3.FORWARD, 99]
	for d in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
		var n := 1
		while n < 10:
			var k := ch(c + d * n)
			if k == "#":
				if n < int(best[1]):
					best = [Vector3(-d.x, 0, -d.y), n]
				break
			if k in ["D", "K", "X", "V", "a", "b", "c"]:
				break
			n += 1
	return best


## A point on the face of that wall, at height y.
func wall_point(c: Vector2i, y: float) -> Array:
	var w := nearest_wall(c)
	var normal: Vector3 = w[0]
	var dist: int = w[1]
	var p := cell_to_world(c) - normal * (dist * S - S / 2.0)
	p.y = y
	return [p, normal]


# ============================================================= environment

func _build_environment() -> void:
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = Color(0, 0, 0)
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.35, 0.42, 0.55)
	_env.ambient_light_energy = float(Game.mode_data()["ambient"]) * 1.6
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.fog_enabled = true
	_env.fog_light_color = Color(0.01, 0.015, 0.025)
	_env.fog_density = 0.035
	_env.glow_enabled = Game.gfx() >= 1
	_env.glow_intensity = 0.6
	# High graphics: soft shadows in corners and a misty air your flashlight cuts
	# through. (Phones and the Low setting skip these.)
	if Game.gfx() >= 1:
		_env.ssao_enabled = true
		_env.ssao_radius = 1.5
		_env.ssao_intensity = 2.5
	if Game.gfx() >= 2:
		_env.tonemap_mode = Environment.TONE_MAPPER_ACES
		_env.tonemap_exposure = 1.1
		_env.fog_enabled = false
		_env.volumetric_fog_enabled = true
		_env.volumetric_fog_density = 0.035
		_env.volumetric_fog_albedo = Color(0.7, 0.75, 0.8)
		_env.volumetric_fog_emission = Color(0.0, 0.0, 0.0)
		_env.volumetric_fog_length = 40.0
	_env.adjustment_enabled = true

	_env.adjustment_brightness = Game.brightness
	_env.adjustment_saturation = 0.8
	var we := WorldEnvironment.new()
	we.environment = _env
	add_child(we)


func _mat(color: Color, rough := 0.85, metal := 0.0, scale := 0.35) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	var n := FastNoiseLite.new()
	n.frequency = 0.035
	n.fractal_octaves = 4
	tex.noise = n
	var g := Gradient.new()
	g.set_color(0, Color(0.55, 0.55, 0.55))
	g.set_color(1, Color(1, 1, 1))
	tex.color_ramp = g
	m.albedo_texture = tex
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * scale
	return m


func _box(size: Vector3, pos: Vector3, mat: Material, parent: Node = self) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi


func _glow(color: Color, energy := 2.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


func _label(text: String, pos: Vector3, normal: Vector3, size: int, color: Color, px := 0.005) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = px
	l.modulate = color
	l.outline_size = 0
	l.position = pos + normal * 0.02
	l.rotation.y = atan2(normal.x, normal.z)
	add_child(l)
	return l


# =================================================================== level

func _build_level() -> void:
	# Real photographed surfaces (Poly Haven, CC0), with the old painted look as a fallback.
	var wall_mat: Material = Game.tex_mat("wall", 0.33, Color(0.8, 0.82, 0.86))
	if wall_mat == null:
		wall_mat = _mat(Color(0.32, 0.36, 0.4), 0.9, 0.0, 0.3)
	var floor_mat: Material = Game.tex_mat("floor", 0.33, Color(0.75, 0.75, 0.75))
	if floor_mat == null:
		floor_mat = _mat(Color(0.2, 0.21, 0.22), 0.95, 0.0, 0.5)
	var ceil_mat: Material = Game.tex_mat("ceiling", 0.33, Color(0.55, 0.55, 0.58))
	if ceil_mat == null:
		ceil_mat = _mat(Color(0.12, 0.13, 0.15), 0.95)
	var grate_mat: Material = Game.tex_mat("grate", 0.66, Color.WHITE, 0.6)
	if grate_mat == null:
		grate_mat = _mat(Color(0.42, 0.3, 0.2), 0.5, 0.7, 0.9)

	# Floor and ceiling, in chunks. (Phones light each object with at most a
	# few lights, so one huge floor would leave most rooms dark there.)
	var center := Vector3((cols - 1) * S / 2.0, 0, (rows - 1) * S / 2.0)
	for cy in range(0, rows, CHUNK):
		for cx in range(0, cols, CHUNK):
			var w := mini(CHUNK, cols - cx)
			var h := mini(CHUNK, rows - cy)
			var mid := Vector3((cx + (w - 1) / 2.0) * S, 0, (cy + (h - 1) / 2.0) * S)
			_box(Vector3(w * S, 0.2, h * S), mid + Vector3(0, -0.1, 0), floor_mat)
			_box(Vector3(w * S, 0.2, h * S), mid + Vector3(0, WALL_H + 0.1, 0), ceil_mat)
	var solid := StaticBody3D.new()
	solid.collision_layer = 1
	solid.collision_mask = 0
	add_child(solid)
	_shape(solid, Vector3(cols * S, 0.2, rows * S), center + Vector3(0, -0.1, 0))
	_shape(solid, Vector3(cols * S, 0.2, rows * S), center + Vector3(0, WALL_H + 0.1, 0))

	# Walls, as one MultiMesh (fast) plus collision boxes.
	var wall_cells: Array[Vector2i] = []
	for r in rows:
		for c in cols:
			if ch(Vector2i(c, r)) == "#":
				wall_cells.append(Vector2i(c, r))
	var wall_mesh := BoxMesh.new()
	wall_mesh.size = Vector3(S, WALL_H, S)
	wall_mesh.material = wall_mat
	var wall_shape := BoxShape3D.new()
	wall_shape.size = Vector3(S, WALL_H, S)
	var chunks: Dictionary = {}   # chunk -> Array of wall positions
	for wc in wall_cells:
		var p := cell_to_world(wc) + Vector3(0, WALL_H / 2.0, 0)
		var key := Vector2i(wc.x / CHUNK, wc.y / CHUNK)
		if not chunks.has(key):
			chunks[key] = []
		chunks[key].append(p)
		var cs := CollisionShape3D.new()
		cs.shape = wall_shape
		cs.position = p
		solid.add_child(cs)
	for key in chunks:
		var list: Array = chunks[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = wall_mesh
		mm.instance_count = list.size()
		for i in list.size():
			mm.set_instance_transform(i, Transform3D(Basis(), list[i]))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		add_child(mmi)

	# A painted stripe along the walls of each room helps you find your way.
	var stripe_mat := _glow(Color(0.15, 0.35, 0.5), 0.6)

	for r in rows:
		for c in cols:
			var cell := Vector2i(c, r)
			var k := ch(cell)
			var p := cell_to_world(cell)
			match k:
				"P":
					start_cell = cell
				"M":
					listener_home = p
				"R":
					replacement_home = p
					has_replacement = true
				"g":
					grates[cell] = true
					_box(Vector3(S, 0.04, S), p + Vector3(0, 0.02, 0), grate_mat)
					for s in 5:
						_box(Vector3(S, 0.05, 0.08), p + Vector3(0, 0.04, -S / 2.0 + 0.3 + s * 0.6), grate_mat)
				"D", "K", "X":
					_spawn_door(cell, k)
				"V":
					_box(Vector3(S, WALL_H - VENT_H, S), p + Vector3(0, VENT_H + (WALL_H - VENT_H) / 2.0, 0), wall_mat)
					_shape(solid, Vector3(S, WALL_H - VENT_H, S), p + Vector3(0, VENT_H + (WALL_H - VENT_H) / 2.0, 0))
					_box(Vector3(S * 0.96, 0.06, 0.06), p + Vector3(0, VENT_H - 0.05, -S / 2.0 + 0.05), _glow(Color(0.25, 0.25, 0.3), 0.3))
				"L":
					_spawn_locker(cell)
				"i":
					_spawn_intercom(cell)
				"n":
					_spawn_note(cell)
				"k":
					_spawn_keycard(cell)
				"B":
					_spawn_breakers(cell)
				"f":
					_spawn_fragment(cell)
				"1", "2", "3", "4":
					_spawn_digit(cell, int(k) - 1)
				"E":
					_spawn_exit(cell)
				_:
					_custom_cell(k, cell)
	_build_rooms(stripe_mat)
	_dress_elevator()


func _shape(body: StaticBody3D, size: Vector3, pos: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	cs.shape = b
	cs.position = pos
	body.add_child(cs)


func _build_rooms(stripe_mat: Material) -> void:
	var light_mult: float = [1.25, 1.0, 0.7][Game.mode]
	for room in rooms:
		var room_name: String = room[0]
		var rect: Rect2i = room[1]
		var center := Vector3((rect.position.x + (rect.size.x - 1) / 2.0) * S, 0, (rect.position.y + (rect.size.y - 1) / 2.0) * S)
		# The room's name stencilled on the floor.
		if room_name != "CRAWLSPACE" and room_name != "ELEVATOR":
			var l := Label3D.new()
			l.text = room_name if room_name != "MAIN HALL" else sector_title
			# Stencilled along the room's long side, and small enough that the
			# whole name fits (narrow halls and shafts got cut off before).
			l.font_size = 96
			l.outline_size = 0
			var along_z := rect.size.y > rect.size.x
			var long_m := float(maxi(rect.size.x, rect.size.y)) * S * 0.8
			var short_m := float(mini(rect.size.x, rect.size.y)) * S * 0.6
			var text_w := float(l.text.length()) * 96.0 * 0.62   # rough width in font pixels
			l.pixel_size = minf(0.008, minf(long_m / text_w, short_m / 96.0))
			l.modulate = Color(0.85, 0.88, 0.9, 0.55)
			l.rotation = Vector3(-PI / 2.0, PI / 2.0 if along_z else 0.0, 0)
			l.position = center + Vector3(0, 0.03, 0)
			add_child(l)
		# Ceiling lights.
		if room_name == "CRAWLSPACE":
			continue
		var count := maxi(1, ceili(rect.size.x / 4.0))
		for i in count:
			var x := (rect.position.x - 0.5 + (i + 0.5) * rect.size.x / float(count)) * S
			var pos := Vector3(x, WALL_H - 0.35, center.z)
			var light := OmniLight3D.new()
			light.position = pos
			light.omni_range = 8.0
			light.omni_attenuation = 1.4
			light.light_color = Color(0.35, 0.5, 1.0)
			light.light_energy = 0.55 * light_mult
			if room_name == "ELEVATOR":
				light.light_color = Color(1.0, 0.85, 0.4)
			add_child(light)
			var fixture := _box(Vector3(1.2, 0.08, 0.3), pos + Vector3(0, 0.3, 0), _glow(Color(0.35, 0.5, 1.0), 1.5))
			lights.append({"light": light, "fixture": fixture, "flicker": randf() < 0.3, "mult": light_mult, "room": room_name})
		# Pipes along the halls.
		if room_name.ends_with("HALL"):
			var pipe := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.12
			cyl.bottom_radius = 0.12
			cyl.height = rect.size.x * S
			pipe.mesh = cyl
			pipe.material_override = _mat(Color(0.3, 0.28, 0.25), 0.4, 0.8)
			pipe.rotation.z = PI / 2.0
			pipe.position = Vector3(center.x, WALL_H - 0.25, (rect.position.y - 0.5) * S + 0.25)
			add_child(pipe)
	# Wayfinding stripe on every wall face next to a floor cell.
	for r in rows:
		for c in cols:
			var cell := Vector2i(c, r)
			if ch(cell) == "#":
				continue
			for d in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
				if ch(cell + d) == "#":
					var n := Vector3(-d.x, 0, -d.y)
					var p := cell_to_world(cell) - n * (S / 2.0 - 0.01)
					var size := Vector3(S, 0.06, 0.02) if d.y != 0 else Vector3(0.02, 0.06, S)
					_box(size, p + Vector3(0, 1.0, 0), stripe_mat)


func _build_grid() -> void:
	grid.region = Rect2i(0, 0, cols, rows)
	grid.cell_size = Vector2(1, 1)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.update()
	for r in rows:
		for c in cols:
			var cell := Vector2i(c, r)
			var k := ch(cell)
			if k in _solid_chars():
				grid.set_point_solid(cell, true)
			elif not (room_at(cell) in no_wander_rooms):
				wander_cells.append(cell)


func unlock_cell(cell: Vector2i) -> void:
	grid.set_point_solid(cell, false)


# ================================================================= objects

func _spawn_door(cell: Vector2i, k: String) -> void:
	var along_x := ch(cell + Vector2i(-1, 0)) == "#" and ch(cell + Vector2i(1, 0)) == "#"
	var d := Door.new()
	d.position = cell_to_world(cell)
	add_child(d)
	var kind := "door"
	if k == "K":
		kind = "keycard"
	elif k == "X":
		kind = "exit"
	d.setup(self, cell, along_x, kind)
	doors[cell] = d
	if kind == "exit":
		exit_door = d


func _spawn_locker(cell: Vector2i) -> void:
	var w := nearest_wall(cell)
	var normal: Vector3 = w[0]
	var l := Locker.new()
	l.position = cell_to_world(cell) - normal * (S / 2.0 - 0.33)
	add_child(l)
	l.setup(self, normal)
	lockers.append(l)


func _spawn_intercom(cell: Vector2i) -> void:
	var wp := wall_point(cell, 1.7)
	var p: Vector3 = wp[0]
	var n: Vector3 = wp[1]
	var box := _box(Vector3(0.5, 0.6, 0.12), p + n * 0.06, _mat(Color(0.25, 0.27, 0.3), 0.5, 0.6))
	box.rotation.y = atan2(n.x, n.z)
	var lamp := _box(Vector3(0.1, 0.1, 0.05), p + n * 0.14 + Vector3(0, 0.2, 0), _glow(Color(1.0, 0.2, 0.15), 3.0))
	_label("INTERCOM", p + n * 0.13 + Vector3(0, -0.15, 0), n, 24, Color(0.7, 0.8, 0.9), 0.003)
	intercoms.append({"cell": cell, "lamp": lamp, "used": false})


func _table(p: Vector3) -> void:
	var m := _mat(Color(0.3, 0.25, 0.2), 0.7)
	_box(Vector3(1.2, 0.06, 0.7), p + Vector3(0, 0.8, 0), m)
	for x in [-0.5, 0.5]:
		for z in [-0.28, 0.28]:
			_box(Vector3(0.05, 0.8, 0.05), p + Vector3(x, 0.4, z), m)


func _spawn_note(cell: Vector2i) -> void:
	var p := cell_to_world(cell)
	_table(p)
	var it := Interactable.new()
	it.position = p + Vector3(0, 0.86, 0)
	add_child(it)
	_box(Vector3(0.3, 0.01, 0.4), Vector3.ZERO, _glow(Color(0.9, 0.88, 0.75), 0.25), it)
	_shape_for(it, Vector3(0.6, 0.3, 0.6))
	it.prompt_text = "Read note"
	it.on_use = func():
		Sound.play("click", -6.0)
		hud.show_note("MAINTENANCE NOTE - BREAKER RESET",
			"If the power trips again, reset the 3 breakers in SECURITY:\n\n- %s\n- %s\n\n" % breaker_clues
			+ "And don't listen to the intercom about this. It's been... saying things.\n   - J.")
		hud.add_clue("Breakers (in SECURITY): %s %s" % breaker_clues)
		if not has_keycard:
			hud.set_objective("Find a security keycard to get into SECURITY.")


func _shape_for(body: StaticBody3D, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = size
	cs.shape = b
	body.add_child(cs)


func _spawn_keycard(cell: Vector2i) -> void:
	var p := cell_to_world(cell)
	_table(p)
	var it := Interactable.new()
	it.position = p + Vector3(0, 0.86, 0)
	add_child(it)
	_box(Vector3(0.22, 0.01, 0.14), Vector3.ZERO, _glow(Color(1.0, 0.55, 0.1), 2.0), it)
	_shape_for(it, Vector3(0.5, 0.3, 0.5))
	it.prompt_text = "Take security keycard"
	it.on_use = func():
		has_keycard = true
		Sound.play("pickup", -4.0)
		hud.toast("Got the SECURITY KEYCARD.")
		hud.add_clue("The keycard opens SECURITY (orange door off the main hall).")
		hud.set_objective("Open SECURITY and restore the power.")
		it.queue_free()
		_keycard_scare()


func _spawn_breakers(cell: Vector2i) -> void:
	var wp := wall_point(cell, 1.4)
	var p: Vector3 = wp[0]
	var n: Vector3 = wp[1]
	var right := (-n).cross(Vector3.UP)
	var panel := _box(Vector3(1.8, 1.0, 0.1), p + n * 0.05, _mat(Color(0.25, 0.27, 0.25), 0.6, 0.5))
	panel.rotation.y = atan2(n.x, n.z)
	_label("BREAKERS  -  RESET IN THE RIGHT ORDER", p + n * 0.11 + Vector3(0, 0.62, 0), n, 28, Color(1, 0.85, 0.3), 0.004)
	var names := ["LEFT", "MIDDLE", "RIGHT"]
	for i in 3:
		var side: String = names[i]
		var lp := p + n * 0.12 + right * ((i - 1) * 0.55)
		_label(side, lp + Vector3(0, -0.36, 0), n, 24, Color(0.85, 0.9, 1.0), 0.004)
		var it := Interactable.new()
		it.position = lp
		it.rotation.y = atan2(n.x, n.z)
		add_child(it)
		var lever := _box(Vector3(0.12, 0.42, 0.12), Vector3(0, 0.1, 0.06), _glow(Color(0.9, 0.2, 0.15), 1.2), it)
		levers[side] = lever
		_shape_for(it, Vector3(0.4, 0.6, 0.3))
		it.prompt_text = "Flip the %s breaker" % side
		it.on_use = func(): _flip_breaker(side, it)


func _spawn_fragment(cell: Vector2i) -> void:
	var idx := fragment_total
	fragment_total += 1
	var it := Interactable.new()
	it.position = cell_to_world(cell) + Vector3(0, 1.1, 0)
	add_child(it)
	it.add_child(preload("res://scripts/crystal.gd").new())
	_shape_for(it, Vector3(0.6, 0.6, 0.6))
	it.prompt_text = "Take signal fragment"
	it.on_use = func():
		fragments += 1
		Game.fragments_ever["s%d_%d" % [sector_id, idx]] = true
		Sound.play("pickup", -4.0, 0.8)
		hud.set_fragments(fragments, fragment_total)
		hud.show_note("SIGNAL FRAGMENT %d / %d" % [fragments, fragment_total], fragment_text[idx % fragment_text.size()])
		hud.add_clue("Fragment: " + fragment_text[idx % fragment_text.size()])
		it.queue_free()


func _spawn_digit(cell: Vector2i, spot: int) -> void:
	# Spot 1-4 shows the digit for one colour (which colour is random each game).
	var color_index: int = digit_colors[spot]
	var wp := wall_point(cell, 1.9)
	var p: Vector3 = wp[0]
	var n: Vector3 = wp[1]
	var col: Color = CODE_COLORS[color_index][1]
	_label(str(code_digits[color_index]), p, n, 220, col, 0.006)
	var splash := _label("o", p + Vector3(0, -0.05, 0), n, 400, Color(col.r, col.g, col.b, 0.18), 0.006)
	splash.position -= n * 0.01
	digit_spots.append({"pos": p + n * 0.1, "color": color_index, "room": room_at(cell), "found": false})


func _spawn_exit(_cell: Vector2i) -> void:
	pass   # the elevator's sign is over its doors now


func room_rect(room_name: String) -> Rect2i:
	for r in rooms:
		if r[0] == room_name:
			return r[1]
	return Rect2i()


## Make the ELEVATOR room look like the inside of an old service elevator:
## brushed-steel wall panels with handrails, a scuffed metal floor, a low
## ceiling with one buzzing halogen panel, and a button panel. One of the
## buttons says 13. It's lit.
func _dress_elevator() -> void:
	var rect := room_rect("ELEVATOR")
	if rect.size == Vector2i.ZERO:
		return
	const CAB_H := 2.6
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.5, 0.52, 0.53)
	steel.metallic = 0.85
	steel.roughness = 0.38
	steel.anisotropy_enabled = true
	steel.anisotropy = 0.5
	var seam_mat := _mat(Color(0.08, 0.08, 0.09), 0.6, 0.5)
	var rail_mat := _mat(Color(0.7, 0.7, 0.68), 0.25, 1.0)
	var floor_mat: StandardMaterial3D = Game.tex_mat("metal", 0.6, Color(0.42, 0.42, 0.4), 0.7)
	if floor_mat == null:
		floor_mat = _mat(Color(0.25, 0.25, 0.26), 0.6, 0.7)
	var lo := cell_to_world(rect.position) - Vector3(S / 2.0, 0, S / 2.0)
	var size := Vector3(rect.size.x * S, 0, rect.size.y * S)
	var mid := lo + size / 2.0
	_box(Vector3(size.x, 0.03, size.z), mid + Vector3(0, 0.015, 0), floor_mat)
	_box(Vector3(size.x, 0.06, size.z), mid + Vector3(0, CAB_H + 0.03, 0), _mat(Color(0.14, 0.14, 0.15), 0.7, 0.4))
	var panel_done := false
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var cell := Vector2i(x, y)
			for d in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
				if ch(cell + d) != "#":
					continue
				var out := Vector3(d.x, 0, d.y)
				var face := cell_to_world(cell) + out * (S / 2.0 - 0.03)
				var along := Vector3(absf(out.z), 0, absf(out.x))   # direction along the wall
				var thick := Vector3(absf(out.x), 0, absf(out.z)) * 0.04
				_box(along * S + thick + Vector3(0, CAB_H, 0), face + Vector3(0, CAB_H / 2.0, 0), steel)
				for k in [-1, 1]:   # seams between the panels
					_box(along * 0.02 + thick * 1.3 + Vector3(0, CAB_H, 0), face + along * (S / 6.0) * k + Vector3(0, CAB_H / 2.0, 0), seam_mat)
				_box(along * S + thick * 2.0 + Vector3(0, 0.12, 0), face - out * 0.02 + Vector3(0, 0.06, 0), seam_mat)   # kick strip
				# Handrail on stand-offs.
				_box(along * (S - 0.3) + Vector3(0, 0.045, 0) + thick * 1.1, face - out * 0.09 + Vector3(0, 0.95, 0), rail_mat)
				for k in [-1, 1]:
					_box(Vector3(0.03, 0.03, 0.03) + thick * 2.0, face - out * 0.05 + along * (S / 2.0 - 0.3) * k + Vector3(0, 0.95, 0), rail_mat)
				if not panel_done:
					panel_done = true
					_elevator_buttons(face - out * 0.03, out, along)
	# A soft fill low in the cab, so you can see who's standing in it.
	var fill := OmniLight3D.new()
	fill.light_color = Color(1.0, 0.85, 0.65)
	fill.light_energy = 0.7
	fill.omni_range = 4.5
	fill.position = mid + Vector3(0, 1.3, 0)
	add_child(fill)
	var fill_fx := MeshInstance3D.new()   # no visible fixture: it's a glow, not a lamp
	add_child(fill_fx)
	lights.append({"light": fill, "fixture": fill_fx, "flicker": false, "mult": 1.0, "room": "ELEVATOR"})
	if exit_door:
		var into: Vector3 = mid - exit_door.global_position
		exit_door.set_hall_side(-1.0 if into.dot(exit_door.global_transform.basis.z) > 0.0 else 1.0)
	# The halogen panel: move the room's lights under the low ceiling.
	for l in lights:
		if l["room"] != "ELEVATOR":
			continue
		var light: OmniLight3D = l["light"]
		light.position.y = CAB_H - 0.25
		light.light_color = Color(1.0, 0.9, 0.72)
		light.light_energy = 1.8
		light.omni_range = 7.0
		var fx: MeshInstance3D = l["fixture"]
		fx.position.y = CAB_H - 0.02
		fx.material_override = _glow(Color(1.0, 0.92, 0.75), 2.2)
		fx.scale = Vector3(1.0, 0.5, 2.0)
		l["flicker"] = true


func _elevator_buttons(face: Vector3, out: Vector3, along: Vector3) -> void:
	var base := face + along * (S / 2.0 - 0.45) + Vector3(0, 1.35, 0)
	var plate := _box(along * 0.28 + Vector3(0, 0.62, 0) + Vector3(absf(out.x), 0, absf(out.z)) * 0.02, base, _mat(Color(0.3, 0.3, 0.31), 0.3, 0.9))
	plate.name = "ButtonPlate"
	var labels := ["6", "5", "4", "3", "2", "1", "13"]
	for i in labels.size():
		var lit: bool = labels[i] == "13"
		var p := base + Vector3(0, 0.24 - i * 0.075, 0) - out * 0.015
		_box(Vector3(0.05, 0.05, 0.05) * (along + Vector3(0, 1, 0)) + Vector3(absf(out.x), 0, absf(out.z)) * 0.02, p,
			_glow(Color(1.0, 0.2, 0.1), 2.0) if lit else _mat(Color(0.75, 0.75, 0.72), 0.4, 0.6))
		var l := _label(labels[i], p + along * 0.07 - out * 0.005, -out, 28, Color(1.0, 0.3, 0.2) if lit else Color(0.8, 0.8, 0.8), 0.0025)
		l.modulate.a = 1.0


func _make_code() -> void:
	code_digits.clear()
	for i in CODE_COLORS.size():
		code_digits.append(randi() % 10)
	code_order = [0, 1, 2, 3]
	code_order.shuffle()
	exit_code = ""
	for idx in code_order:
		exit_code += str(code_digits[idx])


# ================================================================== actors

func _spawn_actors() -> void:
	player = Player.new()
	player.sector = self
	add_child(player)
	player.global_position = cell_to_world(start_cell)
	player.look_at_yaw(-PI / 2.0)
	checkpoint = player.global_position
	checkpoint_yaw = -PI / 2.0

	listener = Listener.new()
	add_child(listener)
	listener.global_position = listener_home
	listener.setup(self)
	listener.set_physics_process(false)   # wakes up when you reach the main hall

	replacement = Replacement.new()
	add_child(replacement)
	replacement.global_position = replacement_home
	replacement.setup(self)
	replacement.rotation.y = PI / 2.0
	replacement.visible = has_replacement
	if not has_replacement:
		_remove_solid(replacement)   # not in this sector: don't leave an invisible wall

	if echo_enabled:
		echo = Echo.new()
		add_child(echo)
		echo.setup(self)


## Scatter everyday items through the sector, somewhere different each game:
## batteries, glow sticks, things to throw, and some that are just junk.
func _spawn_loot() -> void:
	const Items := preload("res://scripts/items.gd")
	const WorldItem := preload("res://scripts/world_item.gd")
	# Only squares you can actually walk to (not behind glass, not inside walls).
	var reach: Dictionary = {start_cell: true}
	var todo: Array[Vector2i] = [start_cell]
	while not todo.is_empty():
		var at: Vector2i = todo.pop_back()
		for d in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
			var nb: Vector2i = at + d
			if not reach.has(nb) and not ch(nb) in ["#", "w", "Q", "O", "W", "Z", "T", "S"]:
				reach[nb] = true
				todo.append(nb)
	var spots: Array[Vector2i] = []
	for r in rows:
		for c in cols:
			var cell := Vector2i(c, r)
			var room := room_at(cell)
			if ch(cell) != "." or room == "" or room == "ELEVATOR" or cell == start_cell or grates.has(cell) or not reach.has(cell):
				continue
			var near_door := false
			for d in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
				if not ch(cell + d) in [".", "#", "g", "L", "f", "i"]:
					near_door = true
			if not near_door:
				spots.append(cell)
	spots.shuffle()
	var n := 0
	for id in Items.SPAWN:
		for k in int(Items.SPAWN[id][Game.mode]):
			if n >= spots.size():
				return
			var w := WorldItem.new()
			add_child(w)
			w.setup(self, id)
			w.global_position = cell_to_world(spots[n]) + Vector3(randf_range(-1.0, 1.0), 0.05, randf_range(-1.0, 1.0))
			w.rotation.y = randf() * TAU
			n += 1


## Is there a lit glow stick within `radius` of this point?
func near_glow(pos: Vector3, radius: float) -> bool:
	for g in glows:
		if is_instance_valid(g) and g.glowing() and g.global_position.distance_to(pos) <= radius:
			return true
	return false


func emit_noise(pos: Vector3, radius: float, from_player: bool) -> void:
	if listener and listener.is_physics_processing():
		listener.hear(pos, radius, from_player)


func _remove_solid(n: Node) -> void:
	for b in n.find_children("*", "StaticBody3D", true, false):
		b.get_parent().remove_child(b)
		b.queue_free()


func is_grate(pos: Vector3) -> bool:
	return grates.has(world_to_cell(pos))


func find_path(from: Vector3, to: Vector3) -> Array[Vector2i]:
	var a := world_to_cell(from)
	var b := world_to_cell(to)
	var empty: Array[Vector2i] = []
	if not grid.is_in_boundsv(a) or not grid.is_in_boundsv(b):
		return empty
	if grid.is_point_solid(b):
		var found := false
		for d in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
			if grid.is_in_boundsv(b + d) and not grid.is_point_solid(b + d):
				b = b + d
				found = true
				break
		if not found:
			return empty
	if grid.is_point_solid(a):
		return empty
	var path := grid.get_id_path(a, b)
	if path.size() > 0:
		path.remove_at(0)
	return path


func random_floor_pos() -> Vector3:
	return cell_to_world(wander_cells[randi() % wander_cells.size()])


func lockers_near(pos: Vector3, radius: float, count: int) -> Array:
	var near: Array = []
	for l in lockers:
		if l.global_position.distance_to(pos) <= radius:
			near.append(l)
	near.sort_custom(func(a, b): return a.global_position.distance_to(pos) < b.global_position.distance_to(pos))
	# If you're hiding near here, your locker is one of the ones it checks.
	var mine: Node = player.hidden_in
	if mine and mine.global_position.distance_to(pos) <= radius and not (mine in near.slice(0, count)):
		near.insert(0, mine)
	return near.slice(0, count)


func monster_entering(cell: Vector2i) -> void:
	if doors.has(cell):
		doors[cell].monster_near()


func anyone_near(pos: Vector3, radius: float) -> bool:
	for n in [player, listener, replacement]:
		if n == null:
			continue
		var d := Vector2(n.global_position.x - pos.x, n.global_position.z - pos.z).length()
		if d < radius:
			if n == replacement and not replacement.active:
				continue
			return true
	if echo and echo.visible and Vector2(echo.global_position.x - pos.x, echo.global_position.z - pos.z).length() < radius:
		return true
	return false


# ================================================== learning (the Listener)

func on_player_hid(_locker: Node) -> void:
	if echo and (echo.active or not trail.is_empty()):
		# ECHO can't copy a trail that stops inside a locker.
		var was_following: bool = echo.active
		echo.lose_trail(float(Game.mode_data()["echo_delay"]) * 0.6)
		if was_following:
			hud.toast("You broke your trail. ECHO lost you - for now.", 3.0)
	if _hid_recently > 0.0:
		return
	_hid_recently = 15.0
	Game.hide_count += 1
	var need: int = Game.mode_data()["learn_hide"]
	if need > 0 and not Game.learned_lockers and Game.hide_count >= need:
		Game.learned_lockers = true
		await get_tree().create_timer(2.5).timeout
		hud.say("ai", "It has noticed that you hide. It will start checking the lockers.")
		hud.say("ai", "If it stops at yours, hold your breath. SPACE.")
		hud.toast("THE LISTENER IS LEARNING: it now checks lockers.", 5.0)


## You've been crawling around a lot: it learns to hear that too.
func note_crouch() -> void:
	var need := float(Game.mode_data()["learn_crouch"])
	if Game.learned_crouch or need <= 0.0 or Game.crouch_time < need:
		return
	Game.learned_crouch = true
	hud.say("ai", "It has learned to hear you crawl. Crouching will not hide you for long now.")
	hud.toast("THE LISTENER IS LEARNING: it can hear you crouch-walk now.", 5.0)


func note_sprint(pos: Vector3, delta: float) -> void:
	var c := world_to_cell(pos)
	Game.sprint_cells[c] = float(Game.sprint_cells.get(c, 0.0)) + delta
	if Game.learned_traps or Game.sprint_time < float(Game.mode_data()["learn_sprint"]):
		return
	Game.learned_traps = true
	_place_traps()


func _place_traps() -> void:
	var cells: Array = Game.sprint_cells.keys()
	cells.sort_custom(func(a, b): return Game.sprint_cells[a] > Game.sprint_cells[b])
	var placed := 0
	for c in cells:
		if placed >= 3:
			break
		var cell: Vector2i = c
		if ch(cell) != "." or grates.has(cell):
			continue
		if cell_to_world(cell).distance_to(player.global_position) < 7.0:
			continue
		_spawn_trap(cell)
		placed += 1
	if placed > 0:
		hud.say("ai", "It knows which halls you run through. It has strung wires across them.")
		hud.say("ai", "Look for red wires near the floor. Crouch to step over them.")
		hud.toast("THE LISTENER IS LEARNING: tripwires in the halls you run.", 5.0)


func _spawn_trap(cell: Vector2i) -> void:
	var p := cell_to_world(cell)
	var area := Area3D.new()
	area.collision_layer = 0
	area.collision_mask = 4
	area.position = p
	add_child(area)
	var cs := CollisionShape3D.new()
	var b := BoxShape3D.new()
	b.size = Vector3(S, 1.0, 0.6)
	cs.shape = b
	cs.position.y = 0.5
	area.add_child(cs)
	var along_x := not (ch(cell + Vector2i(-1, 0)) == "#" and ch(cell + Vector2i(1, 0)) == "#")
	if not along_x:
		area.rotation.y = PI / 2.0
	var wire_mat := _glow(Color(1.0, 0.1, 0.1), 1.2 if Game.mode != Game.Mode.NIGHTMARE else 0.5)
	_box(Vector3(S, 0.02, 0.02), Vector3(0, 0.25, 0), wire_mat, area)
	for x in [-S / 2.0 + 0.1, S / 2.0 - 0.1]:
		_box(Vector3(0.06, 0.4, 0.06), Vector3(x, 0.2, 0), _mat(Color(0.3, 0.3, 0.3)), area)
	area.body_entered.connect(func(body):
		if body != player or not is_instance_valid(area):
			return
		if player.crouching:
			hud.toast("You step carefully over the wire.", 2.0)
			return
		Sound.play_at("trap", area.global_position, 2.0)
		emit_noise(area.global_position, 26.0, true)
		hud.toast("You hit a tripwire!", 2.5)
		area.queue_free())
	traps.append(area)


## ECHO stepped out for the first time.
func on_echo_appeared() -> void:
	hud.say("ai", "Something just stepped out where you came in. It is walking exactly where you walked.")
	hud.say("ai", "Keep moving. Do not go back the way you came. Hiding in a locker breaks your trail.")
	hud.add_clue("ECHO walks exactly where you walked. Keep moving, don't double back, hide in a locker to lose it.")
	if not Game.is_explorer():
		Sound.play("heartbeat", -2.0)


func on_hunt_started() -> void:
	if Game.is_explorer():
		if _hunt_warnings < 3:
			_hunt_warnings += 1
			hud.toast("It heard you! Move away quietly, or hide in a locker.", 3.0)
	else:
		Sound.play("heartbeat", -2.0)
		Sound.play_at("shriek", listener.global_position + Vector3(0, 2.3, 0), 2.0, randf_range(0.9, 1.1))


func on_locker_checked(locker: Node) -> void:
	if player.hidden_in == locker:
		hud.toast("IT'S COMING TO YOUR LOCKER.  HOLD  SPACE!", 4.0)
		Sound.play("heartbeat", 0.0)


# ================================================================= puzzles

func _flip_breaker(side: String, it: Node) -> void:
	if power_on or side in breaker_seq:
		return
	Sound.play_at("breaker", it.global_position, 0.0)
	var lever: MeshInstance3D = levers[side]
	lever.rotation.x = -0.9
	lever.material_override = _glow(Color(0.2, 1.0, 0.4), 1.4)
	breaker_seq.append(side)
	var i := breaker_seq.size() - 1
	if breaker_seq[i] != breaker_order[i]:
		# Wrong order: the breakers trip with a loud alarm.
		await get_tree().create_timer(0.4).timeout
		Sound.play_at("alarm", it.global_position, 4.0)
		emit_noise(it.global_position, 30.0, false)
		hud.toast("THE BREAKERS TRIPPED! They reset - and that was LOUD.", 4.0)
		breaker_seq.clear()
		for s in levers:
			var l: MeshInstance3D = levers[s]
			l.rotation.x = 0.0
			l.material_override = _glow(Color(0.9, 0.2, 0.15), 1.2)
		return
	if breaker_seq.size() == breaker_order.size():
		_power_on()


func _power_on() -> void:
	power_on = true
	Sound.play("power_on", 0.0)
	for l in lights:
		var light: OmniLight3D = l["light"]
		light.light_color = Color(1.0, 0.93, 0.8)
		light.light_energy = 1.0 * float(l["mult"])
		light.omni_range = 9.0
		var fx: MeshInstance3D = l["fixture"]
		fx.material_override = _glow(Color(1.0, 0.93, 0.8), 2.0)
	_env.ambient_light_energy *= 1.6
	var names: Array[String] = []
	for idx in code_order:
		names.append(CODE_COLORS[idx][0])
	exit_door.set_display("EXIT CODE ORDER\n%s  %s\n%s  %s" % names, Color(1.0, 0.95, 0.6))
	emit_noise(player.global_position, 12.0, false)
	hud.set_objective("Power is on. Find the elevator (lower hall) and its exit code.")
	hud.say("ai", "Power restored. Thank you.")
	hud.say("ai", "The elevator needs a four-digit exit code. The night staff painted the numbers around the sector, in colours.")
	hud.say("unknown", "...you turned the lights on. now it can see you too.")
	replacement.active = true
	if Game.mode_data()["replacement_hunts"]:
		await get_tree().create_timer(14.0).timeout
		hud.say("ai", "The mannequin in Lab 2 was not there yesterday. If it moves, keep your light on it.")


## SECTOR HOOK: the elevator door's prompt and what pressing E on it does.
func exit_prompt(door: Node) -> String:
	if door.unlocked:
		return "Open elevator"
	return "Elevator keypad" if power_on else "Elevator: no power"


func exit_interact(door: Node) -> void:
	if not power_on:
		Sound.play_at("locked", door.global_position, -2.0)
		hud.toast("The elevator has no power.")
		return
	open_keypad()


## SECTOR HOOK: vault doors (Sector 2 and later).
func vault_prompt(_door: Node) -> String:
	return ""


func vault_interact(_door: Node) -> void:
	pass


## SECTOR HOOK: signal gates (Sector 3 and later).
func gate_prompt(_door: Node) -> String:
	return "Signal gate: no signal"


func gate_interact(door: Node) -> void:
	Sound.play_at("locked", door.global_position, -2.0)


# ======================================================= carrying things
# Relays (Sector 3) and jammers (Sector 4) are "carryables": pick one up with
# E, put it down on the floor square in front of you with E. Each has a
# `cell`, a `home_cell`, an `item_name`, set_carried(on), and may have
# set_facing(i) if it can be turned with R.

const DIRS := [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]  # E, S, W, N

var carryables: Array = []
var _marker: MeshInstance3D


## SECTOR HOOK: something was picked up, put down or turned.
func _on_carry_changed() -> void:
	pass


## SECTOR HOOK: extra rules for where things can be put down.
func _extra_place_ok(_cell: Vector2i) -> bool:
	return true


func _carryable_at(cell: Vector2i) -> Node:
	for item in carryables:
		if item.cell == cell and item != player.carrying:
			return item
	return null


func pick_up(item: Node) -> void:
	if player.carrying:
		return
	player.carrying = item
	item.set_carried(true)
	item.reparent(player.cam)
	item.position = Vector3(0.6, -1.15, -1.3)
	item.rotation = Vector3.ZERO
	item.scale = Vector3.ONE * 0.45
	Sound.play("locker", -10.0, 1.4)
	_on_carry_changed()


func _player_dir_index() -> int:
	var fwd: Vector3 = -player.global_transform.basis.z
	if absf(fwd.x) > absf(fwd.z):
		return 0 if fwd.x > 0.0 else 2
	return 1 if fwd.z > 0.0 else 3


## The floor square in front of you, in whichever of the 4 directions you face most.
func _place_target() -> Vector2i:
	return world_to_cell(player.global_position) + DIRS[_player_dir_index()]


func _can_place(cell: Vector2i) -> bool:
	var k := ch(cell)
	if not k in [".", "g", "r", "j", "f", "P", "M", "C"]:
		return false
	if _carryable_at(cell) != null:
		return false
	return _extra_place_ok(cell)


func carry_prompt() -> String:
	var cell := _place_target()
	var ok := _can_place(cell)
	_show_marker(cell, ok)
	if not ok:
		return "Can't put it there"
	var item: Node = player.carrying
	var text: String = "Put the %s down" % item.item_name
	if item.has_method("set_facing"):
		text += "      [R] turn it"
	return text


func _show_marker(cell: Vector2i, ok: bool) -> void:
	if _marker == null:
		_marker = MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(S * 0.8, S * 0.8)
		_marker.mesh = pm
		add_child(_marker)
	_marker.visible = player.carrying != null
	_marker.global_position = cell_to_world(cell) + Vector3(0, 0.03, 0)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.4, 1.0, 0.6, 0.25) if ok else Color(1.0, 0.3, 0.3, 0.2)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_marker.material_override = m


func try_place() -> void:
	var item: Node = player.carrying
	var cell := _place_target()
	if not _can_place(cell):
		Sound.play("locked", -10.0)
		return
	_put(item, cell)
	Sound.play_at("breaker", item.global_position, -10.0, 1.6)
	emit_noise(item.global_position, 4.0, true)


func _put(item: Node, cell: Vector2i) -> void:
	if player.carrying == item:
		player.carrying = null
	item.reparent(self)
	item.scale = Vector3.ONE
	item.rotation = Vector3.ZERO
	item.cell = cell
	item.global_position = cell_to_world(cell)
	item.set_carried(false)
	if _marker:
		_marker.visible = false
	_on_carry_changed()


func turn_carried() -> void:
	var item: Node = player.carrying
	if item.has_method("set_facing"):
		item.set_facing(item.facing + 1)
		Sound.play("click", -6.0)


## You got caught while carrying something: it drops where it last stood.
func drop_carried() -> void:
	var item: Node = player.carrying
	var cell: Vector2i = item.cell if _carryable_at(item.cell) == null else item.home_cell
	_put(item, cell)


## SECTOR HOOK: R was pressed. Return true if the sector used it (Sector 5 stops a recording).
func on_rotate_pressed() -> bool:
	return false


## SECTOR HOOK: true where the Replacement can't move at all (Sector 6's lit rooms).
func replacement_frozen(_pos: Vector3) -> bool:
	return false


## SECTOR HOOK: put sector-specific things back after you're caught.
func _on_respawn() -> void:
	pass


## SECTOR HOOK: true where your footsteps make no sound (Sector 4's jammers).
func noise_muffled(_pos: Vector3) -> bool:
	return false


## SECTOR HOOK: true where ECHO can't step (Sector 4's jammer fields).
func echo_blocked(_pos: Vector3) -> bool:
	return false


## SECTOR HOOK: true while you're somewhere ECHO can't follow (shielded rooms).
func trail_shielded() -> bool:
	return false


func open_keypad() -> void:
	player.frozen = true
	hud.open_keypad(_on_code, close_keypad)


func close_keypad() -> void:
	hud.close_keypad()
	if not ended and not catching:
		player.frozen = false
		Game.capture_mouse()


func _on_code(code: String) -> void:
	if code == exit_code:
		Sound.play("key_ok", -2.0)
		close_keypad()
		exit_open = true
		exit_door.unlocked = true
		exit_door.stay_open = true
		exit_door.set_display("CODE ACCEPTED", Color(0.4, 1.0, 0.5))
		unlock_cell(exit_door.cell)
		exit_door.open(true)
		hud.set_objective("Get in the elevator!")
		hud.say("ai", "Exit code accepted. Goodbye, and thank you for your cooperation.")
		return
	Sound.play("key_bad", -2.0)
	hud.keypad_message("WRONG CODE")
	var mode := Game.mode_data()
	if mode["wrong_code_alarm"]:
		Sound.play_at("alarm", exit_door.global_position, 2.0)
		emit_noise(exit_door.global_position, 30.0, false)
	elif not Game.is_explorer():
		emit_noise(exit_door.global_position, 10.0, false)


# =================================================================== scares

func _keycard_scare() -> void:
	if not Game.mode_data()["scares"]:
		return
	await get_tree().create_timer(1.2).timeout
	_blackout(1.6)
	var was_on: bool = player.flashlight.visible
	player.flashlight.visible = false
	await get_tree().create_timer(0.7).timeout
	var fwd: Vector3 = -player.global_transform.basis.z
	var mq := Replacement.build_model()
	_remove_solid(mq)   # a glimpse in the dark, not something you bump into
	add_child(mq)
	mq.global_position = player.global_position + fwd * 2.2
	mq.rotation.y = atan2(-fwd.x, -fwd.z)
	player.flashlight.visible = true
	Sound.play("sting", -3.0)
	await get_tree().create_timer(0.5).timeout
	player.flashlight.visible = false
	mq.queue_free()
	await get_tree().create_timer(0.4).timeout
	player.flashlight.visible = was_on or player.battery > 1.0
	hud.say("unknown", "...not yet.")


func _blackout(seconds: float) -> void:
	_blackout_t = seconds
	for l in lights:
		l["light"].visible = false
		l["fixture"].visible = false


func _random_event() -> void:
	var m := Game.mode_data()
	var options := ["flicker", "whisper", "echo_call"]
	if not power_on and not replacement.active:
		options.append("glimpse")
	match options[randi() % options.size()]:
		"flicker":
			_blackout(randf_range(0.8, 1.6))
			Sound.play_at("creak", player.global_position + Vector3(randf_range(-6, 6), 1, randf_range(-6, 6)), 0.0)
		"whisper":
			var lines := ["...can you hear it too?", "it's behind the next door.", "thirteen. thirteen. thirteen.", "you weren't on the employee list."]
			hud.say("unknown", lines[randi() % lines.size()])
		"echo_call":
			var lines := ["Over here. Quickly. The exit is this way.", "Stop. Do not move. ...Now run.", "You can trust me. I am MERIDIAN."]
			hud.say("echo", lines[randi() % lines.size()])
		"glimpse":
			# The mannequin, standing in the dark ahead of you. Then it's gone.
			var fwd: Vector3 = -player.global_transform.basis.z
			fwd.y = 0.0
			fwd = fwd.normalized()
			var spot: Vector3 = player.global_position + fwd * 7.0
			var q := PhysicsRayQueryParameters3D.create(player.eye_position(), spot + Vector3(0, 1.5, 0), 1)
			if not get_world_3d().direct_space_state.intersect_ray(q).is_empty():
				return
			var mq := Replacement.build_model()
			add_child(mq)
			mq.global_position = spot
			mq.rotation.y = atan2(-fwd.x, -fwd.z)
			Sound.play("sting", -6.0)
			await get_tree().create_timer(0.35).timeout
			_blackout(0.5)
			await get_tree().create_timer(0.3).timeout
			mq.queue_free()
	if m["name"] == "NIGHTMARE" and randf() < 0.4:
		emit_noise(random_floor_pos(), 6.0, false)   # it goes to look somewhere


# =================================================================== catch

func on_caught(by: String) -> void:
	if catching or ended:
		return
	catching = true
	catches += 1
	if hud.keypad_open():
		hud.close_keypad()
		Game.capture_mouse()
	if player.hidden_in:
		player.leave_locker()
	if player.carrying:
		drop_carried()
	player.frozen = true
	paused_world = true
	var soft := Game.is_explorer()
	if by == "listener" and listener:
		var lt := ("IT FOUND YOU.\nBack to the last checkpoint.\n\nTip: crouch to stay quiet, and avoid the metal grates. Running makes it come FAST."
			if soft else "SIGNAL LOST\n\nTip: crouch to stay quiet, and avoid the metal grates. Running makes it come FAST.")
		_listener_catch(Game.full_scares(), lt)
		return
	Sound.play("static", -12.0 if soft else -2.0)
	var tips := {
		"listener": "Tip: crouch to stay quiet, and avoid the metal grates.",
		"replacement": "Tip: it only moves when you can't see it. Keep your light on it.",
		"echo": "Tip: ECHO walks exactly where you walked. Keep moving, don't double back, and hide in a locker to break your trail.",
	}
	var tip: String = tips.get(by, "")
	var text := ("IT FOUND YOU.\nBack to the last checkpoint.\n\n" + tip) if soft else ("SIGNAL LOST\n\n" + tip)
	hud.show_caught(soft, text, _respawn)


## Caught by the Listener. Full version: you spin to face it and its eyeless
## head is suddenly RIGHT in your face with a shriek; you fall backwards onto
## the floor and it bends down over you, face to face, ears flaring. Gentle
## version (Explorer, unless a parent turns it on): no shriek and no sudden
## face - you stumble back and fall, and it slowly leans down over you.
func _listener_catch(full: bool, text: String) -> void:
	var cam: Camera3D = player.cam
	var p: Vector3 = player.global_position
	var to: Vector3 = listener.global_position - p
	to.y = 0.0
	if to.length() < 0.05:
		to = -player.global_transform.basis.z
	to = to.normalized()
	player.yaw = atan2(-to.x, -to.z)
	player.rotation.y = player.yaw
	player.pitch = 0.0
	cam.rotation = Vector3.ZERO
	player.set_view_only(true)
	player.flashlight.visible = true   # you swing your light up at it
	hud.cinematic(true)
	listener.rotation.y = atan2(-to.x, -to.z)   # facing you
	if full:
		# Its head drops to yours: it bends right over at the waist.
		listener.global_position = Vector3(p.x, listener.global_position.y, p.z) + to * 2.15
		listener.pose(1.3, -0.1, 0.06)
		Sound.play("jumpscare", 0.0)
		hud.jump_flash()
		var t0 := 0.0
		while t0 < 0.55:
			cam.h_offset = randf_range(-0.04, 0.04)
			cam.v_offset = randf_range(-0.04, 0.04)
			await get_tree().process_frame
			if not is_inside_tree():
				return
			t0 += get_process_delta_time()
		cam.h_offset = 0.0
		cam.v_offset = 0.0
	else:
		Sound.play_at("listener_snap", listener.global_position + Vector3(0, 2.0, 0), -6.0, 0.8)
	# You fall backwards. It stands over you and bends down, face to face.
	Sound.play("body_fall", -3.0 if full else -8.0)
	var fall := create_tween().set_parallel(true)
	fall.tween_property(cam, "position", Vector3(0, 0.3, 0.35), 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	fall.tween_property(cam, "rotation", Vector3(1.2, 0, 0.22), 0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	listener.global_position = Vector3(p.x, listener.global_position.y, p.z) + to * 0.75
	listener.pose(0.95, 1.1, 0.5 if full else 2.2)
	if not full:
		Sound.play("listener_loom", -10.0)
	await get_tree().create_timer(0.5).timeout
	if not is_inside_tree():
		return
	var hold := 1.7 if full else 1.4
	var t := 0.0
	while t < hold:
		if randf() < (0.35 if full else 0.12):
			listener.pose_twitch()
			if full and randf() < 0.3:
				Sound.play_at("listener_click", listener.global_position + Vector3(0, 1.8, 0), 0.0, randf_range(0.8, 1.2))
		await get_tree().create_timer(0.08).timeout
		if not is_inside_tree():
			return
		t += 0.08
	hud.show_caught(not full, text, _respawn)


func _respawn() -> void:
	hud.cinematic(false)
	player.set_view_only(false)
	player.reset_view()
	player.global_position = checkpoint
	player.look_at_yaw(checkpoint_yaw)
	player.velocity = Vector3.ZERO
	player.stamina = 100.0
	player.breath = 100.0
	# Put the monsters somewhere far away from the checkpoint.
	var far := listener_home
	for i in 40:
		var p := random_floor_pos()
		if p.distance_to(checkpoint) > 20.0:
			far = p
			break
	listener.reset_to(far)
	replacement.reset_to(replacement_home)
	if echo:
		echo.lose_trail(Game.mode_data()["echo_delay"])
	_on_respawn()
	await get_tree().create_timer(0.8).timeout
	player.frozen = false
	paused_world = false
	catching = false


# ================================================================ main loop

func set_paused(on: bool) -> void:
	get_tree().paused = on
	if on:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Game.capture_mouse()


func _process(delta: float) -> void:
	if ended:
		return
	run_time += delta
	_hid_recently = maxf(_hid_recently - delta, 0.0)

	# Lights: flicker, and come back after a blackout.
	if _blackout_t > 0.0:
		_blackout_t -= delta
		if _blackout_t <= 0.0:
			for l in lights:
				if l.get("off", false):
					continue   # a light with its power switched off stays off
				l["light"].visible = true
				l["fixture"].visible = true
	else:
		for l in lights:
			if l["flicker"] and not l.get("off", false):
				var on := randf() > 0.04
				l["light"].visible = on
				l["fixture"].visible = on

	_check_player_cell()
	_update_dread()
	_record_trail(delta)

	# Spot painted numbers (you have to actually see them).
	_clue_t -= delta
	if _clue_t <= 0.0:
		_clue_t = 0.2
		_check_clues()

	# Distant facility sounds.
	_ambient_t -= delta
	if _ambient_t <= 0.0:
		_ambient_t = randf_range(10.0, 22.0)
		var where := player.global_position + Vector3(randf_range(-15, 15), 2.5, randf_range(-15, 15))
		var vol := -14.0 if Game.is_explorer() else -6.0
		Sound.play_at("bang" if randf() < 0.4 else "drip", where, vol, randf_range(0.8, 1.2))

	# Random scares (never in Explorer).
	if Game.mode_data()["scares"] and listener.is_physics_processing() and not catching:
		_event_t -= delta
		if _event_t <= 0.0:
			var gap: Vector2 = Game.mode_data()["scare_gap"]
			_event_t = randf_range(gap.x, gap.y)
			_random_event()


## Remember where you walk, so ECHO can walk it too.
func _record_trail(delta: float) -> void:
	if not echo_enabled or player.hidden_in or player.frozen or trail_shielded():
		return
	_trail_t -= delta
	if _trail_t > 0.0:
		return
	_trail_t = 0.15
	var p := player.global_position
	if trail.is_empty() or trail[trail.size() - 1].distance_to(p) > 0.4:
		trail.append(p)


## ECHO hid: hiding in a locker wipes your trail.
func on_trail_broken() -> void:
	trail.clear()


## The Listener close by: the screen edges darken and your flashlight flickers.
## (Survivor and Nightmare only. Explorer stays calm.)
func _update_dread() -> void:
	var amount := 0.0
	if not Game.is_explorer() and listener.is_physics_processing() and not catching:
		var d := listener.global_position.distance_to(player.global_position)
		if echo and echo.visible:
			d = minf(d, echo.global_position.distance_to(player.global_position) + 2.0)
		amount = clampf(1.0 - (d - 2.0) / 8.0, 0.0, 1.0)
		if amount > 0.3 and player.flashlight.visible and randf() < amount * 0.25:
			player.flashlight.light_energy = randf_range(0.0, 0.8)
	hud.set_dread(amount)
	var fuzz := 0.0
	if not Game.is_explorer() and echo and echo.visible and not catching:
		# ECHO is made of static, and up close it gets into your eyes too.
		fuzz = clampf(1.0 - (echo.global_position.distance_to(player.global_position) - 1.5) / 6.0, 0.0, 1.0)
	hud.set_fuzz(fuzz)


func _check_player_cell() -> void:
	var c := world_to_cell(player.global_position)
	if c == _last_cell:
		return
	_last_cell = c
	var room := room_at(c)
	if room != "" and not visited.has(room):
		visited[room] = true
		_entered_room(room)
	# Checkpoints at intercoms.
	for ic in intercoms:
		var ic_cell: Vector2i = ic["cell"]
		if absi(ic_cell.x - c.x) + absi(ic_cell.y - c.y) <= 1 and checkpoint.distance_to(cell_to_world(ic_cell)) > 0.5:
			checkpoint = cell_to_world(ic_cell)
			checkpoint_yaw = player.yaw
			ic["lamp"].material_override = _glow(Color(0.2, 1.0, 0.4), 3.0)
			if ic["used"] == false:
				ic["used"] = true
				Sound.play("checkpoint", -4.0)
				hud.toast("Checkpoint", 2.0)
	if ch(c) == "E" and exit_open:
		_win()


func _entered_room(room: String) -> void:
	match room:
		"MAIN HALL":
			listener.set_physics_process(true)
			hud.say("ai", "Walk softly. Something in this sector hunts by sound.")
			hud.say("ai", "Hold CTRL to crouch. The metal grates are loud. Running is louder.")
			if Game.is_explorer():
				hud.say("ai", "The NOISE bar, bottom left, shows how far your sound carries. Listen for its clicking.")
			hud.add_clue("The Listener is blind but hears everything. Crouch on grates. Hide in lockers.")
		"BREAK ROOM":
			if not visited.has("note_hint"):
				visited["note_hint"] = true
		"SECURITY":
			var wrong: Array = ["LEFT", "MIDDLE", "RIGHT"].filter(func(x): return x != breaker_order[0])
			hud.say("echo", "Start with the %s breaker. Trust me." % wrong[randi() % wrong.size()])
			if Game.mode_data()["echo_hint"]:
				hud.say("ai", "...That was not me. Something on this channel is copying my voice. Check the maintenance note.")
		"LAB 2":
			if not power_on:
				hud.say("unknown", "don't look away from it.")
		"LOWER HALL":
			if not power_on:
				hud.say("ai", "The service elevator is at the end of this hall. It needs power first.")
		"CRAWLSPACE":
			hud.toast("A secret room!", 2.5)


func _check_clues() -> void:
	for spot in digit_spots:
		if spot["found"]:
			continue
		var p: Vector3 = spot["pos"]
		if p.distance_to(player.eye_position()) < 9.0 and player.can_see(p):
			spot["found"] = true
			var color_name: String = CODE_COLORS[spot["color"]][0]
			hud.add_clue("%s number: %d  (painted in %s)" % [color_name, code_digits[spot["color"]], spot["room"]])
	if power_on and not order_seen:
		# A point just in front of the door's screen, on your side.
		var dp: Vector3 = exit_door.global_position + Vector3(0, 1.6, 0)
		var toward := player.eye_position() - dp
		toward.y = 0.0
		dp += toward.normalized() * 0.4
		if dp.distance_to(player.eye_position()) < 10.0 and player.can_see(dp):
			order_seen = true
			var names: Array[String] = []
			for idx in code_order:
				names.append(CODE_COLORS[idx][0])
			hud.add_clue("Elevator code order: " + ", ".join(names))
			hud.set_objective("Find the 4 painted numbers, then type the code at the elevator.")


func _win() -> void:
	ended = true
	paused_world = true
	player.frozen = true
	Sound.play("power_on", -4.0, 0.7)
	var mode_name := Game.mode_name()
	var best_key := mode_name if sector_id == 1 else "S%d %s" % [sector_id, mode_name]
	var best: float = Game.best_times.get(best_key, 0.0)
	var new_best := best == 0.0 or run_time < best
	if new_best:
		Game.best_times[best_key] = run_time
	Game.sector_unlocked = maxi(Game.sector_unlocked, sector_id + 1)
	Game.save_settings()
	var learned: Array[String] = []
	if Game.learned_lockers:
		learned.append("to check lockers")
	if Game.learned_traps:
		learned.append("to set tripwires where you run")
	var learned_text := "It never figured you out." if learned.is_empty() else "It learned " + " and ".join(learned) + "."
	var body := "Mode: %s\nTime: %d:%02d%s\nTimes caught: %d\nSignal fragments: %d / %d\nThe Listener: %s\n\n%s" % [
		mode_name, int(run_time) / 60, int(run_time) % 60, "  (new best!)" if new_best else "",
		catches, fragments, fragment_total, learned_text, _end_story()]
	var next := next_scene if ResourceLoader.exists(next_scene) else ""
	Game.carry_items(sector_id + 1, player.inventory)
	_elevator_cutscene(func(): hud.show_end("SECTOR %d CLEAR" % sector_id, body, next))


## The end of a sector, as a short cutscene. The camera pulls slowly back out
## of your head until you can see yourself standing in the elevator, facing
## out. The doors slide shut. The halogen light buzzes and stutters. Black.
func _elevator_cutscene(done: Callable) -> void:
	var rect := room_rect("ELEVATOR")
	if exit_door == null or rect.size == Vector2i.ZERO:
		hud.fade_out(1.5, done)
		return
	hud.cinematic(true)
	var lo := cell_to_world(rect.position) - Vector3(S / 2.0, 0, S / 2.0)
	var center := lo + Vector3(rect.size.x * S, 0, rect.size.y * S) / 2.0
	var door_pos: Vector3 = exit_door.global_position
	var out_dir := door_pos - center
	out_dir.y = 0.0
	out_dir = out_dir.normalized()
	# Where you end up standing: in the middle of the cab, turned to face out.
	var stand := center + out_dir * 0.2
	stand.y = player.global_position.y
	var cam := Camera3D.new()
	cam.fov = player.cam.fov
	cam.near = 0.05
	add_child(cam)
	cam.global_transform = player.cam.global_transform
	cam.current = true
	player.set_cutscene(true)
	player.body.visible = false
	var from_xf: Transform3D = cam.global_transform
	var face_out := atan2(-out_dir.x, -out_dir.z)
	var from_pos: Vector3 = player.global_position
	var from_yaw: float = player.rotation.y
	var shot := door_pos + out_dir * 2.6 + Vector3(0, 1.6, 0) + out_dir.cross(Vector3.UP) * 0.35
	var target := stand + Vector3(0, 1.25, 0)
	var to_xf := Transform3D(Basis.looking_at(target - shot, Vector3.UP), shot)
	var hum := Sound.play_at("halogen_buzz", center + Vector3(0, 2.4, 0), -14.0)
	var pull := func(t: float) -> void:
		var e := t * t * (3.0 - 2.0 * t)
		player.global_position = from_pos.lerp(stand, minf(t * 1.6, 1.0))
		player.rotation.y = lerp_angle(from_yaw, face_out, minf(t * 1.4, 1.0))
		player.body.visible = t > 0.12
		cam.global_transform = from_xf.interpolate_with(to_xf, e)
	var tw := create_tween()
	tw.tween_method(pull, 0.0, 1.0, 4.2)
	await tw.finished
	if not is_inside_tree():
		return
	await get_tree().create_timer(0.5).timeout
	if not is_inside_tree():
		return
	exit_door.close_elevator(3.2)
	# The lights inside start to fail as the doors close.
	var cab_lights: Array = []
	for l in lights:
		if l["room"] == "ELEVATOR":
			l["flicker"] = false
			cab_lights.append(l)
	var t := 0.0
	var faded := false
	while t < 5.0:
		var gap := randf_range(0.04, 0.22)
		var on := randf() > 0.45
		for l in cab_lights:
			l["light"].visible = on
			l["fixture"].visible = on
		Sound.play_at("halogen_flick", center + Vector3(0, 2.4, 0), -10.0 if on else -14.0, randf_range(0.9, 1.15))
		if is_instance_valid(hum):
			hum.volume_db = -10.0 if on else -24.0
		cam.global_position += out_dir * 0.012   # a slow drift back
		await get_tree().create_timer(gap).timeout
		if not is_inside_tree():
			return
		t += gap
		if t > 2.4 and not faded:
			faded = true
			hud.fade_out(2.4, func(): pass)
	for l in cab_lights:
		l["light"].visible = false
		l["fixture"].visible = false
	if is_instance_valid(hum):
		hum.stop()
	Sound.play("elevator_drop", -6.0)
	await get_tree().create_timer(0.8).timeout
	if not is_inside_tree():
		return
	hud.cinematic(false)
	done.call()
