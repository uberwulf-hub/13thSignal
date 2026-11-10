extends CanvasLayer
## On-screen controls for phones and tablets. They press the same actions as
## the keyboard and controller, so the rest of the game doesn't care.
##
##   Left thumb:  a joystick appears wherever you touch the left side. Move.
##   Right thumb: drag anywhere on the right side to look around.
##   Buttons:     USE, LIGHT, RUN (on/off), CROUCH (on/off), and only when
##                they make sense: BREATH (in a locker), TURN/R (Sectors 3+),
##                plus JOURNAL and PAUSE at the top.

const STICK_RADIUS := 110.0
const ALPHA := 0.38

var sector: Node
var _buttons: Dictionary = {}       # id -> TouchScreenButton
var _toggles: Dictionary = {"run": false, "crouch": false}
var _stick_index := -1
var _stick_origin := Vector2.ZERO
var _look_index := -1
var _stick_base: TextureRect
var _stick_knob: TextureRect


func setup(s: Node) -> Node:
	sector = s
	layer = 4
	process_mode = Node.PROCESS_MODE_ALWAYS
	_add("use", "USE", "interact", 170, Color(0.3, 0.85, 1.0))
	_add("light", "LIGHT", "flashlight", 110, Color(1.0, 0.9, 0.4))
	_add("run", "RUN", "", 120, Color(0.4, 1.0, 0.5))
	_add("crouch", "CROUCH", "", 120, Color(0.7, 0.6, 1.0))
	_add("breath", "HOLD\nBREATH", "hold_breath", 170, Color(0.5, 0.8, 1.0))
	_add("turn", "R", "rotate", 110, Color(1.0, 0.6, 0.3))
	_add("journal", "JOURNAL", "journal", 96, Color(0.6, 0.7, 0.8))
	_add("pause", "II", "pause", 86, Color(0.6, 0.6, 0.75))
	_buttons["run"].pressed.connect(func(): _toggle("run", "sprint"))
	_buttons["crouch"].pressed.connect(func(): _toggle("crouch", "crouch"))
	_stick_base = _circle_rect(int(STICK_RADIUS * 2.0), Color(1, 1, 1), 0.15)
	_stick_knob = _circle_rect(90, Color(0.4, 0.8, 1.0), 0.5)
	_stick_base.visible = false
	_stick_knob.visible = false
	add_child(_stick_base)
	add_child(_stick_knob)
	return self


func _ready() -> void:
	get_viewport().size_changed.connect(_layout)
	_layout()


func _layout() -> void:
	var sz := get_viewport().get_visible_rect().size
	var w := sz.x
	var h := sz.y
	# Kept clear of the subtitles (bottom middle) and the mode/fragment text (top right).
	_place("use", Vector2(w - 210, h - 230))
	_place("run", Vector2(w - 380, h - 300))
	_place("crouch", Vector2(w - 200, h - 400))
	_place("light", Vector2(w - 330, h - 560))
	_place("turn", Vector2(w - 470, h - 470))
	_place("breath", Vector2(w - 400, h - 340))
	_place("journal", Vector2(w - 250, 72))
	_place("pause", Vector2(w - 130, 72))


func _place(id: String, pos: Vector2) -> void:
	(_buttons[id] as TouchScreenButton).position = pos


func _toggle(id: String, action: String) -> void:
	_toggles[id] = not _toggles[id]
	if _toggles[id]:
		Input.action_press(action)
	else:
		Input.action_release(action)
	(_buttons[id] as TouchScreenButton).modulate = Color(1.6, 1.6, 1.6) if _toggles[id] else Color.WHITE
	if id == "crouch" and _toggles["crouch"] and _toggles["run"]:
		_toggle("run", "sprint")


