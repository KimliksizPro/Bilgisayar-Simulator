extends RefCounted
## Ortak arayüz teması: "mahalle tamirhanesi" kimliği.
## - Paneller: köşeleri vidalı, hafif kabartmalı metal plaka
## - Düğmeler: mekanik klavye tuşu (basınca içeri gömülür); tuş ipuçları eski bej klavye tuşu
## - Kâğıt (servis fişi / Z raporu), LCD (yazar kasa), segmentli LED çubuklar
## `build()` tüm oyunun temasını üretir (assets/ui/theme.res bu fonksiyonla dev/make_theme.gd tarafından oluşturulur).

# --- atölye paleti (sıcak grafit + tabela amberi) ---
const BG := Color("0f1013")
const PANEL := Color("1d1f24")
const PANEL2 := Color("2a2d34")
const PANEL3 := Color("373b44")
const BORDER := Color("454a55")
const ACCENT := Color("ffb52e")
const ACCENT_HI := Color("ffcf6b")
const ACCENT_LO := Color("c98512")
const TEXT := Color("efe9dc")
const MUTED := Color("a39d90")
const GOOD := Color("74e08a")
const BAD := Color("ff6a50")
const INFO := Color("6cc9ff")
# kâğıt / mürekkep
const PAPER := Color("f3ebd7")
const PAPER_DARK := Color("ddd0b2")
const INK := Color("2b2620")
const INK_MUTED := Color("7a6f5e")
const PEN := Color("1f3f94")        # tükenmez kalem mavisi
const STAMP_RED := Color("c4362a")
const STAMP_GREEN := Color("23824a")
# yazar kasa LCD
const LCD_BG := Color("0c1a10")
const LCD := Color("9df58a")
const LCD_DIM := Color("4f8f4a")
# eski klavye tuşu
const BEIGE := Color("e4d9bf")
const STICKY := Color("ffe270")

const FONT_PATH := "res://assets/fonts/Exo2.ttf"
const SIGN_FONT := "res://assets/fonts/Bungee.ttf"
const LCD_FONT := "res://assets/fonts/VT323.ttf"
const HAND_FONT := "res://assets/fonts/Caveat.ttf"
const WGHT_TAG := 2003265652   # "wght" OpenType ekseni


static func font(weight: int, spacing := 0) -> FontVariation:
	var fv := FontVariation.new()
	fv.base_font = load(FONT_PATH)
	fv.variation_opentype = {WGHT_TAG: weight}
	if spacing != 0:
		fv.spacing_glyph = spacing
	return fv


static func sign_font(spacing := 0) -> Font:
	var fv := FontVariation.new()
	fv.base_font = load(SIGN_FONT)
	fv.spacing_glyph = spacing
	return fv


static func lcd_font() -> Font:
	return load(LCD_FONT)


static func hand_font() -> FontVariation:
	var fv := FontVariation.new()
	fv.base_font = load(HAND_FONT)
	fv.variation_opentype = {WGHT_TAG: 700}
	return fv


static func flat(bg: Color, radius := 10, border := Color(0, 0, 0, 0), bw := 0, pad := Vector2(16, 10), shadow := 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(radius)
	s.set_border_width_all(bw)
	s.border_color = border
	s.content_margin_left = pad.x
	s.content_margin_right = pad.x
	s.content_margin_top = pad.y
	s.content_margin_bottom = pad.y
	if shadow > 0:
		s.shadow_size = shadow
		s.shadow_color = Color(0, 0, 0, 0.42)
		s.shadow_offset = Vector2(0, shadow * 0.35)
	s.anti_aliasing = true
	return s


# ------------------------------------------------------------------ çizim yardımcıları
static func _alpha(d: float) -> float:
	return clampf(0.5 - d, 0.0, 1.0)


## Yuvarlatılmış dikdörtgen işaretli mesafe (içeride negatif).
static func _sd_rrect(p: Vector2, lo: Vector2, hi: Vector2, r: float) -> float:
	var c := (lo + hi) * 0.5
	var half := (hi - lo) * 0.5
	var q := (p - c).abs() - half + Vector2(r, r)
	return Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0) - r


