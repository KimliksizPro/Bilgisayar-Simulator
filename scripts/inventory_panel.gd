extends CanvasLayer
## Atölye dolabı: görselli parça gözleri, kategori çekmeceleri ve parça kartı.

const T := preload("res://scripts/ui_theme.gd")
const K := preload("res://scripts/ui_kit.gd")
const PM := preload("res://scripts/part_models.gd")
const PREVIEW := preload("res://scripts/part_preview.gd")
const DEEP := T.BG
const SLOT := T.PANEL2
const CREAM := T.TEXT
const MUTED := T.MUTED
const INK := T.INK
const GOLD := T.ACCENT
const GREEN := T.GOOD
const CATS := [
	{"id": "all", "label": "Tüm parçalar", "cats": []},
	{"id": "mobo", "label": "Anakart", "cats": ["mobo"]},
	{"id": "cpu", "label": "İşlemci", "cats": ["cpu"]},
	{"id": "ram", "label": "Bellek", "cats": ["ram"]},
	{"id": "gpu", "label": "Ekran kartı", "cats": ["gpu"]},
	{"id": "storage", "label": "Depolama", "cats": ["ssd", "nvme", "hdd"]},
	{"id": "psu", "label": "Güç kaynağı", "cats": ["psu"]},
	{"id": "cooling", "label": "Soğutma", "cats": ["cooler", "fan"]},
	{"id": "other", "label": "Diğer", "cats": ["cmos"]},
]

signal pick_requested(sku_id: String, cheap: bool)
signal return_requested

var _root: Control
var _panel: PanelContainer
var _cat_id := "all"
var _selected_sku := ""
var _cat_btns := {}
var _stock_only := false
var _compat_only := false
var _stock_only_btn: Button
var _compat_only_btn: Button
var _search: LineEdit
var _bench_l: Label
var _total_l: Label
var _result_l: Label
var _held_l: Label
var _return_btn: Button
var _empty_l: Label
var _grid: GridContainer
var _scroll: ScrollContainer
var _cards := {}
var _detail_name: Label
var _detail_brand: Label
var _detail_spec: Label
var _detail_compat: Label
var _detail_stock: Label
var _detail_orig: Button
var _detail_cheap: Button
var _preview_tex: TextureRect
var _preview: SubViewport
var _thumb_stage: SubViewport
var _thumb_pending: Array[String] = []
var _baking := false
var _closing := false
var _modal_tween: Tween


func _ready() -> void:
	layer = 10
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.visible = false
	add_child(_root)
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.02, 0.05, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)
	_panel = PanelContainer.new()
	_panel.theme_type_variation = "ModalPanel"
	_panel.add_theme_stylebox_override("panel", T.plate_box(T.PANEL, true, Vector2(25, 24)))
	_root.add_child(_panel)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 13)
	_panel.add_child(layout)
	_build_header(layout)
	var stripe := TextureRect.new()
	stripe.texture = T.hazard_tex()
	stripe.stretch_mode = TextureRect.STRETCH_TILE
	stripe.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stripe.custom_minimum_size.y = 5
	stripe.modulate.a = 0.8
	layout.add_child(stripe)
	_build_held_bar(layout)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	layout.add_child(body)
	_build_categories(body)
	_build_grid(body)
	_build_detail(body)
	_build_footer(layout)
	if DisplayServer.get_name() != "headless":
		_preview = PREVIEW.new()
		add_child(_preview)
		_preview_tex.texture = _preview.get_texture()
		_thumb_stage = PREVIEW.new()
		add_child(_thumb_stage)
		_thumb_stage.size = Vector2i(256, 152)
	_root.resized.connect(_fit)
	_fit.call_deferred()
	Game.stock_changed.connect(func(): if is_open(): refresh())
	Game.bench_changed.connect(func(_d): if is_open(): refresh())


