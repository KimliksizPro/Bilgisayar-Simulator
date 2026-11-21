extends Control
## Tezgahtaki laptop: ParçaNet (parça siparişi), Kargo Takip, Geliştirmeler ve Dükkân istatistikleri.

const T := preload("res://scripts/ui_theme.gd")
const K := preload("res://scripts/ui_kit.gd")
const PM := preload("res://scripts/part_models.gd")
const PC_SCRIPT := preload("res://scripts/pc_case.gd")
const BENCH := preload("res://scripts/bench_mode.gd")

const SHOP_CATS := [
	{"id": "all", "label": "Tümü", "cats": []},
	{"id": "mobo", "label": "Anakart", "cats": ["mobo"]},
	{"id": "cpu", "label": "CPU", "cats": ["cpu"]},
	{"id": "ram", "label": "RAM", "cats": ["ram"]},
	{"id": "gpu", "label": "GPU", "cats": ["gpu"]},
	{"id": "storage", "label": "Depolama", "cats": ["ssd", "nvme", "hdd"]},
	{"id": "psu", "label": "PSU", "cats": ["psu"]},
	{"id": "other", "label": "Soğutma/Diğer", "cats": ["cooler", "fan", "cmos"]},
	{"id": "mobile", "label": "Mobil", "cats": ["lap_ram", "lap_ssd", "lap_bat", "lap_scr", "lap_kbd", "lap_wifi", "lap_dc", "tel_bat", "tel_scr", "tel_port", "tel_cam", "tel_spk", "tel_back"]},
]

signal back

var _root: Control
var _panel: Control
var _pages: Array[Control] = []
var _tabs: Array[Button] = []
var _money: Label
var _cart := {}             # "<sku>" veya "<sku>:c" -> adet
var _express := false
var _cheap := false         # ParçaNet kalite seçimi: false = orijinal, true = muadil
var _cat_id := "all"        # ParçaNet kategori filtresi
var _cat_btns := {}         # cat_id -> Button
var _compat_on := false     # ParçaNet "Uyumluluk" rozetleri açık mı
var _compat_only := false   # Yalnızca uyumlu parçaları göster
var _compat_btn: Button
var _compat_only_btn: Button
var _bench_watt_l: Label
var _bench_info_l: Label
var _qual_btns: Array[Button] = []
var _qual_note: Label
# ParçaNet satırları: sku -> {panel, def, stock, price, qty, line, retail, compat}
var _rows := {}
var _market: Label
var _sub_l: Label
var _ship_l: Label
var _bulk_l: Label
var _total_l: Label
var _eta_l: Label
var _order_btn: Button
var _ship_btns: Array[Button] = []
# kargo / geliştirme / dükkân
var _orders_box: VBoxContainer
var _up_rows := {}
var _stats_grid: GridContainer
var _tab_cargo: Button
var _used_box: VBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := K.modal(self, 960, 0.7)
	_root = m[0]
	_panel = m[1]
	var vb: VBoxContainer = m[2]
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	vb.add_child(head)
	var tv := VBoxContainer.new()
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tv.add_theme_constant_override("separation", 0)
	head.add_child(tv)
	K.label(tv, "Dükkân Bilgisayarı", 32, T.ACCENT, "TitleLabel")
	K.label(tv, "Parça siparişi, kargo takibi ve dükkân yönetimi.", 16, T.MUTED, "MutedLabel")
	var lc := K.lcd(head, "", 38, Vector2(16, 0))
	lc[0].size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_money = lc[1]
	# sekmeler
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	vb.add_child(tabs)
	var group := ButtonGroup.new()
	var names := ["ParçaNet", "Kargo Takip", "Geliştirmeler", "Dükkân", "İkinci El", "Personel"]
	for i in names.size():
		var b := K.button(tabs, names[i], func(): _show_page(i), "TabButton", 19, Vector2(0, 42))
		b.toggle_mode = true
		b.button_group = group
		_tabs.append(b)
	_tab_cargo = _tabs[1]
	K.hsep(vb)
	var holder := VBoxContainer.new()
	holder.custom_minimum_size = Vector2(0, 470)
	vb.add_child(holder)
	for i in names.size():
		var page := VBoxContainer.new()
		page.add_theme_constant_override("separation", 10)
		page.size_flags_vertical = Control.SIZE_EXPAND_FILL
		page.visible = false
		holder.add_child(page)
		_pages.append(page)
	_build_shop(_pages[0])
	_build_cargo(_pages[1])
	_build_upgrades(_pages[2])
	_build_stats(_pages[3])
	_build_used(_pages[4])
	_build_staff(_pages[5])  # PERSONEL
	K.hsep(vb)
	var foot := HBoxContainer.new()
	vb.add_child(foot)
	K.label(foot, "Esc: kapat", 15, Color(1, 1, 1, 0.35), "MutedLabel").size_flags_horizontal = Control.SIZE_EXPAND_FILL
	K.button(foot, "Kapat", func(): back.emit(), "", 19, Vector2(150, 46))
	Game.money_changed.connect(func(_v): refresh())
	Game.stock_changed.connect(refresh)
	Game.orders_changed.connect(refresh)
	Game.upgrade_bought.connect(func(_id): refresh())
	Game.day_started.connect(refresh)
	Game.staff_changed.connect(refresh)  # PERSONEL
	Game.bench_changed.connect(func(_d): refresh())
	_show_page(0)