func _process(_delta: float) -> void:
	var paused := get_tree().paused
	var busy: bool = paused or (sector.hud and sector.hud.keypad_open()) or sector.ended
	visible = not busy
	if busy:
		_release_stick()
		_look_index = -1
		return
	var hidden: bool = sector.player and sector.player.hidden_in != null
	_buttons["breath"].visible = hidden
	_buttons["run"].visible = not hidden
	_buttons["crouch"].visible = not hidden
	_buttons["turn"].visible = sector.sector_id >= 3 and not hidden
	# You can't keep running once you're out of breath.
	if _toggles["run"] and sector.player and sector.player.stamina <= 0.0:
		_toggle("run", "sprint")


func _on_button(pos: Vector2) -> bool:
	for id in _buttons:
		var b: TouchScreenButton = _buttons[id]
		if not b.visible:
			continue
		var size := (b.texture_normal as Texture2D).get_size()
		if pos.distance_to(b.position + size * 0.5) <= size.x * 0.5:
			return true
	return false


func _input(event: InputEvent) -> void:
	if not visible:
		return
	var w := get_viewport().get_visible_rect().size.x
	if event is InputEventScreenTouch:
		if event.pressed:
			if _on_button(event.position):
				return
			if event.position.x < w * 0.42 and _stick_index == -1:
				_stick_index = event.index
				_stick_origin = event.position
				_stick_base.visible = true
				_stick_knob.visible = true
				_stick_base.position = _stick_origin - _stick_base.size * 0.5
				_stick_knob.position = _stick_origin - _stick_knob.size * 0.5
			elif event.position.x >= w * 0.42 and _look_index == -1:
				_look_index = event.index
		else:
			if event.index == _stick_index:
				_release_stick()
			elif event.index == _look_index:
				_look_index = -1
	elif event is InputEventScreenDrag:
		if event.index == _stick_index:
			var off: Vector2 = event.position - _stick_origin
			if off.length() > STICK_RADIUS:
				off = off.normalized() * STICK_RADIUS
			_stick_knob.position = _stick_origin + off - _stick_knob.size * 0.5
			_set_move(off / STICK_RADIUS)
		elif event.index == _look_index and sector.player:
			sector.player.touch_look(event.relative)


func _set_move(v: Vector2) -> void:
	for pair in [["move_right", v.x], ["move_left", -v.x], ["move_back", v.y], ["move_forward", -v.y]]:
		var amount: float = pair[1]
		if amount > 0.08:
			Input.action_press(pair[0], clampf(amount, 0.0, 1.0))
		else:
			Input.action_release(pair[0])


func _release_stick() -> void:
	_stick_index = -1
	_stick_base.visible = false
	_stick_knob.visible = false
	_set_move(Vector2.ZERO)


func _add(id: String, text: String, action: String, size: int, col: Color) -> void:
	var b := TouchScreenButton.new()
	b.texture_normal = _circle(size, col, ALPHA)
	b.texture_pressed = _circle(size, col.lightened(0.25), 0.8)
	b.action = action
	b.passby_press = false
	b.visibility_mode = TouchScreenButton.VISIBILITY_ALWAYS
	var shape := CircleShape2D.new()
	shape.radius = size * 0.5
	b.shape = shape
	b.shape_centered = true
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", int(size * 0.2) if text.length() > 2 else int(size * 0.38))
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 6)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.size = Vector2(size, size)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(l)
	add_child(b)
	_buttons[id] = b


func _circle_rect(size: int, col: Color, alpha: float) -> TextureRect:
	var t := TextureRect.new()
	t.texture = _circle(size, col, alpha)
	t.size = Vector2(size, size)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return t


## A soft round button picture with a white ring.
static func _circle(size: int, col: Color, alpha: float) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := Vector2(size, size) * 0.5
	var r := size * 0.5 - 1.0
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c)
			if d > r:
				continue
			var edge := clampf(r - d, 0.0, 1.0)
			var px := Color(col.r, col.g, col.b, alpha * edge)
			if d > r - 4.0:
				px = Color(1, 1, 1, 0.7 * edge)
			img.set_pixel(x, y, px)
	return ImageTexture.create_from_image(img)
