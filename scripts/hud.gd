extends CanvasLayer
## Everything on screen during play: the intercom subtitles, objective, the
## NOISE meter, stamina/battery/breath, the journal, the locker view, the
## "signal lost" screen, pause menu and the end screen.

const PinPad := preload("res://scripts/pin_pad.gd")

const SPEAKERS := {
	"ai": ["MERIDIAN", Color(0.5, 0.85, 1.0)],
	"echo": ["MERIDIAN", Color(0.5, 0.85, 1.0)],
	"unknown": ["???", Color(0.85, 0.5, 1.0)],
	"you": ["YOU", Color(0.85, 0.85, 0.85)],
}

var sector: Node
var _root: Control
var _prompt: Label
var _objective: Label
var _sub_box: PanelContainer
var _sub_name: Label
var _sub_text: Label
var _toast: Label
var _toast_t := 0.0
var _status: Label
var _hotbar: HBoxContainer
var _slots: Array = []   # [Button]
var _mode_label: Label
var _frag_label: Label
var _noise_bar: ProgressBar
var _stamina_bar: ProgressBar
var _battery_bar: ProgressBar
var _breath_box: VBoxContainer
var _breath_bar: ProgressBar
var _breath_hint: Label
var _locker_view: Control
var _note_panel: PanelContainer
var _note_title: Label
var _note_body: Label
var _note_t := 0.0
var _journal: PanelContainer
var _journal_text: Label
var _journal_scroll: ScrollContainer
var _clues: Array[String] = []
var _static: ColorRect
var _caught_label: Label
var _fade: ColorRect
var _pause: Control
var _pad: Control
var _crosshair: Label
var _dread: ColorRect
var _dread_mat: ShaderMaterial
var _dread_amount := 0.0
var _fuzz: ColorRect
var _fuzz_mat: ShaderMaterial
var _fuzz_amount := 0.0
var _glitch_t := 0.0

var _lines: Array = []       # queued intercom lines: [style, text]
var _line_shown := 0.0
var _line_hold := 0.0
var _line_full := ""
var _line_style := ""
var _blip_t := 0.0


