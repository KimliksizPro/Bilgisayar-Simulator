extends CanvasLayer
## Mobil dokunmatik kontroller: sol sanal analog joystick, sağ kamera sürükleme alanı ve ergonomik eylem düğmeleri.

signal interact_pressed
signal interact_alt_pressed

const DEADZONE := 0.12
const BASE_JOY_RADIUS := 78.0
const BASE_KNOB_RADIUS := 32.0

var move_vector := Vector2.ZERO

var _enabled := false
var _hud_scale := 1.0
var _joy_finger := -1
var _look_finger := -1
var _look_last_pos := Vector2.ZERO
var _look_delta := Vector2.ZERO

var _root: Control
var _joy_view: _JoystickView
var _btn_e: Button
var _btn_f: Button
var _btn_bench: Button
var _btn_inv: Button
var _btn_menu: Button
var _all_buttons: Array[Button] = []


## Sol alt sanal analog çubuk çizimi.
class _JoystickView extends Control:
	var ring_radius := 78.0
	var knob_radius := 32.0
	var knob_offset := Vector2.ZERO
	var active := false

	func _draw() -> void:
		var c := size * 0.5
		var ring_bg := Color(0.06, 0.08, 0.13, 0.42 if active else 0.28)
		var ring_border := Color(0.95, 0.78, 0.42, 0.78 if active else 0.45)
		draw_circle(c, ring_radius, ring_bg)
		draw_arc(c, ring_radius, 0.0, TAU, 48, ring_border, 2.5, true)
		var knob_pos := c + knob_offset
		var knob_col := Color(0.96, 0.82, 0.48, 0.85 if active else 0.55)
		draw_circle(knob_pos, knob_radius, knob_col)
		draw_arc(knob_pos, knob_radius, 0.0, TAU, 32, Color(1.0, 0.96, 0.85, 0.9), 2.0, true)


func _ready() -> void:
	layer = 4
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	_refresh_settings()
	if Settings.has_signal("changed"):
		Settings.changed.connect(_on_setting_changed)
	get_viewport().size_changed.connect(_layout)


func is_touch_active() -> bool:
	return _enabled


## Biriken dokunmatik kamera deltasını döndürür ve sıfırlar.
func consume_look_delta() -> Vector2:
	var d := _look_delta
	_look_delta = Vector2.ZERO
	return d


func _should_enable() -> bool:
	var mode = Settings.get("touch_controls")
	if mode is String:
		if mode == "on":
			return true
		if mode == "off":
			return false
	return OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")


func _get_hud_scale() -> float:
	var s = Settings.get("hud_scale")
	if s is float or s is int:
		return clampf(float(s), 0.7, 1.6)
	return 1.0


func _on_setting_changed(key: String) -> void:
	if key == "touch_controls" or key == "hud_scale":
		_refresh_settings()


func _refresh_settings() -> void:
	_enabled = _should_enable()
	_hud_scale = _get_hud_scale()
	if not _enabled:
		_reset_touch_state()
	_layout()
	_sync_visibility()


func _build_ui() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_joy_view = _JoystickView.new()
	_joy_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_joy_view)

	_btn_e = _make_button("E\nEtkileşim", true, func(): interact_pressed.emit())
	_btn_f = _make_button("F\nBırak / Reddet", false, func(): interact_alt_pressed.emit())
	_btn_bench = _make_button("Tezgâh", false, _on_bench_pressed)
	_btn_inv = _make_button("Envanter", false, func(): _dispatch_key(KEY_I))
	_btn_menu = _make_button("Menü", false, func(): _dispatch_key(KEY_ESCAPE))

	_all_buttons = [_btn_e, _btn_f, _btn_bench, _btn_inv, _btn_menu]


func _make_button(text: String, primary: bool, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	b.pressed.connect(cb)
	_style_button(b, primary)
	_root.add_child(b)
	return b


func _style_button(b: Button, primary: bool) -> void:
	var radius := 48 if primary else 18
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.86, 0.56, 0.16, 0.78) if primary else Color(0.08, 0.11, 0.18, 0.68)
	normal.border_color = Color(1.0, 0.88, 0.62, 0.92) if primary else Color(0.75, 0.82, 0.92, 0.52)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(radius)
	var pressed := normal.duplicate()
	pressed.bg_color = Color(0.98, 0.68, 0.24, 0.92) if primary else Color(0.18, 0.24, 0.36, 0.85)
	var hover := normal.duplicate()
	hover.bg_color = normal.bg_color.lightened(0.08)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_color_override("font_color", Color(0.98, 0.98, 0.98))
	b.add_theme_color_override("font_pressed_color", Color(1.0, 1.0, 1.0))


