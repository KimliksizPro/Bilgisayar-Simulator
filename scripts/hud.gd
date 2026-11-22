extends CanvasLayer
## Ekran arayüzü: para/gün kartı, iş kartı, nişangah, etkileşim ipucu, bildirimler,
## öğretici ipuçları, gün sonu / yönetim paneli / iflas ekranları ve duraklatma menüsü.

const T := preload("res://scripts/ui_theme.gd")
const K := preload("res://scripts/ui_kit.gd")
const CROSS := preload("res://scripts/crosshair.gd")
const PAUSE := preload("res://scripts/pause_menu.gd")
const OFFICE := preload("res://scripts/office_panel.gd")
const ST := preload("res://scripts/job_store.gd")

var _ui_root: Control
# sol üst kart
var _money_card: PanelContainer
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
var job_no: Label
var job_who: Label
var _job_holder: Control
var _last_job := ""
# açık işler listesi
var _job_card: Control
var _jobs_holder: Control
var _jobs_box: VBoxContainer
var _jobs_count: Label
var _jobs_sig := ""
var _jobs_t := 0.0
var _summary_sub: Label
var job_desc: Label
var patience_row: Control
var patience_bar: ProgressBar
var _pfill: StyleBoxTexture
# merkez
var crosshair: Control
var corner_hint: Control   # sağ alttaki "Esc Duraklat" ipucu (tezgâh modunda gizlenir)
var _held_card: PanelContainer
var _held_accent: ColorRect
var _held_lbl: Label
var _held_sub: Label
var _held_sig := ""
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
var office: Control
var cargo_row: Control
var cargo_label: Label

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
	_build_jobs_list(root)
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
	Game.orders_changed.connect(_refresh_cargo)
	Game.jobs_changed.connect(_refresh_jobs)
	Settings.changed.connect(_on_setting_changed)
	fps_label.visible = Settings.show_fps
	_on_money(Game.money)
	_on_rep(Game.rep)
	set_job("Hoş geldin!", "")
	set_patience(-1.0)
	_apply_hud_scale()
	call_deferred("_apply_hud_scale")


func _on_setting_changed(k: String) -> void:
	if k == "show_fps":
		fps_label.visible = Settings.show_fps
	elif k == "hud_scale":
		_apply_hud_scale()


## Yazar kasa kartının ekrandaki alt Y konumu (HUD ölçeği dahil).
func money_card_bottom() -> float:
	if _money_card:
		var h := _money_card.size.y
		if h <= 1.0:
			h = _money_card.get_combined_minimum_size().y
		return _money_card.position.y + maxf(h, 175.0) * Settings.hud_scale
	return 196.0 * Settings.hud_scale


func _place_fps() -> void:
	if fps_label:
		fps_label.position = Vector2(24.0, money_card_bottom() + 10.0)


func _apply_hud_scale() -> void:
	var s := Settings.hud_scale
	var sv := Vector2(s, s)
	if _money_card:
		_money_card.pivot_offset = Vector2.ZERO
		_money_card.scale = sv
	if fps_label:
		fps_label.pivot_offset = Vector2.ZERO
		fps_label.scale = sv
		_place_fps()
	if _job_holder:
		_job_holder.pivot_offset = Vector2(_job_holder.size.x if _job_holder.size.x > 1.0 else 380.0, 0.0)
		_job_holder.scale = sv
	if _jobs_holder:
		_jobs_holder.pivot_offset = Vector2(_jobs_holder.size.x if _jobs_holder.size.x > 1.0 else 380.0, 0.0)
		_jobs_holder.scale = sv
	_place_jobs_list()
	if prompt:
		prompt.pivot_offset = Vector2(prompt.size.x * 0.5, 0.0)
		prompt.scale = sv
	if toasts:
		toasts.pivot_offset = Vector2(0.0, toasts.size.y)
		toasts.scale = sv
	if tip_card:
		tip_card.pivot_offset = Vector2(330.0, 0.0)
		tip_card.scale = sv
	if corner_hint:
		corner_hint.pivot_offset = corner_hint.size
		corner_hint.scale = sv
	if _held_card:
		_held_card.pivot_offset = _held_card.size
		_held_card.scale = sv