func _build_header(parent: Control) -> void:
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 18)
	parent.add_child(head)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	titles.add_theme_constant_override("separation", 0)
	head.add_child(titles)
	K.label(titles, "PARÇA DOLABI", 32, T.ACCENT, "TitleLabel")
	K.label(titles, "ENVANTER   /   Parçayı seç, incele ve eline al.", 14, MUTED)
	var counts := VBoxContainer.new()
	counts.add_theme_constant_override("separation", 2)
	counts.custom_minimum_size.x = 245
	head.add_child(counts)
	_total_l = K.label(counts, "", 22, T.LCD, "LcdLabel")
	_total_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_bench_l = K.label(counts, "", 13, MUTED)
	_bench_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT


func _build_held_bar(parent: Control) -> void:
	var bar := K.panel(parent)
	bar.theme_type_variation = "InsetPanel"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	bar.add_child(row)
	_held_l = K.label(row, "", 14, MUTED)
	_held_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_held_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_held_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_return_btn = _button(row, "DOLABA GERİ KOY", func():
		return_requested.emit()
		refresh(), true, 13, Vector2(184, 30))


func _build_categories(parent: Control) -> void:
	var nav := VBoxContainer.new()
	nav.custom_minimum_size.x = 170
	nav.add_theme_constant_override("separation", 5)
	parent.add_child(nav)
	K.label(nav, "ÇEKMECELER", 13, MUTED, "BoldLabel")
	K.spacer(nav, 5)
	var group := ButtonGroup.new()
	for c in CATS:
		var cid: String = c.id
		var b := _button(nav, c.label, func(): _set_category(cid), false, 15, Vector2(170, 39))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggle_mode = true
		b.button_group = group
		_cat_btns[cid] = b
	var gap := Control.new()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	nav.add_child(gap)
	var paper := K.panel(nav)
	paper.theme_type_variation = "StickyNote"
	var note := K.label(paper, "Önce test et,\nsonra değiştir.", 24, T.PEN, "HandLabel")
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _build_grid(parent: Control) -> void:
	var middle := VBoxContainer.new()
	middle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle.add_theme_constant_override("separation", 9)
	parent.add_child(middle)
	_search = LineEdit.new()
	_search.placeholder_text = "Parça ara…  /  ad, marka, soket"
	_search.clear_button_enabled = true
	_search.custom_minimum_size.y = 39
	_search.add_theme_stylebox_override("normal", T.flat(DEEP, 6, T.BORDER, 1, Vector2(12, 6)))
	_search.add_theme_stylebox_override("focus", T.flat(DEEP, 3, GOLD, 1, Vector2(12, 6)))
	_search.add_theme_color_override("font_color", CREAM)
	_search.add_theme_color_override("font_placeholder_color", MUTED)
	_search.add_theme_font_size_override("font_size", 15)
	middle.add_child(_search)
	_search.text_changed.connect(func(_s):
		_scroll.scroll_vertical = 0
		refresh())
	var filters := HBoxContainer.new()
	filters.add_theme_constant_override("separation", 8)
	middle.add_child(filters)
	_stock_only_btn = _button(filters, "Stoktakiler", func():
		_stock_only = _stock_only_btn.button_pressed
		refresh(), false, 13, Vector2(0, 29))
	_stock_only_btn.toggle_mode = true
	_compat_only_btn = _button(filters, "Uyumlu parçalar", func():
		_compat_only = _compat_only_btn.button_pressed
		refresh(), false, 13, Vector2(0, 29))
	_compat_only_btn.toggle_mode = true
	_result_l = K.label(filters, "", 13, MUTED)
	_result_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_result_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_result_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	middle.add_child(_scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(content)
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 9)
	_grid.add_theme_constant_override("v_separation", 9)
	content.add_child(_grid)
	for d in DB.parts.shelf_items(["pc"]):
		_build_card(d)
	_empty_l = K.label(content, "Bu gözlerde parça bulunamadı.\nAramayı veya filtreleri değiştirebilirsin.", 17, MUTED)
	_empty_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_l.custom_minimum_size.y = 150



