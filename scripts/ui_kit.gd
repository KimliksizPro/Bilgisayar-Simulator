extends RefCounted
## Arayüz yardımcıları: etiket, düğme, tuş kapağı, açılış/kapanış animasyonları.

const T := preload("res://scripts/ui_theme.gd")
const STAR := preload("res://scripts/star_rating.gd")


static func label(parent: Node, text: String, size := 18, color := T.TEXT, variation := "") -> Label:
	var l := Label.new()
	l.text = text
	if variation != "":
		l.theme_type_variation = variation
	if size != 18:
		l.add_theme_font_size_override("font_size", size)
	if color != T.TEXT:
		l.add_theme_color_override("font_color", color)
	if parent:
		parent.add_child(l)
	return l


## Tema düğmesi: tıklama/üstüne gelme sesi, üstüne gelince hafif büyüme, odak = üstüne gelme.
static func button(parent: Node, text: String, cb := Callable(), variation := "", font_size := 20, min_size := Vector2(0, 48)) -> Button:
	var b := Button.new()
	b.text = text
	if variation != "":
		b.theme_type_variation = variation
	if font_size != 20:
		b.add_theme_font_size_override("font_size", font_size)
	b.custom_minimum_size = min_size
	b.focus_mode = Control.FOCUS_ALL
	b.resized.connect(func(): b.pivot_offset = b.size * 0.5)
	b.mouse_entered.connect(func():
		if not b.disabled:
			b.grab_focus()
			Game.sfx.ui_hover())
	b.focus_entered.connect(func(): _grow(b, 1.025))
	b.focus_exited.connect(func(): _grow(b, 1.0))
	b.pressed.connect(func(): Game.sfx.ui_click())
	if cb.is_valid():
		b.pressed.connect(cb)
	if parent:
		parent.add_child(b)
	return b


static func _grow(b: Control, s: float) -> void:
	if not b.is_inside_tree():
		return
	if b.has_meta("tw"):
		var old: Tween = b.get_meta("tw")
		if old and old.is_valid():
			old.kill()
	var tw := b.create_tween()
	tw.tween_property(b, "scale", Vector2(s, s), 0.12).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	b.set_meta("tw", tw)


static func panel(parent: Node, variation := "") -> PanelContainer:
	var p := PanelContainer.new()
	if variation != "":
		p.theme_type_variation = variation
	if parent:
		parent.add_child(p)
	return p


## "E" gibi tuş kapağı kutusu.
static func keycap(parent: Node, text: String, size := 18) -> PanelContainer:
	var p := panel(parent, "KeyCap")
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := label(p, text, size, T.INK, "HeavyLabel")
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.custom_minimum_size = Vector2(maxf(30.0, size * 1.7), 0)
	return p


static func stars(parent: Node, px := 22, dim := Color(1, 1, 1, 0.16), on := T.ACCENT) -> Control:
	var s: Control = STAR.new()
	s.px = px
	s.dim = dim
	s.on = on
	if parent:
		parent.add_child(s)
	return s


static func hsep(parent: Node) -> HSeparator:
	var s := HSeparator.new()
	parent.add_child(s)
	return s


static func spacer(parent: Node, h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(c)
	return c


## Türkçe biçim: 12450 -> "12.450".
static func money(v: int) -> String:
	var s := str(absi(v))
	var out := ""
	for i in s.length():
		if i > 0 and (s.length() - i) % 3 == 0:
			out += "."
		out += s[i]
	return ("-" if v < 0 else "") + out


## Tam ekran karartma + ortalanmış ModalPanel; [kök, panel, içerik VBox] döndürür.
static func modal(parent: Node, width: float, dim := 0.7) -> Array:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.visible = false
	parent.add_child(root)
	var d := ColorRect.new()
	d.color = Color(0.01, 0.02, 0.05, dim)
	d.set_anchors_preset(Control.PRESET_FULL_RECT)
	d.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(d)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(cc)
	var pc := panel(cc, "ModalPanel")
	pc.custom_minimum_size = Vector2(width, 0)
	pc.resized.connect(func(): pc.pivot_offset = pc.size * 0.5)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	pc.add_child(vb)
	return [root, pc, vb]


static func open(root: Control, pnl: Control = null) -> void:
	root.visible = true
	root.modulate.a = 0.0
	var tw := root.create_tween().set_parallel(true)
	tw.tween_property(root, "modulate:a", 1.0, 0.18)
	if pnl:
		pnl.scale = Vector2(0.93, 0.93)
		tw.tween_property(pnl, "scale", Vector2.ONE, 0.26).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


static func close(root: Control, pnl: Control = null) -> void:
	if not root.visible:
		return
	var tw := root.create_tween().set_parallel(true)
	tw.tween_property(root, "modulate:a", 0.0, 0.14)
	if pnl:
		tw.tween_property(pnl, "scale", Vector2(0.96, 0.96), 0.14)
	tw.chain().tween_callback(func(): root.visible = false)


## İlk odaklanabilir düğmeyi bulup odaklar (klavye/gamepad).
static func focus_first(n: Node) -> void:
	for c in n.find_children("*", "Button", true, false):
		if c is Button and c.is_visible_in_tree() and not c.disabled:
			c.grab_focus()
			return


## Pencere başlığı: tabela yazısı (Bungee) + altında sarı-siyah ikaz şeridi.
static func title(parent: Node, text: String, size := 34, color := T.ACCENT, stripe := true) -> Label:
	var l := label(parent, text, size, color, "TitleLabel")
	if stripe:
		var tr := TextureRect.new()
		tr.texture = T.hazard_tex()
		tr.stretch_mode = TextureRect.STRETCH_TILE
		tr.custom_minimum_size = Vector2(0, 6)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.modulate.a = 0.85
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(tr)
	return l


## Yazar kasa LCD ekranı: [panel, etiket].
static func lcd(parent: Node, text: String, size := 34, pad := Vector2(14, 2)) -> Array:
	var p := panel(parent, "LcdPanel")
	p.add_theme_stylebox_override("panel", T.lcd_box(pad))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := label(p, text, size, T.LCD, "LcdLabel")
	lcd_glow(l)
	return [p, l]


static func lcd_glow(l: Label, color := T.LCD) -> void:
	l.add_theme_constant_override("outline_size", 8)
	l.add_theme_color_override("font_outline_color", Color(color.r, color.g, color.b, 0.16))


## Eğik lastik mühür (kapsayıcı döndürmeyi sıfırladığı için sabit boyutlu bir taşıyıcı içinde).
static func stamp(parent: Node, text: String, color := T.STAMP_RED, size := 18, angle := -6.0) -> Array:
	var holder := Control.new()
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(holder)
	var p := panel(holder, "")
	p.add_theme_stylebox_override("panel", T.stamp_box(color))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := label(p, text, size, color, "SignLabel")
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.rotation_degrees = angle
	p.resized.connect(func():
		p.pivot_offset = p.size * 0.5
		var a := absf(deg_to_rad(angle))
		var bb := Vector2(p.size.x * cos(a) + p.size.y * sin(a), p.size.x * sin(a) + p.size.y * cos(a))
		holder.custom_minimum_size = bb + Vector2(6, 6)
		p.position = (holder.custom_minimum_size - p.size) * 0.5)
	return [holder, p, l]


## El yazısı etiketi (Caveat).
static func hand(parent: Node, text: String, size := 28, color := T.PEN) -> Label:
	return label(parent, text, size, color, "HandLabel")
