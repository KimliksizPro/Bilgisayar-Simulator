extends CanvasLayer
## Ekran arayüzü: para/gün kartı, iş kartı, nişangah, etkileşim ipucu, bildirimler,
## öğretici ipuçları, gün sonu / yönetim paneli / iflas ekranları ve duraklatma menüsü.

const T := preload("res://scripts/ui_theme.gd")
const K := preload("res://scripts/ui_kit.gd")
const CROSS := preload("res://scripts/crosshair.gd")
const PAUSE := preload("res://scripts/pause_menu.gd")

var _ui_root: Control
# sol üst kart
var money_label: Label
var day_label: Label
var clock_label: Label
var day_bar: ProgressBar
var rep_stars: Control
var rep_label: Label
var fps_label: Label
# iş kartı
var job_name: Label
var job_pay: Label
var job_pay_pill: Control
var job_desc: Label
var patience_row: Control
var patience_bar: ProgressBar
var _pfill: StyleBoxFlat
# merkez
var crosshair: Control
var prompt: Control
var prompt_key: Control
var prompt_text: Label
var toasts: VBoxContainer
var tip_card: Control
var tip_label: Label
var pause: CanvasLayer
# modallar
var summary_root: Control
var summary_panel: Control
var summary_title: Label
var summary_rows: VBoxContainer
var summary_note: Label
var summary_btn: Button
var over_root: Control
var over_panel: Control
var over_text: Label
var upgrade_root: Control
var upgrade_panel: Control
var upgrade_money: Label
var upgrade_rows := {}
var upgrade_close: Button

var _clock_cache := ""
var _last_hint := "\u0001"
var _money_target := 0
var _money_shown := 0.0
var _money_init := false
var _money_tw: Tween
var _money_flash: Tween
var _fps_t := 0.0
var _tips: Array = []
var _tip_id := ""
var _tip_tw: Tween


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Game.hud = self
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_ui_root = root
	_build_money_card(root)
	_build_job_card(root)
	_build_center(root)
	_build_toasts(root)
	_build_tip(root)
	_build_corner(root)
	_build_summary(root)
	_build_over(root)
	_build_upgrades(root)
	pause = PAUSE.new()
	add_child(pause)

	Game.money_changed.connect(_on_money)
	Game.rep_changed.connect(_on_rep)
	Game.day_ended.connect(_on_day_ended)
	Game.game_over.connect(_on_game_over)
	Game.day_started.connect(_on_day_started)
	Game.upgrade_bought.connect(func(_id): _refresh_upgrades())
	Settings.changed.connect(func(k): if k == "show_fps": fps_label.visible = Settings.show_fps)
	fps_label.visible = Settings.show_fps
	_on_money(Game.money)
	_on_rep(Game.rep)
	set_job("Hoş geldin!", "")
	set_patience(-1.0)


# ---------------------------------------------------------------- yapı
func _coin(parent: Control, d := 36) -> Control:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", T.flat(T.ACCENT, d / 2, T.ACCENT_HI, 2, Vector2(0, 0), 6))
	p.custom_minimum_size = Vector2(d, d)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := K.label(p, "₺", int(d * 0.62), Color("1a1204"), "BoldLabel")
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	parent.add_child(p)
	return p


func _build_money_card(root: Control) -> void:
	var card := K.panel(root, "HudCard")
	card.position = Vector2(20, 20)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	card.add_child(vb)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	vb.add_child(top)
	_coin(top)
	money_label = K.label(top, "0", 34, T.TEXT, "BoldLabel")
	money_label.custom_minimum_size = Vector2(150, 0)
	var dr := HBoxContainer.new()
	dr.add_theme_constant_override("separation", 10)
	vb.add_child(dr)
	day_label = K.label(dr, "Gün 1", 19, T.ACCENT_HI, "BoldLabel")
	clock_label = K.label(dr, "09:00", 19, T.TEXT)
	clock_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clock_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	day_bar = ProgressBar.new()
	day_bar.max_value = 1.0
	day_bar.show_percentage = false
	day_bar.custom_minimum_size = Vector2(0, 6)
	day_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := T.flat(T.INFO, 3)
	day_bar.add_theme_stylebox_override("fill", fill)
	day_bar.add_theme_stylebox_override("background", T.flat(Color(0, 0, 0, 0.45), 3))
	vb.add_child(day_bar)
	var rr := HBoxContainer.new()
	rr.add_theme_constant_override("separation", 10)
	vb.add_child(rr)
	rep_stars = K.stars(rr, 20)
	rep_label = K.label(rr, "3.0", 17, T.MUTED, "MutedLabel")
	fps_label = K.label(root, "", 15, T.GOOD, "BoldLabel")
	fps_label.position = Vector2(24, 190)
	fps_label.add_theme_constant_override("outline_size", 5)
	fps_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))