func is_open() -> bool:
	return _root != null and _root.visible


func open(page := 0) -> void:
	refresh()
	_show_page(page)
	K.open(_root, _panel)
	_tabs[page].grab_focus()


func close() -> void:
	K.close(_root, _panel)


func _show_page(i: int) -> void:
	for j in _pages.size():
		_pages[j].visible = j == i
		_tabs[j].set_pressed_no_signal(j == i)
	refresh()


func _unhandled_input(event: InputEvent) -> void:
	if is_open() and event.is_action_pressed("ui_cancel"):
		Game.sfx.ui_back()
		back.emit()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- ParçaNet
func _build_shop(p: Control) -> void:
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 14)
	p.add_child(top)
	var brand := VBoxContainer.new()
	brand.add_theme_constant_override("separation", -2)
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(brand)
	K.label(brand, "ParçaNet  ·  Toptan Bilgisayar Parçası", 20, T.INFO, "SignLabel")
	K.label(brand, "Fiyatlar her sabah piyasaya göre değişir. Aynı üründen %d+ adete %%%d indirim." % [Game.BULK_QTY, int(Game.BULK_DISCOUNT * 100)], 15, T.MUTED, "MutedLabel")
	# kalite seçimi: orijinal / muadil
	var qv := VBoxContainer.new()
	qv.add_theme_constant_override("separation", 2)
	top.add_child(qv)
	K.label(qv, "KALİTE", 12, T.MUTED, "SmallCaps")
	var qh := HBoxContainer.new()
	qh.add_theme_constant_override("separation", 6)
	qv.add_child(qh)
	var qg := ButtonGroup.new()
	for i in 2:
		var qb := K.button(qh, "Orijinal" if i == 0 else "Muadil -%%%d" % roundi((1.0 - Game.CHEAP_FACTOR) * 100.0), func():
			_cheap = i == 1
			refresh(), "SegButton", 16, Vector2(0, 38))
		qb.toggle_mode = true
		qb.button_group = qg
		_qual_btns.append(qb)
	_qual_note = K.label(qv, "", 13, T.MUTED, "MutedLabel")
	var mk := K.lcd(top, "", 26, Vector2(12, 0))
	mk[0].size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_market = mk[1]
	# kategori filtre sekmeleri
	var cat_bar := HFlowContainer.new()
	cat_bar.add_theme_constant_override("h_separation", 4)
	cat_bar.add_theme_constant_override("v_separation", 4)
	p.add_child(cat_bar)
	var cg := ButtonGroup.new()
	for c in SHOP_CATS:
		var cid: String = c.id
		var cb := K.button(cat_bar, c.label, func():
			_cat_id = cid
			refresh(), "SegButton", 14, Vector2(0, 32))
		cb.toggle_mode = true
		cb.button_group = cg
		_cat_btns[cid] = cb
	# tezgâh PC uyumluluk düğmesi + canlı watt göstergesi
	var cbar := HBoxContainer.new()
	cbar.add_theme_constant_override("separation", 10)
	p.add_child(cbar)
	_compat_btn = K.button(cbar, "Uyumluluk", func():
		_compat_on = _compat_btn.button_pressed
		if not _compat_on:
			_compat_only = false
		refresh(), "SegButton", 14, Vector2(0, 32))
	_compat_btn.toggle_mode = true
	_compat_only_btn = K.button(cbar, "Sadece uyumlu", func():
		_compat_only = _compat_only_btn.button_pressed
		refresh(), "SegButton", 14, Vector2(0, 32))
	_compat_only_btn.toggle_mode = true
	_compat_only_btn.visible = false
	_bench_info_l = K.label(cbar, "", 14, T.MUTED, "MutedLabel")
	_bench_info_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bench_info_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_bench_watt_l = K.label(cbar, "", 15, T.GOOD, "BoldLabel")
	_bench_watt_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# başlık satırı
	var hdr := _grid_row(p)
	for t in [["ÜRÜN", 330], ["STOK", 90], ["BİRİM FİYAT", 130], ["ADET", 160], ["TUTAR", 105]]:
		var l := K.label(hdr, t[0], 12, T.MUTED, "SmallCaps")
		l.custom_minimum_size.x = t[1]
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	# katalog uzun (PC + mobil SKU'lar): kaydırılabilir liste
	var lsc := ScrollContainer.new()
	lsc.custom_minimum_size = Vector2(0, 270)
	lsc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lsc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	p.add_child(lsc)
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lsc.add_child(list)
	for d in DB.parts.catalog():
		var k: String = d.id
		var ip := K.panel(list, "InsetPanel")
		ip.add_theme_stylebox_override("panel", T.flat(Color(0, 0, 0, 0.25), 5, Color(1, 1, 1, 0.04), 1, Vector2(12, 5)))
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 0)
		ip.add_child(r)
		var nm := VBoxContainer.new()
		nm.add_theme_constant_override("separation", -2)
		nm.custom_minimum_size.x = 330
		r.add_child(nm)
		K.label(nm, PM.display_name_sku(k), 17, T.TEXT, "BoldLabel")
		var spec_s := BENCH._spec_text(d)
		if spec_s != "":
			K.label(nm, spec_s, 13, T.INFO)
		var retail := K.label(nm, "", 13, T.MUTED, "MutedLabel")
		var compat_l := K.label(nm, "", 13, T.GOOD, "BoldLabel")
		compat_l.visible = false
		var st := K.label(r, "", 19, T.TEXT, "BoldLabel")
		st.custom_minimum_size.x = 90
		st.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var pr := K.label(r, "", 19, T.ACCENT_HI, "BoldLabel")
		pr.custom_minimum_size.x = 130
		pr.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var step := HBoxContainer.new()
		step.add_theme_constant_override("separation", 6)
		step.custom_minimum_size.x = 160
		step.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		r.add_child(step)
		K.button(step, "−", func(): _add(k, -1), "SegButton", 20, Vector2(38, 36))
		var lq := K.lcd(step, "0", 24, Vector2(8, 0))
		lq[1].custom_minimum_size.x = 26
		lq[1].horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		K.button(step, "+", func(): _add(k, 1), "SegButton", 20, Vector2(38, 36))
		var ln := K.label(r, "", 18, T.TEXT, "BoldLabel")
		ln.custom_minimum_size.x = 105
		ln.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		ln.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_rows[k] = {"panel": ip, "def": d, "stock": st, "price": pr, "qty": lq[1], "line": ln, "retail": retail, "compat": compat_l}
	K.spacer(p, 2)
	# sepet özeti + kargo seçimi
	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 20)
	p.add_child(bottom)
	var ship := VBoxContainer.new()
	ship.add_theme_constant_override("separation", 6)
	ship.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bottom.add_child(ship)
	K.label(ship, "KARGO", 12, T.MUTED, "SmallCaps")
	var sh := HBoxContainer.new()
	sh.add_theme_constant_override("separation", 6)
	ship.add_child(sh)
	var sg := ButtonGroup.new()
	for i in 2:
		var b := K.button(sh, "", func():
			_express = i == 1
			refresh(), "SegButton", 16, Vector2(0, 40))
		b.toggle_mode = true
		b.button_group = sg
		_ship_btns.append(b)
	_eta_l = K.label(ship, "", 15, T.MUTED, "MutedLabel")
	var sum := VBoxContainer.new()
	sum.add_theme_constant_override("separation", 0)
	sum.custom_minimum_size.x = 260
	bottom.add_child(sum)
	_sub_l = _sum_row(sum, "Ara toplam")
	_bulk_l = K.label(sum, "", 14, T.GOOD, "MutedLabel")
	_bulk_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ship_l = _sum_row(sum, "Kargo")
	_total_l = _sum_row(sum, "TOPLAM", true)
	var btns := VBoxContainer.new()
	btns.add_theme_constant_override("separation", 8)
	btns.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bottom.add_child(btns)
	_order_btn = K.button(btns, "Siparişi Ver", _order, "PrimaryButton", 20, Vector2(190, 52))
	K.button(btns, "Sepeti boşalt", func():
		_cart.clear()
		refresh(), "", 15, Vector2(190, 38))


