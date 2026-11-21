extends "res://scripts/device_base.gd"
## Müşteri telefonu: masada ekranı yukarı bakar. Açmak: ekran modülü sol kenardan kitap gibi kalkıp
## yana yatar (esnek kablosu bağlı). İçeride: batarya ve şarj soketi; ekran modülü de sökülebilir.

const PW := 0.075
const PL := 0.158
const PT := 0.0085
const LIFT := 0.0015        # arka kamera çıkıntısı
const OPEN_ANGLE := 3.2     # ~183 derece: ekran yüzüstü sola yatar
const SWOLLEN_ANGLE := 0.07 # şişmiş batarya ekranı kaldırır (~4 derece)
const COLORS := [Color(0.1, 0.13, 0.25), Color(0.85, 0.6, 0.62), Color(0.9, 0.9, 0.88), Color(0.2, 0.35, 0.28), Color(0.08, 0.08, 0.09)]

var hinge: Node3D
var body: Node3D
var _shake: Tween
var _liquid_node: Node3D


func _ready() -> void:
	device_name = "Telefon"
	_build()


func _build() -> void:
	body = Node3D.new()
	add_child(body)
	var col: Color = COLORS.pick_random()
	var back := MU.mat(col, 0.3, 0.15)
	var metal := MU.mat(col.lerp(Color(0.75, 0.76, 0.78), 0.6), 0.9, 0.25)
	var dark := MU.mat(Color(0.04, 0.04, 0.045), 0.2, 0.5)
	var mid := MU.mat(Color(0.3, 0.31, 0.33), 0.7, 0.4)
	# arka cam yuvası (alt yüz) + kamera çıkıntısı çerçevesi
	_add_slot("back", "tel_back", body, Vector3(0, 0.0006, 0), Vector3(0, 0, 180))
	MU.rbox(body, Vector3(0.028, 0.0015, 0.03), Vector3(-0.017, -0.00075, -0.057), back, 0.004)
	for p in [Vector2(-0.024, -0.064), Vector2(-0.024, -0.05), Vector2(-0.01, -0.057)]:
		MU.cyl(body, 0.0045, 0.0016, Vector3(p.x, -0.0008, p.y), MU.mat(Color(0.02, 0.02, 0.025), 0.5, 0.1), Vector3.ZERO, 16)
	# yan çerçeve (metal)
	var ft := 0.0025
	for sx in [-1, 1]:
		MU.rbox(body, Vector3(ft, PT, PL), Vector3(sx * (PW / 2 - ft / 2), PT / 2, 0), metal, 0.0011)
	for sz in [-1, 1]:
		MU.rbox(body, Vector3(PW, PT, ft), Vector3(0, PT / 2, sz * (PL / 2 - ft / 2)), metal, 0.0011)
	# yan tuşlar + alt kenar: USB-C ağzı ve hoparlör delikleri
	MU.rbox(body, Vector3(0.0012, 0.0026, 0.018), Vector3(PW / 2 + 0.0005, 0.0048, -0.028), metal, 0.0005)
	for z in [-0.04, -0.02]:
		MU.rbox(body, Vector3(0.0012, 0.0026, 0.012), Vector3(-PW / 2 - 0.0005, 0.0048, z), metal, 0.0005)
	MU.rbox(body, Vector3(0.009, 0.0032, 0.001), Vector3(0, 0.0045, PL / 2 + 0.0001), dark, 0.0012)
	for i in 5:
		MU.cyl(body, 0.0007, 0.001, Vector3(0.014 + i * 0.0035, 0.0045, PL / 2 + 0.0001), dark, Vector3(90, 0, 0), 8)
	# iç: ara şase, anakart, kameralar
	MU.box(body, Vector3(PW - 2 * ft, 0.0006, PL - 2 * ft), Vector3(0, 0.0015, 0), mid)
	MU.box(body, Vector3(0.064, 0.0010, 0.04), Vector3(0, 0.0023, -0.054), MU.tex_mat(MU.pcb_texture(Color(0.05, 0.12, 0.25))))
	var shield := MU.mat(Color(0.75, 0.76, 0.78), 0.9, 0.3)
	MU.rbox(body, Vector3(0.022, 0.0014, 0.02), Vector3(0.016, 0.0033, -0.052), shield, 0.0006)
	MU.rbox(body, Vector3(0.012, 0.0012, 0.012), Vector3(0.016, 0.0033, -0.068), shield, 0.0006)
	MU.rbox(body, Vector3(0.012, 0.0015, 0.006), Vector3(0.012, 0.0032, -0.033), dark, 0.0004)  # batarya konnektörü
	MU.rbox(body, Vector3(0.014, 0.0015, 0.006), Vector3(-0.012, 0.0032, -0.033), dark, 0.0004) # ekran konnektörü
	# titreşim motoru
	MU.rbox(body, Vector3(0.014, 0.003, 0.008), Vector3(0.02, 0.0032, 0.044), dark, 0.001)
	# sıvı teması oksit lekeleri (anakart üzerinde)
	_liquid_node = MU.no_merge(Node3D.new())
	body.add_child(_liquid_node)
	var ox := MU.mat(Color(0.32, 0.65, 0.36), 0.2, 0.85)
	var rust := MU.mat(Color(0.45, 0.22, 0.08), 0.1, 0.9)
	for lp in [Vector3(0.006, 0.0036, -0.052), Vector3(-0.004, 0.0034, -0.042)]:
		MU.sphere(_liquid_node, 0.0032, lp, ox, Vector3(1.5, 0.35, 1.3))
	MU.sphere(_liquid_node, 0.0028, Vector3(0.014, 0.0035, -0.058), rust, Vector3(1.4, 0.3, 1.2))
	_liquid_node.visible = false
	# yuvalar
	_add_slot("cam", "tel_cam", body, Vector3(-0.018, 0.0036, -0.056))
	_add_slot("bat", "tel_bat", body, Vector3(0, 0.0039, 0.012))
	_add_slot("spk", "tel_spk", body, Vector3(-0.018, 0.0032, 0.056))
	_add_slot("port", "tel_port", body, Vector3(0, 0.0031, 0.068))
	# ekran modülü menteşesi (sol kenar)
	hinge = MU.no_merge(Node3D.new())
	hinge.position = Vector3(-PW / 2 + 0.0015, 0.0058, 0)
	body.add_child(hinge)
	var s = _add_slot("scr", "tel_scr", hinge, Vector3(PW / 2 - 0.0015, 0.0014, 0))
	_make_screen(Vector2i(180, 380), s, Vector2(0.066, 0.142), Vector3(0, 0.0016, 0))
	# esnek kablo (menteşe boyunca, açılınca görünür)
	MU.box(hinge, Vector3(0.002, 0.0004, 0.014), Vector3(0.001, -0.0004, -0.033), MU.mat(Color(0.85, 0.5, 0.1), 0, 0.5))
	# etkileşim: telefonu aç/kapat ve güç tuşu
	MU.interactable(body, Vector3(PW, 0.003, PL), Vector3(0, 0.0015, 0),
		func(_p): return "Ekranı kapat  [E]" if panel_open else "Ekranı kaldır, telefonu aç  [E]",
		func(_p): toggle_panel())
	MU.interactable(body, Vector3(0.012, 0.012, 0.03), Vector3(PW / 2 + 0.005, 0.005, -0.028),
		func(_p): return "Telefonu kapat  [E]" if powered else "Güç tuşu  [E]",
		func(_p): power_button())
	MU.merge_static(body)
	_update_visuals()
	_show("off")


