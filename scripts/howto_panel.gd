extends Control
## "Nasıl Oynanır" ekranı: kontroller, oyun döngüsü, arıza rehberi, gün/kira/itibar.

const T := preload("res://scripts/ui_theme.gd")
const K := preload("res://scripts/ui_kit.gd")

signal back

var _root: Control
var _panel: Control
var _scroll: ScrollContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := K.modal(self, 980, 0.62)
	_root = m[0]
	_panel = m[1]
	var vb: VBoxContainer = m[2]
	K.label(vb, "Nasıl Oynanır?", 36, T.ACCENT, "TitleLabel")
	K.hsep(vb)
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(0, 470)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(_scroll)
	var c := VBoxContainer.new()
	c.add_theme_constant_override("separation", 14)
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(c)
	_controls(c)
	_loop(c)
	_guide(c)
	_economy(c)
	K.hsep(vb)
	var foot := HBoxContainer.new()
	vb.add_child(foot)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(sp)
	K.button(foot, "Geri", func(): back.emit(), "PrimaryButton", 20, Vector2(150, 46))


func is_open() -> bool:
	return _root != null and _root.visible


func open() -> void:
	_scroll.scroll_vertical = 0
	K.open(_root, _panel)
	K.focus_first(_root)


func close() -> void:
	K.close(_root, _panel)


func _unhandled_input(event: InputEvent) -> void:
	if is_open() and event.is_action_pressed("ui_cancel"):
		Game.sfx.ui_back()
		back.emit()
		get_viewport().set_input_as_handled()


func _section(parent: Control, title: String) -> VBoxContainer:
	var p := K.panel(parent, "InsetPanel")
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	K.label(v, title, 24, T.ACCENT, "BoldLabel")
	return v


func _para(parent: Control, text: String, color := T.TEXT) -> Label:
	var l := K.label(parent, text, 18, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(300, 0)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


func _controls(parent: Control) -> void:
	var v := _section(parent, "Kontroller")
	var g := GridContainer.new()
	g.columns = 4
	g.add_theme_constant_override("h_separation", 14)
	g.add_theme_constant_override("v_separation", 10)
	v.add_child(g)
	var rows := [["WASD", "Yürü"], ["Shift", "Koş"], ["E / Sol tık", "Etkileşim"], ["G / Sağ tık", "Elindekini bırak"],
		["Esc", "Duraklat / menü"], ["F2", "Grafik kalitesi"], ["F3", "FPS sayacı"], ["Fare", "Etrafa bak"]]
	for r in rows:
		var cell := HBoxContainer.new()
		cell.custom_minimum_size = Vector2(150, 0)
		g.add_child(cell)
		K.keycap(cell, r[0], 16)
		var l := K.label(g, r[1], 18, T.TEXT)
		l.custom_minimum_size = Vector2(190, 0)


func _step(parent: Control, n: int, title: String, body: String) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	parent.add_child(h)
	var badge := K.panel(h, "KeyCap")
	badge.custom_minimum_size = Vector2(40, 0)
	badge.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	var nl := K.label(badge, str(n), 20, T.ACCENT_HI, "BoldLabel")
	nl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var t := VBoxContainer.new()
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	t.add_theme_constant_override("separation", 0)
	h.add_child(t)
	K.label(t, title, 19, T.TEXT, "BoldLabel")
	_para(t, body, T.MUTED)


func _loop(parent: Control) -> void:
	var v := _section(parent, "Oyun Döngüsü")
	_step(v, 1, "Müşteriyi karşıla", "Tezgaha gelen müşteriye bak ve E'ye bas. Derdini anlatır, bilgisayarını masana bırakır.")
	_step(v, 2, "Arızayı bul", "Bilgisayarın cam kapağını aç, güç düğmesine bas. Bip seslerini, ekranı ve anakartın hata LED'lerini izle.")
	_step(v, 3, "Parçayı değiştir", "Arızalı parçayı sök (E), hurda kutusuna at. Raftan yenisini satın al ve yuvaya tak.")
	_step(v, 4, "Teslim et", "Kapağı kapat, bilgisayarı çalıştır ve müşteriyle konuş. Ücretini alırsın; hızlı servis itibarı artırır.")


func _guide(parent: Control) -> void:
	var v := _section(parent, "Arıza Rehberi")
	var g := GridContainer.new()
	g.columns = 2
	g.add_theme_constant_override("h_separation", 24)
	g.add_theme_constant_override("v_separation", 6)
	v.add_child(g)
	var rows := [
		["Hiçbir tepki yok", "Güç kaynağı (PSU)"],
		["Fan dönüyor, bip yok, görüntü yok", "İşlemci (CPU)"],
		["Sürekli kısa bipler", "RAM"],
		["1 uzun 3 kısa bip", "Ekran kartı (GPU)"],
		["\"Boot device\" hatası", "SSD"],
		["Açılıp kendi kendine kapanma", "Aşırı ısınma"],
		["Tek kısa bip, sorunsuz açılış", "Her şey yolunda"],
	]
	for r in rows:
		var a := K.label(g, r[0], 18, T.TEXT)
		a.custom_minimum_size = Vector2(380, 0)
		K.label(g, r[1], 18, T.GOOD if r[1].begins_with("Her şey") else T.ACCENT_HI, "BoldLabel")
	K.spacer(v, 4)
	_para(v, "Hata LED'leri: anakartta CPU, DRAM, VGA ve BOOT ışıkları vardır. Açılışta yanan LED sorunlu parçayı gösterir.", T.MUTED)
	K.spacer(v, 2)
	K.label(v, "Aşırı ısınma", 20, T.TEXT, "BoldLabel")
	_para(v, "Toz birikmişse: basınçlı hava (aleti al, tozlu parçaya E). Macun kurumuşsa: termal macun sür. Bilgisayar ısınınca kendini kapatır; sebebi temizlemeden teslim etme.", T.MUTED)


func _economy(parent: Control) -> void:
	var v := _section(parent, "Gün, Kira ve İtibar")
	_para(v, "Dükkân her gün 09:00 - 19:00 arası açıktır. Kapanışta gün sonu özeti açılır: gelir, parça giderleri, kira ve net kazanç.")
	_para(v, "Kira: her gün sonunda ödenir ve zamanla artar. Kasa üst üste iki gün eksi kalırsa iflas edersin.", T.MUTED)
	_para(v, "İtibar (5 yıldız): hızlı ve doğru servis artırır, hatalı teslim ve kızıp giden müşteri düşürür. İtibar iş ücretini ve müşteri sıklığını etkiler.")
	_para(v, "Sabır: müşteriler uzun beklemeyi sevmez. Sağ üstteki çubuk kalan sabrı gösterir; renk yeşilden kırmızıya döner.", T.MUTED)
	_para(v, "Yükseltmeler: tezgahtaki laptopla Yönetim Paneli'ni aç. Reklam tabelası, toptan anlaşma, kahve makinesi ve usta sertifikası alabilirsin.")
	_para(v, "Oyun gün sonunda ve çıkarken otomatik kaydedilir.", T.MUTED)