func _build_card(d: PartDef) -> void:
	var sku: String = d.id
	var card := Button.new()
	card.custom_minimum_size = Vector2(205, 175)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.toggle_mode = true
	card.clip_contents = true
	card.tooltip_text = d.name + "\n" + _spec_text(d)
	card.add_theme_stylebox_override("normal", T.flat(SLOT, 6, T.BORDER, 1, Vector2.ZERO))
	card.add_theme_stylebox_override("hover", T.flat(T.PANEL3, 6, GOLD.darkened(0.25), 1, Vector2.ZERO))
	card.add_theme_stylebox_override("pressed", T.flat(T.PANEL3, 6, GOLD, 2, Vector2.ZERO))
	card.add_theme_stylebox_override("hover_pressed", T.flat(T.PANEL3.lightened(0.06), 6, GOLD, 2, Vector2.ZERO))
	card.add_theme_stylebox_override("focus", T.flat(Color.TRANSPARENT, 3, GOLD, 1, Vector2.ZERO))
	_grid.add_child(card)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10 if side in ["left", "right"] else 7)
	card.add_child(margin)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 1)
	margin.add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	var brand := K.label(top, d.brand.to_upper(), 11, MUTED, "BoldLabel")
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	brand.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var stock := K.label(top, "", 11, GOLD, "BoldLabel")
	var thumb := TextureRect.new()
	thumb.custom_minimum_size.y = 83
	thumb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	thumb.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	thumb.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	v.add_child(thumb)
	var name_l := K.label(v, d.name, 14, CREAM, "BoldLabel")
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_l.custom_minimum_size.y = 37
	name_l.max_lines_visible = 2
	name_l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var spec := K.label(v, _spec_text(d), 11, MUTED)
	spec.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_ignore_input(margin)
	card.pressed.connect(func():
		Game.sfx.ui_click()
		_select(sku))
	card.mouse_entered.connect(func(): Game.sfx.ui_hover())
	_cards[sku] = {"panel": card, "def": d, "stock": stock, "thumb": thumb, "count": 0}
	_thumb_pending.append(sku)


func _build_detail(parent: Control) -> void:
	var paper := K.panel(parent)
	paper.custom_minimum_size.x = 320
	paper.theme_type_variation = "ReceiptPanel"
	paper.add_theme_stylebox_override("panel", T.paper_box(false, true, Vector2(18, 14), T.PAPER))
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 7)
	paper.add_child(v)
	K.label(v, "PARÇA KARTI", 24, T.INK, "ReceiptLabel")
	var stage := K.panel(v)
	stage.add_theme_stylebox_override("panel", T.flat(DEEP, 6, T.BORDER, 1, Vector2(8, 4)))
	_preview_tex = TextureRect.new()
	_preview_tex.custom_minimum_size = Vector2(0, 151)
	_preview_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_preview_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	stage.add_child(_preview_tex)
	_detail_brand = K.label(v, "", 12, T.INK_MUTED, "BoldLabel")
	_detail_brand.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_detail_name = K.label(v, "", 21, INK, "HeavyLabel")
	_detail_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_name.custom_minimum_size.y = 52
	_detail_spec = K.label(v, "", 14, T.INK_MUTED)
	_detail_spec.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_spec.custom_minimum_size.y = 43
	_detail_compat = K.label(v, "", 13, T.STAMP_GREEN, "BoldLabel")
	_detail_compat.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_compat.custom_minimum_size.y = 38
	var gap := Control.new()
	gap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(gap)
	_detail_stock = K.label(v, "", 15, INK, "BoldLabel")
	_detail_stock.custom_minimum_size.y = 27
	_detail_orig = _button(v, "ORİJİNALİ ELİNE AL", func(): _pick(_selected_sku, false), true, 15, Vector2(0, 40))
	_detail_cheap = _button(v, "MUADİLİ ELİNE AL", func(): _pick(_selected_sku, true), false, 14, Vector2(0, 37))


func _build_footer(parent: Control) -> void:
	var foot := HBoxContainer.new()
	foot.add_theme_constant_override("separation", 8)
	parent.add_child(foot)
	K.keycap(foot, "I", 14)
	K.keycap(foot, "Esc", 14)
	K.label(foot, "Dolabı kapat", 13, MUTED)
	var tip := K.label(foot, "Yeni parça siparişleri tezgahtaki laptoptan.", 13, MUTED)
	tip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_button(foot, "KAPAT", close, false, 14, Vector2(110, 35))