static func _over(dst: Color, src: Color) -> Color:
	var a := src.a + dst.a * (1.0 - src.a)
	if a <= 0.0001:
		return Color(0, 0, 0, 0)
	var rgb := (Vector3(src.r, src.g, src.b) * src.a + Vector3(dst.r, dst.g, dst.b) * dst.a * (1.0 - src.a)) / a
	return Color(rgb.x, rgb.y, rgb.z, a)


static func _hash(x: int, y: int) -> float:
	var n := (x * 374761393 + y * 668265263) & 0x7fffffff
	n = ((n ^ (n >> 13)) * 1274126177) & 0x7fffffff
	return float(n & 0xffff) / 65535.0


## Yıldız tornavida başlı vida.
static func _screw(p: Vector2, c: Vector2, r: float, base: Color) -> Color:
	var d := p.distance_to(c)
	if d > r + 1.0:
		return Color(0, 0, 0, 0)
	var t := clampf(d / r, 0.0, 1.0)
	var lit := clampf(0.5 - (p - c).normalized().dot(Vector2(0.6, 0.8)) * 0.5, 0.0, 1.0) if d > 0.01 else 0.5
	var col := base.lightened(0.35 * lit).darkened(0.25 * t)
	# ince koyu kenar
	col = col.lerp(base.darkened(0.6), clampf((d - (r - 1.0)), 0.0, 1.0))
	# çapraz yiv
	var q := (p - c).rotated(PI / 4.0)
	if (absf(q.x) < 0.7 or absf(q.y) < 0.7) and d < r - 1.2:
		col = base.darkened(0.65)
	col.a = _alpha(d - r)
	return col


## Metal plaka: kabartma kenar, hafif dikey ışık geçişi, isteğe bağlı köşe vidaları ve gömülü gölge.
static func _plate_tex(base: Color, radius := 7.0, screws := true, pad := 10, size := 72, alpha := 1.0) -> ImageTexture:
	var w := size + pad * 2
	var img := Image.create(w, w, false, Image.FORMAT_RGBA8)
	var lo := Vector2(pad, pad)
	var hi := Vector2(pad + size, pad + size)
	for y in w:
		for x in w:
			var p := Vector2(x + 0.5, y + 0.5)
			var d := _sd_rrect(p, lo, hi, radius)
			# gölge (aşağı kaymış, yumuşak)
			var ds := _sd_rrect(p - Vector2(0, 4), lo, hi, radius)
			var sh := clampf(1.0 - (ds + 1.0) / float(pad), 0.0, 1.0)
			var col := Color(0, 0, 0, sh * sh * 0.55)
			if d < 0.5:
				var v := (p.y - lo.y) / size
				var face := base.lightened(0.07 * (1.0 - v)).darkened(0.12 * v)
				# fırçalanmış metal: çok hafif yatay çizgiler
				face = face.lightened((_hash(0, y) - 0.5) * 0.035)
				# kabartma kenar: üst/sol açık, alt/sağ koyu
				if d > -2.0:
					var g := (p - (lo + hi) * 0.5)
					var up := clampf(-g.y / (size * 0.5), -1.0, 1.0) * 0.6 + clampf(-g.x / (size * 0.5), -1.0, 1.0) * 0.4
					face = face.lightened(0.22 * maxf(up, 0.0)).darkened(0.35 * maxf(-up, 0.0))
				if d > -0.6:
					face = face.darkened(0.55)
				face.a = alpha
				col = _over(col, Color(face.r, face.g, face.b, _alpha(d) * alpha))
			if screws and d < -3.0:
				for sc in [Vector2(lo.x + 12, lo.y + 12), Vector2(hi.x - 12, lo.y + 12), Vector2(lo.x + 12, hi.y - 12), Vector2(hi.x - 12, hi.y - 12)]:
					var s := _screw(p, sc, 4.6, Color("8d929c"))
					if s.a > 0.0:
						col = _over(col, s)
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


static func plate_box(base := PANEL, screws := true, pad := Vector2(26, 20), alpha := 1.0, shadow_pad := 10) -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	s.texture = _plate_tex(base, 7.0, screws, shadow_pad, 72, alpha)
	var m := float(shadow_pad + 20)
	s.texture_margin_left = m
	s.texture_margin_right = m
	s.texture_margin_top = m
	s.texture_margin_bottom = m
	s.set_expand_margin_all(shadow_pad)
	s.content_margin_left = pad.x
	s.content_margin_right = pad.x
	s.content_margin_top = pad.y
	s.content_margin_bottom = pad.y
	return s


