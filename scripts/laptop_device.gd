extends "res://scripts/device_base.gd"
## Müşteri laptopu. Normalde kapağı (ekranı) açık durur, kendi ekranında hata gösterir.
## Alt kapağı açmak: ekran kapanır, laptop ters döner, alt kapak sökülüp yana konur.
## İçeride: SO-DIMM RAM, M.2 SSD, batarya. Ekran paneli kapaktadır (laptop düzken sökülür).

const W := 0.34
const D := 0.235
const BH := 0.02        # gövde kalınlığı
const LT := 0.006       # ekran kapağı kalınlığı
const PIV := (BH + LT) / 2.0
const LIFT := 0.0024    # lastik ayak yüksekliği
const LID_OPEN := -1.88 # ~108 derece
const COVER_OFF := Vector3(0.37, 0.022, 0)  # masaya (keçenin üstüne) yatar

var flip: Node3D
var base: Node3D
var lid: Node3D
var cover: Node3D
var touchpad: Node3D
var led_mat: StandardMaterial3D
var hum: AudioStreamPlayer3D


func _ready() -> void:
	device_name = "Laptop"
	_build()


func _build() -> void:
	var shell := MU.mat(Color(0.55, 0.57, 0.6), 0.8, 0.35) if randf() < 0.6 else MU.mat(Color(0.12, 0.12, 0.14), 0.5, 0.4)
	var inner := MU.mat(Color(0.2, 0.21, 0.23), 0.6, 0.45)
	var dark := MU.mat(Color(0.05, 0.05, 0.06), 0.2, 0.5)
	flip = MU.no_merge(Node3D.new())
	flip.position = Vector3(0, PIV, 0)
	add_child(flip)
	base = Node3D.new()
	base.position = Vector3(0, -PIV, 0)
	flip.add_child(base)
	# gövde: yan duvarlar + üst güverte (klavye yüzü)
	var t := 0.004
	MU.rbox(base, Vector3(W, 0.0035, D), Vector3(0, BH - 0.00175, 0), shell, 0.003)
	MU.rbox(base, Vector3(W, BH - 0.002, t), Vector3(0, 0.002 + (BH - 0.002) / 2, -D / 2 + t / 2), shell, 0.0015)
	MU.rbox(base, Vector3(W, BH - 0.002, t), Vector3(0, 0.002 + (BH - 0.002) / 2, D / 2 - t / 2), shell, 0.0015)
	for sx in [-1, 1]:
		MU.rbox(base, Vector3(t, BH - 0.002, D), Vector3(sx * (W / 2 - t / 2), 0.002 + (BH - 0.002) / 2, 0), shell, 0.0015)
	# iç yüz (güvertenin altı) koyu magnezyum
	MU.box(base, Vector3(W - 2 * t, 0.0005, D - 2 * t), Vector3(0, BH - 0.0038, 0), inner)
	_build_keyboard(dark)
	_build_ports(dark)
	_build_internals(inner, dark)
	_build_cover(shell, dark)
	_build_lid(shell, dark)
	# etkileşim: güverte (servis kapağı) ve güç düğmesi
	MU.interactable(base, Vector3(W, 0.0035, D), Vector3(0, BH - 0.00175, 0),
		func(_p): return "Alt kapağı kapat, laptopu düzelt  [E]" if panel_open else "Laptopu ters çevir, alt kapağı aç  [E]",
		func(_p): toggle_panel())
	MU.interactable(base, Vector3(0.03, 0.012, 0.022), Vector3(0.14, BH + 0.004, -D / 2 + 0.014),
		func(_p): return "Laptopu kapat  [E]" if powered else "Güç düğmesi  [E]",
		func(_p): power_button())
	MU.merge_static(base)
	hum = AudioStreamPlayer3D.new()
	hum.stream = Game.sfx.hum()
	hum.bus = "SFX"
	hum.volume_db = -24.0
	hum.pitch_scale = 1.6
	add_child(hum)
	_update_visuals()
	_show("off")