func _layout() -> void:
	if _root == null:
		return
	var vp := get_viewport().get_visible_rect().size
	if vp.x <= 1.0 or vp.y <= 1.0:
		return
	var s := _hud_scale
	var pad := 28.0 * s

	# Sol alt joystick
	var joy_r := BASE_JOY_RADIUS * s
	var knob_r := BASE_KNOB_RADIUS * s
	var joy_box := (joy_r + knob_r) * 2.0
	_joy_view.ring_radius = joy_r
	_joy_view.knob_radius = knob_r
	_joy_view.size = Vector2(joy_box, joy_box)
	_joy_view.position = Vector2(pad + 12.0 * s, vp.y - pad - joy_box)
	_joy_view.queue_redraw()

	# Sağ alt ana etkileşim (E) ve ikincil (F) düğmeleri
	var e_sz := Vector2(116.0, 116.0) * s
	var f_sz := Vector2(118.0, 62.0) * s
	_btn_e.size = e_sz
	_btn_e.position = Vector2(vp.x - pad - e_sz.x, vp.y - pad - e_sz.y)
	_btn_e.add_theme_font_size_override("font_size", int(round(18.0 * s)))

	_btn_f.size = f_sz
	_btn_f.position = Vector2(_btn_e.position.x - 16.0 * s - f_sz.x, vp.y - pad - f_sz.y - 8.0 * s)
	_btn_f.add_theme_font_size_override("font_size", int(round(15.0 * s)))

	# Sağ üst kısayol düğmeleri (Menü, Envanter, Tezgâh)
	var top_h := 48.0 * s
	var gap := 10.0 * s
	var menu_w := 88.0 * s
	var inv_w := 108.0 * s
	var bench_w := 102.0 * s
	var top_y := 18.0 * s

	_btn_menu.size = Vector2(menu_w, top_h)
	_btn_menu.position = Vector2(vp.x - pad - menu_w, top_y)
	_btn_menu.add_theme_font_size_override("font_size", int(round(16.0 * s)))

	_btn_inv.size = Vector2(inv_w, top_h)
	_btn_inv.position = Vector2(_btn_menu.position.x - gap - inv_w, top_y)
	_btn_inv.add_theme_font_size_override("font_size", int(round(16.0 * s)))

	_btn_bench.size = Vector2(bench_w, top_h)
	_btn_bench.position = Vector2(_btn_inv.position.x - gap - bench_w, top_y)
	_btn_bench.add_theme_font_size_override("font_size", int(round(16.0 * s)))


func _process(_delta: float) -> void:
	_sync_visibility()


func _sync_visibility() -> void:
	var show_any := _enabled and Game.started and not Game.paused and not Game.ui_modal
	visible = show_any
	if not show_any:
		_reset_touch_state()
		return
	var in_bench := Game.bench_active
	_joy_view.visible = not in_bench
	_btn_e.visible = not in_bench
	_btn_f.visible = not in_bench
	_btn_inv.visible = not in_bench
	_btn_bench.visible = true
	_btn_menu.visible = true
	if in_bench:
		_reset_touch_state()


func _reset_touch_state() -> void:
	if _joy_finger != -1 or move_vector != Vector2.ZERO:
		_joy_finger = -1
		move_vector = Vector2.ZERO
		if _joy_view:
			_joy_view.active = false
			_joy_view.knob_offset = Vector2.ZERO
			_joy_view.queue_redraw()
	_look_finger = -1
	_look_delta = Vector2.ZERO


func _hits_any_button(pos: Vector2) -> bool:
	for b in _all_buttons:
		if b.visible and b.get_global_rect().has_point(pos):
			return true
	return false


func _input(event: InputEvent) -> void:
	if not visible or Game.bench_active or Game.ui_modal or Game.paused or not Game.started:
		return
	var vp := get_viewport().get_visible_rect().size
	if event is InputEventScreenTouch:
		var idx: int = event.index
		var pos: Vector2 = event.position
		if event.pressed:
			if _hits_any_button(pos):
				return
			# Sol taraf: sanal joystick parmağı
			if _joy_finger == -1 and pos.x < vp.x * 0.42 and pos.y > vp.y * 0.35:
				_joy_finger = idx
				_joy_view.active = true
				_update_joystick(pos)
				get_viewport().set_input_as_handled()
			# Sağ taraf: kamera bakış parmağı
			elif _look_finger == -1 and idx != _joy_finger and pos.x >= vp.x * 0.38:
				_look_finger = idx
				_look_last_pos = pos
				get_viewport().set_input_as_handled()
		else:
			if idx == _joy_finger:
				_joy_finger = -1
				move_vector = Vector2.ZERO
				_joy_view.active = false
				_joy_view.knob_offset = Vector2.ZERO
				_joy_view.queue_redraw()
				get_viewport().set_input_as_handled()
			elif idx == _look_finger:
				_look_finger = -1
				get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		var idx: int = event.index
		if idx == _joy_finger:
			_update_joystick(event.position)
			get_viewport().set_input_as_handled()
		elif idx == _look_finger:
			var rel: Vector2 = event.relative if event.relative != Vector2.ZERO else (event.position - _look_last_pos)
			_look_last_pos = event.position
			_look_delta += rel
			get_viewport().set_input_as_handled()


func _update_joystick(pos: Vector2) -> void:
	var center := _joy_view.position + _joy_view.size * 0.5
	var offset := pos - center
	var r := _joy_view.ring_radius
	if offset.length() > r:
		offset = offset.normalized() * r
	_joy_view.knob_offset = offset
	_joy_view.queue_redraw()
	var norm := offset / maxf(r, 1.0)
	if norm.length() < DEADZONE:
		move_vector = Vector2.ZERO
	else:
		move_vector = norm


func _on_bench_pressed() -> void:
	var scene := get_tree().current_scene
	var bench = scene.get_node_or_null("BenchMode") if scene else null
	if bench != null:
		if bench.state == "off":
			if not Game.ui_modal and Game.bench_device != null and not Game.is_carrying():
				bench.enter()
			return
		elif bench.state == "on":
			bench.exit()
			return
	_dispatch_key(KEY_TAB)


func _dispatch_key(keycode: Key) -> void:
	var down := InputEventKey.new()
	down.keycode = keycode
	down.physical_keycode = keycode
	down.pressed = true
	Input.parse_input_event(down)
	var up := InputEventKey.new()
	up.keycode = keycode
	up.physical_keycode = keycode
	up.pressed = false
	Input.parse_input_event(up)