func _grid_row(parent: Control) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 0)
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", 13)
	parent.add_child(m)
	m.add_child(h)
	return h


func _sum_row(parent: Control, text: String, big := false) -> Label:
	var h := HBoxContainer.new()
	parent.add_child(h)
	K.label(h, text, 20 if big else 16, T.TEXT if big else T.MUTED, "SignLabel" if big else "MutedLabel").size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := K.label(h, "", 24 if big else 17, T.ACCENT_HI if big else T.TEXT, "BoldLabel")
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return v


func _add(base: String, d: int) -> void:
	var k := base + (":c" if _cheap else "")  # muadil sepet anahtarı "tür:seviye:c"
	_cart[k] = clampi(int(_cart.get(k, 0)) + d, 0, 20)
	if _cart[k] == 0:
		_cart.erase(k)
	refresh()


func _order() -> void:
	if _cart.is_empty():
		Game.sfx.error()
		return
	if Game.place_order(_cart, _express):
		_cart.clear()
		refresh()
		_show_page(1)


# ---------------------------------------------------------------- Kargo Takip
func _build_cargo(p: Control) -> void:
	K.label(p, "Yoldaki ve kapıdaki kargoların. Kurye koliyi kapının yanına bırakır; koliye bakıp E'ye basınca parçalar stoğa girer.", 16, T.MUTED, "MutedLabel").autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	p.add_child(sc)
	_orders_box = VBoxContainer.new()
	_orders_box.add_theme_constant_override("separation", 8)
	_orders_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_orders_box)