# ---------------------------------------------------------------- yapı
## Yazar kasa: vidalı plaka içinde yeşil LCD (para, gün, saat), LED gün çubuğu ve itibar yıldızları.
func _build_money_card(root: Control) -> void:
	var card := K.panel(root, "ScrewCard")
	card.position = Vector2(18, 18)
	card.pivot_offset = Vector2.ZERO
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.resized.connect(_place_fps)
	_money_card = card
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 7)
	card.add_child(vb)
	var head := HBoxContainer.new()
	vb.add_child(head)
	K.label(head, "YAZAR KASA", 12, T.MUTED, "SmallCaps").size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var led := ColorRect.new()
	led.color = T.LCD
	led.custom_minimum_size = Vector2(7, 7)
	led.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(led)
	var lp := K.panel(vb, "LcdPanel")
	lp.add_theme_stylebox_override("panel", T.lcd_box(Vector2(14, 2)))
	lp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", -8)
	lp.add_child(lv)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	lv.add_child(top)
	var cur := K.label(top, "₺", 40, T.LCD_DIM, "LcdLabel")
	cur.size_flags_vertical = Control.SIZE_SHRINK_END
	money_label = K.label(top, "0", 58, T.LCD, "LcdLabel")
	K.lcd_glow(money_label)
	money_label.custom_minimum_size = Vector2(190, 0)
	money_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	money_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var dr := HBoxContainer.new()
	lv.add_child(dr)
	day_label = K.label(dr, "GÜN 01", 26, T.LCD_DIM, "LcdLabel")
	day_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clock_label = K.label(dr, "09:00", 26, T.LCD, "LcdLabel")
	K.lcd_glow(clock_label)
	day_bar = ProgressBar.new()
	day_bar.max_value = 1.0
	day_bar.show_percentage = false
	day_bar.custom_minimum_size = Vector2(0, 9)
	day_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	day_bar.add_theme_stylebox_override("fill", T.seg_box(T.ACCENT))
	vb.add_child(day_bar)
	var rr := HBoxContainer.new()
	rr.add_theme_constant_override("separation", 10)
	vb.add_child(rr)
	rep_stars = K.stars(rr, 19)
	rep_stars.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rep_label = K.label(rr, "3.0", 17, T.ACCENT_HI, "BoldLabel")
	# yoldaki kargo göstergesi
	var cr := HBoxContainer.new()
	cr.add_theme_constant_override("separation", 8)
	vb.add_child(cr)
	cargo_row = cr
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", T.flat(Color(0.68, 0.52, 0.33), 2, Color(0.82, 0.7, 0.45), 2, Vector2(0, 0)))
	box.custom_minimum_size = Vector2(16, 13)
	box.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	cr.add_child(box)
	cargo_label = K.label(cr, "", 15, T.TEXT, "BoldLabel")
	cr.visible = false
	fps_label = K.label(root, "", 15, T.GOOD, "BoldLabel")
	fps_label.position = Vector2(24, 250)
	fps_label.add_theme_constant_override("outline_size", 5)
	fps_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))