func _build_job_card(root: Control) -> void:
	var card := K.panel(root, "HudCard")
	card.anchor_left = 1.0
	card.anchor_right = 1.0
	card.offset_left = -400
	card.offset_right = -20
	card.offset_top = 20
	card.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	card.add_child(vb)
	K.label(vb, "AKTİF İŞ", 13, T.MUTED, "SmallCaps")
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	vb.add_child(top)
	job_name = K.label(top, "", 22, T.ACCENT_HI, "BoldLabel")
	job_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	job_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	job_name.custom_minimum_size = Vector2(200, 0)
	job_pay_pill = K.panel(top, "Pill")
	job_pay_pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	job_pay = K.label(job_pay_pill, "", 17, T.GOOD, "BoldLabel")
	job_desc = K.label(vb, "", 16, T.TEXT)
	job_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	job_desc.custom_minimum_size = Vector2(340, 0)
	patience_row = HBoxContainer.new()
	patience_row.add_theme_constant_override("separation", 10)
	vb.add_child(patience_row)
	K.label(patience_row, "Sabır", 14, T.MUTED, "MutedLabel")
	patience_bar = ProgressBar.new()
	patience_bar.max_value = 1.0
	patience_bar.show_percentage = false
	patience_bar.custom_minimum_size = Vector2(0, 10)
	patience_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	patience_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	patience_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pfill = T.flat(T.GOOD, 5)
	patience_bar.add_theme_stylebox_override("fill", _pfill)
	patience_row.add_child(patience_bar)
	patience_row.visible = false


func _build_center(root: Control) -> void:
	crosshair = CROSS.new()
	crosshair.anchor_left = 0.5
	crosshair.anchor_right = 0.5
	crosshair.anchor_top = 0.5
	crosshair.anchor_bottom = 0.5
	crosshair.offset_left = -24
	crosshair.offset_right = 24
	crosshair.offset_top = -24
	crosshair.offset_bottom = 24
	root.add_child(crosshair)
	# etkileşim ipucu: [E] Eylem
	prompt = K.panel(root, "HudCard")
	prompt.set_anchors_preset(Control.PRESET_CENTER)
	prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	prompt.offset_left = 0
	prompt.offset_right = 0
	prompt.offset_top = 38
	prompt.offset_bottom = 38
	prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prompt.visible = false
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	prompt.add_child(h)
	prompt_key = K.keycap(h, "E", 20)
	prompt_text = K.label(h, "", 21, T.TEXT, "BoldLabel")
	prompt_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


func _build_toasts(root: Control) -> void:
	toasts = VBoxContainer.new()
	toasts.anchor_top = 1.0
	toasts.anchor_bottom = 1.0
	toasts.offset_left = 24
	toasts.offset_right = 700
	toasts.offset_top = -420
	toasts.offset_bottom = -64
	toasts.alignment = BoxContainer.ALIGNMENT_END
	toasts.add_theme_constant_override("separation", 8)
	toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(toasts)


func _build_tip(root: Control) -> void:
	tip_card = K.panel(root, "HudCard")
	tip_card.anchor_left = 0.5
	tip_card.anchor_right = 0.5
	tip_card.anchor_top = 0.0
	tip_card.anchor_bottom = 0.0
	tip_card.grow_horizontal = Control.GROW_DIRECTION_BOTH
	tip_card.offset_top = 22
	tip_card.offset_bottom = 22
	tip_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip_card.visible = false
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	tip_card.add_child(h)
	var tag := K.panel(h, "Pill")
	tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tag.add_theme_stylebox_override("panel", T.flat(Color(T.ACCENT.r, T.ACCENT.g, T.ACCENT.b, 0.18), 20, T.ACCENT, 1, Vector2(12, 3)))
	K.label(tag, "İPUCU", 15, T.ACCENT_HI, "BoldLabel")
	tip_label = K.label(h, "", 20, T.TEXT)
	tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip_label.custom_minimum_size = Vector2(560, 0)
	var hide := HBoxContainer.new()
	hide.add_theme_constant_override("separation", 6)
	h.add_child(hide)
	K.keycap(hide, "H", 14)
	K.label(hide, "gizle", 14, T.MUTED, "MutedLabel").vertical_alignment = VERTICAL_ALIGNMENT_CENTER