func _build_keyboard(dark: Material) -> void:
	# klavye çukuru + tuşlar
	MU.rbox(base, Vector3(0.3, 0.0008, 0.105), Vector3(0, BH + 0.0001, -0.035), MU.mat(Color(0.03, 0.03, 0.035), 0.1, 0.6), 0.003)
	var key_m := MU.mat(Color(0.09, 0.09, 0.1), 0.1, 0.55)
	for r in 5:
		for c in 14:
			MU.rbox(base, Vector3(0.0175, 0.0012, 0.0165), Vector3(-0.1365 + c * 0.021, BH + 0.0008, -0.077 + r * 0.02), key_m, 0.0015)
	MU.rbox(base, Vector3(0.12, 0.0012, 0.0165), Vector3(-0.01, BH + 0.0008, 0.023), key_m, 0.0015)
	# güç düğmesi (sağ üst) + güç LED'i (ön kenar)
	MU.rbox(base, Vector3(0.018, 0.0014, 0.012), Vector3(0.14, BH + 0.0006, -D / 2 + 0.014), MU.mat(Color(0.15, 0.15, 0.17), 0.3, 0.4), 0.002)
	MU.cyl(base, 0.0025, 0.0003, Vector3(0.14, BH + 0.0014, -D / 2 + 0.014), MU.mat(Color(0.8, 0.8, 0.82), 0.6, 0.3), Vector3.ZERO, 12)
	led_mat = MU.new_mat(Color(0.15, 0.15, 0.15))
	MU.box(base, Vector3(0.006, 0.0015, 0.001), Vector3(-0.13, BH - 0.004, D / 2 + 0.0002), led_mat)
	# dokunmatik yüzey (şişen batarya onu yukarı iter)
	touchpad = MU.no_merge(Node3D.new())
	touchpad.position = Vector3(0, BH, 0.075)
	base.add_child(touchpad)
	MU.rbox(touchpad, Vector3(0.11, 0.0008, 0.065), Vector3(0, 0.0002, 0), MU.mat(Color(0.3, 0.31, 0.33), 0.5, 0.25), 0.003)
	MU.merge_static(touchpad)


func _build_ports(dark: Material) -> void:
	for sx in [-1, 1]:
		var x: float = sx * (W / 2 + 0.0002)
		for i in 2:
			MU.box(base, Vector3(0.0012, 0.004, 0.012), Vector3(x, 0.01, -0.04 + i * 0.02), dark)
	MU.cyl(base, 0.0018, 0.002, Vector3(-W / 2 - 0.0002, 0.01, 0.04), dark, Vector3(0, 0, 90), 10)


