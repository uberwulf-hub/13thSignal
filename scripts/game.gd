extends Node
## Global state (autoloaded as `Game`): the play mode and the Parent Lock,
## settings, and what the monster has learned about the player this run.
##
## SAFEGUARD: every time the game starts it is in EXPLORER mode (no jump
## scares, gentle monsters). SURVIVOR and NIGHTMARE need the Parent PIN,
## once per launch. A parent creates the PIN in Parent Settings.

const SAVE_PATH := "user://the_13th_signal.cfg"
const PIN_SALT := "13th-signal/parent-lock/"

enum Mode { EXPLORER, SURVIVOR, NIGHTMARE }

## Every sector, in order: [title shown in the menu, scene].
const SECTORS := [
	["SECTOR 1: INTAKE", "res://scenes/sector.tscn"],
	["SECTOR 2: ARCHIVES", "res://scenes/sector_2.tscn"],
	["SECTOR 3: RELAY STATION", "res://scenes/sector_3.tscn"],
	["SECTOR 4: SECURITY WING", "res://scenes/sector_4.tscn"],
	["SECTOR 5: PLAYBACK LAB", "res://scenes/sector_5.tscn"],
	["SECTOR 6: SHOWROOM", "res://scenes/sector_6.tscn"],
]

## Everything that changes between the three modes lives here.
const MODES := [
	{
		"name": "EXPLORER",
		"blurb": "No jump scares. Slower, gentler monsters that never learn to check lockers. Puzzle-focused.",
		"color": Color(0.45, 0.85, 1.0),
		"listener_speed": 0.75, "hearing": 0.6,
		"learn_hide": 0, "learn_sprint": 45.0,
		"replacement_hunts": false, "scares": false, "scare_gap": Vector2(70, 120),
		"battery_drain": 0.6, "breath_drain": 10.0, "ambient": 0.12, "wrong_code_alarm": false,
		"echo_hint": true,
		"echo_delay": 40.0, "echo_speed": 1.7, "echo_catches": false,
		"learn_crouch": 0.0, "hunch_gap": Vector2(110, 160), "hunch_radius": 12.0,
		"sense": 0.0, "lunge": false, "predict": 0.0, "door_noise": 13.0,
		"stare_glitch": 4.0, "glitch_bias": -1,
	},
	{
		"name": "SURVIVOR",
		"blurb": "Jump scares, suspense and hiding. The monsters learn your habits.",
		"color": Color(1.0, 0.75, 0.3),
		"listener_speed": 1.0, "hearing": 1.0,
		"learn_hide": 3, "learn_sprint": 25.0,
		"replacement_hunts": true, "scares": true, "scare_gap": Vector2(55, 100),
		"battery_drain": 1.2, "breath_drain": 16.0, "ambient": 0.08, "wrong_code_alarm": false,
		"echo_hint": false,
		"echo_delay": 22.0, "echo_speed": 2.3, "echo_catches": true,
		"learn_crouch": 50.0, "hunch_gap": Vector2(40, 70), "hunch_radius": 9.0,
		"sense": 3.5, "lunge": true, "predict": 0.8, "door_noise": 16.0,
		"stare_glitch": 2.5, "glitch_bias": 0,
	},
	{
		"name": "NIGHTMARE",
		"blurb": "Unpredictable encounters, faster learning, darker halls, intense audio. Mistakes make noise.",
		"color": Color(1.0, 0.25, 0.25),
		"listener_speed": 1.2, "hearing": 1.35,
		"learn_hide": 2, "learn_sprint": 14.0,
		"replacement_hunts": true, "scares": true, "scare_gap": Vector2(30, 65),
		"battery_drain": 2.0, "breath_drain": 22.0, "ambient": 0.05, "wrong_code_alarm": true,
		"echo_hint": false,
		"echo_delay": 12.0, "echo_speed": 2.8, "echo_catches": true,
		"learn_crouch": 25.0, "hunch_gap": Vector2(20, 40), "hunch_radius": 6.0,
		"sense": 5.0, "lunge": true, "predict": 1.2, "door_noise": 20.0,
		"stare_glitch": 1.5, "glitch_bias": 1,
	},
]