func _refresh_cargo() -> void:
	for c in _orders_box.get_children():
		c.free()
	_tab_cargo.text = "Kargo Takip" + ("  (%d)" % Game.orders.size() if Game.orders.size() > 0 else "")
	if Game.orders.is_empty():
		var l := K.label(_orders_box, "Yolda kargo yok. ParçaNet sekmesinden sipariş verebilirsin.", 18, T.MUTED, "MutedLabel")
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		return
	for o in Game.orders:
		var ip := K.panel(_orders_box, "InsetPanel")
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 16)
		ip.add_child(h)
		var no := K.lcd(h, "#%03d" % int(o.id), 28, Vector2(10, 0))
		no[0].size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(v)
		var il := K.label(v, Game.items_text(o.items), 18, T.TEXT, "BoldLabel")
		il.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		il.custom_minimum_size.x = 420
		K.label(v, "%s kargo  ·  %d TL ödendi  ·  Tahmini varış: %s" % ["Ekspres" if o.express else "Standart", int(o.cost), Game.abs_time_text(float(o.eta))], 15, T.MUTED, "MutedLabel")
		var st: String = o.get("state", "transit")
		var txt: String = {"transit": "YOLDA", "courier": "KURYEDE", "door": "KAPIDA"}.get(st, "YOLDA")
		var col: Color = {"transit": T.INFO, "courier": T.ACCENT, "door": T.GOOD}.get(st, T.INFO)
		var stp := CenterContainer.new()
		stp.custom_minimum_size.x = 150
		h.add_child(stp)
		K.stamp(stp, txt, col, 18, -5.0)