## İç düzen (güvertenin altı, -Y'ye bakar): anakart, fan + ısı borusu, RAM, SSD, batarya, hoparlörler.
func _build_internals(inner: Material, dark: Material) -> void:
	var by := BH - 0.0045   # kartın alt yüzü
	MU.box(base, Vector3(0.32, 0.0012, 0.105), Vector3(0, by + 0.0006, -0.06), MU.tex_mat(MU.pcb_texture(Color(0.04, 0.12, 0.22))))
	var copper := MU.mat(Color(0.85, 0.48, 0.28), 1.0, 0.28)
	var alu := MU.mat(Color(0.7, 0.72, 0.75), 0.85, 0.3)
	# fan (yuvarlak gövde + kanat izleri) ve soğutucu peteği
	MU.cyl(base, 0.03, 0.006, Vector3(-0.122, by - 0.003, -0.065), MU.mat(Color(0.1, 0.1, 0.11), 0.2, 0.5), Vector3.ZERO, 24)
	MU.cyl(base, 0.024, 0.0004, Vector3(-0.122, by - 0.0062, -0.065), MU.mat(Color(0.2, 0.2, 0.22), 0.2, 0.5), Vector3.ZERO, 24)
	MU.cyl(base, 0.008, 0.0006, Vector3(-0.122, by - 0.0064, -0.065), alu, Vector3.ZERO, 16)
	for i in 9:
		MU.box(base, Vector3(0.001, 0.005, 0.014), Vector3(-0.15 + i * 0.006, by - 0.003, -0.104), alu)
	# işlemci + ısı borusu
	MU.rbox(base, Vector3(0.022, 0.0012, 0.022), Vector3(-0.065, by - 0.0006, -0.045), alu, 0.001)
	MU.rbox(base, Vector3(0.03, 0.0008, 0.03), Vector3(-0.065, by - 0.0016, -0.045), copper, 0.001)
	var pipe: Array[Vector3] = [Vector3(-0.065, by - 0.0022, -0.045), Vector3(-0.1, by - 0.0022, -0.07), Vector3(-0.122, by - 0.0022, -0.1)]
	MU.tube(base, pipe, 0.0025, copper, 6)
	# RAM soketi (SO-DIMM) ve M.2 soketi
	MU.rbox(base, Vector3(0.07, 0.004, 0.005), Vector3(0.0, by - 0.002, -0.087), dark, 0.0008)
	for x in [-0.036, 0.036]:
		MU.box(base, Vector3(0.002, 0.003, 0.03), Vector3(x, by - 0.0015, -0.07), MU.mat(Color(0.7, 0.7, 0.72), 0.8, 0.3))
	MU.rbox(base, Vector3(0.006, 0.0035, 0.024), Vector3(0.132, by - 0.0018, -0.03), dark, 0.0008)
	MU.cyl(base, 0.002, 0.003, Vector3(0.048, by - 0.0015, -0.03), alu, Vector3.ZERO, 10)
	# çipler ve kondansatörler
	for c in [[Vector3(0.05, 0, -0.085), 0.012], [Vector3(0.1, 0, -0.09), 0.009], [Vector3(-0.025, 0, -0.03), 0.008]]:
		MU.box(base, Vector3(c[1], 0.001, c[1]), c[0] + Vector3(0, by - 0.0005, 0), MU.mat(Color(0.03, 0.03, 0.035), 0.1, 0.35))
	# batarya konnektörü + hoparlörler
	MU.rbox(base, Vector3(0.016, 0.003, 0.006), Vector3(-0.073, by - 0.0015, 0.0), MU.mat(Color(0.92, 0.92, 0.88), 0, 0.5), 0.0006)
	for sx in [-1, 1]:
		MU.rbox(base, Vector3(0.028, 0.008, 0.016), Vector3(sx * 0.14, by - 0.002, 0.095), dark, 0.002)
	# yuvalar (parçalar aşağı bakar: ters dönünce yukarı bakarlar)
	_add_slot("ram", "lap_ram", base, Vector3(0.0, by - 0.0018, -0.07), Vector3(0, 0, 180))
	_add_slot("ssd", "lap_ssd", base, Vector3(0.088, by - 0.0016, -0.03), Vector3(0, 0, 180))
	_add_slot("bat", "lap_bat", base, Vector3(0.0, BH - 0.0038 - 0.0042, 0.055), Vector3(0, 0, 180))


## Alt kapak: vidalı, havalandırma ızgaralı, lastik ayaklı. Ayrı düğüm: sökülüp masaya konur.
func _build_cover(shell: Material, dark: Material) -> void:
	cover = MU.no_merge(Node3D.new())
	base.add_child(cover)
	MU.rbox(cover, Vector3(W - 0.002, 0.002, D - 0.002), Vector3(0, 0.001, 0), shell, 0.0015)
	for i in 12:
		MU.box(cover, Vector3(0.003, 0.0004, 0.05), Vector3(-0.15 + i * 0.008, -0.0001, -0.06), dark)
	for p in [Vector2(-0.15, -0.1), Vector2(0.15, -0.1), Vector2(-0.15, 0.1), Vector2(0.15, 0.1)]:
		MU.cyl(cover, 0.007, 0.0024, Vector3(p.x, -0.0012, p.y), MU.mat(Color(0.04, 0.04, 0.04), 0, 0.9), Vector3.ZERO, 14)
	for p in [Vector2(-0.12, -0.1), Vector2(0.12, -0.1), Vector2(-0.16, 0.0), Vector2(0.16, 0.0), Vector2(-0.12, 0.105), Vector2(0.12, 0.105), Vector2(0, 0.105)]:
		MU.cyl(cover, 0.0022, 0.0004, Vector3(p.x, -0.0001, p.y), MU.mat(Color(0.35, 0.35, 0.37), 0.9, 0.3), Vector3.ZERO, 8)
	MU.box(cover, Vector3(0.07, 0.0003, 0.03), Vector3(0.05, -0.0002, 0.05), MU.mat(Color(0.93, 0.93, 0.9), 0, 0.6))
	var sl := MU.label(cover, "BİLGİBOOK 15\nModel BB-15  S/N 4X7Q2", Vector3(0.05, -0.0004, 0.05), 22, Color(0.15, 0.15, 0.15), Vector3(90, 0, 0), 0.0002)
	sl.double_sided = false
	# iç yüzde yalıtım bandı
	MU.box(cover, Vector3(0.2, 0.0003, 0.06), Vector3(0, 0.0021, 0.055), MU.mat(Color(0.1, 0.1, 0.1), 0, 0.8))
	MU.merge_static(cover)