# --- Settings (saved) ---
var mouse_sensitivity := 0.25
var volume := 0.8
var brightness := 1.0
var invert_y := false
var touch_mode := 0                  # on-screen controls: 0 auto (phones/tablets), 1 on, 2 off
var fullscreen := true               # no title bar; F11 or Alt+Enter switches
var quality := -1                    # graphics: 0 low, 1 medium, 2 high (-1 = pick for this device)
var best_times: Dictionary = {}      # mode name -> seconds
var fragments_ever: Dictionary = {}  # fragment id -> true
var sector_unlocked := 1             # the highest sector you can start from

# --- Parent Lock (saved as a salted hash, never the PIN itself) ---
var _pin_hash := ""

# --- This launch only ---
var mode: int = Mode.EXPLORER        # always starts in Explorer
var scary_unlocked := false          # the Parent PIN was entered this launch

# --- This run: what the monster has learned about you ---
var hide_count := 0
var sprint_time := 0.0
var sprint_cells: Dictionary = {}    # Vector2i -> seconds sprinted in that cell
var learned_lockers := false
var learned_traps := false
var crouch_time := 0.0
var learned_crouch := false

var theme: Theme


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_setup_input()
	load_settings()
	theme = _make_theme()
	apply_display()


const TOUCH_NAMES := ["AUTO", "ON", "OFF"]
const QUALITY_NAMES := ["LOW", "MEDIUM", "HIGH"]


## Running on a phone or tablet?
func is_mobile() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")


## Show the on-screen controls? (Auto = on phones, tablets and touch screens.)
func use_touch() -> bool:
	if touch_mode == 1:
		return true
	if touch_mode == 2:
		return false
	return is_mobile() or DisplayServer.is_touchscreen_available()


var _tex_mats: Dictionary = {}


## A realistic surface from assets/textures/<surface>/ (colour, bumps and
## roughness, from Poly Haven, CC0). Wraps around any shape without stretching.
## Returns null if the textures aren't there, so callers can fall back.
func tex_mat(surface: String, scale := 0.25, tint := Color.WHITE, metal := 0.0) -> StandardMaterial3D:
	var key := "%s/%s/%s/%s" % [surface, scale, tint, metal]
	if _tex_mats.has(key):
		return _tex_mats[key]
	var base := "res://assets/textures/%s/" % surface
	if not ResourceLoader.exists(base + "albedo.jpg"):
		return null
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(base + "albedo.jpg")
	m.albedo_color = tint
	m.normal_enabled = true
	m.normal_texture = load(base + "normal.jpg")
	m.roughness_texture = load(base + "rough.jpg")
	m.roughness = 1.0
	m.metallic = metal
	m.uv1_triplanar = true
	m.uv1_scale = Vector3.ONE * scale
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_tex_mats[key] = m
	return m


## Hide and lock the mouse for looking around (not on touch screens, where you look by dragging).
func capture_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if use_touch() else Input.MOUSE_MODE_CAPTURED


## Graphics quality: phones start on LOW, computers on HIGH, until you change it.
func gfx() -> int:
	if quality >= 0:
		return quality
	return 0 if is_mobile() else 2


## Fullscreen (no title bar) or a normal window. Not on phones.
func apply_display() -> void:
	if is_mobile() or DisplayServer.get_name() == "headless":
		return
	if "--windowed" in OS.get_cmdline_user_args():
		return   # launched with "-- --windowed" (e.g. for testing): leave the window alone
	if fullscreen:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		return
	# A normal window with a title bar: 80% of the screen, 16:9, centred.
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	var screen := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	var w := int(screen.size.x * 0.8)
	var h := int(w * 9.0 / 16.0)
	if h > screen.size.y * 0.85:
		h = int(screen.size.y * 0.85)
		w = int(h * 16.0 / 9.0)
	DisplayServer.window_set_size(Vector2i(w, h))
	DisplayServer.window_set_position(screen.position + (screen.size - Vector2i(w, h)) / 2)


func set_fullscreen(on: bool) -> void:
	fullscreen = on
	apply_display()
	save_settings()


func _input(event: InputEvent) -> void:
	# F11, or Alt+Enter, switches between fullscreen and a window anywhere in the game.
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F11 or (event.keycode == KEY_ENTER and event.alt_pressed):
			set_fullscreen(not fullscreen)
			get_viewport().set_input_as_handled()


func mode_data() -> Dictionary:
	return MODES[mode]


func mode_name() -> String:
	return MODES[mode]["name"]


func is_explorer() -> bool:
	return mode == Mode.EXPLORER


func reset_run() -> void:
	hide_count = 0
	sprint_time = 0.0
	sprint_cells = {}
	learned_lockers = false
	learned_traps = false
	crouch_time = 0.0
	learned_crouch = false