## Servis fişi: mandalla tutturulmuş kâğıt; müşteri adı tükenmez kalemle, ücret lastik mühürle.
func _build_job_card(root: Control) -> void:
	var holder := Control.new()
	holder.anchor_left = 1.0
	holder.anchor_right = 1.0
	holder.offset_left = -404
	holder.offset_right = -24
	holder.offset_top = 30
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.rotation_degrees = 0.8
	holder.pivot_offset = Vector2(380, 0)
	root.add_child(holder)
	_job_holder = holder
	var card := K.panel(holder, "PaperPanel")
	card.custom_minimum_size = Vector2(380, 0)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_job_card = card
	card.resized.connect(_place_jobs_list)
	# mandal
	var clip := PanelContainer.new()
	var cs := T.flat(Color("5d636e"), 3, Color("9aa1ad"), 0, Vector2(0, 0), 3)
	cs.border_width_top = 2
	cs.border_width_bottom = 3
	cs.border_color = Color("9aa1ad")
	clip.add_theme_stylebox_override("panel", cs)
	clip.position = Vector2(168, -10)
	clip.size = Vector2(44, 16)
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(clip)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	card.add_child(vb)
	var head := HBoxContainer.new()
	vb.add_child(head)
	K.label(head, "TEZGÂH FİŞİ", 17, T.INK, "SignLabel").size_flags_horizontal = Control.SIZE_EXPAND_FILL
	job_no = K.label(head, "No. 0000", 22, T.INK_MUTED, "ReceiptLabel")
	job_no.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var sep := HSeparator.new()
	sep.theme_type_variation = "InkSeparator"
	sep.add_theme_constant_override("separation", 6)
	vb.add_child(sep)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	vb.add_child(top)
	var who := VBoxContainer.new()
	who.add_theme_constant_override("separation", -6)
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(who)
	job_who = K.label(who, "MÜŞTERİ", 12, T.INK_MUTED, "SmallCaps")
	job_name = K.hand(who, "", 36)
	job_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	job_name.custom_minimum_size = Vector2(200, 0)
	var st := K.stamp(top, "0 TL", T.STAMP_GREEN, 19, -7.0)
	job_pay_pill = st[0]
	job_pay_pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	job_pay = st[2]
	job_desc = K.label(vb, "", 16, T.INK)
	job_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	job_desc.custom_minimum_size = Vector2(330, 0)
	patience_row = HBoxContainer.new()
	patience_row.add_theme_constant_override("separation", 10)
	vb.add_child(patience_row)
	K.label(patience_row, "SABIR", 12, T.INK_MUTED, "SmallCaps").size_flags_vertical = Control.SIZE_SHRINK_CENTER
	patience_bar = ProgressBar.new()
	patience_bar.max_value = 1.0
	patience_bar.show_percentage = false
	patience_bar.custom_minimum_size = Vector2(0, 12)
	patience_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	patience_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	patience_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pfill = T.seg_box(T.STAMP_GREEN)
	patience_bar.add_theme_stylebox_override("fill", _pfill)
	patience_bar.add_theme_stylebox_override("background", T.flat(Color(T.INK.r, T.INK.g, T.INK.b, 0.12), 2, Color(T.INK.r, T.INK.g, T.INK.b, 0.3), 1, Vector2(0, 0)))
	patience_row.add_child(patience_bar)
	patience_row.visible = false


## Açık işler listesi: tezgâh fişinin altında ikinci bir kâğıt. Fiş no, müşteri, kısa iş, durum ve teslim saati;
## tezgâhtaki iş vurgulanır. Veri Game.jobs_active; değişince (jobs_changed) ve saat ilerleyince yenilenir.
func _build_jobs_list(root: Control) -> void:
	var holder := Control.new()
	holder.anchor_left = 1.0
	holder.anchor_right = 1.0
	holder.offset_left = -404
	holder.offset_right = -24
	holder.offset_top = 250
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.rotation_degrees = -0.5
	holder.pivot_offset = Vector2(380, 0)
	root.add_child(holder)
	_jobs_holder = holder
	var card := K.panel(holder, "PaperPanel")
	card.custom_minimum_size = Vector2(380, 0)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	card.add_child(vb)
	var head := HBoxContainer.new()
	vb.add_child(head)
	K.label(head, "AÇIK İŞLER", 17, T.INK, "SignLabel").size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_jobs_count = K.label(head, "0 / 3", 22, T.INK_MUTED, "ReceiptLabel")
	var sep := HSeparator.new()
	sep.theme_type_variation = "InkSeparator"
	sep.add_theme_constant_override("separation", 6)
	vb.add_child(sep)
	_jobs_box = VBoxContainer.new()
	_jobs_box.add_theme_constant_override("separation", 5)
	vb.add_child(_jobs_box)


## Tezgâh fişinin boyu değişince liste hemen altına kayar.
func _place_jobs_list() -> void:
	if _jobs_holder and _job_card:
		var s := Settings.hud_scale
		_jobs_holder.offset_top = 30.0 + _job_card.size.y * s + 20.0 * s


## Tezgâh modunda birinci şahıs arayüz kartlarını gizler, çıkınca geri açar; bildirimleri tezgâh kenarına kaydırır.
func set_bench_mode(active: bool) -> void:
	if _money_card:
		_money_card.visible = not active
	if _job_holder:
		_job_holder.visible = not active
	if _jobs_holder:
		_jobs_holder.visible = not active
	if crosshair:
		crosshair.visible = not active
	if corner_hint:
		corner_hint.visible = not active
	if _held_card and active:
		_held_card.visible = false
		_held_sig = ""
	if toasts:
		toasts.offset_left = 330 if active else 24
		toasts.offset_bottom = -112 if active else -64
	if tip_card:
		tip_card.offset_top = 80 if active else 26