## Ekran kapağı: menteşe arka kenarda; kapalıyken +Z yönüne uzanır, ekran -Y'ye bakar.
func _build_lid(shell: Material, dark: Material) -> void:
	lid = MU.no_merge(Node3D.new())
	lid.position = Vector3(0, BH, -D / 2)
	lid.rotation.x = LID_OPEN
	base.add_child(lid)
	var body := Node3D.new()
	lid.add_child(body)
	MU.rbox(body, Vector3(W, LT - 0.0025, D), Vector3(0, 0.0025 + (LT - 0.0025) / 2, D / 2), shell, 0.003)
	# çerçeve (bezel): ekran paneli bunun içine oturur
	var bz := MU.mat(Color(0.04, 0.04, 0.045), 0.2, 0.5)
	var sz := D / 2 + 0.004   # ekran merkezi
	MU.box(body, Vector3(0.015, 0.0025, D), Vector3(-W / 2 + 0.0075, 0.00125, D / 2), bz)
	MU.box(body, Vector3(0.015, 0.0025, D), Vector3(W / 2 - 0.0075, 0.00125, D / 2), bz)
	MU.box(body, Vector3(0.31, 0.0025, sz - 0.095), Vector3(0, 0.00125, (sz - 0.095) / 2), bz)
	MU.box(body, Vector3(0.31, 0.0025, D - sz - 0.095), Vector3(0, 0.00125, (D + sz + 0.095) / 2), bz)
	MU.cyl(body, 0.0018, 0.0004, Vector3(0, -0.0001, D - 0.007), MU.mat(Color(0.01, 0.01, 0.02), 0.3, 0.1), Vector3.ZERO, 12)
	var bl := MU.label(body, "BİLGİBOOK", Vector3(0, -0.0002, 0.012), 34, Color(0.6, 0.6, 0.65), Vector3(90, 0, 0), 0.00025)
	bl.double_sided = false
	# arka yüz logosu + menteşe
	var logo := MU.label(body, "B", Vector3(0, LT + 0.0002, D * 0.55), 160, Color(0.85, 0.86, 0.9), Vector3(-90, 180, 0), 0.0004)
	logo.double_sided = false
	MU.cyl(body, 0.004, W * 0.8, Vector3(0, 0.002, 0.002), dark, Vector3(0, 0, 90), 12)
	MU.merge_static(body)
	var s = _add_slot("scr", "lap_scr", lid, Vector3(0, 0.0022, sz), Vector3(180, 0, 0))
	_make_screen(Vector2i(400, 250), s, Vector2(0.296, 0.18), Vector3(0, 0.0021, 0))


# ---------------------------------------------------------------- durum

func slot_open(s) -> bool:
	if powered:
		return false
	if s.name == "scr":
		return not panel_open   # ekran paneli: laptop düz dururken
	return panel_open


func _update_visuals() -> void:
	if touchpad == null:
		return
	var b = part_in("bat")
	var swollen: bool = b != null and b.broken
	touchpad.position.y = BH + (0.0018 if swollen else 0.0)
	touchpad.rotation_degrees.x = -4.0 if swollen else 0.0