# ---------------------------------------------------------------- Geliştirmeler
func _build_upgrades(p: Control) -> void:
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	p.add_child(sc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(vb)
	for sec in [["shop", "DÜKKÂN GELİŞTİRMELERİ"], ["tool", "TEŞHİS & TAMİR ALETLERİ"]]:
		K.label(vb, sec[1], 13, T.ACCENT, "SmallCaps")
		for u in Game.UPGRADE_LIST:
			if str(u.get("cat", "shop")) != sec[0]:
				continue
			var ip := K.panel(vb, "InsetPanel")
			var row := HBoxContainer.new()
			row.add_theme_constant_override("separation", 16)
			ip.add_child(row)
			var tcol := VBoxContainer.new()
			tcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			tcol.add_theme_constant_override("separation", 0)
			row.add_child(tcol)
			K.label(tcol, u.name, 20, T.TEXT, "BoldLabel")
			K.label(tcol, u.desc, 15, T.MUTED, "MutedLabel")
			var uid: String = u.id
			var owned := CenterContainer.new()
			owned.custom_minimum_size = Vector2(200, 0)
			row.add_child(owned)
			K.stamp(owned, "ALINDI", T.GOOD, 18, -6.0)
			var b := K.button(row, "", func(): Game.buy_upgrade(uid), "PrimaryButton", 17, Vector2(200, 46))
			b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			_up_rows[uid] = [b, owned]


func _refresh_upgrades() -> void:
	for u in Game.UPGRADE_LIST:
		var pair: Array = _up_rows[u.id]
		var b: Button = pair[0]
		var has := Game.has_upgrade(u.id)
		pair[1].visible = has
		b.visible = not has
		if not has:
			b.text = "Satın Al  ·  %d TL" % int(u.price)
			b.disabled = Game.money < int(u.price)


# ---------------------------------------------------------------- Dükkân
func _build_stats(p: Control) -> void:
	K.label(p, "Dükkânın durumu", 20, T.ACCENT, "SignLabel")
	_stats_grid = GridContainer.new()
	_stats_grid.columns = 2
	_stats_grid.add_theme_constant_override("h_separation", 40)
	_stats_grid.add_theme_constant_override("v_separation", 8)
	var ip := K.panel(p, "InsetPanel")
	ip.add_child(_stats_grid)
	var tip := K.label(p, "İpucu: Kur düşükken stok yap, yüksekken stoktan sat. Rafa sağlam parça geri konabilir; " +
		"yükseltme işlerinde müşteriden çıkan eski parçayı rafa koyup sonra satabilirsin.", 15, T.MUTED, "MutedLabel")
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tip.custom_minimum_size.x = 600


func _refresh_stats() -> void:
	for c in _stats_grid.get_children():
		c.free()
	var rows := [
		["Gün", "%d  (%s)" % [Game.day, Game.clock_text()]],
		["Kasa", "%s TL" % K.money(Game.money)],
		["İtibar", "%.1f / 5" % Game.rep],
		["Toplam gelir", "%s TL" % K.money(int(Game.stats.get("total_income", 0)))],
		["Tamamlanan iş", "%d" % int(Game.stats.get("total_jobs", 0))],
		["Tezgah satışı", "%d parça" % int(Game.stats.get("total_sales", 0))],
		["Stok", "%d parça  ·  değeri ~%s TL" % [Game.stock_count(), K.money(Game.stock_value())]],
		["Bugünkü kira", "%s TL (her %d günde artar)" % [K.money(Game.rent()), Game.RENT_RAISE_EVERY]],
		["Piyasa kuru", "%.2f" % Game.market],
	]
	for r in rows:
		K.label(_stats_grid, r[0], 18, T.MUTED, "MutedLabel").custom_minimum_size.x = 220
		K.label(_stats_grid, r[1], 18, T.TEXT, "BoldLabel")


# ---------------------------------------------------------------- İkinci El
func _build_used(p: Control) -> void:
	K.label(p, "İkinci El Pazarı  ·  Günün ilanları", 20, T.INFO, "SignLabel")
	var n := K.label(p, "Kullanılmış parçalar çok ucuzdur ama durumu değişkendir. \"Arızalı çıkabilir\" ilanlarda parça bozuk olabilir; " +
		"raftan alınca bozuk çıkarsa ancak testte anlarsın. Alınan parça rafa (orijinal stok) girer. İlanlar her sabah yenilenir.", 15, T.MUTED, "MutedLabel")
	n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	n.custom_minimum_size.x = 880
	_used_box = VBoxContainer.new()
	_used_box.add_theme_constant_override("separation", 4)
	p.add_child(_used_box)


func _refresh_used() -> void:
	for c in _used_box.get_children():
		c.queue_free()  # satın alma düğmesinin kendi çağrısı içinde yenilenebilir
	for l in Game.used_listings:
		var ip := K.panel(_used_box, "InsetPanel")
		ip.add_theme_stylebox_override("panel", T.flat(Color(0, 0, 0, 0.25), 5, Color(1, 1, 1, 0.04), 1, Vector2(12, 5)))
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 12)
		ip.add_child(r)
		var nm := VBoxContainer.new()
		nm.add_theme_constant_override("separation", -3)
		nm.custom_minimum_size.x = 300
		r.add_child(nm)
		var sku_id := str(l.get("sku", ""))
		if sku_id.is_empty():
			sku_id = Game.sku(str(l.get("type", "")), int(l.get("tier", 1)))
		else:
			sku_id = DB.parts.resolve_id(sku_id)
		var ldef: PartDef = DB.parts.get_def(sku_id)
		var sp_txt := BENCH._spec_text(ldef)
		K.label(nm, PM.display_name_sku(sku_id), 18, T.TEXT, "BoldLabel")
		K.label(nm, "Yeni fiyatı: %d TL%s" % [Game.price_of_sku(sku_id), ("  ·  " + sp_txt) if sp_txt != "" else ""], 14, T.MUTED, "MutedLabel")
		var cond: int = l.cond
		var cl := K.label(r, "Durum %%%d" % cond, 19, T.GOOD if cond >= 70 else (T.ACCENT if cond >= 50 else T.BAD), "BoldLabel")
		cl.custom_minimum_size.x = 130
		cl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var rk := CenterContainer.new()
		rk.custom_minimum_size.x = 210
		r.add_child(rk)
		if l.risky:
			K.stamp(rk, "ARIZALI ÇIKABİLİR", T.BAD, 14, -3.0)
		var pr := K.label(r, "%d TL" % int(l.price), 20, T.ACCENT_HI, "BoldLabel")
		pr.custom_minimum_size.x = 90
		pr.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		pr.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var lid: int = l.id
		var b := K.button(r, "SATILDI" if l.sold else "Satın Al", func(): Game.UM.buy(lid), "PrimaryButton", 17, Vector2(130, 40))
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		b.disabled = l.sold or Game.money < int(l.price)


# ---------------------------------------------------------------- yenile
func refresh() -> void:
	if _money == null:
		return
	_money.text = "%s TL" % K.money(Game.money)
	if _pages[0].visible:
		_refresh_shop()
	_refresh_cargo()
	if _pages[2].visible:
		_refresh_upgrades()
	if _pages[3].visible:
		_refresh_stats()
	if _pages[4].visible:
		_refresh_used()
	if _pages[5].visible:  # PERSONEL
		_refresh_staff()