func _build_corner(root: Control) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	h.anchor_left = 1.0
	h.anchor_right = 1.0
	h.anchor_top = 1.0
	h.anchor_bottom = 1.0
	h.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	h.grow_vertical = Control.GROW_DIRECTION_BEGIN
	h.offset_left = -20
	h.offset_right = -20
	h.offset_top = -20
	h.offset_bottom = -20
	h.modulate.a = 0.6
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(h)
	K.keycap(h, "Esc", 14)
	var l := K.label(h, "Duraklat", 15, T.TEXT, "MutedLabel")
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER


# ---------------------------------------------------------------- modallar
func _build_summary(root: Control) -> void:
	var m := K.modal(root, 580, 0.72)
	summary_root = m[0]
	summary_panel = m[1]
	var vb: VBoxContainer = m[2]
	summary_title = K.label(vb, "", 38, T.ACCENT, "TitleLabel")
	summary_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var sub := K.label(vb, "Dükkân kapandı. İşte günün özeti.", 17, T.MUTED, "MutedLabel")
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var inset := K.panel(vb, "InsetPanel")
	summary_rows = VBoxContainer.new()
	summary_rows.add_theme_constant_override("separation", 8)
	inset.add_child(summary_rows)
	summary_note = K.label(vb, "", 17, T.BAD)
	summary_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary_note.custom_minimum_size = Vector2(500, 0)
	summary_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	summary_btn = K.button(vb, "Sonraki Gün", func():
		K.close(summary_root, summary_panel)
		Game.next_day()
		_capture(), "PrimaryButton", 23, Vector2(0, 56))


func _build_over(root: Control) -> void:
	var m := K.modal(root, 560, 0.8)
	over_root = m[0]
	over_panel = m[1]
	var vb: VBoxContainer = m[2]
	var t := K.label(vb, "İflas Ettin!", 46, T.BAD, "TitleLabel")
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	over_text = K.label(vb, "", 19, T.TEXT)
	over_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	over_text.custom_minimum_size = Vector2(480, 0)
	over_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	K.spacer(vb, 6)
	K.button(vb, "Yeni Oyun", func():
		K.close(over_root, over_panel)
		Game.new_game()
		_capture(), "PrimaryButton", 22, Vector2(0, 54))
	K.button(vb, "Ana Menü", func():
		Game.return_to_menu(), "", 20, Vector2(0, 48))


func _build_upgrades(root: Control) -> void:
	var m := K.modal(root, 760, 0.7)
	upgrade_root = m[0]
	upgrade_panel = m[1]
	var vb: VBoxContainer = m[2]
	var head := HBoxContainer.new()
	vb.add_child(head)
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_theme_constant_override("separation", 0)
	head.add_child(tv)
	K.label(tv, "Yönetim Paneli", 36, T.ACCENT, "TitleLabel")
	K.label(tv, "Dükkânını geliştir, daha çok kazan.", 17, T.MUTED, "MutedLabel")
	var mp := K.panel(head, "HudCard")
	mp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var mh := HBoxContainer.new()
	mh.add_theme_constant_override("separation", 10)
	mp.add_child(mh)
	_coin(mh, 30)
	upgrade_money = K.label(mh, "", 24, T.TEXT, "BoldLabel")
	K.hsep(vb)
	for u in Game.UPGRADE_LIST:
		var ip := K.panel(vb, "InsetPanel")
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		ip.add_child(row)
		var tcol := VBoxContainer.new()
		tcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tcol.add_theme_constant_override("separation", 0)
		row.add_child(tcol)
		K.label(tcol, u.name, 23, T.TEXT, "BoldLabel")
		K.label(tcol, u.desc, 17, T.MUTED, "MutedLabel")
		var uid: String = u.id
		var owned := K.panel(row, "Pill")
		owned.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		owned.custom_minimum_size = Vector2(190, 0)
		var ol := K.label(owned, "ALINDI", 18, T.GOOD, "BoldLabel")
		ol.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var b := K.button(row, "", func(): Game.buy_upgrade(uid), "PrimaryButton", 19, Vector2(190, 50))
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		upgrade_rows[uid] = [b, owned]
	K.spacer(vb, 2)
	upgrade_close = K.button(vb, "Kapat", close_upgrades, "", 20, Vector2(0, 50))
	_refresh_upgrades()


