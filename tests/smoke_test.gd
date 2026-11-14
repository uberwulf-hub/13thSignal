extends Node
## Plays through Sector 1 automatically and checks the important parts work.
## Run:  godot --headless --path . res://tests/smoke_test.tscn
## Exits with code 0 if everything passed, 1 if anything failed.

var failures := 0
var s: Node


func check(ok: bool, what: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + what)
	if not ok:
		failures += 1


func wait(t: float) -> void:
	await get_tree().create_timer(t).timeout


func _ready() -> void:
	# If a script error stops the test partway, give up instead of hanging forever.
	get_tree().create_timer(300.0).timeout.connect(func():
		print("FAIL  the test timed out (a script error probably stopped it)")
		get_tree().quit(1))
	# --- Parent Lock ---
	Game.lock_scary_modes()
	check(Game.mode == Game.Mode.EXPLORER, "the game starts in Explorer")
	check(not Game.mode_allowed(Game.Mode.SURVIVOR), "Survivor is locked without the Parent PIN")
	check(not Game.mode_allowed(Game.Mode.NIGHTMARE), "Nightmare is locked without the Parent PIN")

	# --- Explorer playthrough ---
	s = load("res://scenes/sector.tscn").instantiate()
	add_child(s)
	await wait(1.0)
	check(s.exit_code.length() == 4, "an exit code was made")
	s.player.global_position = s.cell_to_world(Vector2i(4, 7))
	await wait(0.5)
	check(s.listener.is_physics_processing(), "the Listener wakes up in the main hall")
	var levers: Array = []
	for c in s.get_children():
		if c.get("prompt_text") != null and String(c.prompt_text).begins_with("Flip"):
			levers.append(c)
	check(levers.size() == 3, "there are 3 breakers")
	s._flip_breaker("MIDDLE", levers[1])
	await wait(0.6)
	check(s.breaker_seq.is_empty() and not s.power_on, "the wrong breaker order trips and resets")
	s.listener.reset_to(s.cell_to_world(Vector2i(1, 7)))
	for side in ["RIGHT", "MIDDLE", "LEFT"]:
		s._flip_breaker(side, levers[0])
	check(s.power_on, "the right breaker order turns the power on")
	check(s.replacement.active, "the Replacement wakes up when the power comes on")
	s.listener.reset_to(s.player.global_position + Vector3(0.5, 0, 0))
	await wait(0.3)
	check(s.catching and s.catches == 1, "the Listener catches you when it reaches you")
	await wait(1.2)
	check(s.player.cam.position.y < 0.8 and s.listener.posed, "...you fall backwards and it bends down over you")
	await wait(5.0)
	check(not s.catching and not s.player.frozen, "you respawn at the checkpoint")
	check(absf(s.player.cam.position.y - 1.6) < 0.05 and not s.listener.posed, "...standing up again, and it's back to normal")
	s._on_code("0000" if s.exit_code != "0000" else "1111")
	check(not s.exit_open, "a wrong code keeps the elevator shut")
	s._on_code(s.exit_code)
	check(s.exit_open, "the right code opens the elevator")
	s.player.global_position = s.cell_to_world(Vector2i(25, 16))
	await wait(1.0)
	check(s.ended, "stepping into the elevator finishes the sector")
	check(not Game.learned_lockers, "in Explorer the Listener never learns to check lockers")
	s.queue_free()
	await wait(0.3)

	# --- Survivor: the Listener learns ---
	Game.scary_unlocked = true
	Game.mode = Game.Mode.SURVIVOR
	s = load("res://scenes/sector.tscn").instantiate()
	add_child(s)
	await wait(1.0)
	s.listener.set_physics_process(true)
	for i in 3:
		s._hid_recently = 0.0
		s.on_player_hid(s.lockers[0])
	check(Game.learned_lockers, "in Survivor, hiding 3 times teaches it to check lockers")
	var lk: Node = s.lockers[3]
	s.player.enter_locker(lk)
	s.listener.reset_to(lk.front_pos() + Vector3(4, 0, 0))
	s.listener.state = s.listener.State.LISTEN
	s.listener._wait = 0.01
	Input.action_press("hold_breath")
	await wait(4.5)
	Input.action_release("hold_breath")
	check(s.catches == 0, "holding your breath in a checked locker keeps you safe")
	s.player.leave_locker()
	s.player.enter_locker(lk)
	s.listener.reset_to(lk.front_pos() + Vector3(4, 0, 0))
	s.listener.state = s.listener.State.LISTEN
	s.listener._wait = 0.01
	await wait(4.5)
	check(s.catches == 1, "breathing in a checked locker gets you caught")
	await wait(6.5)
	Game.sprint_cells = {Vector2i(2, 7): 5.0, Vector2i(12, 7): 4.0, Vector2i(24, 7): 3.0, Vector2i(15, 16): 2.0}
	s.player.global_position = s.cell_to_world(Vector2i(3, 2))
	Game.sprint_time = 100.0
	s.note_sprint(s.player.global_position, 0.1)
	check(Game.learned_traps and s.traps.size() == 3, "running a lot makes it set 3 tripwires")

	s.queue_free()
	await wait(0.3)
	check(Game.sector_unlocked >= 2, "clearing Sector 1 unlocks Sector 2")

	# --- Sector 2: the vault logic puzzle always has exactly one answer ---
	var S2 = load("res://scripts/sector_2.gd")
	var probe = S2.new()
	var puzzle_ok := true
	for n in 300:
		probe.make_vault_puzzle()
		var fits := 0
		for v in 3:
			if S2._true_count(probe.statements, v) == 1:
				fits += 1
		if fits != 1 or S2._true_count(probe.statements, probe.correct_vault) != 1:
			puzzle_ok = false
	probe.free()
	check(puzzle_ok, "Sector 2's vault puzzle has exactly one answer (300 random games)")

	# --- Sector 2 playthrough (Survivor) ---
	s = load("res://scenes/sector_2.tscn").instantiate()
	add_child(s)
	await wait(1.0)
	check(s.echo != null, "ECHO is in Sector 2")
	check(s.lockers.size() == 6 and s.vault_doors.size() == 3, "Sector 2 built its lockers and vault doors")
	var door_c = s.vault_doors[s.correct_vault]
	s.vault_interact(door_c)
	check(not door_c.unlocked, "vaults stay shut without power")
	s.has_fuse = true
	var panel = null
	for c in s.get_children():
		if c.get("prompt_text") == "Fuse panel (empty)":
			panel = c
	panel.interact(s.player)
	check(s.vault_power, "the fuse powers the vault row")
	var wrong = s.vault_doors[(s.correct_vault + 1) % 3]
	s.vault_interact(wrong)
	check(not wrong.unlocked, "the wrong vault stays shut")
	s.vault_interact(door_c)
	check(door_c.unlocked, "the right vault opens")
	var drive = null
	for c in s.get_children():
		if c.get("prompt_text") == "Take the archive drive":
			drive = c
	check(drive != null, "the archive drive is inside the vault")
	drive.interact(s.player)
	check(s.has_drive, "you can take the drive")
	var server = null
	for c in s.get_children():
		if c.get("prompt_text") == "Archive server: needs the archive drive":
			server = c
	server.interact(s.player)
	check(s.exit_open and s.exit_door.is_open, "the drive in the server opens the elevator")

	# ECHO: follows your trail and catches you if you stand still.
	s.listener.set_physics_process(false)
	s.listener.reset_to(s.cell_to_world(Vector2i(1, 9)))
	s.trail.clear()
	for x in range(2, 20):
		s.trail.append(s.cell_to_world(Vector2i(x, 7)) + Vector3(0, 0, 0))
	s.player.global_position = s.cell_to_world(Vector2i(20, 7))
	s.echo.lose_trail(0.0)
	for x in range(2, 20):
		s.trail.append(s.cell_to_world(Vector2i(x, 7)))
	var c0: int = s.catches
	await wait(1.0)
	check(s.echo.active and s.echo.visible, "ECHO steps out onto your trail")
	var echo_start: Vector3 = s.echo.global_position
	await wait(1.0)
	check(s.echo.global_position.x > echo_start.x, "ECHO walks along your trail")
	s.echo.global_position = s.player.global_position + Vector3(-3.0, 0, 0)
	s.echo._idx = s.trail.size()
	await wait(2.5)
	check(s.catches == c0 + 1, "in Survivor, ECHO catches you if you stand still")
	await wait(4.0)
	s.trail.append(s.player.global_position)
	s.trail.append(s.player.global_position + Vector3(1, 0, 0))
	s.echo._wait = 0.0
	s.player.enter_locker(s.lockers[0])
	check(not s.echo.active and s.trail.is_empty(), "hiding in a locker breaks your trail")
	s.player.leave_locker()
	s.player.global_position = s.cell_to_world(Vector2i(24, 13))
	await wait(1.0)
	check(s.ended, "stepping into the elevator finishes Sector 2")
	s.queue_free()
	await wait(0.3)

	# --- Explorer: ECHO never catches you ---
	Game.lock_scary_modes()
	s = load("res://scenes/sector_2.tscn").instantiate()
	add_child(s)
	await wait(1.0)
	s.listener.reset_to(s.cell_to_world(Vector2i(25, 3)))
	s.listener.set_physics_process(false)
	s.visited["MAIN HALL"] = true
	s.trail.clear()
	for x in range(2, 10):
		s.trail.append(s.cell_to_world(Vector2i(x, 7)))
	s.player.global_position = s.cell_to_world(Vector2i(10, 7))
	s.echo._wait = 0.0
	await wait(0.5)
	s.echo.global_position = s.player.global_position + Vector3(-2.0, 0, 0)
	s.echo._idx = s.trail.size()
	await wait(2.0)
	check(s.catches == 0 and not s.echo.active, "in Explorer, ECHO glitches away instead of catching you")
	s.queue_free()

	await wait(0.3)
	check(Game.sector_unlocked >= 3, "clearing Sector 2 unlocks Sector 3")

	# --- Sector 3: relay labs (Survivor) ---
	Game.scary_unlocked = true
	Game.mode = Game.Mode.SURVIVOR
	s = load("res://scenes/sector_3.tscn").instantiate()
	add_child(s)
	await wait(1.0)
	s.listener.set_physics_process(false)
	s.listener.reset_to(s.cell_to_world(Vector2i(28, 8)))
	check(s.relays.size() == 8, "Sector 3 has 8 relays")
	check(s.powered.is_empty(), "no receiver is lit at the start")
	var rl = s.relays[0]
	s.player.global_position = s.cell_to_world(Vector2i(9, 3))
	s.pick_up(rl)
	check(s.player.carrying == rl, "you can pick up a relay")
	s._put(rl, Vector2i(13, 2))
	rl.set_facing(1)
	s.update_beams()
	check(s.solved.has("RELAY LAB 1"), "Lab 1: one relay turns the beam into the receiver")
	check(s.gates[Vector2i(20, 6)].is_open, "solving Lab 1 opens Lab 2's gate")
	var lab2 = [[Vector2i(16, 2), 0], [Vector2i(19, 2), 1], [Vector2i(19, 3), 0]]
	for i in 3:
		var r2 = s.relays[1 + i]
		s._put(r2, lab2[i][0])
		r2.set_facing(lab2[i][1])
	s.update_beams()
	check(s.solved.has("RELAY LAB 2"), "Lab 2: the beam goes through the glass to the receiver")
	check(s.gates[Vector2i(6, 10)].is_open, "solving Lab 2 opens Lab 3's gate")
	# Jam: one relay hit by both colours sends nothing.
	var j = s.relays[4]
	s._put(j, Vector2i(10, 15))
	j.set_facing(3)
	var j2 = s.relays[5]
	s._put(j2, Vector2i(10, 11))
	j2.set_facing(1)
	s.update_beams()
	check(not s.solved.has("RELAY LAB 3"), "a relay hit by red and blue jams")
	var lab3 = [[Vector2i(10, 11), 1], [Vector2i(10, 13), 0], [Vector2i(3, 15), 3], [Vector2i(3, 13), 2]]
	for i in 4:
		var r3 = s.relays[4 + i]
		s._put(r3, lab3[i][0])
		r3.set_facing(lab3[i][1])
	s.update_beams()
	check(s.solved.has("RELAY LAB 3") and s.exit_open, "Lab 3: red and blue reach their receivers and open the elevator")
	# ECHO can't follow into a lab.
	s.player.global_position = s.cell_to_world(Vector2i(5, 13))
	await wait(0.2)
	check(s.trail_shielded(), "the labs are shielded")
	var before_trail: int = s.trail.size()
	await wait(0.6)
	check(s.trail.size() == before_trail, "your trail isn't recorded inside a lab")
	s.player.global_position = s.cell_to_world(Vector2i(29, 13))
	await wait(1.0)
	check(s.ended, "stepping into the elevator finishes Sector 3")
	s.queue_free()
	await wait(0.3)

	# --- Explorer: monsters can't walk into the labs ---
	Game.lock_scary_modes()
	s = load("res://scenes/sector_3.tscn").instantiate()
	add_child(s)
	await wait(0.8)
	var into_lab: Array = s.find_path(s.cell_to_world(Vector2i(15, 8)), s.cell_to_world(Vector2i(10, 3)))
	check(into_lab.is_empty(), "in Explorer, monsters can't path into the relay labs")
	s.queue_free()
	await wait(0.3)

	check(Game.sector_unlocked >= 4, "clearing Sector 3 unlocks Sector 4")

	# --- Sector 4: jammers (Survivor) ---
	Game.scary_unlocked = true
	Game.mode = Game.Mode.SURVIVOR
	s = load("res://scenes/sector_4.tscn").instantiate()
	add_child(s)
	await wait(1.0)
	s.listener.set_physics_process(false)
	s.listener.reset_to(s.cell_to_world(Vector2i(1, 9)))
	check(s.jammers.size() == 2 and s.lasers.size() == 3 and s.cameras.size() == 2, "Sector 4 has 2 jammers, 3 laser grids and 2 cameras")
	var cp := Vector2i(8, 5)
	check(s.lasers[cp]["on"] and s.grid.is_point_solid(cp), "the checkpoint laser grid starts on")
	var hall_j = s.jammers[1]
	s.player.global_position = s.cell_to_world(Vector2i(6, 7))
	s.pick_up(hall_j)
	check(s.player.carrying == hall_j, "you can pick up a jammer")
	s._put(hall_j, Vector2i(8, 6))
	check(not s.lasers[cp]["on"] and not s.grid.is_point_solid(cp), "a jammer next to a laser grid switches it off")
	check(s.noise_muffled(s.cell_to_world(Vector2i(8, 6))) and not s.noise_muffled(s.cell_to_world(Vector2i(20, 8))), "footsteps are silent only inside a jammer's field")
	check(s.echo_blocked(s.cell_to_world(Vector2i(8, 7))), "ECHO can't step into a jammer's field")
	s.player.global_position = s.cell_to_world(Vector2i(8, 2))
	s.pick_up(hall_j)
	s._update_jamming()
	check(s.lasers[cp]["on"], "picking the jammer back up switches the grid on again")
	var button = null
	for c in s.get_children():
		if c.get("prompt_text") == "Open the shutter":
			button = c
	button.interact(s.player)
	check(s.shutter.is_open and not s.grid.is_point_solid(s.shutter.cell), "the armory button opens the shutter")
	s._put(hall_j, Vector2i(8, 2))
	# Cameras: point camera 1 straight at you and let it watch.
	var cam: Dictionary = s.cameras[0]
	s.player.global_position = s.cell_to_world(Vector2i(25, 11))
	var to: Vector3 = s.player.global_position - cam["pivot"].global_position
	cam["base"] = atan2(to.x, to.z)
	cam["amp"] = 0.0
	await wait(1.6)
	check(cam["cooldown"] > 0.0, "a camera that keeps you in view sets off the alarm")
	s.listener.reset_to(s.cell_to_world(Vector2i(1, 9)))
	var cam_j = s.jammers[0]
	s._put(cam_j, Vector2i(27, 12))
	s._update_jamming()
	cam["cooldown"] = 0.0
	await wait(1.5)
	check(not cam["on"] and cam["cooldown"] == 0.0, "a jammed camera goes dark and can't spot you")
	# The elevator wing needs both jammers: one on the grid, one on the camera.
	s._put(cam_j, Vector2i(27, 16))
	s._put(hall_j, Vector2i(21, 15))
	s._update_jamming()
	check(not s.cameras[1]["on"] and not s.lasers[Vector2i(20, 15)]["on"] and not s.lasers[Vector2i(20, 16)]["on"], "two jammers cover the final grid and camera")
	s.exit_interact(s.exit_door)
	check(s.exit_open, "the elevator opens")
	s.player.global_position = s.cell_to_world(Vector2i(15, 15))
	await wait(1.0)
	check(s.ended, "stepping into the elevator finishes Sector 4")
	s.queue_free()
	await wait(0.3)

	check(Game.sector_unlocked >= 5, "clearing Sector 4 unlocks Sector 5")

	# --- Sector 5: recordings and pressure plates (Survivor) ---
	Game.scary_unlocked = true
	Game.mode = Game.Mode.SURVIVOR
	s = load("res://scenes/sector_5.tscn").instantiate()
	add_child(s)
	await wait(1.0)
	s.listener.set_physics_process(false)
	s.listener.reset_to(s.cell_to_world(Vector2i(1, 7)))
	check(s.plate_doors.size() == 3 and s.plate_pads.size() == 4, "Sector 5 has 4 plates and 3 plate doors")
	var y1: Vector2i = Vector2i(14, 2)
	check(not s.doors[y1].is_open, "plate doors start shut")
	s.player.global_position = s.cell_to_world(Vector2i(13, 4))
	await wait(0.2)
	check(s.doors[y1].is_open, "standing on a plate opens its door")
	s.player.global_position = s.cell_to_world(Vector2i(11, 3))
	await wait(0.2)
	check(not s.doors[y1].is_open, "stepping off the plate shuts the door again")
	# Record: walk from the booth to the plate, then stop.
	s.player.global_position = s.cell_to_world(Vector2i(7, 2))
	s.start_recording()
	check(s.recording, "pressing E at a booth starts recording")
	for x in range(7, 14):
		s.player.global_position = s.cell_to_world(Vector2i(x, 3))
		await wait(0.12)
	s.player.global_position = s.cell_to_world(Vector2i(13, 4))
	await wait(0.3)
	check(s.on_rotate_pressed() and not s.recording and s.copy != null, "R stops recording and your copy appears")
	s.player.global_position = s.cell_to_world(Vector2i(12, 2))
	await wait(0.2)
	check(s.copy_cell() != Vector2i(13, 4), "the copy starts from where the recording began")
	await wait(2.0)
	check(s.copy_cell() == Vector2i(13, 4) and s.doors[y1].is_open, "your copy walks to the plate and holds the door open")
	await wait(1.0)
	check(s.doors[y1].is_open, "the copy stays on the plate after the recording ends")
	s.start_recording()
	check(s.copy == null, "a new recording replaces the old copy")
	s.stop_recording()
	# Lab 2 timing: copy holds ORANGE for a while, then moves to YELLOW.
	s.player.global_position = s.cell_to_world(Vector2i(15, 2))
	s.start_recording()
	await wait(0.2)
	s.player.global_position = s.cell_to_world(Vector2i(16, 4))
	await wait(2.0)
	s.player.global_position = s.cell_to_world(Vector2i(17, 4))
	await wait(0.2)
	s.player.global_position = s.cell_to_world(Vector2i(18, 4))
	await wait(0.3)
	s.stop_recording()
	s.player.global_position = s.cell_to_world(Vector2i(17, 2))
	await wait(0.6)
	check(s.doors[Vector2i(19, 2)].is_open and not s.doors[Vector2i(25, 2)].is_open, "Lab 2: the copy holds ORANGE first")
	s.player.global_position = s.cell_to_world(Vector2i(22, 2))
	await wait(2.4)
	check(s.doors[Vector2i(25, 2)].is_open and not s.doors[Vector2i(19, 2)].is_open, "Lab 2: then it moves on to YELLOW, so you get through both doors")

	# The Listener erases a copy it reaches.
	s.player.global_position = s.cell_to_world(Vector2i(20, 12))
	s.start_recording()
	await wait(0.2)
	s.player.global_position = s.cell_to_world(Vector2i(18, 12))
	await wait(0.3)
	s.stop_recording()
	s.player.global_position = s.cell_to_world(Vector2i(28, 13))
	await wait(1.0)
	check(s.exit_open, "a copy on the GREEN plate holds the elevator open")
	s.listener.set_physics_process(true)
	s.listener.reset_to(s.copy.global_position + Vector3(0.6, 0, 0))
	await wait(0.3)
	check(s.copy == null, "in Survivor, the Listener erases a recording it reaches")
	await wait(0.3)
	check(not s.exit_open, "...and the elevator shuts again")
	s.listener.set_physics_process(false)
	s.listener.reset_to(s.cell_to_world(Vector2i(1, 7)))
	s.player.global_position = s.cell_to_world(Vector2i(20, 12))
	s.start_recording()
	await wait(0.2)
	s.player.global_position = s.cell_to_world(Vector2i(18, 12))
	await wait(0.3)
	s.stop_recording()
	await wait(1.0)
	s.player.global_position = s.cell_to_world(Vector2i(14, 11))
	await wait(1.0)
	check(s.ended, "stepping into the elevator finishes Sector 5")
	s.queue_free()
	await wait(0.3)

	check(Game.sector_unlocked >= 6, "clearing Sector 5 unlocks Sector 6")

	# --- Sector 6: mannequins and the power board (Survivor) ---
	Game.scary_unlocked = true
	Game.mode = Game.Mode.SURVIVOR
	s = load("res://scenes/sector_6.tscn").instantiate()
	add_child(s)
	await wait(1.0)
	s.listener.set_physics_process(false)
	s.listener.reset_to(s.cell_to_world(Vector2i(1, 8)))
	check(s.mannequins.size() == 2, "Survivor has 2 real mannequins among the props")
	for r in s.mannequins:
		r.active = false
	var east = s.doors[Vector2i(19, 6)]
	check(not east.is_open, "showroom shutters start shut (no power)")
	s.flip("EAST")
	await wait(0.2)
	check(east.is_open, "switching on the EAST circuit opens its shutter")
	s.flip("STOCKROOM")
	s.flip("WEST")
	await wait(0.2)
	check(not s.power["EAST"] and not s.power["STOCKROOM"] and not east.is_open, "a third circuit overloads the board and everything goes dark")
	await wait(4.3)
	s.flip("EAST")
	s.flip("STOCKROOM")
	await wait(0.2)
	check(s.lit_at(s.cell_to_world(Vector2i(20, 2))) and not s.lit_at(s.cell_to_world(Vector2i(5, 13))), "a powered room is lit; the others are dark")
	var m0 = s.mannequins[0]
	m0.active = true
	s.player.global_position = s.cell_to_world(Vector2i(21, 4))
	s.player.look_at_yaw(0.0)
	m0.reset_to(s.cell_to_world(Vector2i(16, 2)))
	var m_before: Vector3 = m0.global_position
	await wait(1.0)
	check(m0.global_position.distance_to(m_before) < 0.01, "a mannequin can't move in a lit room, even unseen")
	m0.active = false
	s.has_key = true
	s.flip("EAST")
	s.flip("STOCKROOM")
	s.flip("WEST")
	s.flip("ELEVATOR")
	await wait(0.3)
	check(s.exit_open and s.exit_door.is_open, "WEST + ELEVATOR with the key opens the elevator")
	s.player.global_position = s.cell_to_world(Vector2i(17, 13))
	await wait(1.0)
	check(s.ended, "stepping into the elevator finishes Sector 6")
	s.queue_free()
	await wait(0.3)

	# --- Inventory: items to pick up, use and throw (Survivor) ---
	Game.scary_unlocked = true
	Game.mode = Game.Mode.SURVIVOR
	s = load("res://scenes/sector.tscn").instantiate()
	add_child(s)
	await wait(1.2)
	var WI = load("res://scripts/world_item.gd")
	var loot := 0
	for c in s.get_children():
		if c.get_script() == WI:
			loot += 1
	check(loot >= 10, "everyday items are scattered through the sector (%d)" % loot)
	var pl = s.player
	pl.inventory.clear()
	var it = WI.new()
	s.add_child(it)
	it.setup(s, "battery")
	it.global_position = pl.global_position + Vector3(0.5, 0.2, 0)
	it.interact(pl)
	check(pl.selected_id() == "battery", "picking an item up puts it in your inventory (and your hand)")
	pl.add_item("battery")
	check(pl.inventory.size() == 1 and pl.inventory[0]["count"] == 2, "matching items stack in one slot")
	pl.battery = 10.0
	pl.use_item()
	check(pl.battery >= 69.0 and pl.inventory[0]["count"] == 1, "a battery recharges the flashlight")
	for id in ["soda_can", "glowstick", "photo", "wrench", "clipboard"]:
		pl.add_item(id)
	check(not pl.add_item("bottle"), "six slots: a full inventory refuses more")
	var ev := InputEventAction.new()
	ev.action = "slot_2"
	ev.pressed = true
	Game.touch_mode = 1   # (a headless test has no captured mouse; touch mode lets input through)
	pl._unhandled_input(ev)
	Game.touch_mode = 0
	check(pl.selected_id() == "soda_can", "the number keys pick a slot")
	# Throw the can: the Listener goes to where it lands, not to you.
	var lis2 = s.listener
	lis2.set_physics_process(true)
	pl.global_position = s.cell_to_world(Vector2i(3, 7))
	pl.look_at_yaw(-PI / 2.0)
	pl.pitch = 0.0
	pl._apply_look()
	lis2.reset_to(s.cell_to_world(Vector2i(8, 8)))
	lis2._wait = 99.0
	lis2._hunch_t = 999.0
	pl.use_item()
	await wait(1.5)
	check(lis2.state == lis2.State.INVESTIGATE or lis2.state == lis2.State.LISTEN, "a thrown can makes a noise that draws the Listener")
	check(lis2.last_heard.distance_to(pl.global_position) > 4.0, "...to where it landed, not to you")
	lis2.set_physics_process(false)
	lis2.reset_to(s.cell_to_world(Vector2i(1, 9)))
	# A glow stick holds a mannequin still in its light.
	pl.select_slot(1)
	check(pl.selected_id() == "glowstick", "the glow stick is in slot 2 now")
	pl.use_item()
	await wait(1.0)
	check(s.glows.size() == 1 and s.near_glow(s.glows[0].global_position, 1.0), "a cracked glow stick lights up")
	var rep = s.replacement
	rep.active = true
	rep.reset_to(s.glows[0].global_position + Vector3(1.5, 0, 0))
	pl.look_at_yaw(PI / 2.0)
	var rp: Vector3 = rep.global_position
	await wait(0.8)
	check(rep.global_position.distance_to(rp) < 0.01, "a mannequin can't move in a glow stick's light")
	rep.active = false
	# Mannequins are solid: you can't walk through one, and things bounce off it.
	var Rep = load("res://scripts/replacement.gd")
	var dummy: Node3D = Rep.build_model()
	s.add_child(dummy)
	dummy.global_position = s.cell_to_world(Vector2i(3, 7))
	await wait(0.2)
	pl.global_position = dummy.global_position + Vector3(1.2, 0, 0)
	check(pl.test_move(pl.global_transform, Vector3(-1.5, 0, 0)), "you can't walk through a mannequin")
	var wr = WI.new()
	s.add_child(wr)
	wr.setup(s, "wrench")
	wr.thrown = true
	wr.global_position = dummy.global_position + Vector3(1.0, 1.1, 0)
	wr.linear_velocity = Vector3(-7.0, 0, 0)
	await wait(1.5)
	check(is_instance_valid(wr) and wr.global_position.x > dummy.global_position.x, "a thrown wrench bounces off a mannequin instead of going through")
	check(is_instance_valid(wr) and wr.hit_mannequin, "...and the mannequin makes a sound when it's hit")
	check(is_instance_valid(wr) and "concrete" in wr.surfaces_hit, "...then it clatters on the concrete floor (%s)" % [wr.surfaces_hit if is_instance_valid(wr) else []])
	for snd in ["obj_can", "obj_steel", "obj_ceramic", "obj_bottle", "obj_board", "surf_concrete", "surf_metal", "surf_grate", "surf_glass", "surf_mannequin", "mq_hit_reaction"]:
		if Sound.stream(snd) == null:
			check(false, "impact sound exists: " + snd)
	dummy.queue_free()
	# The journal scrolls when it gets long.
	for i in 40:
		s.hud.add_clue("Test clue number %d, which is long enough to wrap around a line or two in the journal panel." % i)
	Input.action_press("journal")
	await wait(0.3)
	var jsc: ScrollContainer = s.hud._journal_scroll
	s.hud.scroll_journal(300.0)
	await wait(0.1)
	check(s.hud.journal_open() and jsc.scroll_vertical > 0, "a long journal scrolls")
	check(s.hud._journal.size.y <= get_viewport().get_visible_rect().size.y, "...and fits on the screen")
	Input.action_release("journal")
	var before_count: int = pl.inventory.size()
	pl.drop_item()
	check(pl.inventory.size() == before_count - 1, "G drops the item in your hand")
	s.queue_free()
	await wait(0.3)

	# --- A harder, less predictable Listener (Survivor) ---
	Game.scary_unlocked = true
	Game.mode = Game.Mode.SURVIVOR
	s = load("res://scenes/sector.tscn").instantiate()
	add_child(s)
	await wait(1.0)
	var lis = s.listener
	lis.set_physics_process(true)
	lis.reset_to(s.cell_to_world(Vector2i(14, 7)))
	lis._wait = 99.0
	lis._hunch_t = 999.0
	s.player.global_position = s.cell_to_world(Vector2i(10, 6))
	s.doors[Vector2i(10, 5)].interact(s.player)
	check(lis.state != lis.State.WANDER, "opening a door is loud enough to bring the Listener")
	lis.reset_to(s.cell_to_world(Vector2i(24, 8)))
	lis._hunch_t = 0.0
	await wait(0.1)
	check(lis.state == lis.State.INVESTIGATE, "it sometimes gets a hunch and comes to check where you are")
	s.player.global_position = s.cell_to_world(Vector2i(16, 7))
	lis.reset_to(s.cell_to_world(Vector2i(16, 7)) + Vector3(2.5, 0, 0))
	lis.state = lis.State.LISTEN
	lis._wait = 5.0
	lis._hunch_t = 999.0
	await wait(0.15)
	check(lis.state == lis.State.HUNT or s.catching, "standing silent right next to it while it listens isn't safe")
	await wait(4.0)
	Game.crouch_time = 60.0
	s.note_crouch()
	check(Game.learned_crouch, "in Survivor, crouching a lot teaches it to hear you crawl")
	# Stare at it: it glitches and jumps a short distance.
	lis.state = lis.State.WANDER
	lis.path.clear()
	lis._wait = 99.0
	lis._hunch_t = 999.0
	s.player.global_position = s.cell_to_world(Vector2i(8, 7))
	lis.reset_to(s.cell_to_world(Vector2i(13, 7)))
	lis._wait = 99.0
	s.player.look_at_yaw(-PI / 2.0)
	s.player.flashlight.visible = true
	var before: Vector3 = lis.global_position
	await wait(3.2)
	var jumped: float = lis.global_position.distance_to(before)
	var gap_to_you := Vector2(lis.global_position.x - s.player.global_position.x, lis.global_position.z - s.player.global_position.z).length()
	check(jumped > 1.5 and gap_to_you >= 2.6, "staring at the Listener makes it glitch and jump (never right on top of you)")
	s.queue_free()
	await wait(0.3)
	Game.lock_scary_modes()
	s = load("res://scenes/sector.tscn").instantiate()
	add_child(s)
	await wait(0.8)
	Game.crouch_time = 999.0
	s.note_crouch()
	check(not Game.learned_crouch, "in Explorer it never learns to hear you crawl")
	s.listener.set_physics_process(true)
	s.player.global_position = s.cell_to_world(Vector2i(16, 7))
	s.listener.reset_to(s.cell_to_world(Vector2i(16, 7)) + Vector3(2.5, 0, 0))
	s.listener.state = s.listener.State.LISTEN
	s.listener._wait = 5.0
	await wait(0.15)
	check(s.listener.state == s.listener.State.LISTEN, "in Explorer it can't sense a silent player")
	var el = s.listener
	el.state = el.State.WANDER
	el.path.clear()
	el._hunch_t = 999.0
	s.player.global_position = s.cell_to_world(Vector2i(8, 7))
	el.reset_to(s.cell_to_world(Vector2i(13, 7)))
	el._wait = 99.0
	s.player.look_at_yaw(-PI / 2.0)
	s.player.flashlight.visible = true
	var d_before: float = el.global_position.distance_to(s.player.global_position)
	await wait(4.8)
	check(el.global_position.distance_to(s.player.global_position) > d_before, "in Explorer it always glitches away from you")
	s.queue_free()
	await wait(0.3)

	# --- Touch controls (phones and tablets) ---
	Game.lock_scary_modes()
	Game.touch_mode = 1
	s = load("res://scenes/sector.tscn").instantiate()
	add_child(s)
	await wait(1.0)
	s.listener.set_physics_process(false)
	var tc = null
	for c in s.get_children():
		if c.get_script() == load("res://scripts/touch_controls.gd"):
			tc = c
	check(tc != null, "touch controls appear when on-screen controls are on")
	# Feed touches straight to the controls, in screen coordinates.
	var vp: Vector2 = tc.get_viewport().get_visible_rect().size
	var down := InputEventScreenTouch.new()
	down.index = 0
	down.pressed = true
	down.position = Vector2(vp.x * 0.15, vp.y * 0.7)
	tc._input(down)
	var drag := InputEventScreenDrag.new()
	drag.index = 0
	drag.position = down.position + Vector2(0, -100)
	drag.relative = Vector2(0, -100)
	tc._input(drag)
	await wait(0.1)
	check(Input.get_vector("move_left", "move_right", "move_forward", "move_back").y < -0.5, "the left thumb joystick moves you forward")
	var up := InputEventScreenTouch.new()
	up.index = 0
	up.pressed = false
	up.position = drag.position
	tc._input(up)
	await wait(0.1)
	check(Input.get_vector("move_left", "move_right", "move_forward", "move_back").length() < 0.01, "letting go of the joystick stops you")
	var yaw_before: float = s.player.yaw
	var look_down := InputEventScreenTouch.new()
	look_down.index = 1
	look_down.pressed = true
	look_down.position = Vector2(vp.x * 0.6, vp.y * 0.4)
	tc._input(look_down)
	var look_drag := InputEventScreenDrag.new()
	look_drag.index = 1
	look_drag.position = look_down.position + Vector2(80, 0)
	look_drag.relative = Vector2(80, 0)
	tc._input(look_drag)
	await wait(0.1)
	check(absf(s.player.yaw - yaw_before) > 0.05, "dragging on the right side turns your view")
	tc._buttons["crouch"].pressed.emit()
	check(Input.is_action_pressed("crouch"), "the CROUCH button toggles crouching on")
	tc._buttons["crouch"].pressed.emit()
	check(not Input.is_action_pressed("crouch"), "...and off again")
	Game.touch_mode = 0
	s.queue_free()
	await wait(0.3)

	# --- The elevator: cutscene, carried items, and the Listener's alert ---
	Game.mode = Game.Mode.EXPLORER
	Game.carried = {}
	s = load("res://scenes/sector.tscn").instantiate()
	add_child(s)
	await wait(1.2)
	s.listener.set_physics_process(true)
	s.listener.reset_to(s.cell_to_world(Vector2i(8, 8)))
	s.listener._alert_cool = 0.0
	s.listener.hear(s.listener.global_position + Vector3(4, 0, 0), 12.0, true)
	check(s.listener._alert_t > 0.0 and s.listener._rush_t > 0.0, "running near the Listener makes it rear up, screech and rush the sound")
	s.listener.last_heard = s.cell_to_world(Vector2i(12, 7))
	s.listener._search_left = 2
	s.listener._after_listen()
	check(s.listener.state == s.listener.State.INVESTIGATE and not s.listener.path.is_empty() and s.listener._search_left == 1,
		"when it loses you, it searches the spots around where it last heard you")
	s.listener.set_physics_process(false)
	s.player.inventory.clear()
	s.player.add_item("wrench")
	s.player.add_item("battery")
	s._on_code(s.exit_code)
	await wait(0.3)
	check(s.exit_door.is_open, "the elevator doors slide open")
	s.player.global_position = s.cell_to_world(Vector2i(25, 16))
	await wait(1.0)
	check(s.ended and s.player.body.visible, "stepping in starts the cutscene: you see yourself in the elevator")
	await wait(13.0)
	check(not s.exit_door.is_open, "...the doors close behind you")
	check(s.hud.end_shown, "...then the screen fades to the sector-clear panel")
	check(Game.carried_for(2).size() == 2, "your items are carried to the next sector")
	s.queue_free()
	await wait(0.3)
	s = load("res://scenes/sector_2.tscn").instantiate()
	add_child(s)
	await wait(1.0)
	check(s.player.inventory.size() == 2 and s.player.selected_id() == "wrench", "...and you start Sector 2 with them in your inventory")
	s.queue_free()
	await wait(0.3)

	# --- The menu's switch for the full catch scare (older players) ---
	Game.mode = Game.Mode.EXPLORER
	Game.explorer_scares = false
	Game.players_can_unlock_scares = true
	Game.session_scares = false
	var menu = load("res://scenes/main_menu.tscn").instantiate()
	add_child(menu)
	await wait(0.5)
	check(menu._scares_button.visible and not Game.full_scares(), "Explorer starts with the gentle catch scare, and shows the switch")
	menu._scares_pressed()
	await wait(0.2)
	var rx := RegEx.create_from_string("(\\d+) x (\\d+)")
	var qm := rx.search(menu._pad._title.text)
	var right_answer := str(int(qm.get_string(1)) * int(qm.get_string(2)))
	menu._pad.submitted.emit("1" if right_answer != "1" else "2")
	await wait(0.2)
	check(not Game.full_scares() and menu._pad != null and is_instance_valid(menu._pad), "a wrong answer keeps it gentle (and asks a new question)")
	qm = rx.search(menu._pad._title.text)
	menu._pad.submitted.emit(str(int(qm.get_string(1)) * int(qm.get_string(2))))
	await wait(0.2)
	check(Game.full_scares() and Game.session_scares, "the right times-table answer switches the full catch scare on")
	Game.save_settings()
	var cfg := ConfigFile.new()
	cfg.load(Game.SAVE_PATH)
	check(not cfg.has_section_key("parent", "session_scares"), "...only until the game closes (it isn't saved)")
	menu._scares_pressed()
	check(not Game.full_scares(), "pressing it again switches it straight back off")
	Game.players_can_unlock_scares = false
	menu._refresh_scares()
	check(menu._scares_button.disabled, "a parent can lock the switch")
	Game.players_can_unlock_scares = true
	menu.queue_free()
	await wait(0.3)

	Game.lock_scary_modes()
	print("\n%s (%d failed)" % ["ALL PASSED" if failures == 0 else "SOME TESTS FAILED", failures])
	get_tree().quit(1 if failures > 0 else 0)
