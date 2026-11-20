extends CanvasLayer
## Parça Dolabı arayüzü: kategori sekmeleri, stok (orijinal/muadil), tezgâh PC uyumluluk rozeti
## ve tek tıkla "Eline Al" / "Muadil Al" düğmeleri.

const T := preload("res://scripts/ui_theme.gd")
const K := preload("res://scripts/ui_kit.gd")
const PM := preload("res://scripts/part_models.gd")

const CATS := [
	{"id": "all", "label": "Tümü", "cats": []},
	{"id": "mobo", "label": "Anakart", "cats": ["mobo"]},
	{"id": "cpu", "label": "CPU", "cats": ["cpu"]},
	{"id": "ram", "label": "RAM", "cats": ["ram"]},
	{"id": "gpu", "label": "GPU", "cats": ["gpu"]},
	{"id": "storage", "label": "Depolama", "cats": ["ssd", "nvme", "hdd"]},
	{"id": "psu", "label": "PSU", "cats": ["psu"]},
	{"id": "cooling", "label": "Soğutma", "cats": ["cooler", "fan"]},
	{"id": "other", "label": "Diğer", "cats": ["cmos"]},
]

signal pick_requested(sku_id: String, cheap: bool)
signal return_requested

var _root: Control
var _panel: Control
var _cat_id := "all"
var _cat_btns := {}        # cat_id -> Button
var _stock_only := false
var _compat_only := false
var _stock_only_btn: Button
var _compat_only_btn: Button
var _bench_l: Label
var _held_row: Control
var _held_l: Label
var _return_btn: Button
var _empty_l: Label
var _rows := {}            # sku -> {panel, def, stock_orig, stock_cheap, compat, btn_orig, btn_cheap}