## Tezgâhta PC kasası varsa onu, yoksa null döndürür.
func _bench_pc():
	var d = Game.bench_device
	return d if is_instance_valid(d) and d.get_script() == PC_SCRIPT else null


## Tezgâhtaki PC'nin standart kasa durumu (anakart yuvasız eski kasalarda yerleşik AM4 varsayılır).
func _bench_case_state() -> Dictionary:
	var pc = _bench_pc()
	if pc == null:
		return {}
	var st := Compatibility.case_state_of(pc)
	if st.mobo == null and "slots" in pc and not pc.slots.has("mobo"):
		st.mobo = DB.parts.get_def("mobo_am4_matx")
	return st


func _active_cat_list() -> Array:
	for c in SHOP_CATS:
		if c.id == _cat_id:
			return c.cats
	return []


func _refresh_shop() -> void:
	var ch := (Game.market / maxf(Game.market_prev, 0.01) - 1.0) * 100.0
	var arrow := "▲" if ch > 0.5 else ("▼" if ch < -0.5 else "■")
	_market.text = "KUR %.2f %s%+.0f%%" % [Game.market, arrow, ch]
	_market.add_theme_color_override("font_color", T.BAD if ch > 0.5 else (T.LCD if ch < -0.5 else T.LCD_DIM))
	for cid in _cat_btns:
		_cat_btns[cid].set_pressed_no_signal(cid == _cat_id)
	# tezgâhtaki PC uyumluluk ve watt durumu
	var bench_st := _bench_case_state()
	var has_pc := not bench_st.is_empty()
	if not has_pc:
		_compat_on = false
		_compat_only = false
	_compat_btn.disabled = not has_pc
	_compat_btn.set_pressed_no_signal(_compat_on)
	_compat_btn.tooltip_text = "Tezgâhtaki PC ile uyumluluk rozetlerini göster" if has_pc else "Tezgâhta PC yok"
	_compat_only_btn.visible = has_pc and _compat_on
	_compat_only_btn.set_pressed_no_signal(_compat_only)
	if has_pc:
		var cdef: Dictionary = bench_st.get("case_def", {})
		var mobo: PartDef = bench_st.get("mobo", null)
		var mtxt := "%s · %s" % [str(mobo.compat.get("socket", "")), str(mobo.compat.get("ram_type", ""))] if mobo != null else "Anakart yok"
		_bench_info_l.text = "Tezgâh: %s · %s" % [str(cdef.get("name", "PC")), mtxt]
		var w := Compatibility.calc_watts(bench_st)
		var w_col := T.GOOD
		if w.psu <= 0 or w.draw > w.psu:
			w_col = T.BAD
		elif w.psu < w.recommended or float(w.draw) / float(w.psu) > 0.85:
			w_col = T.ACCENT
		_bench_watt_l.text = "Güç: %dW / %s" % [w.draw, ("%dW" % w.psu) if w.psu > 0 else "PSU yok"]
		_bench_watt_l.add_theme_color_override("font_color", w_col)
		_bench_watt_l.tooltip_text = "Önerilen PSU: %dW+" % w.recommended
		_bench_watt_l.visible = true
	else:
		_bench_info_l.text = "Tezgâhta PC yok"
		_bench_watt_l.visible = false
	var cat_list := _active_cat_list()
	for k in _rows:
		var r: Dictionary = _rows[k]
		var d: PartDef = r.def
		var cat_ok := cat_list.is_empty() or cat_list.has(d.category)
		var compat_ok := true
		var compat_lbl: Label = r.compat
		var row_panel: Control = r.panel
		if has_pc and _compat_on and d.device == "pc":
			var res := Compatibility.check_catalog_part(d, bench_st)
			compat_lbl.visible = true
			if not res.ok:
				compat_ok = false
				compat_lbl.text = "✕ Uyumsuz: %s" % str(res.reason)
				compat_lbl.add_theme_color_override("font_color", T.BAD)
				row_panel.tooltip_text = str(res.reason)
			elif str(res.get("severity", "ok")) == "warn":
				compat_lbl.text = "⚠ %s" % str(res.reason)
				compat_lbl.add_theme_color_override("font_color", T.ACCENT)
				row_panel.tooltip_text = str(res.reason)
			else:
				compat_lbl.text = "✓ Uyumlu"
				compat_lbl.add_theme_color_override("font_color", T.GOOD)
				row_panel.tooltip_text = "Tezgâhtaki PC ile uyumlu"
		else:
			compat_lbl.visible = false
			row_panel.tooltip_text = ""
		row_panel.visible = cat_ok and (not _compat_only or compat_ok)
		var n := Game.stock_of_sku(k)
		var cn := Game.stock_cheap_of_sku(k)
		r.stock.text = ((str(n) if n > 0 else "0") + (" +%dM" % cn if cn > 0 else "")) if n + cn > 0 else "YOK"
		r.stock.add_theme_color_override("font_color", T.TEXT if n + cn > 1 else (T.ACCENT if n + cn == 1 else T.BAD))
		var pr := Game.price_of_sku(k, _cheap)
		r.price.text = "%d TL" % pr
		r.price.add_theme_color_override("font_color", T.GOOD if _cheap else T.ACCENT_HI)
		var q := int(_cart.get(k + (":c" if _cheap else ""), 0))
		r.qty.text = str(q)
		# satır tutarı: iki kalitenin toplamı (diğer kalite sepetteyse küçük not)
		var line := 0
		var qo := int(_cart.get(k, 0))
		var qc := int(_cart.get(k + ":c", 0))
		if qo > 0:
			line += Game.cart_subtotal({k: qo})
		if qc > 0:
			line += Game.cart_subtotal({k + ":c": qc})
		r.line.text = ("%d TL" % line) if q + (qc if not _cheap else qo) > 0 else "—"
		r.line.add_theme_color_override("font_color", T.GOOD if (qo >= Game.BULK_QTY or qc >= Game.BULK_QTY) else T.TEXT)
		var other := qo if _cheap else qc
		r.retail.text = "Tezgahta satış: %d TL" % Game.retail_price_sku(k) + ("   ·   sepette %d %s" % [other, "orijinal" if _cheap else "muadil"] if other > 0 else "")
	var sub := Game.cart_subtotal(_cart)
	var raw := 0
	for ck in _cart:
		var pk := Game.parse_cart_key(str(ck))
		raw += Game.price_of_sku(pk.sku, pk.cheap) * int(_cart[ck])
	_qual_btns[0].set_pressed_no_signal(not _cheap)
	_qual_btns[1].set_pressed_no_signal(_cheap)
	_qual_note.text = "ucuz ama garanti riski var" if _cheap else "güvenilir, garanti sorunu yok"
	_qual_note.add_theme_color_override("font_color", T.BAD if _cheap else T.MUTED)
	_sub_l.text = "%d TL" % sub
	_bulk_l.text = ("toplu alım indirimi: -%d TL" % (raw - sub)) if raw > sub else ""
	var fee := Game.ship_fee(_express, sub)
	_ship_l.text = "Ücretsiz" if fee == 0 else "%d TL" % fee
	_total_l.text = "%d TL" % (sub + fee)
	var std_fee := Game.ship_fee(false, sub)
	_ship_btns[0].text = "Standart · %s · %s" % [_hours_text(Game.ship_hours(false)), "ücretsiz" if std_fee == 0 else "%d TL" % std_fee]
	_ship_btns[1].text = "Ekspres · %s · %s" % [_hours_text(Game.ship_hours(true)), "ücretsiz" if Game.ship_fee(true, sub) == 0 else "%d TL" % Game.SHIP_EXP_FEE]
	_ship_btns[0].set_pressed_no_signal(not _express)
	_ship_btns[1].set_pressed_no_signal(_express)
	var eta := Game.now_abs() + Game.ship_hours(_express)
	_eta_l.text = "Tahmini varış: %s%s" % [Game.abs_time_text(eta),
		"" if Game.has_upgrade("courier") or _express or sub >= Game.FREE_SHIP_OVER else "   ·   %d TL üstü standart kargo ücretsiz" % Game.FREE_SHIP_OVER]
	_order_btn.disabled = _cart.is_empty() or Game.money < sub + fee