func _ready() -> void:
	layer = 5
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = Game.theme
	add_child(_root)

	_dread = ColorRect.new()
	_dread.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dread.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dsh := Shader.new()
	dsh.code = """
shader_type canvas_item;
uniform float amount = 0.0;
void fragment() {
	float d = distance(UV, vec2(0.5));
	float pulse = 0.85 + 0.15 * sin(TIME * 7.0);
	float edge = smoothstep(0.25, 0.75, d) * amount * pulse;
	COLOR = vec4(0.25, 0.0, 0.0, edge * 0.9);
}
"""
	_dread_mat = ShaderMaterial.new()
	_dread_mat.shader = dsh
	_dread.material = _dread_mat
	_root.add_child(_dread)
	_fuzz = ColorRect.new()
	_fuzz.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fuzz.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Not TV static: when the Listener is close or glitches, the picture itself
	# goes wrong - it tears sideways in bands, the colours split apart, the
	# edges close in and everything drains towards a sick red.
	var wsh := Shader.new()
	wsh.code = """
shader_type canvas_item;
uniform float amount = 0.0;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
float rnd(float x) { return fract(sin(x * 91.7) * 43758.5453); }
void fragment() {
	vec2 uv = SCREEN_UV;
	float t = floor(TIME * 16.0);
	float band = floor(uv.y * 11.0 + rnd(t) * 11.0);
	float tear = step(1.0 - amount * 0.55, rnd(band + t * 3.1)) * (rnd(band * 1.7 + t) - 0.5) * 0.14 * amount;
	float wob = sin(uv.y * 7.0 + TIME * 2.3) * 0.005 * amount;
	vec2 o = vec2(tear + wob, 0.0);
	float ca = 0.014 * amount;
	vec3 col = vec3(texture(screen_tex, uv + o + vec2(ca, 0.0)).r,
		texture(screen_tex, uv + o).g,
		texture(screen_tex, uv + o - vec2(ca, ca * 0.5)).b);
	float lum = dot(col, vec3(0.3, 0.59, 0.11));
	col = mix(col, vec3(lum * 1.15, lum * 0.7, lum * 0.65), clamp(amount * 0.6, 0.0, 1.0));
	float vig = smoothstep(0.95, 0.25, distance(uv, vec2(0.5)));
	col *= mix(1.0, vig, clamp(amount * 0.7, 0.0, 1.0));
	COLOR = vec4(col, 1.0);
}
"""
	_fuzz_mat = ShaderMaterial.new()
	_fuzz_mat.shader = wsh
	_fuzz.material = _fuzz_mat
	_fuzz.visible = false
	_root.add_child(_fuzz)
	_locker_view = _make_locker_view()
	_root.add_child(_locker_view)

	_crosshair = _label("+", 22, Color(1, 1, 1, 0.55))
	_crosshair.set_anchors_preset(Control.PRESET_CENTER)
	_crosshair.position -= Vector2(5, 18)
	_root.add_child(_crosshair)
	_prompt = _label("", 20, Color(1, 1, 1))
	_prompt.set_anchors_preset(Control.PRESET_CENTER)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.custom_minimum_size.x = 600
	_prompt.position += Vector2(-300, 30)
	_root.add_child(_prompt)

	_objective = _label("", 19, Game.INK)
	_objective.position = Vector2(24, 20)
	_objective.custom_minimum_size.x = 620
	_objective.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_root.add_child(_objective)

	_mode_label = _label("", 16, Game.mode_data()["color"])
	_mode_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_mode_label.position += Vector2(-260, 20)
	_mode_label.custom_minimum_size.x = 236
	_mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_mode_label.text = Game.mode_name()
	_root.add_child(_mode_label)
	_frag_label = _label("", 16, Color(0.7, 0.6, 1.0))
	_frag_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_frag_label.position += Vector2(-260, 44)
	_frag_label.custom_minimum_size.x = 236
	_frag_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_root.add_child(_frag_label)

	# Meters, bottom left.
	var meters := VBoxContainer.new()
	meters.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	meters.position = Vector2(24, -150)
	meters.add_theme_constant_override("separation", 4)
	_root.add_child(meters)
	_noise_bar = _meter(meters, "NOISE", Color(1.0, 0.45, 0.3))
	_stamina_bar = _meter(meters, "STAMINA", Color(0.5, 0.9, 0.5))
	_battery_bar = _meter(meters, "BATTERY", Color(1.0, 0.9, 0.4))

	# Breath meter (only while hiding).
	_breath_box = VBoxContainer.new()
	_breath_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_breath_box.position += Vector2(-200, -230)
	_breath_box.custom_minimum_size.x = 400
	_breath_box.visible = false
	_root.add_child(_breath_box)
	_breath_hint = _label("Hold SPACE to hold your breath when it comes close.", 16, Game.INK)
	_breath_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_breath_box.add_child(_breath_hint)
	_breath_bar = ProgressBar.new()
	_breath_bar.show_percentage = false
	_breath_bar.custom_minimum_size = Vector2(400, 14)
	_breath_bar.add_theme_stylebox_override("fill", _fill(Color(0.45, 0.75, 1.0)))
	_breath_box.add_child(_breath_bar)

	# Subtitles.
	_sub_box = PanelContainer.new()
	_sub_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_sub_box.custom_minimum_size = Vector2(660, 0)
	_sub_box.position += Vector2(-310, -200)
	_sub_box.visible = false
	_root.add_child(_sub_box)
	var sv := VBoxContainer.new()
	_sub_box.add_child(sv)
	_sub_name = _label("", 16, Color(0.75, 0.68, 0.5))
	sv.add_child(_sub_name)
	_sub_text = _label("", 20, Game.INK)
	_sub_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sub_text.custom_minimum_size.x = 620
	sv.add_child(_sub_text)

	# The inventory hotbar, bottom middle. Keys 1-6, the scroll wheel, or tap a slot.
	_hotbar = HBoxContainer.new()
	_hotbar.add_theme_constant_override("separation", 6)
	_hotbar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hotbar.position += Vector2(-6 * 64 / 2.0 - 15, -78)
	_root.add_child(_hotbar)
	for i in 6:
		var b := Button.new()
		b.custom_minimum_size = Vector2(64, 64)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 13)
		b.pressed.connect(func():
			if sector and sector.player:
				sector.player.select_slot(i))
		_hotbar.add_child(b)
		_slots.append(b)
	set_hotbar([], 0)
	_status = _label("", 24, Color(1.0, 0.3, 0.3))
	_status.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.custom_minimum_size.x = 600
	_status.position += Vector2(-300, 52)
	_root.add_child(_status)
	_toast = _label("", 20, Color(1, 0.85, 0.5))
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.custom_minimum_size.x = 800
	_toast.position += Vector2(-400, 90)
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_root.add_child(_toast)

	# Notes you pick up.
	_note_panel = PanelContainer.new()
	_note_panel.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_note_panel.position += Vector2(-420, -140)
	_note_panel.custom_minimum_size = Vector2(390, 0)
	_note_panel.visible = false
	_root.add_child(_note_panel)
	var nv := VBoxContainer.new()
	_note_panel.add_child(nv)
	_note_title = _label("", 18, Color(1.0, 0.9, 0.6))
	nv.add_child(_note_title)
	_note_body = _label("", 17, Color(0.9, 0.9, 0.85))
	_note_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note_body.custom_minimum_size.x = 350
	nv.add_child(_note_body)

	# Journal (Tab).
	# It scrolls when the list gets long: mouse wheel, arrow keys, or drag on a touch screen.
	_journal = PanelContainer.new()
	_journal.visible = false
	_root.add_child(_journal)
	var jcol := VBoxContainer.new()
	_journal.add_child(jcol)
	_journal_scroll = ScrollContainer.new()
	_journal_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_journal_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	jcol.add_child(_journal_scroll)
	_journal_text = _label("", 18, Game.INK)
	_journal_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_journal_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_journal_scroll.add_child(_journal_text)
	var jhint := _label("Scroll: mouse wheel / arrow keys" + (" / drag" if Game.use_touch() else ""), 13, Game.INK_DIM)
	jhint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	jcol.add_child(jhint)
	get_viewport().size_changed.connect(_layout_journal)
	_layout_journal()

	# Caught: static.
	_static = ColorRect.new()
	_static.set_anchors_preset(Control.PRESET_FULL_RECT)
	_static.material = Game.static_material(0.0)
	_static.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_static.visible = false
	_root.add_child(_static)
	_caught_label = _label("", 48, Game.INK)
	_caught_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_caught_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caught_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_caught_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_caught_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_caught_label.add_theme_constant_override("outline_size", 10)
	_caught_label.visible = false
	_root.add_child(_caught_label)

	_fade = ColorRect.new()
	_fade.color = Color(0, 0, 0, 1)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_fade)
	create_tween().tween_property(_fade, "color:a", 0.0, 2.0)