## Mekanik klavye tuşu: koyu etek + üst yüz. `press` 0..1 arası gömülme.
static func _key_tex(base: Color, press := 0.0, w := 56, h := 56) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var skirt := lerpf(7.0, 2.0, press)
	var drop := lerpf(0.0, 4.0, press)
	var outer_lo := Vector2(0.5, 0.5 + drop)
	var outer_hi := Vector2(w - 0.5, h - 0.5)
	var face_lo := Vector2(3.5, 2.5 + drop)
	var face_hi := Vector2(w - 3.5, h - 0.5 - skirt)
	for y in h:
		for x in w:
			var p := Vector2(x + 0.5, y + 0.5)
			var d := _sd_rrect(p, outer_lo, outer_hi, 9.0)
			var col := Color(0, 0, 0, 0)
			if d < 0.5:
				# etek: koyu, alt kısmı daha koyu
				var sv := clampf((p.y - outer_lo.y) / (outer_hi.y - outer_lo.y), 0.0, 1.0)
				var sk := base.darkened(0.38 + 0.22 * sv)
				if d > -1.0:
					sk = sk.darkened(0.5)
				col = Color(sk.r, sk.g, sk.b, _alpha(d))
				var fd := _sd_rrect(p, face_lo, face_hi, 7.0)
				if fd < 0.5:
					var v := clampf((p.y - face_lo.y) / (face_hi.y - face_lo.y), 0.0, 1.0)
					var face := base.lightened(0.14 * (1.0 - v)).darkened(0.05 * v)
					# yüzün üst kenarında ince parlama
					if fd > -1.6 and p.y < face_lo.y + 5.0:
						face = face.lightened(0.25)
					# hafif içbükey: kenara doğru koyulaşma
					face = face.darkened(0.08 * clampf(1.0 + fd / 6.0, 0.0, 1.0))
					col = _over(col, Color(face.r, face.g, face.b, _alpha(fd)))
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


static func key_box(base: Color, press := 0.0, pad := Vector2(22, 0), small := false) -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	if small:
		s.texture = _key_tex(base, press, 30, 30)
		s.texture_margin_left = 9
		s.texture_margin_right = 9
		s.texture_margin_top = 9
		s.texture_margin_bottom = 11
	else:
		s.texture = _key_tex(base, press)
		s.texture_margin_left = 14
		s.texture_margin_right = 14
		s.texture_margin_top = 14
		s.texture_margin_bottom = 16
	var skirt := lerpf(7.0, 2.0, press) if not small else lerpf(5.0, 2.0, press)
	var drop := lerpf(0.0, 4.0, press)
	s.content_margin_left = pad.x
	s.content_margin_right = pad.x
	s.content_margin_top = (pad.y if pad.y > 0 else 6.0) + drop
	s.content_margin_bottom = (pad.y if pad.y > 0 else 6.0) + skirt
	return s


## Kâğıt: krem renk, lif lekeleri, isteğe bağlı tırtıklı (yırtık) üst/alt kenar.
static func _paper_tex(top_zig: bool, bottom_zig: bool, base := PAPER, pad := 8) -> ImageTexture:
	var w := 64 + pad * 2
	var h := 64 + pad * 2
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var period := 8.0
	var amp := 4.0
	for y in h:
		for x in w:
			var p := Vector2(x + 0.5, y + 0.5)
			var top := float(pad)
			var bot := float(h - pad)
			var tri := absf(fmod(p.x - pad, period) / period - 0.5) * 2.0   # 0..1 testere dişi
			if top_zig:
				top += tri * amp
			if bottom_zig:
				bot -= tri * amp
			var inside := minf(minf(p.y - top, bot - p.y), minf(p.x - pad, w - pad - p.x))
			# gölge
			var sp := p - Vector2(0, 3)
			var sin_ := minf(minf(sp.y - top, bot - sp.y), minf(sp.x - pad, w - pad - sp.x))
			var col := Color(0, 0, 0, clampf((sin_ + pad) / float(pad), 0.0, 1.0) * 0.4 if sin_ > -pad else 0.0)
			if inside > -0.5:
				var n := _hash(x, y)
				var c := base.darkened(0.05 * n)
				if n > 0.985:
					c = c.darkened(0.12)
				col = _over(col, Color(c.r, c.g, c.b, clampf(inside + 0.5, 0.0, 1.0)))
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