func _hours_text(h: float) -> String:
	return ("%d dk" % roundi(h * 60.0)) if h < 1.0 else ("%s saat" % (str(int(h)) if is_equal_approx(h, roundf(h)) else "%.1f" % h))


# ---------------------------------------------------------------- Personel (çalışan alma)
const SD := preload("res://scripts/staff_data.gd")
var _team_box: VBoxContainer
var _cand_box: VBoxContainer
var _team_title: Label
var _wage_l: Label


func _build_staff(p: Control) -> void:
	p.add_theme_constant_override("separation", 8)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 14)
	p.add_child(top)
	var brand := VBoxContainer.new()
	brand.add_theme_constant_override("separation", -2)
	brand.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(brand)
	K.label(brand, "Personel  ·  Çırak ve Usta İlanı", 20, T.INFO, "SignLabel")
	K.label(brand, "Maaşlar gün sonunda kasadan ödenir. En fazla %d çalışan. Teknisyene raftaki işi vermek için ona bakıp E'ye bas." % Game.STAFF_MAX, 15, T.MUTED, "MutedLabel")
	var lc := K.lcd(top, "", 24, Vector2(12, 0))
	lc[0].size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_wage_l = lc[1]
	_team_title = K.label(p, "", 12, T.MUTED, "SmallCaps")
	_team_box = VBoxContainer.new()
	_team_box.add_theme_constant_override("separation", 6)
	p.add_child(_team_box)
	K.label(p, "BUGÜNKÜ ADAYLAR", 12, T.MUTED, "SmallCaps")
	_cand_box = VBoxContainer.new()
	_cand_box.add_theme_constant_override("separation", 6)
	p.add_child(_cand_box)