# ---------------------------------------------------------------- Parent Lock

func has_pin() -> bool:
	return _pin_hash != ""


func check_pin(pin: String) -> bool:
	return has_pin() and (PIN_SALT + pin).sha256_text() == _pin_hash


func set_pin(pin: String) -> void:
	_pin_hash = (PIN_SALT + pin).sha256_text()
	save_settings()


func remove_pin() -> void:
	_pin_hash = ""
	scary_unlocked = false
	mode = Mode.EXPLORER
	save_settings()


## A mode is allowed if it's Explorer, or a parent has unlocked this launch.
func mode_allowed(m: int) -> bool:
	return m == Mode.EXPLORER or scary_unlocked


func lock_scary_modes() -> void:
	scary_unlocked = false
	mode = Mode.EXPLORER


# ------------------------------------------------------------------ Settings

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	mouse_sensitivity = cfg.get_value("settings", "mouse_sensitivity", mouse_sensitivity)
	volume = cfg.get_value("settings", "volume", volume)
	brightness = cfg.get_value("settings", "brightness", brightness)
	invert_y = cfg.get_value("settings", "invert_y", invert_y)
	touch_mode = clampi(int(cfg.get_value("settings", "touch", 0)), 0, 2)
	quality = clampi(int(cfg.get_value("settings", "quality", -1)), -1, 2)
	fullscreen = cfg.get_value("settings", "fullscreen", true)
	best_times = cfg.get_value("progress", "best_times", {})
	fragments_ever = cfg.get_value("progress", "fragments", {})
	sector_unlocked = cfg.get_value("progress", "sector_unlocked", 1)
	_pin_hash = cfg.get_value("parent", "pin_hash", "")
	apply_volume()


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("settings", "mouse_sensitivity", mouse_sensitivity)
	cfg.set_value("settings", "volume", volume)
	cfg.set_value("settings", "brightness", brightness)
	cfg.set_value("settings", "invert_y", invert_y)
	cfg.set_value("settings", "touch", touch_mode)
	cfg.set_value("settings", "quality", quality)
	cfg.set_value("settings", "fullscreen", fullscreen)
	cfg.set_value("progress", "best_times", best_times)
	cfg.set_value("progress", "fragments", fragments_ever)
	cfg.set_value("progress", "sector_unlocked", sector_unlocked)
	cfg.set_value("parent", "pin_hash", _pin_hash)
	cfg.save(SAVE_PATH)


func apply_volume() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.0001)))


# --------------------------------------------------------------------- Input

func _setup_input() -> void:
	var keys := {
		"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"sprint": [KEY_SHIFT], "crouch": [KEY_CTRL, KEY_C],
		"interact": [KEY_E], "flashlight": [KEY_F], "hold_breath": [KEY_SPACE],
		"journal": [KEY_TAB, KEY_J], "pause": [KEY_ESCAPE, KEY_P],
		"rotate": [KEY_R], "drop_item": [KEY_G],
		"slot_1": [KEY_1], "slot_2": [KEY_2], "slot_3": [KEY_3],
		"slot_4": [KEY_4], "slot_5": [KEY_5], "slot_6": [KEY_6],
	}
	var pad_buttons := {
		"interact": JOY_BUTTON_A, "crouch": JOY_BUTTON_B, "flashlight": JOY_BUTTON_Y,
		"journal": JOY_BUTTON_BACK, "pause": JOY_BUTTON_START, "sprint": JOY_BUTTON_LEFT_STICK,
		"hold_breath": JOY_BUTTON_X, "rotate": JOY_BUTTON_RIGHT_SHOULDER,
		"item_next": JOY_BUTTON_DPAD_RIGHT, "item_prev": JOY_BUTTON_DPAD_LEFT, "drop_item": JOY_BUTTON_DPAD_DOWN,
	}
	var pad_axes := {
		"move_left": [JOY_AXIS_LEFT_X, -1.0], "move_right": [JOY_AXIS_LEFT_X, 1.0],
		"move_forward": [JOY_AXIS_LEFT_Y, -1.0], "move_back": [JOY_AXIS_LEFT_Y, 1.0],
		"look_left": [JOY_AXIS_RIGHT_X, -1.0], "look_right": [JOY_AXIS_RIGHT_X, 1.0],
		"look_up": [JOY_AXIS_RIGHT_Y, -1.0], "look_down": [JOY_AXIS_RIGHT_Y, 1.0],
	}
	for action in ["move_forward", "move_back", "move_left", "move_right", "sprint", "crouch",
			"interact", "flashlight", "hold_breath", "journal", "pause", "rotate",
			"use_item", "drop_item", "item_next", "item_prev",
			"slot_1", "slot_2", "slot_3", "slot_4", "slot_5", "slot_6",
			"look_left", "look_right", "look_up", "look_down"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action, 0.2)
		for k in keys.get(action, []):
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)
		if pad_buttons.has(action):
			var jb := InputEventJoypadButton.new()
			jb.button_index = pad_buttons[action]
			InputMap.action_add_event(action, jb)
		if pad_axes.has(action):
			var ja := InputEventJoypadMotion.new()
			ja.axis = pad_axes[action][0]
			ja.axis_value = pad_axes[action][1]
			InputMap.action_add_event(action, ja)
	# Items: left mouse button (or the right trigger) uses/throws, the scroll
	# wheel picks the next or previous item.
	var lmb := InputEventMouseButton.new()
	lmb.button_index = MOUSE_BUTTON_LEFT
	InputMap.action_add_event("use_item", lmb)
	var rt := InputEventJoypadMotion.new()
	rt.axis = JOY_AXIS_TRIGGER_RIGHT
	rt.axis_value = 1.0
	InputMap.action_add_event("use_item", rt)
	for pair in [["item_next", MOUSE_BUTTON_WHEEL_DOWN], ["item_prev", MOUSE_BUTTON_WHEEL_UP]]:
		var wheel := InputEventMouseButton.new()
		wheel.button_index = pair[1]
		InputMap.action_add_event(pair[0], wheel)
	# The left trigger also sprints.
	var lt := InputEventJoypadMotion.new()
	lt.axis = JOY_AXIS_TRIGGER_LEFT
	lt.axis_value = 1.0
	InputMap.action_add_event("sprint", lt)


