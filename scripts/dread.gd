extends Node
## THE DREAD DIRECTOR. Small things that make the facility feel aware of you,
## timed so they never pile up. Explorer keeps only the gentle ones (slow,
## quiet, never a chase); the deceptive ones are Survivor/Nightmare only.
##
##  - The facility answers your noise: run or clang across a grate and the
##    nearest intercom gives a clipped two-note chime and a relay click.
##    (Survivor+: then MERIDIAN, flatly: "...noted.")
##  - Lights go out behind you, one fixture at a time, and come back later.
##  - (Survivor+) False footsteps: steps in a side corridor while the Listener
##    is far away... then a loose pipe taps twice in the same spot. Learn the
##    difference.
##  - ECHO replays one of your own recent sounds from where you made it, with
##    one extra beat that you didn't make.
##  - A room name on the floor reads SECTOR 13 while you aren't looking.
##  - The elevator's display shows B13 for a moment the first time you get close.
##  - (Survivor+) Once per sector, MERIDIAN says something ECHO said.

const MERIDIAN_NOTED := ["...noted.", "I heard that.", "Footsteps logged.", "Please walk.", "Sound event recorded."]

var sector: Node
var gentle := true
var _answer_cool := 25.0
var _behind_t := 0.0
var _false_t := 0.0
var _leak_t := 0.0
var _echo_t := 0.0
var _copy_line_t := 0.0
var _copy_line_done := false
var _b13_done := false
var _sounds: Array = []      # recent player sounds: [name, position, time]
var _clock := 0.0


func setup(s: Node) -> Node:
	sector = s
	gentle = Game.is_explorer()
	_behind_t = randf_range(60.0, 100.0)
	_false_t = randf_range(70.0, 120.0)
	_leak_t = randf_range(90.0, 160.0)
	_echo_t = randf_range(50.0, 90.0)
	_copy_line_t = randf_range(180.0, 360.0)
	return self


## Called for every noise you make (footsteps, doors, gasps...).
func player_noise(pos: Vector3, radius: float) -> void:
	_sounds.append(["step_run" if radius >= 9.0 else "step", pos, _clock])
	if _sounds.size() > 40:
		_sounds.pop_front()
	if radius >= 9.0 and _answer_cool <= 0.0:
		_answer_cool = randf_range(60.0, 120.0)
		_facility_answers(pos)


func _process(delta: float) -> void:
	if sector == null or sector.ended or sector.paused_world or sector.catching:
		return
	_clock += delta
	_answer_cool -= delta
	_behind_t -= delta
	if _behind_t <= 0.0:
		_behind_t = randf_range(70.0, 120.0)
		_lights_out_behind()
	_leak_t -= delta
	if _leak_t <= 0.0:
		_leak_t = randf_range(120.0, 200.0)
		_leak_13()
	_echo_t -= delta
	if _echo_t <= 0.0:
		_echo_t = randf_range(60.0, 110.0)
		_echo_replay()
	if not gentle:
		_false_t -= delta
		if _false_t <= 0.0:
			_false_t = randf_range(80.0, 140.0)
			_false_footsteps()
		_copy_line_t -= delta
		if _copy_line_t <= 0.0 and not _copy_line_done and sector.echo:
			_copy_line_done = true
			var lines: Array = sector.echo.VOICE_LINES
			sector.hud.say("ai", lines[randi() % lines.size()])
	if not _b13_done and sector.exit_door and sector.exit_door.display:
		if sector.player.global_position.distance_to(sector.exit_door.global_position) < 7.0:
			_b13_done = true
			_flash_b13()


func _facility_answers(pos: Vector3) -> void:
	var best: Vector3 = Vector3.INF
	for ic in sector.intercoms:
		var p: Vector3 = sector.cell_to_world(ic["cell"]) + Vector3(0, 2.0, 0)
		if p.distance_to(pos) < 25.0 and (best == Vector3.INF or p.distance_to(pos) < best.distance_to(pos)):
			best = p
	if best == Vector3.INF:
		best = pos + Vector3(randf_range(-6, 6), 2.6, randf_range(-6, 6))
	Sound.play_at("facility_chime", best, -6.0 if gentle else -2.0)
	if not gentle:
		await get_tree().create_timer(1.3).timeout
		if is_inside_tree() and not sector.ended:
			sector.hud.say("ai", MERIDIAN_NOTED[randi() % MERIDIAN_NOTED.size()])