# ---------------------------------------------------------------- durum

func slot_open(_s) -> bool:
	return panel_open and not powered


func _closed_angle() -> float:
	var b = part_in("bat")
	return SWOLLEN_ANGLE if b != null and b.broken else 0.0


func _update_visuals() -> void:
	if _liquid_node:
		_liquid_node.visible = liquid_damage
	if hinge and not panel_open and not (_anim and _anim.is_running()):
		hinge.rotation.z = _closed_angle()


func fix_software() -> bool:
	if not sw_fault:
		return false
	sw_fault = false
	on_parts_changed()
	return true


func toggle_panel() -> void:
	if powered:
		power_off()
	panel_open = not panel_open
	Game.sfx.click()
	var tw := _new_anim()
	tw.tween_property(hinge, "rotation:z", OPEN_ANGLE if panel_open else _closed_angle(), 0.5) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	if panel_open:
		Game.msg("Ekran modülü kaldırıldı: batarya, kamera, hoparlör ve şarj soketi göründü.", Color(0.7, 0.9, 1.0))


func diagnose_all() -> Array[String]:
	var out: Array[String] = []
	if liquid_damage:
		out.append("tel_liquid")
	if not _ok("bat"):
		out.append("bat")
	if sw_fault:
		out.append("tel_sw")
	if not _ok("port"):
		out.append("port")
	if not _ok("scr"):
		out.append("scr")
	if not _ok("cam"):
		out.append("cam")
	if not _ok("spk"):
		out.append("spk")
	if not _ok("back"):
		out.append("back")
	return out


func tool_hint(tool, _slot) -> String:
	match str(tool.tool_type):
		"ipa":
			return "Sıvı oksidini IPA ile temizle  [E]" if liquid_damage else "Anakartı IPA ile temizle  [E]"
		"install_usb":
			return "Telefon yazılımını sıfırla (Factory Reset)  [E]" if sw_fault else "Yazılım zaten güncel"
		"multimeter":
			return "Multimetre ile telefon devrelerini tara  [E]"
	return super.tool_hint(tool, _slot)