func toggle_panel() -> void:
	if powered:
		power_off()
	panel_open = not panel_open
	Game.sfx.click()
	var tw := _new_anim()
	if panel_open:
		tw.tween_property(lid, "rotation:x", 0.0, 0.35).set_trans(Tween.TRANS_CUBIC)
		tw.tween_property(flip, "rotation:z", PI, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(cover, "position", Vector3(0, -0.05, 0), 0.2)
		tw.tween_property(cover, "position", Vector3(COVER_OFF.x, -0.05, 0), 0.25)
		tw.tween_property(cover, "position", COVER_OFF, 0.15)
		Game.msg("Laptop ters çevrildi, alt kapağın vidaları söküldü.", Color(0.7, 0.9, 1.0))
	else:
		tw.tween_property(cover, "position", Vector3(COVER_OFF.x, -0.05, 0), 0.15)
		tw.tween_property(cover, "position", Vector3(0, -0.05, 0), 0.25)
		tw.tween_property(cover, "position", Vector3.ZERO, 0.2)
		tw.tween_property(flip, "rotation:z", 0.0, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(lid, "rotation:x", LID_OPEN, 0.35).set_trans(Tween.TRANS_CUBIC)


func diagnose() -> String:
	if not _ok("ram"):
		return "ram"
	if not _ok("ssd"):
		return "ssd"
	if not _ok("bat"):
		return "bat"
	if not _ok("scr"):
		return "scr"
	return "ok"


func power_button() -> void:
	Game.sfx.click()
	if panel_open:
		Game.msg("Önce alt kapağı kapatıp laptopu düzelt.", Color(1, 0.8, 0.4))
		return
	if powered:
		power_off()
		Game.msg("Laptop kapatıldı.")
		return
	powered = true
	_token += 1
	led_mat.emission_enabled = true
	led_mat.emission = Color(1.0, 1.0, 1.0)
	led_mat.emission_energy_multiplier = 4.0
	hum.play()
	var code := diagnose()
	match code:
		"ram":
			if part_in("ram") == null:
				_show("black")
				Game.sfx.beeps([0.12, 0.12, 0.12, 0.12, 0.12, 0.12])
				Game.msg("Güç ışığı yandı, laptop öttü ama ekran kapkara. RAM takılı mı?", Color(1, 0.6, 0.4))
			else:
				_boot_then("bsod", 1.4)
				Game.msg("Laptop açıldı, birkaç saniye sonra mavi ekran: MEMORY_MANAGEMENT. Bellek arızası!", Color(1, 0.6, 0.4))
		"ssd":
			_boot_then("noboot")
			Game.msg("Logo geldi ama 'Boot device not found' yazıyor. Disk görünmüyor.", Color(1, 0.8, 0.4))
		"bat":
			_boot_then("bat")
			if part_in("bat") == null:
				Game.msg("Laptop prizle açıldı ama pil simgesinde çarpı var: 'Pil algılanmadı'.", Color(1, 0.8, 0.4))
			else:
				Game.msg("Laptop açıldı ama pil simgesi kırmızı: '%0 — takılı, şarj olmuyor'. Batarya arızalı!", Color(1, 0.6, 0.4))
		"scr":
			_show("glitch")
			if part_in("scr") == null:
				Game.msg("Fan dönüyor, güç ışığı yanıyor... ama ekran paneli takılı değil!", Color(1, 0.6, 0.4))
			else:
				Game.msg("Laptop çalışıyor ama kırık ekranda görüntü bozuk: renkli çizgiler, kara lekeler.", Color(1, 0.6, 0.4))
		"ok":
			_boot_then("desktop")
			Game.msg("Laptop sorunsuz açıldı, pil şarj oluyor!", Color(0.5, 1, 0.5))


func power_off() -> void:
	super.power_off()
	if led_mat:
		led_mat.emission_enabled = false
	if hum:
		hum.stop()


func _show(state: String) -> void:
	super._show(state)
	if scr_quad:
		scr_quad.visible = state != "off" and part_in("scr") != null


func _fault_line(code: String) -> String:
	match code:
		"ram": return "Usta bu laptop hâlâ donup mavi ekran veriyor!"
		"ssd": return "Usta Windows hâlâ gelmiyor, 'boot device' diyor!"
		"bat": return "Usta pil hâlâ şarj olmuyor, kabloyu çekince kapanıyor!"
		"scr": return "Usta ekran hâlâ kırık, hiçbir şey göremiyorum!"
	return "Usta bu laptop hâlâ düzgün çalışmıyor ki!"


func _open_line() -> String:
	return "Alt kapağı takmadan mı vereceksin usta? Vidalar nerede?"


# ---------------------------------------------------------------- ekran içeriği (400x250)

func _paint(state: String) -> void:
	var s := scr_root.size
	match state:
		"boot":
			_rect(Vector2.ZERO, s, Color(0, 0, 0))
			_txt("BİLGİBOOK", Vector2(0, 90), Vector2(s.x, 50), 40, Color(0.85, 0.88, 0.95), HORIZONTAL_ALIGNMENT_CENTER)
			_txt("· · · · ·", Vector2(0, 160), Vector2(s.x, 30), 20, Color(0.6, 0.6, 0.65), HORIZONTAL_ALIGNMENT_CENTER)
		"black":
			_rect(Vector2.ZERO, s, Color(0, 0, 0))
		"glitch":
			_glitch()
		"bsod":
			_rect(Vector2.ZERO, s, Color(0.05, 0.42, 0.8))
			_txt(":(", Vector2(26, 14), Vector2(100, 70), 56)
			_txt("Bilgisayarınız bir sorunla karşılaştı ve yeniden başlatılması gerekiyor.", Vector2(26, 92), Vector2(350, 60), 17)
			_txt("%35 tamamlandı", Vector2(26, 152), Vector2(300, 24), 15)
			_txt("Durdurma kodu: MEMORY_MANAGEMENT", Vector2(26, 196), Vector2(360, 24), 15, Color(0.9, 0.95, 1.0))
		"noboot":
			_rect(Vector2.ZERO, s, Color(0, 0, 0))
			_txt("BİLGİBOOK BIOS v1.08\n\nBoot device not found.\n\nPlease install an operating system\non your hard disk.\n\nHard Disk (3F0)  — F2: Kurulum", Vector2(18, 18), Vector2(370, 220), 15, Color(0.82, 0.82, 0.82))
		"desktop", "bat":
			_wallpaper(Color(0.12, 0.5, 0.55), Color(0.2, 0.15, 0.5))
			for i in 3:
				_rect(Vector2(18, 16 + i * 52), Vector2(30, 26), [Color(0.95, 0.8, 0.3), Color(0.4, 0.9, 0.4), Color(0.8, 0.8, 0.85)][i])
				_txt(["Belgeler", "Oyunlar", "Çöp"][i], Vector2(4, 43 + i * 52), Vector2(60, 16), 11, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER)
			_rect(Vector2(0, s.y - 24), Vector2(s.x, 24), Color(0.06, 0.06, 0.1, 0.92))
			_txt("◆ Başlat", Vector2(6, s.y - 22), Vector2(90, 20), 13)
			var t := Time.get_time_dict_from_system()
			_txt("%02d:%02d" % [t.hour, t.minute], Vector2(s.x - 50, s.y - 22), Vector2(46, 20), 13)
			if state == "desktop":
				_txt("Pil %86  şarj oluyor", Vector2(s.x - 190, s.y - 22), Vector2(136, 20), 13, Color(0.55, 1, 0.55), HORIZONTAL_ALIGNMENT_RIGHT)
			else:
				var missing := part_in("bat") == null
				_txt("Pil yok" if missing else "Pil %0", Vector2(s.x - 160, s.y - 22), Vector2(106, 20), 13, Color(1, 0.35, 0.3), HORIZONTAL_ALIGNMENT_RIGHT)
				var box := _rect(Vector2(s.x - 228, s.y - 104), Vector2(220, 74), Color(0.1, 0.1, 0.14, 0.96))
				_rect(Vector2(0, 0), Vector2(5, 74), Color(0.95, 0.3, 0.25), box)
				_txt("Batarya uyarısı" if not missing else "Pil algılanmadı", Vector2(s.x - 216, s.y - 100), Vector2(200, 20), 14, Color(1, 0.45, 0.4))
				_txt("Takılı, şarj olmuyor. Bataryayı değiştirmeniz önerilir." if not missing else "Prizden çekerseniz laptop kapanır.", Vector2(s.x - 216, s.y - 80), Vector2(204, 44), 12, Color(0.9, 0.9, 0.92))