func _ready() -> void:
	layer = 10
	var m := K.modal(self, 960, 0.72)
	_root = m[0]
	_panel = m[1]
	var vb: VBoxContainer = m[2]

	# başlık + tezgâh PC bilgisi
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	vb.add_child(head)
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_theme_constant_override("separation", 0)
	head.add_child(tv)
	K.label(tv, "Parça Dolabı", 32, T.ACCENT, "TitleLabel")
	K.label(tv, "Stoktaki PC parçalarını seçip eline alabilirsin. Sipariş için tezgahtaki laptopu kullan.", 15, T.MUTED, "MutedLabel")
	_bench_l = K.label(head, "", 14, T.INFO, "BoldLabel")
	_bench_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_bench_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	# elde parça varsa bilgi / iade çubuğu
	var hp := K.panel(vb, "InsetPanel")
	hp.add_theme_stylebox_override("panel", T.flat(Color(0.18, 0.14, 0.06, 0.55), 6, T.ACCENT_LO, 1, Vector2(12, 8)))
	_held_row = hp
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	hp.add_child(hbox)
	_held_l = K.label(hbox, "", 15, T.ACCENT_HI, "BoldLabel")
	_held_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_held_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_return_btn = K.button(hbox, "Dolaba Geri Koy", func():
		return_requested.emit()
		refresh(), "PrimaryButton", 15, Vector2(170, 36))
	hp.visible = false

	# kategori sekmeleri
	var cat_bar := HFlowContainer.new()
	cat_bar.add_theme_constant_override("h_separation", 6)
	cat_bar.add_theme_constant_override("v_separation", 6)
	vb.add_child(cat_bar)
	var cg := ButtonGroup.new()
	for c in CATS:
		var cid: String = c.id
		var cb := K.button(cat_bar, c.label, func():
			_cat_id = cid
			refresh(), "SegButton", 15, Vector2(0, 34))
		cb.toggle_mode = true
		cb.button_group = cg
		_cat_btns[cid] = cb

	# hızlı filtre çubuğu
	var fbar := HBoxContainer.new()
	fbar.add_theme_constant_override("separation", 8)
	vb.add_child(fbar)
	_stock_only_btn = K.button(fbar, "Sadece stokta", func():
		_stock_only = _stock_only_btn.button_pressed
		refresh(), "SegButton", 14, Vector2(0, 32))
	_stock_only_btn.toggle_mode = true
	_compat_only_btn = K.button(fbar, "Sadece uyumlu", func():
		_compat_only = _compat_only_btn.button_pressed
		refresh(), "SegButton", 14, Vector2(0, 32))
	_compat_only_btn.toggle_mode = true
	_compat_only_btn.visible = false

	# sütun başlıkları
	var hdr := HBoxContainer.new()
	hdr.add_theme_constant_override("separation", 0)
	vb.add_child(hdr)
	for col in [["PARÇA", 360], ["STOK", 150], ["UYUMLULUK", 170], ["İŞLEM", 210]]:
		var l := K.label(hdr, col[0], 12, T.MUTED, "SmallCaps")
		l.custom_minimum_size.x = col[1]

	# kaydırılabilir parça listesi
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, 370)
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(sc)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 5)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(list)

	for d in DB.parts.shelf_items(["pc"]):
		var sku_id: String = d.id
		var ip := K.panel(list, "InsetPanel")
		ip.add_theme_stylebox_override("panel", T.flat(Color(0, 0, 0, 0.25), 5, Color(1, 1, 1, 0.04), 1, Vector2(12, 6)))
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 0)
		ip.add_child(r)

		# parça adı + teknik özet
		var nm := VBoxContainer.new()
		nm.add_theme_constant_override("separation", -1)
		nm.custom_minimum_size.x = 360
		r.add_child(nm)
		K.label(nm, PM.display_name_sku(sku_id), 16, T.TEXT, "BoldLabel")
		var spec := _spec_text(d)
		if not spec.is_empty():
			K.label(nm, spec, 13, T.MUTED, "MutedLabel")

		# stok (orijinal + muadil)
		var sv := VBoxContainer.new()
		sv.add_theme_constant_override("separation", -2)
		sv.custom_minimum_size.x = 150
		sv.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		r.add_child(sv)
		var st_orig := K.label(sv, "", 15, T.TEXT, "BoldLabel")
		var st_cheap := K.label(sv, "", 13, T.ACCENT)

		# uyumluluk rozeti
		var cl := K.label(r, "", 13, T.GOOD, "BoldLabel")
		cl.custom_minimum_size.x = 170
		cl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

		# 1-tık alma düğmeleri
		var acts := HBoxContainer.new()
		acts.add_theme_constant_override("separation", 6)
		acts.custom_minimum_size.x = 210
		acts.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		r.add_child(acts)
		var b_orig := K.button(acts, "Eline Al", func(): _pick(sku_id, false), "PrimaryButton", 14, Vector2(96, 36))
		var b_cheap := K.button(acts, "Muadil Al", func(): _pick(sku_id, true), "SegButton", 14, Vector2(102, 36))

		_rows[sku_id] = {
			"panel": ip, "def": d, "stock_orig": st_orig, "stock_cheap": st_cheap,
			"compat": cl, "btn_orig": b_orig, "btn_cheap": b_cheap,
		}

	_empty_l = K.label(list, "Bu filtrede gösterilecek parça yok.", 16, T.MUTED, "MutedLabel")
	_empty_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_l.visible = false

	K.hsep(vb)
	var foot := HBoxContainer.new()
	vb.add_child(foot)
	K.label(foot, "Esc veya I: kapat", 15, Color(1, 1, 1, 0.35), "MutedLabel").size_flags_horizontal = Control.SIZE_EXPAND_FILL
	K.button(foot, "Kapat", close, "", 18, Vector2(140, 44))

	Game.stock_changed.connect(func(): if is_open(): refresh())
	Game.bench_changed.connect(func(_d): if is_open(): refresh())


func is_open() -> bool:
	return _root != null and _root.visible


func open() -> void:
	if is_open():
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	Game.ui_modal = true
	refresh()
	K.open(_root, _panel)
	if _cat_btns.has(_cat_id):
		_cat_btns[_cat_id].grab_focus()