func _button(parent: Node, text: String, cb: Callable, primary := false, fs := 14, min_size := Vector2(0, 36)) -> Button:
	return K.button(parent, text, cb, "PrimaryButton" if primary else "SegButton", fs, min_size)


func _ignore_input(n: Control) -> void:
	n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for child in n.get_children():
		if child is Control:
			_ignore_input(child)


func _fit() -> void:
	if _grid == null:
		return
	var view := _root.size
	var compact := view.x < 1220
	_grid.columns = 2 if compact else 3
	var design := Vector2(1120 if compact else 1340, 800)
	design = design.max(_panel.get_combined_minimum_size())
	_panel.size = design
	var s := minf(1.0, minf((view.x - 40) / design.x, (view.y - 40) / design.y))
	_panel.scale = Vector2.ONE * maxf(s, 0.2)
	_panel.position = (view - _panel.size * _panel.scale) * 0.5


func is_open() -> bool:
	return _root != null and _root.visible and not _closing


func open() -> void:
	if is_open():
		return
	_closing = false
	if _modal_tween and _modal_tween.is_valid():
		_modal_tween.kill()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Game.ui_modal = true
	_root.visible = true
	_root.modulate.a = 0
	refresh()
	_fit()
	_modal_tween = create_tween()
	_modal_tween.tween_property(_root, "modulate:a", 1.0, 0.18)
	if _preview:
		_preview.set_active(_selected_sku != "", true)
	_bake_thumbnails()
	if _cat_btns.has(_cat_id):
		_cat_btns[_cat_id].grab_focus()


func close() -> void:
	if not is_open():
		return
	_closing = true
	if _preview:
		_preview.set_active(false)
	if _modal_tween and _modal_tween.is_valid():
		_modal_tween.kill()
	_modal_tween = create_tween()
	_modal_tween.tween_property(_root, "modulate:a", 0.0, 0.14)
	_modal_tween.tween_callback(func():
		_root.visible = false
		_closing = false
		if Game.started and Game.phase == "day" and not Game.bench_active and not Game.paused:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED)


func _process(_delta: float) -> void:
	if _root != null and _root.visible:
		Game.ui_modal = true
		# İlk container yerleşimindeki geçici minimum yüksekliğin kalmasını önle.
		_fit()


func _unhandled_input(event: InputEvent) -> void:
	if not is_open():
		return
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_I):
		Game.sfx.ui_back()
		close()
		get_viewport().set_input_as_handled()


func _input(event: InputEvent) -> void:
	# Arama alanı odağı Esc'i tüketse bile dolabı kapat; duraklatma menüsüne sızmasın.
	if is_open() and event.is_action_pressed("ui_cancel"):
		Game.sfx.ui_back()
		close()
		get_viewport().set_input_as_handled()


func _set_category(cid: String) -> void:
	_cat_id = cid
	_scroll.scroll_vertical = 0
	refresh()


func _select(sku: String) -> void:
	_selected_sku = sku
	for id in _cards:
		_cards[id].panel.set_pressed_no_signal(id == sku)
	_refresh_detail()


func _pick(sku: String, cheap: bool) -> void:
	if sku.is_empty():
		return
	var p = Game.player
	if Game.is_carrying() or (p != null and p.held != null):
		return
	if (Game.stock_cheap_of_sku(sku) if cheap else Game.stock_of_sku(sku)) <= 0:
		return
	pick_requested.emit(sku, cheap)
	if Game.player and Game.player.held != null:
		close()
	else:
		refresh()


func _bench_pc_state() -> Dictionary:
	var dev = Game.bench_device
	if is_instance_valid(dev) and dev.has_method("case_state"):
		return dev.case_state()
	return {}