func _refresh_jobs() -> void:
	_jobs_sig = ""
	_rebuild_jobs()


func _rebuild_jobs() -> void:
	if _jobs_box == null:
		return
	var now := Game.now_abs()
	var recs: Array = Game.jobs_active.duplicate()
	recs.sort_custom(func(a, b): return float(a.due_abs) < float(b.due_abs))
	var sig := "%d/%d" % [recs.size(), Game.max_active_jobs()]
	for r in recs:
		sig += "|%d%s%s%s" % [int(r.ticket), r.status, r.location, ST.due_label(float(r.due_abs), Game.day)] + ("!" if now > float(r.due_abs) else "")
	if sig == _jobs_sig:
		return
	_jobs_sig = sig
	for c in _jobs_box.get_children():
		_jobs_box.remove_child(c)
		c.queue_free()
	_jobs_count.text = "%d / %d" % [recs.size(), Game.max_active_jobs()]
	if recs.is_empty():
		var e := K.label(_jobs_box, "Rafta iş yok. Müşteri bırakınca fiş burada görünür.", 15, T.INK_MUTED)
		e.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		e.custom_minimum_size = Vector2(330, 0)
		return
	for r in recs:
		_job_row(r, now)


func _job_row(r: Dictionary, now: float) -> void:
	var bench: bool = str(r.location) == "bench"
	var carried: bool = str(r.location) == "carry"
	var col := ST.status_color(r, now)
	var ink := Color(col.r * 0.62, col.g * 0.62, col.b * 0.62)
	var row := PanelContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := Color(T.ACCENT.r, T.ACCENT.g, T.ACCENT.b, 0.34) if (bench or carried) else Color(T.INK.r, T.INK.g, T.INK.b, 0.05)
	row.add_theme_stylebox_override("panel", T.flat(bg, 4, Color(T.ACCENT_LO.r, T.ACCENT_LO.g, T.ACCENT_LO.b, 0.9) if (bench or carried) else Color(0, 0, 0, 0), 2, Vector2(8, 4)))
	_jobs_box.add_child(row)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(h)
	var bar := ColorRect.new()
	bar.color = ink
	bar.custom_minimum_size = Vector2(5, 0)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(bar)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -2)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(v)
	var l1 := HBoxContainer.new()
	l1.add_theme_constant_override("separation", 6)
	v.add_child(l1)
	K.label(l1, "#%d" % int(r.ticket), 22, T.INK_MUTED, "ReceiptLabel")
	var nm := K.hand(l1, str(r.name), 26)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.clip_text = true
	var due := K.label(l1, ST.due_label(float(r.due_abs), Game.day), 15, ink if now > float(r.due_abs) else T.INK, "InkLabel")
	due.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var l2 := HBoxContainer.new()
	l2.add_theme_constant_override("separation", 6)
	v.add_child(l2)
	var goal := K.label(l2, ST.short_goal(r), 14, T.INK_MUTED)
	goal.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	goal.clip_text = true
	var stx := "ELDE" if carried else ST.status_text(r, now)
	K.label(l2, stx, 12, ink, "SmallCaps").size_flags_vertical = Control.SIZE_SHRINK_CENTER


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
	prompt = K.panel(root, "Toast")
	prompt.set_anchors_preset(Control.PRESET_CENTER)
	prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	prompt.offset_left = 0
	prompt.offset_right = 0
	prompt.offset_top = 40
	prompt.offset_bottom = 40
	prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prompt.add_theme_stylebox_override("panel", T.flat(Color(0.06, 0.065, 0.075, 0.88), 6, Color(1, 1, 1, 0.07), 1, Vector2(8, 6), 8))
	prompt.resized.connect(func(): prompt.pivot_offset = Vector2(prompt.size.x * 0.5, 0.0))
	prompt.visible = false
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	prompt.add_child(h)
	prompt_key = K.keycap(h, "E", 20)
	prompt_text = K.label(h, "", 21, T.TEXT, "BoldLabel")
	prompt_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	K.spacer(h, 0).custom_minimum_size.x = 4


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
	toasts.resized.connect(func(): toasts.pivot_offset = Vector2(0.0, toasts.size.y))
	root.add_child(toasts)