func close() -> void:
	if not is_open():
		return
	K.close(_root, _panel)
	if Game.started and Game.phase == "day" and not Game.bench_active and not Game.paused:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _process(_delta: float) -> void:
	# hud._process her karede Game.ui_modal'ı sıfırlar; açıkken modal durumunu koru
	if is_open():
		Game.ui_modal = true


func _unhandled_input(event: InputEvent) -> void:
	if not is_open():
		return
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_I):
		Game.sfx.ui_back()
		close()
		get_viewport().set_input_as_handled()


func _pick(sku_id: String, cheap: bool) -> void:
	pick_requested.emit(sku_id, cheap)
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
	for cid in _cat_btns:
		_cat_btns[cid].set_pressed_no_signal(cid == _cat_id)
	_stock_only_btn.set_pressed_no_signal(_stock_only)

	var st := _bench_pc_state()
	var has_pc := not st.is_empty()
	_compat_only_btn.visible = has_pc
	if not has_pc:
		_compat_only = false
	_compat_only_btn.set_pressed_no_signal(_compat_only)
	if has_pc:
		var cname := str(st.case_def.get("name", "PC"))
		var w := Compatibility.calc_watts(st)
		_bench_l.text = "Tezgâh: %s\nGüç: %dW / %dW" % [cname, int(w.draw), int(w.psu)]
		_bench_l.add_theme_color_override("font_color", T.GOOD if w.ok else T.ACCENT)
	else:
		_bench_l.text = "Tezgâhta PC yok"
		_bench_l.add_theme_color_override("font_color", T.MUTED)

	var p = Game.player
	var hands_full: bool = (p != null and p.held != null) or Game.is_carrying()
	if p != null and p.held != null:
		_held_row.visible = true
		var can_ret: bool = not p.held.is_tool() and not p.held.broken
		_held_l.text = "Elinde: %s" % p.held.display_name + ("" if can_ret else " (dolaba konmaz)")
		_return_btn.visible = can_ret
	elif Game.is_carrying():
		_held_row.visible = true
		_held_l.text = "Cihaz taşıyorsun — önce tezgâha veya rafa bırak."
		_return_btn.visible = false
	else:
		_held_row.visible = false

	var allow_cats: Array = []
	for c in CATS:
		if c.id == _cat_id:
			allow_cats = c.cats
			break

	var shown := 0
	for sku_id in _rows:
		var row: Dictionary = _rows[sku_id]
		var d: PartDef = row.def
		var vis := allow_cats.is_empty() or allow_cats.has(d.category)
		var n_orig := Game.stock_of_sku(sku_id)
		var n_cheap := Game.stock_cheap_of_sku(sku_id)
		if _stock_only and n_orig <= 0 and n_cheap <= 0:
			vis = false

		var cl: Label = row.compat
		if has_pc:
			var cres := Compatibility.check_catalog_part(d, st)
			if _compat_only and cres.severity == "block":
				vis = false
			if cres.severity == "block":
				cl.text = "✕ " + str(cres.reason)
				cl.add_theme_color_override("font_color", T.BAD)
			elif cres.severity == "warn":
				cl.text = "! " + str(cres.reason)
				cl.add_theme_color_override("font_color", T.ACCENT)
			else:
				cl.text = "✓ Uyumlu"
				cl.add_theme_color_override("font_color", T.GOOD)
		else:
			cl.text = "—"
			cl.add_theme_color_override("font_color", T.MUTED)

		row.panel.visible = vis
		if not vis:
			continue
		shown += 1

		var so: Label = row.stock_orig
		so.text = "Orijinal: %d" % n_orig
		so.add_theme_color_override("font_color", T.TEXT if n_orig > 0 else T.BAD)
		var sc_l: Label = row.stock_cheap
		sc_l.text = "Muadil: %d" % n_cheap if n_cheap > 0 else "Muadil: 0"
		sc_l.add_theme_color_override("font_color", T.ACCENT if n_cheap > 0 else T.MUTED)

		row.btn_orig.disabled = hands_full or n_orig <= 0
		row.btn_cheap.disabled = hands_full or n_cheap <= 0

	_empty_l.visible = shown == 0


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