## Behind you, the ceiling lights go out one by one (furthest first), and
## come back on a while later. It never shuts you in, and never chases.
func _lights_out_behind() -> void:
	var player: Node3D = sector.player
	var fwd := -player.global_transform.basis.z
	var picks: Array = []
	for l in sector.lights:
		var light: OmniLight3D = l["light"]
		if l.get("off", false) or l.get("dimmed", false) or l["room"] == "ELEVATOR" or not light.visible:
			continue
		var to: Vector3 = light.global_position - player.global_position
		to.y = 0.0
		if to.length() > 6.0 and to.length() < 20.0 and to.normalized().dot(fwd) < -0.3:
			picks.append(l)
	if picks.size() < 2:
		return
	picks.sort_custom(func(a, b): return a["light"].global_position.distance_to(player.global_position) > b["light"].global_position.distance_to(player.global_position))
	picks = picks.slice(0, mini(picks.size(), 4))
	for l in picks:
		if not is_inside_tree():
			return
		l["dimmed"] = true
		l["light"].visible = false
		l["fixture"].visible = false
		Sound.play_at("breaker", l["light"].global_position, -16.0 if gentle else -10.0, 0.7)
		await get_tree().create_timer(0.9 if gentle else 0.6).timeout
	await get_tree().create_timer(randf_range(18.0, 28.0)).timeout
	for l in picks:
		if not is_inside_tree():
			return
		l["dimmed"] = false
		if not l.get("off", false):
			l["light"].visible = true
			l["fixture"].visible = true
		await get_tree().create_timer(0.4).timeout


## Footsteps where nobody is... then a pipe taps twice in the same spot. It
## was the building. (Only while the Listener is far away and not hunting.)
func _false_footsteps() -> void:
	var lis: Node = sector.listener
	var player: Node3D = sector.player
	if lis == null or lis.state == lis.State.HUNT or lis.global_position.distance_to(player.global_position) < 18.0:
		return
	var spot := Vector3.INF
	for i in 12:
		var p: Vector3 = sector.random_floor_pos()
		var d: float = p.distance_to(player.global_position)
		if d > 7.0 and d < 13.0 and not player.can_see(p + Vector3(0, 1, 0)):
			spot = p
			break
	if spot == Vector3.INF:
		return
	var dir := Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)).normalized()
	for k in 4:
		Sound.play_at("step", spot + dir * k * 0.7, -6.0, randf_range(0.85, 0.95))
		await get_tree().create_timer(0.55).timeout
		if not is_inside_tree():
			return
	await get_tree().create_timer(1.4).timeout
	if is_inside_tree():
		Sound.play_at("pipe_tap", spot + dir * 2.0 + Vector3(0, 2.6, 0), -4.0)


## ECHO plays back one of your own sounds from where you made it... with one
## extra step at the end that you didn't take.
func _echo_replay() -> void:
	if sector.echo == null or not sector.echo.active:
		return
	var old: Array = []
	for snd in _sounds:
		if _clock - float(snd[2]) > 15.0 and _clock - float(snd[2]) < 60.0:
			old.append(snd)
	if old.size() < 3:
		return
	var start := randi() % maxi(old.size() - 3, 1)
	var vol := -14.0 if gentle else -6.0
	for k in 3:
		var snd: Array = old[start + k]
		Sound.play_at(snd[0], snd[1], vol, randf_range(0.95, 1.0))
		await get_tree().create_timer(0.5).timeout
		if not is_inside_tree():
			return
	var last: Array = old[start + 2]
	Sound.play_at(last[0], last[1], vol - 1.0, 0.86)   # the one you didn't make


## A room's name on the floor reads SECTOR 13, but only while you aren't looking.
func _leak_13() -> void:
	var cam: Camera3D = sector.player.cam
	var hidden: Array = []
	for l in sector.floor_labels:
		if not cam.is_position_in_frustum(l.global_position):
			hidden.append(l)
	if hidden.is_empty():
		return
	var lab: Label3D = hidden[randi() % hidden.size()]
	var was := lab.text
	lab.text = "SECTOR 13"
	await get_tree().create_timer(8.0).timeout
	# Put it back... but only once you aren't looking at it.
	for i in 120:
		if not is_inside_tree() or not is_instance_valid(lab):
			return
		if not cam.is_position_in_frustum(lab.global_position):
			lab.text = was
			return
		await get_tree().create_timer(0.5).timeout
	lab.text = was


func _flash_b13() -> void:
	var door: Node = sector.exit_door
	var text: String = door.display.text
	var col: Color = door.display.modulate
	door.set_display("FLOOR  B13", Color(1.0, 0.25, 0.15))
	Sound.play_at("cam_beep", door.global_position + Vector3(0, 2.6, 0), -8.0, 0.6)
	await get_tree().create_timer(1.1).timeout
	if is_instance_valid(door) and door.display.text == "FLOOR  B13":
		door.set_display(text, col)