# ---------------------------------------------------------------- dış API
func open_upgrades() -> void:
	_refresh_upgrades()
	K.open(upgrade_root, upgrade_panel)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	upgrade_close.grab_focus()


func close_upgrades() -> void:
	K.close(upgrade_root, upgrade_panel)
	_capture()


func _capture() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func open_pause() -> void:
	pause.open()


func _refresh_upgrades() -> void:
	if upgrade_money == null:
		return
	upgrade_money.text = K.money(Game.money)
	for u in Game.UPGRADE_LIST:
		var pair: Array = upgrade_rows[u.id]
		var b: Button = pair[0]
		var has := Game.has_upgrade(u.id)
		pair[1].visible = has
		b.visible = not has
		if not has:
			b.text = "Satın Al  ·  %d TL" % int(u.price)
			b.disabled = Game.money < int(u.price)


func _stars_text(r: float) -> String:
	return "%.1f" % r


func _on_money(v: int) -> void:
	var old := _money_target
	_money_target = v
	_refresh_upgrades()
	if not _money_init:
		_money_init = true
		_money_shown = float(v)
		money_label.text = K.money(v)
		return
	if _money_tw:
		_money_tw.kill()
	_money_tw = create_tween()
	_money_tw.tween_method(_set_money_shown, _money_shown, float(v), 0.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if v != old:
		if _money_flash:
			_money_flash.kill()
		money_label.add_theme_color_override("font_color", T.GOOD if v > old else T.BAD)
		_money_flash = create_tween()
		_money_flash.tween_interval(0.5)
		_money_flash.tween_method(func(t: float): money_label.add_theme_color_override("font_color", (T.GOOD if v > old else T.BAD).lerp(T.TEXT, t)), 0.0, 1.0, 0.5)


func _set_money_shown(x: float) -> void:
	_money_shown = x
	money_label.text = K.money(roundi(x))


func _on_rep(r: float) -> void:
	(rep_stars as Object).set("value", r)
	rep_label.text = _stars_text(r)


func _row(label_text: String, value_text: String, color := T.TEXT, big := false) -> void:
	var h := HBoxContainer.new()
	summary_rows.add_child(h)
	var l := K.label(h, label_text, 22 if big else 20, T.MUTED if not big else T.TEXT, "MutedLabel" if not big else "BoldLabel")
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var r := K.label(h, value_text, 24 if big else 20, color, "BoldLabel")
	r.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT


func _on_day_ended(s: Dictionary) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	summary_title.text = "Gün %d Tamamlandı" % s.day
	for c in summary_rows.get_children():
		c.free()
	_row("Tamamlanan iş", "%d" % s.jobs)
	_row("Gelir", "+%s TL" % K.money(s.income), T.GOOD)
	_row("Parça giderleri", "-%s TL" % K.money(s.parts), T.BAD)
	_row("Kira", "-%s TL" % K.money(s.rent), T.BAD)
	K.hsep(summary_rows)
	_row("Net kazanç", "%s%s TL" % ["+" if s.net >= 0 else "", K.money(s.net)], T.GOOD if s.net >= 0 else T.BAD, true)
	var d: float = s.rep_delta
	var rh := HBoxContainer.new()
	summary_rows.add_child(rh)
	var rl := K.label(rh, "İtibar", 20, T.MUTED, "MutedLabel")
	rl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var st := K.stars(rh, 20)
	st.set("value", s.rep)
	st.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var dl := K.label(rh, "(%+.1f)" % d, 18, T.GOOD if d >= 0 else T.BAD, "BoldLabel")
	dl.custom_minimum_size = Vector2(60, 0)
	dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_row("Kasa", "%s TL" % K.money(s.money), T.GOOD if s.money >= 0 else T.BAD, true)
	summary_note.text = ("Dikkat: kasa eksiye düştü! Yarın da eksi kalırsan iflas edersin.\n" if s.warn else "") \
		+ "Yarınki kira: %s TL" % K.money(s.next_rent)
	summary_note.add_theme_color_override("font_color", T.BAD if s.warn else T.MUTED)
	K.open(summary_root, summary_panel)
	summary_btn.grab_focus()


func _on_game_over(s: Dictionary) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	over_text.text = "Gün %d: kasa %s TL, iki gün üst üste eksiye düştün.\nDükkân kapandı." % [s.day, K.money(s.money)]
	K.open(over_root, over_panel)
	K.focus_first(over_root)


func _on_day_started() -> void:
	if Game.day == 1:
		tip("welcome", "WASD ile yürü, fareyle etrafına bak. Birazdan tezgaha ilk müşteri gelecek.")


## Sabır çubuğu: 0..1, negatifse gizle. Renk yeşilden kırmızıya kayar.
func set_patience(f: float) -> void:
	patience_row.visible = f >= 0.0
	if f >= 0.0:
		f = clampf(f, 0.0, 1.0)
		patience_bar.value = f
		var c: Color
		if f > 0.5:
			c = T.ACCENT.lerp(T.GOOD, (f - 0.5) * 2.0)
		else:
			c = T.BAD.lerp(T.ACCENT, f * 2.0)
		_pfill.bg_color = c


## Ödemede yukarı süzülen "+250 TL" ve para kartında parlama.
func pop_money(amount: int) -> void:
	var l := K.label(_ui_root, "%s%s TL" % ["+" if amount >= 0 else "-", K.money(absi(amount))], 40, T.GOOD if amount >= 0 else T.BAD, "TitleLabel")
	l.add_theme_constant_override("outline_size", 10)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.position = Vector2(236, 62)
	l.modulate.a = 0.0
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "modulate:a", 1.0, 0.15)
	tw.tween_property(l, "position:y", 22.0, 1.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.5).set_delay(1.1)
	tw.chain().tween_callback(l.queue_free)