static func paper_box(top_zig := false, bottom_zig := true, pad := Vector2(22, 18), base := PAPER) -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	var sp := 8
	s.texture = _paper_tex(top_zig, bottom_zig, base, sp)
	s.texture_margin_left = sp + 8
	s.texture_margin_right = sp + 8
	s.texture_margin_top = sp + 8
	s.texture_margin_bottom = sp + 8
	s.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	s.set_expand_margin_all(sp)
	s.content_margin_left = pad.x
	s.content_margin_right = pad.x
	s.content_margin_top = pad.y + (4 if top_zig else 0)
	s.content_margin_bottom = pad.y + (4 if bottom_zig else 0)
	return s


## Segmentli LED çubuğu dokusu (beyaz; modulate_color ile renklenir).
static func _seg_tex(h := 12) -> ImageTexture:
	var img := Image.create(8, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in 8:
			var on := x < 6
			img.set_pixel(x, y, Color(1, 1, 1, 1.0 if on else 0.0) if not on or (y > 0 and y < h - 1) else Color(1, 1, 1, 0.7))
	return ImageTexture.create_from_image(img)


static func seg_box(color: Color) -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	s.texture = _seg_tex()
	s.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE
	s.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_STRETCH
	s.modulate_color = color
	return s


static func groove_box(pad := 2) -> StyleBoxFlat:
	var s := flat(Color(0, 0, 0, 0.55), 3, Color(1, 1, 1, 0.06), 1, Vector2(pad, pad))
	s.border_width_top = 2
	s.border_color = Color(0, 0, 0, 0.6)
	return s


static func lcd_box(pad := Vector2(14, 6)) -> StyleBoxFlat:
	var s := flat(LCD_BG, 5, Color("040a05"), 2, pad)
	s.border_width_top = 3
	s.shadow_color = Color(LCD.r, LCD.g, LCD.b, 0.05)
	s.shadow_size = 0
	return s


## Lastik mühür kutusu (çift çizgili kenar hissi için kalın kenarlık).
static func stamp_box(color: Color) -> StyleBoxFlat:
	var s := flat(Color(color.r, color.g, color.b, 0.06), 4, Color(color.r, color.g, color.b, 0.85), 3, Vector2(10, 2))
	return s


## Sürgü topuzu: mikser kanal sürgüsü (fader) başlığı.
static func _fader_tex(hot: bool) -> ImageTexture:
	var w := 18
	var h := 30
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in h:
		for x in w:
			var p := Vector2(x + 0.5, y + 0.5)
			var d := _sd_rrect(p, Vector2(1, 1), Vector2(w - 1, h - 1), 4.0)
			var v := p.y / h
			var c := Color("3c4049").lightened(0.25 * (1.0 - v)) if not hot else Color("4a4f5a").lightened(0.3 * (1.0 - v))
			if d > -1.2:
				c = c.darkened(0.6)
			if absf(p.y - h * 0.5) < 1.5 and absf(p.x - w * 0.5) < w * 0.5 - 3.0:
				c = ACCENT if not hot else ACCENT_HI
			for k in [-6, -3, 3, 6]:
				if absf(p.y - h * 0.5 - k) < 0.5 and absf(p.x - w * 0.5) < w * 0.5 - 4.0:
					c = c.darkened(0.35)
			c.a = _alpha(d)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


## Açma/kapama: kare kenarlı mekanik anahtar + durum LED'i.
static func _switch_tex(on: bool, disabled := false) -> ImageTexture:
	var w := 56
	var h := 28
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var knob_lo := Vector2(w - 26, 3) if on else Vector2(3, 3)
	for y in h:
		for x in w:
			var p := Vector2(x + 0.5, y + 0.5)
			var d := _sd_rrect(p, Vector2(0.5, 0.5), Vector2(w - 0.5, h - 0.5), 6.0)
			var track := Color("0c0d10")
			if d > -1.5:
				track = Color("50555f")
			var col := Color(track.r, track.g, track.b, _alpha(d))
			# LED (kapalı tarafta görünür)
			var led_c := Vector2(14, h * 0.5) if on else Vector2(w - 14, h * 0.5)
			var ld := p.distance_to(led_c)
			var led := (ACCENT if on else Color("2a1c08")) if not disabled else Color(0.13, 0.13, 0.13)
			if ld < 7.0 and on and not disabled:
				col = _over(col, Color(ACCENT.r, ACCENT.g, ACCENT.b, (1.0 - ld / 7.0) * 0.35))
			if ld < 4.0:
				col = _over(col, Color(led.r, led.g, led.b, _alpha(ld - 3.5)))
			var kd := _sd_rrect(p, knob_lo, knob_lo + Vector2(23, 22), 4.0)
			if kd < 0.5:
				var v := (p.y - knob_lo.y) / 22.0
				var kc := Color("d8d2c2").lightened(0.15 * (1.0 - v)).darkened(0.15 * v)
				if disabled:
					kc = kc.darkened(0.45)
				if kd > -1.0:
					kc = kc.darkened(0.4)
				for k in [-4, 0, 4]:
					if absf(p.x - (knob_lo.x + 11.5 + k)) < 0.6 and absf(p.y - h * 0.5) < 5.0:
						kc = kc.darkened(0.3)
				col = _over(col, Color(kc.r, kc.g, kc.b, _alpha(kd)))
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)


