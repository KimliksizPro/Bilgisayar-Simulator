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
var fps_label: Label
var day_label: Label
var rep_label: Label
var patience_bar: ProgressBar
var btn_resume: Button
var btn_continue: Button
var btn_new: Button
var summary_root: Control
var summary_title: Label
var summary_grid: GridContainer
var summary_note: Label
var over_root: Control
var over_text: Label
var upgrade_root: Control
var upgrade_money: Label
var upgrade_rows := {}
var _clock_cache := ""
var _ui_root: Control


func _ready() -> void:
	Game.hud = self
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var money_panel := _panel(root)
	money_panel.position = Vector2(20, 20)
	var mv := VBoxContainer.new()
	money_panel.add_child(mv)
	money_label = _label(mv, "", 28, Color(0.6, 1.0, 0.6))
	day_label = _label(mv, "", 20, Color(0.85, 0.9, 1.0))
	rep_label = _label(mv, "", 22, Color(1.0, 0.82, 0.25))
	_ui_root = root

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
	patience_bar = ProgressBar.new()
	patience_bar.max_value = 1.0
	patience_bar.show_percentage = false
	patience_bar.custom_minimum_size = Vector2(390, 10)
	patience_bar.visible = false
	patience_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.5)
	patience_bar.add_theme_stylebox_override("background", bg)
	vb.add_child(patience_bar)

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
	overlay_sub = _label(ov, "Mahallenin bilgisayarcısı sensin. Müşterilerin derdini dinle,\narızayı bul, parçayı değiştir, parayı kap!", 22)
	var sub := overlay_sub
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var bb := HBoxContainer.new()
	bb.alignment = BoxContainer.ALIGNMENT_CENTER
	bb.add_theme_constant_override("separation", 20)
	ov.add_child(bb)
	btn_resume = _button(bb, "Devam Et", _capture)
	btn_continue = _button(bb, "Devam Et (Kayıtlı Oyun)", _on_continue)
	btn_new = _button(bb, "Yeni Oyun", _on_new)

	fps_label = _label(root, "", 16, Color(0.7, 1.0, 0.7))
	fps_label.position = Vector2(20, 150)
	fps_label.visible = false

	_build_summary(root)
	_build_over(root)
	_build_upgrades(root)

	Game.money_changed.connect(_on_money)
	Game.rep_changed.connect(_on_rep)
	Game.day_ended.connect(_on_day_ended)
	Game.game_over.connect(_on_game_over)
	Game.upgrade_bought.connect(func(_id): _refresh_upgrades())
	_on_money(Game.money)
	_on_rep(Game.rep)


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


func _button(parent: Control, text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 22)
	b.custom_minimum_size = Vector2(200, 48)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _capture() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_new() -> void:
	Game.new_game()
	_capture()


func _on_continue() -> void:
	if Game.continue_game():
		_capture()