func tool_use(player, tool, _slot) -> void:
	match str(tool.tool_type):
		"ipa":
			tool.puff(player, Color(0.72, 0.96, 0.82, 0.35))
			if liquid_damage:
				liquid_damage = false
				_update_visuals()
				Game.msg("Telefon anakartındaki sıvı oksidi IPA ile temizlendi!", Color(0.5, 1.0, 0.5))
			else:
				Game.msg("Anakart kontakları IPA ile temizlendi.")
		"install_usb":
			Game.sfx.beep_scan()
			if fix_software():
				Game.msg("Telefon yazılımı sıfırlandı ve sistem kurtarıldı!", Color(0.5, 1.0, 0.5))
			else:
				Game.msg("Telefon yazılımında sorun görünmüyor.")
		"multimeter":
			Game.sfx.beep_scan()
			if liquid_damage:
				Game.msg("Multimetre (Telefon): Anakartta SIVI KISA DEVRİSİ!", Color(1.0, 0.4, 0.3))
			elif diagnose() != "ok" and diagnose() != "tel_sw":
				Game.msg("Multimetre (Telefon): Arızalı modül saptandı (%s)." % diagnose(), Color(1.0, 0.5, 0.3))
			else:
				Game.msg("Multimetre (Telefon): Güç ve hat voltajları normal.", Color(0.5, 1.0, 0.5))
		_:
			super.tool_use(player, tool, _slot)


func power_button() -> void:
	Game.sfx.click()
	if panel_open:
		Game.msg("Önce ekranı kapat.", Color(1, 0.8, 0.4))
		return
	if powered:
		power_off()
		Game.msg("Telefon kapatıldı.")
		return
	if part_in("bat") == null:
		Game.msg("Hiçbir tepki yok. Batarya takılı mı?", Color(1, 0.6, 0.4))
		return
	powered = true
	_token += 1
	_buzz()
	match diagnose():
		"tel_liquid":
			_show("black")
			Game.msg("Anakartta sıvı oksidi kısa devresi var! Telefon açılmadı, IPA ile temizleyin.", Color(1, 0.45, 0.35))
			var my := _token
			await get_tree().create_timer(1.8).timeout
			if my == _token and powered:
				power_off()
		"bat":
			_show("lowbat")
			Game.msg("Ekranda kırmızı %1 pil simgesi belirdi, telefon hemen kapandı. Batarya bitik!", Color(1, 0.6, 0.4))
			var my := _token
			await get_tree().create_timer(2.5).timeout
			if my == _token and powered:
				power_off()
		"tel_sw":
			_show("bootloop")
			Game.msg("Telefon bootloop'ta takılı kaldı! Kurulum USB veya Tezgâh'tan yazılımı sıfırlayın.", Color(1, 0.6, 0.35))
		"port":
			_boot_then("port")
			Game.msg("Telefon açıldı ama kablo takılıyken şarj olmuyor: 'Şarj soketini kontrol edin'.", Color(1, 0.6, 0.4))
		"scr":
			_show("glitch")
			if part_in("scr") == null:
				Game.msg("Titreşim geldi ama ekran modülü takılı değil!", Color(1, 0.6, 0.4))
			else:
				Game.msg("Titreşti, açıldı ama ekran çatlak, görüntü bozuk; dokunmatik tepki vermiyor.", Color(1, 0.6, 0.4))
		"cam":
			_boot_then("cam")
			Game.msg("Telefon açıldı ama kamera uygulaması karanlık — kamera modülü arızalı!", Color(1, 0.65, 0.35))
		"spk":
			_boot_then("spk")
			Game.msg("Telefon açıldı ama hoparlörden ses gelmiyor!", Color(1, 0.65, 0.35))
		"back":
			_boot_then("home")
			Game.msg("Telefon açıldı ama arka cam kırık/eksik.", Color(1, 0.8, 0.4))
		"ok":
			_boot_then("home")
			Game.msg("Telefon sorunsuz açıldı, şarj oluyor!", Color(0.5, 1, 0.5))


## Açılışta kısa titreşim.
func _buzz() -> void:
	if _shake and _shake.is_valid():
		_shake.kill()
	_shake = create_tween()
	for i in 6:
		_shake.tween_property(body, "position:x", 0.0012 * (1 if i % 2 == 0 else -1), 0.03)
	_shake.tween_property(body, "position:x", 0.0, 0.03)
	Game.sfx.play(Game.sfx.tone(140.0, 0.25, 0.12, true))


func _show(state: String) -> void:
	super._show(state)
	if scr_quad:
		scr_quad.visible = state != "off" and part_in("scr") != null