## Sarı-siyah ikaz şeridi (başlık süsü).
static func hazard_tex() -> ImageTexture:
	var img := Image.create(24, 12, false, Image.FORMAT_RGBA8)
	var dark := Color("17181b")
	for y in 12:
		for x in 24:
			var t := fmod(float(x + y) + 0.5, 12.0)
			var a := clampf(minf(t, 6.0 - t) + 0.5, 0.0, 1.0) if t < 6.0 else 0.0
			img.set_pixel(x, y, dark.lerp(ACCENT, a))
	return ImageTexture.create_from_image(img)


# ------------------------------------------------------------------ tema
static func build() -> Theme:
	var t := Theme.new()
	var regular := font(500)
	var bold := font(700)
	var heavy := font(800)
	t.default_font = regular
	t.default_font_size = 18

	# --- Label ---
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0))
	t.set_constant("line_spacing", "Label", 2)
	for pair in [["BoldLabel", bold, TEXT], ["TitleLabel", sign_font(1), ACCENT], ["MutedLabel", regular, MUTED],
			["AccentLabel", bold, ACCENT], ["SmallCaps", font(800, 2), MUTED], ["HeavyLabel", heavy, TEXT],
			["SignLabel", sign_font(1), ACCENT], ["LcdLabel", lcd_font(), LCD], ["HandLabel", hand_font(), PEN],
			["InkLabel", bold, INK], ["ReceiptLabel", lcd_font(), INK]]:
		t.set_type_variation(pair[0], "Label")
		t.set_font("font", pair[0], pair[1])
		t.set_color("font_color", pair[0], pair[2])
	t.set_color("font_shadow_color", "TitleLabel", Color(0, 0, 0, 0.6))
	t.set_constant("shadow_offset_x", "TitleLabel", 0)
	t.set_constant("shadow_offset_y", "TitleLabel", 3)

	# --- Paneller ---
	var plate := plate_box(PANEL, true, Vector2(26, 22))
	t.set_stylebox("panel", "PanelContainer", plate)
	t.set_stylebox("panel", "Panel", plate)
	t.set_type_variation("ModalPanel", "PanelContainer")
	t.set_stylebox("panel", "ModalPanel", plate_box(PANEL, true, Vector2(34, 28)))
	t.set_type_variation("HudCard", "PanelContainer")
	t.set_stylebox("panel", "HudCard", plate_box(PANEL, false, Vector2(16, 12), 0.93, 8))
	t.set_type_variation("ScrewCard", "PanelContainer")
	t.set_stylebox("panel", "ScrewCard", plate_box(PANEL, true, Vector2(24, 18), 0.95, 8))
	t.set_type_variation("InsetPanel", "PanelContainer")
	var inset := flat(Color(0, 0, 0, 0.3), 6, Color(1, 1, 1, 0.05), 1, Vector2(16, 12))
	inset.border_width_top = 2
	inset.border_color = Color(0, 0, 0, 0.45)
	inset.border_width_bottom = 1
	t.set_stylebox("panel", "InsetPanel", inset)
	t.set_type_variation("PaperPanel", "PanelContainer")
	t.set_stylebox("panel", "PaperPanel", paper_box(false, true))
	t.set_type_variation("ReceiptPanel", "PanelContainer")
	t.set_stylebox("panel", "ReceiptPanel", paper_box(true, true, Vector2(34, 22), Color("f5f1e6")))
	t.set_type_variation("LcdPanel", "PanelContainer")
	t.set_stylebox("panel", "LcdPanel", lcd_box())
	t.set_type_variation("KeyCap", "PanelContainer")
	t.set_stylebox("panel", "KeyCap", key_box(BEIGE, 0.0, Vector2(8, 1), true))
	t.set_type_variation("Pill", "PanelContainer")
	t.set_stylebox("panel", "Pill", stamp_box(GOOD))
	t.set_type_variation("Toast", "PanelContainer")
	var toast := flat(Color(0.075, 0.08, 0.095, 0.94), 4, Color(1, 1, 1, 0.08), 1, Vector2(14, 9), 8)
	t.set_stylebox("panel", "Toast", toast)
	t.set_type_variation("StickyNote", "PanelContainer")
	var sticky := flat(STICKY, 2, Color(0, 0, 0, 0), 0, Vector2(22, 16), 10)
	sticky.shadow_offset = Vector2(3, 6)
	sticky.shadow_color = Color(0, 0, 0, 0.35)
	t.set_stylebox("panel", "StickyNote", sticky)

	# --- Düğmeler: klavye tuşları ---
	var focus := flat(Color(0, 0, 0, 0), 11, ACCENT, 2, Vector2(0, 0))
	focus.set_expand_margin_all(3)
	focus.shadow_color = Color(ACCENT.r, ACCENT.g, ACCENT.b, 0.0)
	var empty := StyleBoxEmpty.new()
	var keys := {
		"Button": [PANEL3, TEXT, Vector2(22, 0)],
		"PrimaryButton": [ACCENT, Color("241703"), Vector2(26, 0)],
		"DangerButton": [Color("8d2a20"), Color("ffe1da"), Vector2(22, 0)],
		"BigMenuButton": [PANEL3, TEXT, Vector2(24, 0)],
		"SegButton": [PANEL3, TEXT, Vector2(14, 0)],
	}
	for k in keys:
		var base: Color = keys[k][0]
		var fc: Color = keys[k][1]
		var pd: Vector2 = keys[k][2]
		if k != "Button":
			t.set_type_variation(k, "Button")
		t.set_stylebox("normal", k, key_box(base, 0.0, pd))
		t.set_stylebox("hover", k, key_box(base.lightened(0.12), 0.0, pd))
		t.set_stylebox("pressed", k, key_box(base.darkened(0.05), 1.0, pd))
		t.set_stylebox("hover_pressed", k, key_box(base, 1.0, pd))
		t.set_stylebox("disabled", k, key_box(Color("2a2c31"), 0.6, pd))
		t.set_stylebox("focus", k, focus if k != "SegButton" else empty)
		for c in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
			t.set_color(c, k, fc)
		t.set_color("font_disabled_color", k, Color(0.55, 0.53, 0.5, 0.7))
	t.set_font("font", "Button", bold)
	t.set_font_size("font_size", "Button", 20)
	t.set_constant("h_separation", "Button", 10)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_hover_color", "BigMenuButton", ACCENT_HI)
	t.set_color("font_focus_color", "BigMenuButton", ACCENT_HI)
	t.set_font_size("font_size", "BigMenuButton", 24)
	t.set_font("font", "BigMenuButton", heavy)
	t.set_font_size("font_size", "SegButton", 17)
	# SegButton seçili: amber tuş, basılı kalmış (kilitli tuş gibi)
	t.set_stylebox("pressed", "SegButton", key_box(ACCENT, 0.75, Vector2(14, 0)))
	t.set_stylebox("hover_pressed", "SegButton", key_box(ACCENT_HI, 0.75, Vector2(14, 0)))
	for c in ["font_pressed_color", "font_hover_pressed_color"]:
		t.set_color(c, "SegButton", Color("241703"))

	# Sekme düğmesi: dosya klasörü sekmesi
	t.set_type_variation("TabButton", "Button")
	var tab_n := flat(Color(0, 0, 0, 0), 6, Color(0, 0, 0, 0), 0, Vector2(20, 8))
	var tab_h := flat(Color(1, 1, 1, 0.04), 6, Color(0, 0, 0, 0), 0, Vector2(20, 8))
	var tab_on := flat(PANEL3, 6, ACCENT, 0, Vector2(20, 8))
	tab_on.border_width_top = 3
	tab_on.corner_radius_bottom_left = 0
	tab_on.corner_radius_bottom_right = 0
	for st in ["normal", "focus"]:
		t.set_stylebox(st, "TabButton", tab_n)
	t.set_stylebox("hover", "TabButton", tab_h)
	t.set_stylebox("pressed", "TabButton", tab_on)
	t.set_stylebox("hover_pressed", "TabButton", tab_on)
	t.set_font("font", "TabButton", font(800, 1))
	t.set_color("font_color", "TabButton", MUTED)
	t.set_color("font_hover_color", "TabButton", TEXT)
	t.set_color("font_focus_color", "TabButton", ACCENT_HI)
	t.set_color("font_pressed_color", "TabButton", ACCENT_HI)
	t.set_color("font_hover_pressed_color", "TabButton", ACCENT_HI)

	# --- CheckButton (anahtar + LED) ---
	var cb := "CheckButton"
	for st in ["normal", "pressed", "hover", "hover_pressed", "disabled"]:
		t.set_stylebox(st, cb, empty)
	var cf := flat(Color(0, 0, 0, 0), 8, ACCENT, 2, Vector2(4, 4))
	t.set_stylebox("focus", cb, cf)
	t.set_icon("checked", cb, _switch_tex(true))
	t.set_icon("unchecked", cb, _switch_tex(false))
	t.set_icon("checked_disabled", cb, _switch_tex(true, true))
	t.set_icon("unchecked_disabled", cb, _switch_tex(false, true))
	t.set_icon("checked_mirrored", cb, _switch_tex(true))
	t.set_icon("unchecked_mirrored", cb, _switch_tex(false))
	t.set_color("font_color", cb, TEXT)

	# --- Sürgü: mikser fader'ı ---
	var track := groove_box(0)
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	t.set_stylebox("slider", "HSlider", track)
	var ga := flat(ACCENT_LO, 2, Color(0, 0, 0, 0), 0, Vector2(0, 4))
	t.set_stylebox("grabber_area", "HSlider", ga)
	t.set_stylebox("grabber_area_highlight", "HSlider", flat(ACCENT, 2, Color(0, 0, 0, 0), 0, Vector2(0, 4)))
	t.set_icon("grabber", "HSlider", _fader_tex(false))
	t.set_icon("grabber_highlight", "HSlider", _fader_tex(true))
	t.set_icon("grabber_disabled", "HSlider", _fader_tex(false))
	t.set_constant("center_grabber", "HSlider", 0)

	# --- İlerleme çubuğu: segmentli LED ---
	t.set_stylebox("background", "ProgressBar", groove_box(0))
	t.set_stylebox("fill", "ProgressBar", seg_box(ACCENT))

	# --- Kaydırma çubuğu ---
	for sb in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", sb, flat(Color(0, 0, 0, 0.3), 3, Color(0, 0, 0, 0), 0, Vector2(4, 4)))
		t.set_stylebox("grabber", sb, flat(Color("5a5f69"), 3, Color(0, 0, 0, 0), 0, Vector2(4, 4)))
		t.set_stylebox("grabber_highlight", sb, flat(ACCENT_LO, 3, Color(0, 0, 0, 0), 0, Vector2(4, 4)))
		t.set_stylebox("grabber_pressed", sb, flat(ACCENT, 3, Color(0, 0, 0, 0), 0, Vector2(4, 4)))

	# --- Ayırıcı: perçin hattı hissi veren çift çizgi ---
	var line := StyleBoxLine.new()
	line.color = Color(0, 0, 0, 0.5)
	line.thickness = 2
	t.set_stylebox("separator", "HSeparator", line)
	t.set_constant("separation", "HSeparator", 14)
	t.set_type_variation("InkSeparator", "HSeparator")
	var dash := StyleBoxLine.new()
	dash.color = Color(INK.r, INK.g, INK.b, 0.35)
	dash.thickness = 1
	t.set_stylebox("separator", "InkSeparator", dash)
	return t