## Öğretici ipucu: bantla yapıştırılmış sarı not kâğıdı.
func _build_tip(root: Control) -> void:
	tip_card = Control.new()
	tip_card.anchor_left = 0.5
	tip_card.anchor_right = 0.5
	tip_card.offset_left = -330
	tip_card.offset_right = 330
	tip_card.offset_top = 26
	tip_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip_card.rotation_degrees = -1.2
	tip_card.pivot_offset = Vector2(330, 0)
	tip_card.visible = false
	root.add_child(tip_card)
	var note := K.panel(tip_card, "StickyNote")
	note.custom_minimum_size = Vector2(660, 0)
	note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tape := ColorRect.new()
	tape.color = Color(1, 1, 1, 0.38)
	tape.size = Vector2(110, 26)
	tape.position = Vector2(275, -12)
	tape.rotation_degrees = 2.0
	tape.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip_card.add_child(tape)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	note.add_child(h)
	var tag := K.hand(h, "Not:", 34, T.STAMP_RED)
	tag.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	tip_label = K.label(h, "", 19, T.INK, "InkLabel")
	tip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip_label.custom_minimum_size = Vector2(480, 0)
	tip_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tip_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var hide := HBoxContainer.new()
	hide.add_theme_constant_override("separation", 6)
	hide.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(hide)
	K.keycap(hide, "H", 14)
	K.label(hide, "gizle", 15, T.INK_MUTED, "MutedLabel").vertical_alignment = VERTICAL_ALIGNMENT_CENTER


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
	h.resized.connect(func(): h.pivot_offset = h.size)
	root.add_child(h)
	corner_hint = h
	K.keycap(h, "Esc", 14)
	var l := K.label(h, "Duraklat", 15, T.TEXT, "MutedLabel")
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	# elde tutulan parça / alet kartı (sağ alt, Esc ipucunun üstünde)
	var hc := K.panel(root, "HudCard")
	hc.add_theme_stylebox_override("panel", T.flat(Color(0.06, 0.075, 0.11, 0.88), 7, Color(0.25, 0.32, 0.42, 0.72), 1, Vector2(10, 7), 4))
	hc.anchor_left = 1.0
	hc.anchor_right = 1.0
	hc.anchor_top = 1.0
	hc.anchor_bottom = 1.0
	hc.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	hc.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hc.offset_left = -20
	hc.offset_right = -20
	hc.offset_top = -56
	hc.offset_bottom = -56
	hc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hc.resized.connect(func(): hc.pivot_offset = hc.size)
	hc.visible = false
	_held_card = hc
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hc.add_child(hb)
	_held_accent = ColorRect.new()
	_held_accent.custom_minimum_size = Vector2(3, 0)
	_held_accent.color = T.ACCENT
	_held_accent.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(_held_accent)
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", 1)
	hv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(hv)
	_held_lbl = K.label(hv, "", 14, T.TEXT, "BoldLabel")
	_held_sub = K.label(hv, "", 11, T.MUTED)


# ---------------------------------------------------------------- modallar
## Gün sonu: yazar kasanın "Z Raporu" fişi.
func _build_summary(root: Control) -> void:
	var m := K.modal(root, 520, 0.72)
	summary_root = m[0]
	summary_panel = m[1]
	summary_panel.theme_type_variation = "ReceiptPanel"
	var vb: VBoxContainer = m[2]
	vb.add_theme_constant_override("separation", 6)
	var shop := K.label(vb, "*** BİLGİSAYARCI ***", 26, T.INK, "ReceiptLabel")
	shop.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var addr := K.label(vb, "Mahalle Cd. No:12  ·  Tel: 0212 555 01 23", 20, T.INK_MUTED, "ReceiptLabel")
	addr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	summary_title = K.label(vb, "", 44, T.INK, "SignLabel")
	summary_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var sub := K.label(vb, "", 22, T.INK_MUTED, "ReceiptLabel")
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_summary_sub = sub
	_receipt_rule(vb)
	summary_rows = VBoxContainer.new()
	summary_rows.add_theme_constant_override("separation", 0)
	vb.add_child(summary_rows)
	_receipt_rule(vb)
	summary_note = K.label(vb, "", 22, T.INK, "ReceiptLabel")
	summary_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	summary_note.custom_minimum_size = Vector2(440, 0)
	summary_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var thanks := K.label(vb, "MALİ DEĞERİ YOKTUR  ·  TEŞEKKÜRLER", 19, T.INK_MUTED, "ReceiptLabel")
	thanks.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	K.spacer(vb, 4)
	summary_btn = K.button(vb, "Sonraki Gün  ›", func():
		K.close(summary_root, summary_panel)
		Game.next_day()
		_capture(), "PrimaryButton", 23, Vector2(0, 58))