func set_job(title: String, desc: String) -> void:
	var parts := title.split(" — ")
	job_name.text = parts[0]
	job_pay_pill.visible = parts.size() > 1
	if parts.size() > 1:
		job_pay.text = parts[1]
	job_desc.text = desc.replace("[E]", "(E)")
	job_desc.visible = desc != ""


## Bildirim: renkten tür çıkarılır (yeşil = para, turuncu/kırmızı = uyarı, mavi = bilgi).
func show_message(text: String, color := Color.WHITE, kind := "") -> void:
	if kind == "":
		if color.r > 0.85 and color.g < 0.9 and color.b < 0.7:
			kind = "warn"
		elif color.g >= 0.85 and color.r < 0.85 and color.b < 0.8:
			kind = "money"
		else:
			kind = "info"
	var col: Color = {"warn": T.BAD, "money": T.GOOD, "info": T.INFO}[kind]
	if kind == "warn" and color.g > 0.7:
		col = T.ACCENT
	var glyph: String = {"warn": "!", "money": "₺", "info": "i"}[kind]
	while toasts.get_child_count() > 4:
		toasts.get_child(0).free()
	var wrap := Control.new()
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toasts.add_child(wrap)
	var inner := K.panel(wrap, "Toast")
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inner.add_theme_stylebox_override("panel", T.flat(Color(0.035, 0.055, 0.11, 0.92), 14, Color(col.r, col.g, col.b, 0.55), 2, Vector2(12, 9), 10))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	inner.add_child(h)
	var ic := PanelContainer.new()
	ic.add_theme_stylebox_override("panel", T.flat(col, 15, Color(0, 0, 0, 0), 0, Vector2(0, 0)))
	ic.custom_minimum_size = Vector2(30, 30)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(ic)
	var gl := K.label(ic, glyph, 19, Color("101423"), "BoldLabel")
	gl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var l := K.label(h, text, 20, T.TEXT)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var fnt := l.get_theme_font("font")
	var w := fnt.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x
	l.custom_minimum_size.x = minf(w + 6.0, 560.0)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	inner.resized.connect(func(): wrap.custom_minimum_size = inner.size)
	inner.modulate.a = 0.0
	inner.position.x = -90.0
	var tw := wrap.create_tween()
	tw.tween_property(inner, "modulate:a", 1.0, 0.25)
	tw.parallel().tween_property(inner, "position:x", 0.0, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(4.0)
	tw.tween_property(inner, "modulate:a", 0.0, 0.3)
	tw.parallel().tween_property(inner, "position:x", -60.0, 0.3).set_ease(Tween.EASE_IN)
	tw.tween_property(wrap, "custom_minimum_size:y", 0.0, 0.18)
	tw.tween_callback(wrap.queue_free)


# ---------------------------------------------------------------- öğretici ipuçları
## Kısa bağlamsal ipucu: her ipucu bir kez gösterilir (Ayarlar > Oyun'dan kapatılabilir).
func tip(id: String, text: String) -> void:
	if not Settings.show_hints or Settings.tips_seen.has(id):
		return
	for t in _tips:
		if t[0] == id:
			return
	if id == _tip_id:
		return
	_tips.append([id, text])
	if _tip_id == "":
		_next_tip()


func dismiss_tip(id: String) -> void:
	for i in range(_tips.size() - 1, -1, -1):
		if _tips[i][0] == id:
			_tips.remove_at(i)
	if _tip_id == id:
		_hide_tip()


func _next_tip() -> void:
	if _tips.is_empty():
		_tip_id = ""
		return
	var t: Array = _tips.pop_front()
	_tip_id = t[0]
	Settings.mark_tip_seen(_tip_id)
	tip_label.text = t[1]
	tip_card.visible = true
	tip_card.modulate.a = 0.0
	if _tip_tw:
		_tip_tw.kill()
	_tip_tw = create_tween()
	_tip_tw.tween_property(tip_card, "modulate:a", 1.0, 0.3)
	_tip_tw.tween_interval(11.0)
	_tip_tw.tween_callback(_hide_tip)


func _hide_tip() -> void:
	if _tip_tw:
		_tip_tw.kill()
	_tip_tw = create_tween()
	_tip_tw.tween_property(tip_card, "modulate:a", 0.0, 0.25)
	_tip_tw.tween_callback(func():
		tip_card.visible = false
		_tip_id = ""
		_next_tip())


# ---------------------------------------------------------------- girdi / kare güncelleme
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if upgrade_root.visible:
			Game.sfx.ui_back()
			close_upgrades()
			get_viewport().set_input_as_handled()
		elif not (summary_root.visible or over_root.visible) and Game.started and Game.phase == "day":
			pause.open()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_F3:
			Settings.set_opt("show_fps", not Settings.show_fps)
		elif event.physical_keycode == KEY_H and _tip_id != "":
			_hide_tip()


func _notification(what: int) -> void:
	# pencere odağı kaybolunca oyunu otomatik duraklat
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and not Game.dev_mode and Game.started \
			and Game.phase == "day" and not Game.ui_modal and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		pause.open()


func _process(delta: float) -> void:
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	# geliştirici araçları menüsüz fareyi yakalayınca yeni oyun say
	if captured and not Game.started and Game.dev_mode:
		Game.new_game()
	Game.ui_modal = summary_root.visible or over_root.visible or upgrade_root.visible or pause.open_now
	Game.running = captured and Game.started and not Game.paused
	if fps_label.visible:
		_fps_t += delta
		if _fps_t >= 0.25:
			_fps_t = 0.0
			fps_label.text = "FPS: %d   Draw call: %d" % [Engine.get_frames_per_second(),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)]
	var minute := int(Game.clock * 60.0)
	var txt := "%d:%d" % [Game.day, minute]
	if txt != _clock_cache:
		_clock_cache = txt
		day_label.text = "Gün %d" % Game.day
		clock_label.text = Game.clock_text()
		day_bar.value = (Game.clock - Game.OPEN_HOUR) / (Game.CLOSE_HOUR - Game.OPEN_HOUR)
	var p = Game.player
	var h: String = p.hint if p and captured else ""
	if h != _last_hint:
		_last_hint = h
		crosshair.set("target", h != "")
		prompt.visible = h != ""
		if h != "":
			var has_key := h.contains("[E]")
			prompt_key.visible = has_key
			prompt_text.text = h.replace("[E]", "").replace("  ", " ").strip_edges()