## Tam ekran karartma + ortalanmış panel; [karartma, içerik kutusu] döndürür.
func _modal(parent: Control, width: float) -> Array:
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.06, 0.78)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.visible = false
	parent.add_child(dim)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dim.add_child(cc)
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.09, 0.13, 0.97)
	sb.set_corner_radius_all(14)
	sb.set_content_margin_all(26)
	sb.border_color = Color(1.0, 0.85, 0.4, 0.6)
	sb.set_border_width_all(2)
	pc.add_theme_stylebox_override("panel", sb)
	pc.custom_minimum_size = Vector2(width, 0)
	pc.mouse_filter = Control.MOUSE_FILTER_STOP
	cc.add_child(pc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	pc.add_child(vb)
	return [dim, vb]


func _row(grid: GridContainer, a: String, b: String, color := Color.WHITE) -> void:
	var l := _label(grid, a, 24, Color(0.8, 0.85, 0.92))
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var r := _label(grid, b, 24, color)
	r.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT


func _build_summary(root: Control) -> void:
	var m := _modal(root, 520)
	summary_root = m[0]
	var vb: VBoxContainer = m[1]
	summary_title = _label(vb, "", 34, Color(1.0, 0.85, 0.4))
	summary_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	summary_grid = GridContainer.new()
	summary_grid.columns = 2
	vb.add_child(summary_grid)
	summary_note = _label(vb, "", 18, Color(1, 0.55, 0.45))
	summary_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_button(vb, "Sonraki gün", func():
		summary_root.visible = false
		Game.next_day()
		_capture())


func _build_over(root: Control) -> void:
	var m := _modal(root, 520)
	over_root = m[0]
	var vb: VBoxContainer = m[1]
	var t := _label(vb, "İflas ettin!", 44, Color(1.0, 0.4, 0.35))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	over_text = _label(vb, "", 20)
	over_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_button(vb, "Yeni oyun", func():
		over_root.visible = false
		_on_new())


func _stars(r: float) -> String:
	var n := roundi(r)
	return "★".repeat(n) + "☆".repeat(5 - n)


func _on_day_ended(s: Dictionary) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	summary_title.text = "Gün %d bitti" % s.day
	for c in summary_grid.get_children():
		c.free()
	var green := Color(0.5, 1, 0.55)
	var red := Color(1, 0.5, 0.45)
	_row(summary_grid, "Tamamlanan iş", "%d" % s.jobs)
	_row(summary_grid, "Gelir", "+%d TL" % s.income, green)
	_row(summary_grid, "Parça giderleri", "-%d TL" % s.parts, red)
	_row(summary_grid, "Kira", "-%d TL" % s.rent, red)
	_row(summary_grid, "Net", "%+d TL" % s.net, green if s.net >= 0 else red)
	var d: float = s.rep_delta
	_row(summary_grid, "İtibar", "%s  (%+.1f)" % [_stars(s.rep), d], green if d >= 0 else red)
	_row(summary_grid, "Kasa", "%d TL" % s.money, green if s.money >= 0 else red)
	summary_note.text = ("Dikkat: kasa eksiye düştü! Yarın da eksi kalırsan iflas edersin.\n" if s.warn else "") \
		+ "Yarınki kira: %d TL" % s.next_rent
	summary_root.visible = true


func _on_game_over(s: Dictionary) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	over_text.text = "Gün %d: kasa %d TL, iki gün üst üste eksiye düştün.\nDükkân kapandı." % [s.day, s.money]
	over_root.visible = true


# --- Yönetim paneli (geliştirmeler) ---
func _build_upgrades(root: Control) -> void:
	var m := _modal(root, 640)
	upgrade_root = m[0]
	var vb: VBoxContainer = m[1]
	var t := _label(vb, "Yönetim Paneli", 34, Color(1.0, 0.85, 0.4))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	upgrade_money = _label(vb, "", 22, Color(0.6, 1.0, 0.6))
	upgrade_money.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for u in Game.UPGRADE_LIST:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		vb.add_child(row)
		var tv := VBoxContainer.new()
		tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(tv)
		_label(tv, u.name, 24, Color(0.9, 0.95, 1.0))
		_label(tv, u.desc, 17, Color(0.7, 0.75, 0.85))
		var uid: String = u.id
		var b := _button(row, "", func(): Game.buy_upgrade(uid))
		b.custom_minimum_size = Vector2(210, 52)
		upgrade_rows[uid] = b
	_button(vb, "Kapat", close_upgrades)
	_refresh_upgrades()


func open_upgrades() -> void:
	_refresh_upgrades()
	upgrade_root.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close_upgrades() -> void:
	upgrade_root.visible = false
	_capture()


func _refresh_upgrades() -> void:
	if upgrade_money == null:
		return
	upgrade_money.text = "Kasa: ₺ %d" % Game.money
	for u in Game.UPGRADE_LIST:
		var b: Button = upgrade_rows[u.id]
		if Game.has_upgrade(u.id):
			b.text = "Alındı ✓"
			b.disabled = true
		else:
			b.text = "Satın al — %d TL" % u.price
			b.disabled = Game.money < int(u.price)


func _on_money(v: int) -> void:
	money_label.text = "₺ %d" % v
	_refresh_upgrades()


func _on_rep(r: float) -> void:
	rep_label.text = "%s  %.1f" % [_stars(r), r]


## Sabır çubuğu: 0..1, negatifse gizle.
func set_patience(f: float) -> void:
	patience_bar.visible = f >= 0.0
	if f >= 0.0:
		patience_bar.value = clampf(f, 0.0, 1.0)
		var fill := StyleBoxFlat.new()
		fill.bg_color = Color(0.4, 0.9, 0.4).lerp(Color(0.95, 0.25, 0.2), 1.0 - clampf(f * 1.6, 0.0, 1.0))
		patience_bar.add_theme_stylebox_override("fill", fill)


## Ödemede yukarı süzülen "+250 TL".
func pop_money(amount: int) -> void:
	var l := _label(_ui_root, "+%d TL" % amount, 34, Color(0.5, 1, 0.55))
	l.add_theme_constant_override("outline_size", 8)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.position = Vector2(210, 60)
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "position:y", 20.0, 1.4)
	tw.tween_property(l, "modulate:a", 0.0, 1.0).set_delay(0.6)
	tw.chain().tween_callback(l.queue_free)


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
	if upgrade_root.visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close_upgrades()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F3:
		fps_label.visible = not fps_label.visible


func _process(_delta: float) -> void:
	if fps_label.visible:
		fps_label.text = "FPS: %d   Draw call: %d" % [Engine.get_frames_per_second(),
			RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)]
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	# seçim yapmadan fare yakalandıysa (dev araçları) yeni oyun say
	if captured and not Game.started:
		Game.new_game()
	var modal: bool = summary_root.visible or over_root.visible or upgrade_root.visible
	Game.running = captured and Game.started
	var txt := "Gün %d  ·  %s" % [Game.day, Game.clock_text()]
	if txt != _clock_cache:
		_clock_cache = txt
		day_label.text = txt
	overlay.visible = not captured and not modal
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE if Game.started else Control.MOUSE_FILTER_STOP
	btn_resume.visible = Game.started
	btn_continue.visible = not Game.started and Game.has_save()
	btn_new.visible = not Game.started
	if Game.started:
		overlay_title.text = "DURAKLATILDI"
		overlay_sub.text = "Devam etmek için tıkla"
	var p = Game.player
	hint_label.text = p.hint if p and captured else ""
	crosshair.modulate = Color(1, 0.85, 0.3) if hint_label.text != "" else Color(1, 1, 1, 0.7)
