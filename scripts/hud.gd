extends CanvasLayer
## Ekran arayüzü: para, aktif iş, nişangah, ipucu, bildirimler, başlangıç/duraklatma ekranı.

var money_label: Label
var job_title: Label
var job_desc: Label
var hint_label: Label
var crosshair: Label
var messages: VBoxContainer
var overlay: ColorRect
var overlay_title: Label
var overlay_sub: Label
var _started := false
var fps_label: Label


func _ready() -> void:
	Game.hud = self
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var money_panel := _panel(root)
	money_panel.position = Vector2(20, 20)
	money_label = _label(money_panel, "", 28, Color(0.6, 1.0, 0.6))

	var job_panel := _panel(root)
	job_panel.anchor_left = 1.0
	job_panel.anchor_right = 1.0
	job_panel.offset_left = -440
	job_panel.offset_right = -20
	job_panel.offset_top = 20
	job_panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	var vb := VBoxContainer.new()
	job_panel.add_child(vb)
	job_title = _label(vb, "", 22, Color(1.0, 0.85, 0.4))
	job_desc = _label(vb, "", 17)
	job_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	job_desc.custom_minimum_size = Vector2(390, 0)

	crosshair = Label.new()
	crosshair.text = "•"
	crosshair.add_theme_font_size_override("font_size", 22)
	crosshair.set_anchors_preset(Control.PRESET_CENTER)
	crosshair.position = Vector2(-5, -16)
	root.add_child(crosshair)

	hint_label = Label.new()
	hint_label.set_anchors_preset(Control.PRESET_CENTER)
	hint_label.position = Vector2(-300, 26)
	hint_label.size = Vector2(600, 40)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.add_theme_font_size_override("font_size", 20)
	hint_label.add_theme_constant_override("outline_size", 6)
	hint_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	root.add_child(hint_label)

	messages = VBoxContainer.new()
	messages.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	messages.position = Vector2(-400, -190)
	messages.size = Vector2(800, 150)
	messages.alignment = BoxContainer.ALIGNMENT_END
	messages.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(messages)

	var help := _label(root, "WASD: Yürü   Shift: Koş   E / Sol Tık: Etkileşim   G / Sağ Tık: Bırak   Esc: Duraklat   F2: Grafik kalitesi   F3: FPS", 15, Color(1, 1, 1, 0.55))
	help.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	help.position = Vector2(20, -34)

	overlay = ColorRect.new()
	overlay.color = Color(0.02, 0.03, 0.06, 0.82)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(overlay)
	var ov := VBoxContainer.new()
	ov.set_anchors_preset(Control.PRESET_CENTER)
	ov.position = Vector2(-400, -150)
	ov.size = Vector2(800, 300)
	ov.alignment = BoxContainer.ALIGNMENT_CENTER
	ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(ov)
	overlay_title = _label(ov, "BİLGİSAYARCI SİMÜLATÖR", 56, Color(1.0, 0.85, 0.4))
	overlay_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay_sub = _label(ov, "Mahallenin bilgisayarcısı sensin. Müşterilerin derdini dinle,\narızayı bul, parçayı değiştir, parayı kap!\n\nBaşlamak için tıkla", 22)
	var sub := overlay_sub
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	fps_label = _label(root, "", 16, Color(0.7, 1.0, 0.7))
	fps_label.position = Vector2(20, 84)
	fps_label.visible = false

	Game.money_changed.connect(_on_money)
	_on_money(Game.money)


func _panel(parent: Control) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.06, 0.09, 0.72)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(14)
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(p)
	return p


func _label(parent: Control, text: String, size: int, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	parent.add_child(l)
	return l


func _on_money(v: int) -> void:
	money_label.text = "₺ %d" % v


func set_job(title: String, desc: String) -> void:
	job_title.text = title
	job_desc.text = desc
	job_desc.visible = desc != ""


func show_message(text: String, color := Color.WHITE) -> void:
	var l := _label(messages, text, 22, color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	while messages.get_child_count() > 4:
		messages.get_child(0).free()
	var tw := l.create_tween()
	tw.tween_interval(4.0)
	tw.tween_property(l, "modulate:a", 0.0, 0.8)
	tw.tween_callback(l.queue_free)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F3:
		fps_label.visible = not fps_label.visible


func _process(_delta: float) -> void:
	if fps_label.visible:
		fps_label.text = "FPS: %d   Draw call: %d" % [Engine.get_frames_per_second(),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)]
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if captured:
		_started = true
	overlay.visible = not captured
	if _started and not captured:
		overlay_title.text = "DURAKLATILDI"
		overlay_sub.text = "Devam etmek için tıkla"
	var p = Game.player
	hint_label.text = p.hint if p and captured else ""
	crosshair.modulate = Color(1, 0.85, 0.3) if hint_label.text != "" else Color(1, 1, 1, 0.7)