func _refresh_staff() -> void:
	# düğmenin kendi sinyali içinde silinmemesi için free değil queue_free
	for box in [_team_box, _cand_box]:
		for c in box.get_children():
			box.remove_child(c)
			c.queue_free()
	_team_title.text = "EKİBİN  (%d / %d)" % [Game.staff.size(), Game.STAFF_MAX]
	_wage_l.text = "MAAŞ %d TL/GÜN" % Game.staff_wages()
	if Game.staff.is_empty():
		var ip := K.panel(_team_box, "InsetPanel")
		K.label(ip, "Henüz çalışanın yok. Aşağıdaki adaylardan birini işe alabilirsin.", 16, T.MUTED, "MutedLabel")
	for d in Game.staff:
		var row := _person_row(_team_box, d)
		var id := int(d.id)
		var mgr = Game.staff_mgr
		if d.role == "teknisyen":
			var ab := K.button(row, "İşi Ver", func():
				var err: String = mgr.assign(id) if mgr else "iş yok"
				if err != "":
					Game.sfx.error()
					Game.msg({"iş yok": "Rafta teknisyene verilecek iş yok.", "meşgul": "%s şu an meşgul." % d.name,
						"başkası yapıyor": "Bu işi zaten başka biri yapıyor."}.get(err, "Stokta gerekli parça yok!"), Color(1, 0.6, 0.4))
				refresh(), "", 16, Vector2(100, 42))
			ab.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			ab.disabled = mgr == null or mgr.jobs.tech_candidates().is_empty()
			var ob := K.button(row, "", func():
				d.auto = not bool(d.get("auto", true))
				refresh(), "SegButton", 15, Vector2(122, 42))
			ob.toggle_mode = true
			ob.set_pressed_no_signal(bool(d.get("auto", true)))
			ob.text = "Kendi alır" if bool(d.get("auto", true)) else "Sen verirsin"
			ob.tooltip_text = "Açıkken masaya konan işi kendiliğinden alır."
			ob.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var fb := K.button(row, "Çıkar", func(): Game.fire_staff(id), "DangerButton", 16, Vector2(96, 42))
		fb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	for d in Game.staff_candidates:
		var row := _person_row(_cand_box, d)
		var id := int(d.id)
		var hb := K.button(row, "İşe Al", func(): Game.hire_staff(id), "PrimaryButton", 17, Vector2(130, 44))
		hb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		hb.disabled = Game.staff.size() >= Game.STAFF_MAX
	if Game.staff_candidates.is_empty():
		K.label(_cand_box, "Bugün başka başvuru yok, yarın yeni adaylar gelir.", 16, T.MUTED, "MutedLabel")


## Çalışan / aday satırı: rol şeridi, isim, rol · huy, beceri yıldızları, maaş. Düğmeler sona eklenir.
func _person_row(parent: Control, d: Dictionary) -> HBoxContainer:
	var ip := K.panel(parent, "InsetPanel")
	ip.add_theme_stylebox_override("panel", T.flat(Color(0, 0, 0, 0.25), 5, Color(1, 1, 1, 0.04), 1, Vector2(12, 6)))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	ip.add_child(row)
	var role_c: Color = SD.ROLES.get(d.role, SD.ROLES.tezgahtar).color
	var strip := ColorRect.new()
	strip.color = role_c.lightened(0.15)
	strip.custom_minimum_size = Vector2(6, 0)
	row.add_child(strip)
	var nm := VBoxContainer.new()
	nm.add_theme_constant_override("separation", -3)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(nm)
	var tr := SD.trait_info(d.trait)
	K.label(nm, "%s  ·  %s" % [d.name, SD.role_name(d.role)], 19, T.TEXT, "BoldLabel")
	K.label(nm, "%s — %s" % [tr.name, tr.desc], 14, T.MUTED, "MutedLabel")
	var sk := VBoxContainer.new()
	sk.add_theme_constant_override("separation", 0)
	sk.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sk.custom_minimum_size.x = 92
	row.add_child(sk)
	K.label(sk, "BECERİ", 11, T.MUTED, "SmallCaps")
	var st := K.stars(sk, 16)
	st.set("value", float(d.skill))
	var w := K.label(row, "%d TL/gün" % int(d.wage), 19, T.ACCENT_HI, "BoldLabel")
	w.custom_minimum_size.x = 110
	w.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	w.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# düğmeler sabit genişlikte sağa yaslı: sütunlar satırlar arasında hizalı kalsın
	var act := HBoxContainer.new()
	act.add_theme_constant_override("separation", 8)
	act.alignment = BoxContainer.ALIGNMENT_END
	act.custom_minimum_size.x = 360
	row.add_child(act)
	return act
