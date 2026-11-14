extends Control
## Tezgahtaki laptop: ParçaNet (parça siparişi), Kargo Takip, Geliştirmeler ve Dükkân istatistikleri.

const T := preload("res://scripts/ui_theme.gd")
const K := preload("res://scripts/ui_kit.gd")
const PM := preload("res://scripts/part_models.gd")

signal back

var _root: Control
var _panel: Control
var _pages: Array[Control] = []
var _tabs: Array[Button] = []
var _money: Label
var _cart := {}             # sku -> adet
var _express := false
var _cheap := false         # ParçaNet kalite seçimi: false = orijinal, true = muadil
var _qual_btns: Array[Button] = []
var _qual_note: Label
# ParçaNet satırları: sku -> {stock, price, qty, line}
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
	var names := ["ParçaNet", "Kargo Takip", "Geliştirmeler", "Dükkân", "İkinci El"]
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
	# başlık satırı
	var hdr := _grid_row(p)
	for t in [["ÜRÜN", 310], ["STOK", 100], ["BİRİM FİYAT", 150], ["ADET", 170], ["TUTAR", 110]]:
		var l := K.label(hdr, t[0], 12, T.MUTED, "SmallCaps")
		l.custom_minimum_size.x = t[1]
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 4)
	p.add_child(list)
	for it in Game.CATALOG:
		var type: String = it[0]
		var tier: int = it[1]
		var k := Game.sku(type, tier)
		var ip := K.panel(list, "InsetPanel")
		ip.add_theme_stylebox_override("panel", T.flat(Color(0, 0, 0, 0.25), 5, Color(1, 1, 1, 0.04), 1, Vector2(12, 5)))
		var r := HBoxContainer.new()
		r.add_theme_constant_override("separation", 0)
		ip.add_child(r)
		var nm := VBoxContainer.new()
		nm.add_theme_constant_override("separation", -3)
		nm.custom_minimum_size.x = 310
		r.add_child(nm)
		K.label(nm, PM.display_name(type, tier), 18, T.TEXT, "BoldLabel")
		var retail := K.label(nm, "", 14, T.MUTED, "MutedLabel")
		var st := K.label(r, "", 20, T.TEXT, "BoldLabel")
		st.custom_minimum_size.x = 100
		st.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var pr := K.label(r, "", 20, T.ACCENT_HI, "BoldLabel")
		pr.custom_minimum_size.x = 150
		pr.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var step := HBoxContainer.new()
		step.add_theme_constant_override("separation", 6)
		step.custom_minimum_size.x = 170
		step.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		r.add_child(step)
		K.button(step, "−", func(): _add(k, -1), "SegButton", 20, Vector2(40, 38))
		var lq := K.lcd(step, "0", 26, Vector2(10, 0))
		lq[1].custom_minimum_size.x = 28
		lq[1].horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		K.button(step, "+", func(): _add(k, 1), "SegButton", 20, Vector2(40, 38))
		var ln := K.label(r, "", 19, T.TEXT, "BoldLabel")
		ln.custom_minimum_size.x = 110
		ln.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		ln.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_rows[k] = {"stock": st, "price": pr, "qty": lq[1], "line": ln, "retail": retail, "type": type, "tier": tier}
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
	for u in Game.UPGRADE_LIST:
		var ip := K.panel(p, "InsetPanel")
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		ip.add_child(row)
		var tcol := VBoxContainer.new()
		tcol.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tcol.add_theme_constant_override("separation", 0)
		row.add_child(tcol)
		K.label(tcol, u.name, 22, T.TEXT, "BoldLabel")
		K.label(tcol, u.desc, 16, T.MUTED, "MutedLabel")
		var uid: String = u.id
		var owned := CenterContainer.new()
		owned.custom_minimum_size = Vector2(200, 0)
		row.add_child(owned)
		K.stamp(owned, "ALINDI", T.GOOD, 20, -6.0)
		var b := K.button(row, "", func(): Game.buy_upgrade(uid), "PrimaryButton", 18, Vector2(200, 50))
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
		K.label(nm, PM.display_name(l.type, l.tier), 18, T.TEXT, "BoldLabel")
		K.label(nm, "Yeni fiyatı: %d TL" % Game.price_of(l.type, l.tier), 14, T.MUTED, "MutedLabel")
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


func _refresh_shop() -> void:
	var ch := (Game.market / maxf(Game.market_prev, 0.01) - 1.0) * 100.0
	var arrow := "▲" if ch > 0.5 else ("▼" if ch < -0.5 else "■")
	_market.text = "KUR %.2f %s%+.0f%%" % [Game.market, arrow, ch]
	_market.add_theme_color_override("font_color", T.BAD if ch > 0.5 else (T.LCD if ch < -0.5 else T.LCD_DIM))
	for k in _rows:
		var r: Dictionary = _rows[k]
		var n := Game.stock_of(r.type, r.tier)
		var cn := Game.stock_cheap_of(r.type, r.tier)
		r.stock.text = ((str(n) if n > 0 else "0") + (" +%dM" % cn if cn > 0 else "")) if n + cn > 0 else "YOK"
		r.stock.add_theme_color_override("font_color", T.TEXT if n + cn > 1 else (T.ACCENT if n + cn == 1 else T.BAD))
		var pr := Game.price_of(r.type, r.tier, _cheap)
		r.price.text = "%d TL" % pr
		r.price.add_theme_color_override("font_color", T.GOOD if _cheap else T.ACCENT_HI)
		r.retail.text = "Tezgahta satış: %d TL" % Game.retail_price(r.type, r.tier)
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
		r.retail.text = "Tezgahta satış: %d TL" % Game.retail_price(r.type, r.tier) + ("   ·   sepette %d %s" % [other, "orijinal" if _cheap else "muadil"] if other > 0 else "")
	var sub := Game.cart_subtotal(_cart)
	var raw := 0
	for k in _cart:
		var pk: PackedStringArray = k.split(":")
		raw += Game.price_of(pk[0], int(pk[1]), pk.size() > 2) * int(_cart[k])
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