func _receipt_rule(parent: Control) -> void:
	var l := K.label(parent, "- - - - - - - - - - - - - - - - - - - - - - - - - - - -", 20, T.INK_MUTED, "ReceiptLabel")
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.clip_text = true


## İflas: metal plakanın üstüne basılmış kırmızı "KAPANDI" mührü.
func _build_over(root: Control) -> void:
	var m := K.modal(root, 560, 0.8)
	over_root = m[0]
	over_panel = m[1]
	var vb: VBoxContainer = m[2]
	K.title(vb, "İflas Ettin", 40, T.BAD)
	K.spacer(vb, 4)
	var sh := CenterContainer.new()
	vb.add_child(sh)
	K.stamp(sh, "DÜKKÂN KAPANDI", T.BAD, 34, -8.0)
	K.spacer(vb, 4)
	over_text = K.label(vb, "", 19, T.TEXT)
	over_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	over_text.custom_minimum_size = Vector2(480, 0)
	over_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	K.spacer(vb, 6)
	K.button(vb, "Yeni Oyun", func():
		K.close(over_root, over_panel)
		Game.new_game()
		_capture(), "PrimaryButton", 22, Vector2(0, 56))
	K.button(vb, "Ana Menü", func():
		Game.return_to_menu(), "", 20, Vector2(0, 50))


func _build_upgrades(root: Control) -> void:
	office = OFFICE.new()
	office.back.connect(close_upgrades)
	root.add_child(office)


# ---------------------------------------------------------------- dış API
## Tezgahtaki laptop: ParçaNet / Kargo / Geliştirmeler / Dükkân.
func open_upgrades(page := 0) -> void:
	office.open(page)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close_upgrades() -> void:
	office.close()
	_capture()


func _capture() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func open_pause() -> void:
	pause.open()


func _stars_text(r: float) -> String:
	return "%.1f" % r


func _on_money(v: int) -> void:
	var old := _money_target
	_money_target = v
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
		var fc := Color("e8ffe0") if v > old else Color("ff8a6a")
		money_label.add_theme_color_override("font_color", fc)
		_money_flash = create_tween()
		_money_flash.tween_interval(0.5)
		_money_flash.tween_method(func(t: float): money_label.add_theme_color_override("font_color", fc.lerp(T.LCD, t)), 0.0, 1.0, 0.5)


func _set_money_shown(x: float) -> void:
	_money_shown = x
	money_label.text = K.money(roundi(x))


func _on_rep(r: float) -> void:
	(rep_stars as Object).set("value", r)
	rep_label.text = _stars_text(r)


func _row(label_text: String, value_text: String, color := T.INK, big := false) -> void:
	var h := HBoxContainer.new()
	summary_rows.add_child(h)
	var l := K.label(h, label_text.to_upper(), 30 if big else 25, T.INK if big else T.INK_MUTED, "ReceiptLabel")
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var r := K.label(h, value_text, 32 if big else 25, color, "ReceiptLabel")
	r.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT


func _on_day_ended(s: Dictionary) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	summary_title.text = "Z RAPORU"
	_summary_sub.text = "GÜN %d  ·  KAPANIŞ 19:00  ·  FİŞ NO %04d" % [s.day, 1000 + s.day]
	for c in summary_rows.get_children():
		c.free()
	var green := T.STAMP_GREEN
	var red := T.STAMP_RED
	_row("Tamamlanan iş", "%d ADET" % s.jobs)
	if int(s.get("sales", 0)) > 0:
		_row("Tezgah satışı", "%d PARÇA" % s.sales)
	if int(s.get("open_jobs", 0)) > 0:
		_row("Rafta açık iş", "%d ADET" % int(s.open_jobs))
	_row("Gelir", "+%s TL" % K.money(s.income), green)
	_row("Parça siparişi", "-%s TL" % K.money(s.parts), red)
	if int(s.get("shipping", 0)) > 0:
		_row("Kargo", "-%s TL" % K.money(s.shipping), red)
	_row("Kira", "-%s TL" % K.money(s.rent), red)
	if int(s.get("utility", 0)) > 0:
		_row("Elektrik faturası", "-%s TL" % K.money(s.utility), red)
	if int(s.get("wages", 0)) > 0:  # PERSONEL
		_row("Maaşlar", "-%s TL" % K.money(int(s.wages)), red)
	_receipt_rule(summary_rows)
	_row("Net kazanç", "%s%s TL" % ["+" if s.net >= 0 else "", K.money(s.net)], green if s.net >= 0 else red, true)
	var d: float = s.rep_delta
	var rh := HBoxContainer.new()
	rh.add_theme_constant_override("separation", 10)
	summary_rows.add_child(rh)
	var rl := K.label(rh, "İTİBAR", 25, T.INK_MUTED, "ReceiptLabel")
	rl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var st := K.stars(rh, 19, Color(T.INK.r, T.INK.g, T.INK.b, 0.15), T.INK)
	st.set("value", s.rep)
	st.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var dl := K.label(rh, "(%+.1f)" % d, 25, green if d >= 0 else red, "ReceiptLabel")
	dl.custom_minimum_size = Vector2(64, 0)
	dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_row("Kasa", "%s TL" % K.money(s.money), T.INK if s.money >= 0 else red, true)
	summary_note.text = ("!! DİKKAT: KASA EKSİDE !!\nYarın da eksi kalırsa iflas.\n" if s.warn else "") \
		+ ("Garanti dönüşü bekleyen: %d iş\n" % int(s.warranty_pending) if int(s.get("warranty_pending", 0)) > 0 else "") \
		+ "Yarınki kira: %s TL" % K.money(s.next_rent)
	summary_note.add_theme_color_override("font_color", red if s.warn else T.INK)
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
		var amber := Color("d98a0b")
		if f > 0.5:
			c = amber.lerp(T.STAMP_GREEN, (f - 0.5) * 2.0)
		else:
			c = T.STAMP_RED.lerp(amber, f * 2.0)
		_pfill.modulate_color = c


## Ödemede yukarı süzülen "+250 TL" ve para kartında parlama.
func pop_money(amount: int) -> void:
	var l := K.label(_ui_root, "%s%s TL" % ["+" if amount >= 0 else "-", K.money(absi(amount))], 38, T.GOOD if amount >= 0 else T.BAD, "SignLabel")
	l.add_theme_constant_override("outline_size", 12)
	l.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.06, 0.9))
	var y0 := money_card_bottom() + 8.0
	l.position = Vector2(30, y0)
	l.modulate.a = 0.0
	var tw := l.create_tween()
	tw.set_parallel(true)
	tw.tween_property(l, "modulate:a", 1.0, 0.15)
	tw.tween_property(l, "position:y", y0 - 27.0, 1.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.5).set_delay(1.1)
	tw.chain().tween_callback(l.queue_free)