func refresh() -> void:
	var st := _bench_pc_state()
	var has_pc := not st.is_empty()
	_compat_only_btn.visible = has_pc
	if not has_pc:
		_compat_only = false
	_stock_only_btn.set_pressed_no_signal(_stock_only)
	_compat_only_btn.set_pressed_no_signal(_compat_only)
	if has_pc:
		var w := Compatibility.calc_watts(st)
		_bench_l.text = "TEZGÂH  /  %d W yük · %d W PSU" % [int(w.draw), int(w.psu)]
		_bench_l.add_theme_color_override("font_color", GREEN if w.ok else GOLD)
	else:
		_bench_l.text = "TEZGÂH  /  PC bağlı değil"
		_bench_l.add_theme_color_override("font_color", MUTED)
	var allow_cats: Array = []
	for c in CATS:
		if c.id == _cat_id:
			allow_cats = c.cats
	var shown: Array[String] = []
	var count := 0
	var stocked := 0
	var query := _search.text.strip_edges().to_lower()
	for sku in _cards:
		var card: Dictionary = _cards[sku]
		var d: PartDef = card.def
		var amount := Game.stock_of_sku(sku) + Game.stock_cheap_of_sku(sku)
		card.count = amount
		count += amount
		if amount > 0:
			stocked += 1
		card.stock.text = "%02d ADET" % amount if amount > 0 else "STOK YOK"
		card.stock.add_theme_color_override("font_color", GOLD if amount > 0 else MUTED.darkened(0.15))
		card.thumb.modulate = Color.WHITE if amount > 0 else Color(0.6, 0.65, 0.64, 0.6)
		var visible: bool = allow_cats.is_empty() or allow_cats.has(d.category)
		visible = visible and (not _stock_only or amount > 0)
		if query != "" and not (d.name + " " + d.brand + " " + _spec_text(d) + " " + sku).to_lower().contains(query):
			visible = false
		if _compat_only and Compatibility.check_catalog_part(d, st).severity == "block":
			visible = false
		card.panel.visible = visible
		if visible:
			shown.append(sku)
	for c in CATS:
		var available := 0
		for card in _cards.values():
			if c.cats.is_empty() or c.cats.has(card.def.category):
				available += int(card.count)
		_cat_btns[c.id].text = "%s   /  %02d" % [c.label, available]
		_cat_btns[c.id].set_pressed_no_signal(c.id == _cat_id)
	_total_l.text = "%02d PARÇA   /   %02d ÇEŞİT STOKTA" % [count, stocked]
	_result_l.text = "%d parça çeşidi" % shown.size()
	_empty_l.visible = shown.is_empty()
	if not shown.has(_selected_sku):
		_selected_sku = ""
		for sku in shown:
			if int(_cards[sku].count) > 0:
				_selected_sku = sku
				break
		if _selected_sku == "" and not shown.is_empty():
			_selected_sku = shown[0]
	_select(_selected_sku)
	_refresh_held()


func _refresh_held() -> void:
	var p = Game.player
	_return_btn.visible = false
	_held_l.add_theme_color_override("font_color", MUTED)
	if p != null and p.held != null:
		var h = p.held
		var can_return: bool = not h.is_tool() and not h.broken
		var from_customer: bool = "origin" in h and str(h.origin) == "customer"
		var tag := str(h.origin_tag()) if h.has_method("origin_tag") else ""
		_held_l.text = "ELİNDE  /  " + h.display_name + ("  [" + tag + "]" if tag != "" else "")
		if not can_return:
			_held_l.text += " — Dolaba konmaz"
		_held_l.add_theme_color_override("font_color", GOLD)
		_return_btn.visible = can_return
		_return_btn.text = "KENDİNE AL (STOĞA)" if from_customer else "DOLABA GERİ KOY"
	elif Game.is_carrying():
		_held_l.text = "CİHAZ TAŞIYORSUN  /  Önce tezgâha veya rafa bırak."
	else:
		_held_l.text = "ELLERİN BOŞ  /  Raftan bir parça seç, kartını incele ve eline al."