## Big titles look badly printed: a faint red ghost of the text, out of register.
static func _misprint(l: Label) -> void:
	l.add_theme_color_override("font_shadow_color", Color(0.75, 0.1, 0.06, 0.55))
	l.add_theme_constant_override("shadow_offset_x", 3)
	l.add_theme_constant_override("shadow_offset_y", 1)


func _label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _fill(c: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	return s


func _meter(parent: Control, title: String, color: Color) -> ProgressBar:
	var h := HBoxContainer.new()
	parent.add_child(h)
	var l := _label(title, 14, color)
	l.custom_minimum_size.x = 84
	h.add_child(l)
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(150, 12)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.add_theme_stylebox_override("fill", _fill(color))
	var bg := _fill(Color(0, 0, 0, 0.6))
	bar.add_theme_stylebox_override("background", bg)
	h.add_child(bar)
	return bar


func _make_locker_view() -> Control:
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.visible = false
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
void fragment() {
	float slat = step(0.42, fract(UV.y * 9.0));
	float edge = smoothstep(0.0, 0.25, UV.x) * smoothstep(1.0, 0.75, UV.x);
	COLOR = vec4(0.0, 0.0, 0.0, max(slat * 0.96, 1.0 - edge * 0.9));
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	var r := ColorRect.new()
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.material = m
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(r)
	return c


# ---------------------------------------------------------------- public API

func set_prompt(text: String) -> void:
	_prompt.text = ("[E]  " + text) if text != "" else ""


func set_objective(text: String) -> void:
	_objective.text = "OBJECTIVE:  " + text
	Sound.play("click", -10.0)


func set_fragments(found: int, total: int) -> void:
	_frag_label.text = "SIGNAL FRAGMENTS  %d / %d" % [found, total]


## A line that stays on screen until changed (Sector 5's recording indicator).
func set_status(text: String, color := Color(1.0, 0.3, 0.3)) -> void:
	_status.text = text
	_status.add_theme_color_override("font_color", color)


func toast(text: String, seconds := 3.5) -> void:
	_toast.text = text
	_toast_t = seconds


## Queue an intercom line. style: "ai" (MERIDIAN), "echo" (something pretending
## to be MERIDIAN), "unknown" (something else entirely).
func say(style: String, text: String) -> void:
	if style == "ai" and sector and sector.has_method("meridian_voice"):
		text = sector.meridian_voice(text)
	_lines.append([style, text])


func is_talking() -> bool:
	return _sub_box.visible or not _lines.is_empty()


var _notes_seen: Dictionary = {}


## Show a note, a photo, a terminal, a fragment... once. After that it's
## in your journal, so reading it again just says so (no big panel).
func show_note(title: String, body: String) -> void:
	var key := title + "|" + body
	if _notes_seen.has(key):
		toast("In your journal (TAB)", 1.5)
		return
	_notes_seen[key] = true
	_note_title.text = title
	_note_body.text = body
	_note_panel.visible = true
	_note_t = 7.0


func add_clue(text: String) -> void:
	if text in _clues:
		return
	_clues.append(text)
	_refresh_journal()
	if not _note_panel.visible:
		toast("Journal updated (TAB)", 2.0)


## The journal fits the screen, however big or small the window is.
func _layout_journal() -> void:
	var sz := get_viewport().get_visible_rect().size
	var w := minf(760.0, sz.x - 40.0)
	var h := minf(560.0, sz.y * 0.78)
	_journal.custom_minimum_size = Vector2(w, h)
	_journal.size = Vector2(w, h)
	_journal.position = (sz - Vector2(w, h)) / 2.0


func journal_open() -> bool:
	return _journal.visible


func scroll_journal(pixels: float) -> void:
	_journal_scroll.scroll_vertical = int(_journal_scroll.scroll_vertical + pixels)


## While the journal is open the mouse wheel scrolls it (instead of
## switching the item in your hand).
func _input(event: InputEvent) -> void:
	if not _journal.visible:
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			scroll_journal(-60.0)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			scroll_journal(60.0)
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed:
		if event.keycode == KEY_UP or event.keycode == KEY_PAGEUP:
			scroll_journal(-60.0 if event.keycode == KEY_UP else -400.0)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_DOWN or event.keycode == KEY_PAGEDOWN:
			scroll_journal(60.0 if event.keycode == KEY_DOWN else 400.0)
			get_viewport().set_input_as_handled()


func _refresh_journal() -> void:
	var t := "JOURNAL\n\n"
	if _clues.is_empty():
		t += "Nothing yet. Look around."
	for c in _clues:
		t += "- " + c + "\n"
	_journal_text.text = t


func set_dread(amount: float) -> void:
	_dread_amount = lerpf(_dread_amount, amount, 0.1)
	_dread_mat.set_shader_parameter("amount", _dread_amount)


func set_fuzz(amount: float) -> void:
	_fuzz_amount = lerpf(_fuzz_amount, amount, 0.15)
	var level := _fuzz_amount * 0.35
	if _glitch_t > 0.0:
		_glitch_t -= get_process_delta_time()
		level = maxf(level, 0.9)
	if _jump_t > 0.0:
		_jump_t -= get_process_delta_time()
		level = 1.0
	_fuzz.visible = level > 0.02
	_fuzz_mat.set_shader_parameter("amount", level)


var _jump_t := 0.0


## The jump scare: the picture tears apart and flashes red for a moment.
func jump_flash() -> void:
	_jump_t = 0.35
	_fade.color = Color(0.45, 0.0, 0.0, 0.35)
	var t := create_tween()
	t.tween_property(_fade, "color", Color(0, 0, 0, 0.0), 0.5)


## The picture tears for a moment (the Listener glitching).
func glitch_flash(seconds := 0.25) -> void:
	_glitch_t = seconds


func set_meters(player: Node) -> void:
	_noise_bar.value = clampf(player.noise / 20.0 * 100.0, 0.0, 100.0)
	_stamina_bar.value = player.stamina
	_battery_bar.value = player.battery
	_breath_bar.value = player.breath


func set_hotbar(inventory: Array, selected: int) -> void:
	for i in _slots.size():
		var b: Button = _slots[i]
		var text := "%d\n" % (i + 1)
		if i < inventory.size():
			var id: String = inventory[i]["id"]
			var info: Dictionary = preload("res://scripts/items.gd").info(id)
			text += info.get("short", id)
			if int(inventory[i]["count"]) > 1:
				text += " x%d" % inventory[i]["count"]
		b.text = text
		b.modulate = Color(1.3, 1.3, 0.8) if i == selected else Color(1, 1, 1, 0.75)


func show_locker(on: bool) -> void:
	_locker_view.visible = on
	_breath_box.visible = on
	_crosshair.visible = not on
	if on:
		_breath_hint.text = ("Hold SPACE to hold your breath if it comes to listen."
			if Game.learned_lockers or not Game.is_explorer() else "You're hidden. Stay still until it passes.")


func show_caught(soft: bool, text: String, on_done: Callable) -> void:
	# Cut to black, then the words.
	_static.material = null
	_static.color = Color(0, 0, 0, 0)
	_static.visible = true
	_caught_label.visible = false
	_caught_label.text = text
	_caught_label.add_theme_font_size_override("font_size", 34 if soft else 52)
	_misprint(_caught_label)
	var t := create_tween()
	t.tween_property(_static, "color:a", 1.0, 0.25 if soft else 0.05)
	t.tween_callback(func(): _caught_label.visible = true)
	t.tween_interval(2.2)
	t.tween_callback(on_done)
	t.tween_property(_static, "color:a", 0.0, 0.8)
	t.tween_callback(func():
		_static.visible = false
		_caught_label.visible = false)


func flash_black(seconds: float) -> void:
	_fade.color.a = 1.0
	var t := create_tween()
	t.tween_interval(seconds)
	t.tween_property(_fade, "color:a", 0.0, 0.3)


## Cutscenes: hide everything except the fade-to-black.
var _cinematic := false


func cinematic(on: bool) -> void:
	_cinematic = on
	for c in _root.get_children():
		if c == _fade:
			continue
		if on:
			c.set_meta("was_visible", c.visible)
			c.visible = false
		elif c.has_meta("was_visible"):
			c.visible = c.get_meta("was_visible")


func fade_out(seconds: float, on_done: Callable) -> void:
	var t := create_tween()
	t.tween_property(_fade, "color:a", 1.0, seconds)
	t.tween_callback(on_done)


# --------------------------------------------------------------- keypad

func open_keypad(on_submit: Callable, on_cancel: Callable) -> void:
	close_keypad()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_pad = PinPad.new()
	_root.add_child(_pad)
	_pad.setup("SERVICE ELEVATOR\nEnter the 4-digit exit code.", false)
	_pad.submitted.connect(on_submit)
	_pad.cancelled.connect(on_cancel)


func keypad_message(text: String, color := Color(1, 0.5, 0.45)) -> void:
	if _pad:
		_pad.show_message(text, color)
		_pad.clear_entry()


func close_keypad() -> void:
	if _pad and is_instance_valid(_pad):
		_pad.queue_free()
	_pad = null


func keypad_open() -> bool:
	return _pad != null


# ------------------------------------------------------------ pause / end

func toggle_pause() -> void:
	if _pause:
		_pause.queue_free()
		_pause = null
		sector.set_paused(false)
		return
	sector.set_paused(true)
	_pause = _menu_panel("PAUSED", "Mode: %s\nThe Listener hears everything. Crouch on metal grates." % Game.mode_name(), [
		["RESUME", func(): toggle_pause()],
		["RESTART SECTOR", func():
			get_tree().paused = false
			get_tree().reload_current_scene()],
		["QUIT TO MENU", func():
			get_tree().paused = false
			get_tree().change_scene_to_file("res://scenes/main_menu.tscn")],
	])


var end_shown := false


func show_end(title: String, body: String, next_scene := "") -> void:
	end_shown = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_fade.color.a = 1.0
	var buttons: Array = []
	if next_scene != "":
		buttons.append(["CONTINUE TO THE NEXT SECTOR", func(): get_tree().change_scene_to_file(next_scene)])
	buttons.append(["MAIN MENU", func(): get_tree().change_scene_to_file("res://scenes/main_menu.tscn")])
	_menu_panel(title, body, buttons)


func _menu_panel(title: String, body: String, buttons: Array) -> Control:
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(c)
	var p := PanelContainer.new()
	c.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	p.add_child(v)
	var t := _label(title, 40, Game.INK)
	_misprint(t)
	v.add_child(t)
	var b := _label(body, 18, Game.INK.darkened(0.08))
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.custom_minimum_size.x = 560
	v.add_child(b)
	var first: Button = null
	for entry in buttons:
		var btn := Button.new()
		btn.text = entry[0]
		btn.custom_minimum_size = Vector2(300, 46)
		btn.pressed.connect(entry[1])
		v.add_child(btn)
		if first == null:
			first = btn
	first.grab_focus()
	return c


# ------------------------------------------------------------------ update

func _process(delta: float) -> void:
	if _toast_t > 0.0:
		_toast_t -= delta
		_toast.modulate.a = clampf(_toast_t, 0.0, 1.0)
	if _note_t > 0.0:
		_note_t -= delta
		if _note_t <= 0.0:
			_note_panel.visible = false
	var jopen := Input.is_action_pressed("journal") and _pause == null
	if jopen and not _journal.visible:
		_journal_scroll.scroll_vertical = 0
	_journal.visible = jopen
	if sector and sector.player:
		set_meters(sector.player)
	_update_subtitles(delta)
	if _cinematic:
		_sub_box.visible = false
		_journal.visible = false


func _update_subtitles(delta: float) -> void:
	if _line_full == "":
		if _lines.is_empty():
			_sub_box.visible = false
			return
		var line: Array = _lines.pop_front()
		_line_style = line[0]
		_line_full = line[1]
		_line_shown = 0.0
		_line_hold = 2.4 + _line_full.length() * 0.035
		var who: Array = SPEAKERS.get(_line_style, SPEAKERS["ai"])
		_sub_name.text = who[0]
		var name_color: Color = who[1]
		_sub_text.add_theme_color_override("font_color", Game.INK)
		if _line_style == "echo":
			# ECHO copies MERIDIAN's voice. Explorer gives a hint that it's wrong.
			if Game.mode_data()["echo_hint"]:
				_sub_name.text = "MERIDIAN?"
				name_color = Color(1.0, 0.45, 0.45)
				_sub_text.add_theme_color_override("font_color", Color(1.0, 0.8, 0.8))
			elif Game.mode == Game.Mode.SURVIVOR:
				_sub_name.text = "MERlDIAN"   # one letter is off...
		_sub_name.add_theme_color_override("font_color", name_color)
		_sub_box.visible = true
		Sound.play("chime", -8.0 if _line_style == "ai" else -12.0, 0.92 if _line_style == "echo" else 1.0)
	if _line_shown < _line_full.length():
		_line_shown = minf(_line_shown + delta * 45.0, _line_full.length())
		_blip_t -= delta
		if _blip_t <= 0.0:
			_blip_t = 0.06
			Sound.play("echo_blip" if _line_style != "ai" else "blip", -14.0, randf_range(0.95, 1.05))
	var shown := _line_full.substr(0, int(_line_shown))
	if _line_style == "unknown" and randf() < 0.15 and shown.length() > 2:
		var i := randi() % shown.length()
		shown = shown.substr(0, i) + "#" + shown.substr(i + 1)
	_sub_text.text = shown
	if _line_shown >= _line_full.length():
		_line_hold -= delta
		if _line_hold <= 0.0:
			_line_full = ""


func _unhandled_input(event: InputEvent) -> void:
	if sector == null or sector.ended:
		return
	if event.is_action_pressed("pause"):
		if keypad_open():
			sector.close_keypad()
		else:
			toggle_pause()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and _pause == null and not keypad_open():
		# Clicking back into the game window grabs the mouse again.
		Game.capture_mouse()