func set_job(title: String, desc: String, ticket := -1) -> void:
	var parts := title.split(" — ")
	var is_job := parts.size() > 1
	job_name.text = parts[0]
	job_who.text = "MÜŞTERİ" if is_job else "DURUM"
	job_pay_pill.visible = is_job
	if is_job:
		job_pay.text = parts[1]
		if parts[0] != _last_job:
			_last_job = parts[0]
			# yeni fiş: hafif sallanma
			var tw := _job_holder.create_tween()
			tw.tween_property(_job_holder, "rotation_degrees", -2.5, 0.12).set_ease(Tween.EASE_OUT)
			tw.tween_property(_job_holder, "rotation_degrees", 0.8, 0.5).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	job_no.text = "No. %04d" % ticket if ticket >= 0 else "No. ----"
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
	while toasts.get_child_count() > 4:
		toasts.get_child(0).free()
	var wrap := Control.new()
	wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toasts.add_child(wrap)
	var inner := K.panel(wrap, "Toast")
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := T.flat(Color(0.07, 0.075, 0.09, 0.94), 4, col, 0, Vector2(14, 9), 8)
	sb.border_width_left = 5
	inner.add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	inner.add_child(h)
	# durum LED'i
	var led := PanelContainer.new()
	var ls := T.flat(col, 6, col.lightened(0.5), 1, Vector2(0, 0))
	ls.shadow_color = Color(col.r, col.g, col.b, 0.55)
	ls.shadow_size = 6
	led.add_theme_stylebox_override("panel", ls)
	led.custom_minimum_size = Vector2(11, 11)
	led.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	led.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(led)
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
		if Game.bench_active:  # tezgâh modu Esc'i kendisi işler
			return
		if office.is_open():
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
	Game.ui_modal = summary_root.visible or over_root.visible or office.is_open() or pause.open_now
	Game.running = (captured or Game.bench_active) and Game.started and not Game.paused
	if fps_label.visible:
		_fps_t += delta
		if _fps_t >= 0.25:
			_fps_t = 0.0
			fps_label.text = "FPS: %d   Draw call: %d" % [Engine.get_frames_per_second(),
				RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)]
	_jobs_t -= delta
	if _jobs_t <= 0.0:
		_jobs_t = 1.0
		_rebuild_jobs()
	var minute := int(Game.clock * 60.0)
	var txt := "%d:%d" % [Game.day, minute]
	if txt != _clock_cache:
		_clock_cache = txt
		day_label.text = "GÜN %02d" % Game.day
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
	_refresh_held_card(p)


func _refresh_held_card(p) -> void:
	if _held_card == null:
		return
	var h = p.held if (p != null and not Game.bench_active and Game.started and Game.phase == "day") else null
	if h == null or not is_instance_valid(h):
		_held_card.visible = false
		_held_sig = ""
		return
	var tag := ""
	var col := T.INFO
	if h.has_method("is_tool") and h.is_tool():
		tag = "Alet"
		col = T.INFO
	else:
		var otag := str(h.origin_tag()) if h.has_method("origin_tag") else ""
		var orig := str(h.get("origin")) if "origin" in h else ""
		if orig == "stock":
			col = T.GOOD
		elif orig == "customer":
			col = T.ACCENT
		elif "is_test_part" in h and h.is_test_part:
			col = T.INFO
		tag = otag if otag != "" else "Parça"
		if Game.has_upgrade("multimeter") and "broken" in h and h.broken:
			tag += " · ARIZALI"
			col = T.BAD
	var pdi: Dictionary = p.put_down_info() if p.has_method("put_down_info") else {}
	var drop_lbl := str(pdi.get("label", "Bırak"))
	var sig := "%s|%s|%s|%s" % [str(h.display_name), tag, str(col), drop_lbl]
	if sig != _held_sig:
		_held_sig = sig
		_held_lbl.text = str(h.display_name)
		_held_sub.text = "%s  ·  [Sağ Tık / G] %s" % [tag, drop_lbl]
		_held_sub.add_theme_color_override("font_color", col)
		_held_accent.color = col
		_held_card.reset_size()
		_held_card.pivot_offset = _held_card.size
	_held_card.visible = true


## Para kartının altında: yoldaki/kapıdaki kargo sayısı ve en yakın varış.
func _refresh_cargo() -> void:
	if cargo_row == null:
		return
	var n := Game.orders.size()
	cargo_row.visible = n > 0
	if n == 0:
		return
	var door := Game.orders.filter(func(o): return o.get("state", "") == "door").size()
	if door > 0:
		cargo_label.text = "%d koli kapıda — aç!" % door
		cargo_label.add_theme_color_override("font_color", T.GOOD)
		return
	var eta := 1e9
	for o in Game.orders:
		eta = minf(eta, float(o.eta))
	cargo_label.text = "Kargo yolda (%d) · %s" % [n, Game.abs_time_text(eta)]
	cargo_label.add_theme_color_override("font_color", T.TEXT)