func _refresh_detail() -> void:
	var valid := _cards.has(_selected_sku)
	_preview_tex.visible = valid
	_detail_orig.disabled = true
	_detail_cheap.disabled = true
	if not valid:
		_detail_brand.text = "BOŞ GÖZ"
		_detail_name.text = "Parça seçilmedi"
		_detail_spec.text = "Aramayı veya filtreleri değiştir."
		_detail_compat.text = ""
		_detail_stock.text = ""
		if _preview:
			_preview.set_active(false)
		return
	var d: PartDef = _cards[_selected_sku].def
	_detail_brand.text = d.brand.to_upper() + "  /  " + PM.type_name(d.category).to_upper()
	_detail_name.text = d.name
	_detail_spec.text = _spec_text(d)
	var st := _bench_pc_state()
	if st.is_empty():
		_detail_compat.text = "Uyumluluk için tezgâha bir PC yerleştir."
		_detail_compat.add_theme_color_override("font_color", T.INK_MUTED)
	else:
		var check := Compatibility.check_catalog_part(d, st)
		_detail_compat.text = "UYUMLU  /  Tezgâhtaki PC'ye takılabilir." if check.severity == "ok" else str(check.reason)
		_detail_compat.add_theme_color_override("font_color", T.STAMP_RED if check.severity == "block" else (T.INK_MUTED if check.severity == "warn" else T.STAMP_GREEN))
	var orig := Game.stock_of_sku(d.id)
	var cheap := Game.stock_cheap_of_sku(d.id)
	_detail_stock.text = "Orijinal: %02d     /     Muadil: %02d" % [orig, cheap]
	var p = Game.player
	var full: bool = (p != null and p.held != null) or Game.is_carrying()
	_detail_orig.disabled = full or orig <= 0
	_detail_cheap.disabled = full or cheap <= 0
	_detail_orig.text = "ELİN DOLU" if full else ("ORİJİNALİ ELİNE AL" if orig > 0 else "ORİJİNAL STOKTA YOK")
	_detail_cheap.text = "MUADİLİ ELİNE AL" if cheap > 0 else "MUADİL STOKTA YOK"
	if _preview:
		_preview.show_sku(d.id)
		_preview.set_active(is_open(), true)


func _bake_thumbnails() -> void:
	if _baking or _thumb_stage == null or not is_open():
		return
	_baking = true
	while not _thumb_pending.is_empty() and is_open():
		# Önce o an görünen çekmeceyi doldur.
		var sku: String = _thumb_pending[0]
		for pending in _thumb_pending:
			if _cards[pending].panel.visible:
				sku = pending
				break
		_thumb_pending.erase(sku)
		_thumb_stage.show_sku(sku)
		_thumb_stage.set_active(true)
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		if not is_instance_valid(_thumb_stage):
			return
		var img := _thumb_stage.get_texture().get_image()
		if img != null and not img.is_empty():
			img.generate_mipmaps()
			_cards[sku].thumb.texture = ImageTexture.create_from_image(img)
	_thumb_stage.set_active(false)
	_baking = false


## Parça için kısa teknik özet (soket, DDR, watt, boyut vb.).
static func _spec_text(d: PartDef) -> String:
	if d == null:
		return ""
	var parts: Array[String] = []
	var s := d.specs
	var c := d.compat
	if c.has("form_factor"):
		parts.append(str(c.form_factor))
	if c.has("socket"):
		parts.append(str(c.socket))
	if c.has("ram_type"):
		parts.append(str(c.ram_type))
	if s.has("gb"):
		parts.append("%d GB" % int(s.gb))
	if s.has("vram"):
		parts.append("%d GB VRAM" % int(s.vram))
	if s.has("watts"):
		parts.append("%dW" % int(s.watts))
	if s.has("tdp"):
		parts.append("%dW TDP" % int(s.tdp))
	if s.has("length_mm"):
		parts.append("%dmm" % int(s.length_mm))
	if s.has("height_mm"):
		parts.append("%dmm" % int(s.height_mm))
	if s.has("radiator_mm"):
		parts.append("%dmm AIO" % int(s.radiator_mm))
	if s.has("igpu"):
		parts.append("iGPU" if bool(s.igpu) else "iGPU yok")
	return " · ".join(parts)