# --------------------------------------------------------------------- Theme

func _make_theme() -> Theme:
	var t := Theme.new()
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Consolas", "DejaVu Sans Mono", "Liberation Mono", "Courier New", "monospace"])
	t.default_font = font
	t.default_font_size = 20
	var normal := _box(Color(0.04, 0.07, 0.1, 0.92), Color(0.2, 0.45, 0.6))
	var hover := _box(Color(0.07, 0.14, 0.2, 0.95), Color(0.45, 0.85, 1.0))
	var pressed := _box(Color(0.1, 0.2, 0.28, 1.0), Color(0.7, 0.95, 1.0))
	var disabled := _box(Color(0.03, 0.04, 0.05, 0.9), Color(0.15, 0.18, 0.2))
	for s in ["normal", "hover", "pressed", "disabled", "focus"]:
		var box: StyleBoxFlat = normal
		match s:
			"hover", "focus": box = hover
			"pressed": box = pressed
			"disabled": box = disabled
		t.set_stylebox(s, "Button", box)
	t.set_color("font_color", "Button", Color(0.8, 0.92, 1.0))
	t.set_color("font_hover_color", "Button", Color(1, 1, 1))
	t.set_color("font_focus_color", "Button", Color(1, 1, 1))
	t.set_color("font_disabled_color", "Button", Color(0.4, 0.45, 0.5))
	t.set_stylebox("panel", "PanelContainer", _box(Color(0.02, 0.035, 0.05, 0.94), Color(0.2, 0.45, 0.6), 18))
	t.set_color("font_color", "Label", Color(0.82, 0.92, 1.0))
	return t


func _box(bg: Color, border: Color, margin := 12) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = bg
	b.border_color = border
	b.set_border_width_all(2)
	b.set_corner_radius_all(4)
	b.content_margin_left = margin + 6
	b.content_margin_right = margin + 6
	b.content_margin_top = margin
	b.content_margin_bottom = margin
	return b


## A full-screen static/noise shader, used on the menu and when you're caught.
func static_material(amount: float) -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
uniform float amount = 1.0;
float rnd(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
void fragment() {
	vec2 px = floor(UV * vec2(320.0, 180.0));
	float n = rnd(px + vec2(floor(TIME * 30.0) * 7.31, floor(TIME * 30.0) * 3.17));
	float lines = 0.8 + 0.2 * sin(UV.y * 600.0 + TIME * 12.0);
	COLOR = vec4(vec3(n * lines) * vec3(0.8, 0.9, 1.0), amount);
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("amount", amount)
	return m