func _fault_line(code: String) -> String:
	var f = DB.jobs.fault_by_code(code, "phone")
	return f.fail_lines.pick_random() if f != null and not f.fail_lines.is_empty() else "Usta telefon hâlâ düzgün çalışmıyor!"


func _open_line() -> String:
	return "Telefonun ekranı açık duruyor usta, kapatsana!"


# ---------------------------------------------------------------- ekran içeriği (180x380)

func _round(pos: Vector2, size: Vector2, col: Color, radius := 10) -> Panel:
	var p := Panel.new()
	p.position = pos
	p.size = size
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(radius)
	p.add_theme_stylebox_override("panel", sb)
	scr_root.add_child(p)
	return p


func _paint(state: String) -> void:
	var s := scr_root.size
	match state:
		"black":
			_rect(Vector2.ZERO, s, Color(0, 0, 0))
		"boot":
			_rect(Vector2.ZERO, s, Color(0, 0, 0))
			_txt("bilgiPhone", Vector2(0, 165), Vector2(s.x, 40), 26, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
		"bootloop":
			_rect(Vector2.ZERO, s, Color(0, 0, 0))
			_txt("bilgiPhone", Vector2(0, 145), Vector2(s.x, 38), 26, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
			_txt("Açılış döngüsü (Bootloop)!\nYazılım sıfırlama gerekli.", Vector2(12, 200), Vector2(s.x - 24, 60), 13, Color(1, 0.55, 0.35), HORIZONTAL_ALIGNMENT_CENTER)
		"glitch":
			_glitch()
		"lowbat":
			_rect(Vector2.ZERO, s, Color(0, 0, 0))
			_round(Vector2(55, 130), Vector2(70, 120), Color(0.9, 0.2, 0.18), 10)
			_round(Vector2(60, 135), Vector2(60, 110), Color(0, 0, 0), 7)
			_round(Vector2(77, 120), Vector2(26, 12), Color(0.9, 0.2, 0.18), 3)
			_rect(Vector2(64, 233), Vector2(52, 8), Color(0.95, 0.25, 0.2))
			_txt("%1", Vector2(0, 262), Vector2(s.x, 34), 26, Color(1, 0.4, 0.35), HORIZONTAL_ALIGNMENT_CENTER)
			_txt("Pil bitti. Kapanıyor...", Vector2(0, 300), Vector2(s.x, 24), 14, Color(0.8, 0.8, 0.82), HORIZONTAL_ALIGNMENT_CENTER)
		"home", "port", "cam", "spk":
			_wallpaper(Color(0.95, 0.45, 0.35), Color(0.3, 0.15, 0.55))
			_txt("14:42", Vector2(12, 6), Vector2(60, 20), 13)
			_txt("%14" if state == "port" else "%78", Vector2(100, 6), Vector2(70, 20), 13, Color(1, 0.6, 0.5) if state == "port" else Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT)
			_txt("14:42", Vector2(0, 40), Vector2(s.x, 50), 40, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
			_txt("Cumartesi, 14 Kasım", Vector2(0, 88), Vector2(s.x, 20), 12, Color(1, 1, 1, 0.85), HORIZONTAL_ALIGNMENT_CENTER)
			var icons := [Color(0.3, 0.8, 0.4), Color(0.25, 0.55, 0.95), Color(0.95, 0.75, 0.2), Color(0.9, 0.3, 0.35),
				Color(0.6, 0.4, 0.9), Color(0.2, 0.75, 0.8), Color(0.95, 0.5, 0.2), Color(0.85, 0.85, 0.9)]
			for i in icons.size():
				_round(Vector2(18 + (i % 4) * 38, 150 + (i / 4) * 46), Vector2(30, 30), icons[i], 8)
			_round(Vector2(10, 322), Vector2(160, 46), Color(1, 1, 1, 0.25), 16)
			for i in 4:
				_round(Vector2(22 + i * 38, 330), Vector2(30, 30), icons[i], 8)
			if state != "home":
				_round(Vector2(8, 120), Vector2(164, 92), Color(0.08, 0.08, 0.1, 0.95), 14)
				var wt := "Şarj olmuyor" if state == "port" else ("Kamera Hatası" if state == "cam" else "Ses Çıkışı Yok")
				var wd := "Kablo takılı ama akım gelmiyor. Şarj soketini kontrol edin." if state == "port" else ("Kamera açılamıyor — arka kamera modülü arızalı." if state == "cam" else "Hoparlör yanıt vermiyor — ses modülünü değiştirin.")
				_txt(wt, Vector2(18, 128), Vector2(150, 20), 15, Color(1, 0.45, 0.4))
				_txt(wd, Vector2(18, 150), Vector2(148, 60), 12, Color(0.9, 0.9, 0.92))
