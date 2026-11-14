extends Node3D
## Müşterinin bilgisayar kasası: anakart, yuvalar, cam kapak, güç düğmesi, teşhis.

const MU := preload("res://scripts/mesh_util.gd")
const PM := preload("res://scripts/part_models.gd")
const SLOT := preload("res://scripts/slot.gd")
const PART := preload("res://scripts/part.gd")

const W := 0.22
const H := 0.46
const D := 0.44
const BOARD_X := -0.0875

const SLOT_POS := {
	"cpu": Vector3(BOARD_X, 0.36, -0.06),
	"ram1": Vector3(BOARD_X, 0.35, 0.03),
	"ram2": Vector3(BOARD_X, 0.35, 0.046),
	"gpu": Vector3(BOARD_X, 0.235, -0.04),
	"psu": Vector3(0.0, 0.0475, -0.13),
	"ssd": Vector3(0.02, 0.01, 0.12),
}

var slots := {}
var monitor = null
var powered := false
var panel_open := false
var panel_pivot: Node3D
var case_fans: Array = []
var rgb_mats: Array = []
var hum: AudioStreamPlayer3D
var led_mat: StandardMaterial3D
var inner_light: OmniLight3D
var debug_leds := {}
var _hue := 0.0


func _ready() -> void:
	_build()


func _build() -> void:
	var white := randf() < 0.4
	var shell_m := MU.mat(Color(0.9, 0.9, 0.92) if white else Color(0.08, 0.08, 0.09), 0.4, 0.45)
	var inner_m := MU.mat(Color(0.8, 0.8, 0.82) if white else Color(0.11, 0.11, 0.12), 0.4, 0.5)
	var t := 0.006
	var body := StaticBody3D.new()
	body.collision_layer = 1
	add_child(body)
	var pieces := [
		[Vector3(W, t, D), Vector3(0, t / 2, 0), shell_m],
		[Vector3(W, t, D), Vector3(0, H - t / 2, 0), shell_m],
		[Vector3(W, H, t), Vector3(0, H / 2, -D / 2 + t / 2), inner_m],
		[Vector3(W, H, t), Vector3(0, H / 2, D / 2 - t / 2), shell_m],
		[Vector3(t, H, D), Vector3(-W / 2 + t / 2, H / 2, 0), shell_m],
	]
	for p in pieces:
		MU.rbox(body, p[0], p[1], p[2], 0.004)
		MU.add_box_shape(body, p[0], p[1])
	# dış kenar çerçevesi (yuvarlatılmış)
	for y in [0.0, H]:
		MU.rbox(self, Vector3(W + 0.004, 0.014, D + 0.004), Vector3(0, y, 0), shell_m, 0.006)
	# ön panel ızgarası
	var mesh_m := MU.mat(Color(0.2, 0.2, 0.22) if not white else Color(0.75, 0.75, 0.78), 0.6, 0.5)
	for i in 14:
		MU.box(self, Vector3(0.002, H * 0.8, 0.003), Vector3(-0.03 + i * 0.009, H / 2, D / 2 + 0.002), mesh_m)
	# ayaklar
	for x in [-0.08, 0.08]:
		for z in [-0.18, 0.18]:
			MU.box(self, Vector3(0.03, 0.01, 0.03), Vector3(x, -0.005, z), MU.mat(Color(0.05, 0.05, 0.05)))
	# ön panel detayları
	MU.box(self, Vector3(0.006, H * 0.86, 0.004), Vector3(-0.07, H / 2, D / 2 + 0.002), MU.mat(Color(0.3, 0.3, 0.32), 0.8, 0.3))
	led_mat = MU.new_mat(Color(0.1, 0.1, 0.1))
	MU.box(self, Vector3(0.008, 0.003, 0.003), Vector3(0.04, H - 0.03, D / 2 + 0.001), led_mat)
	# güç düğmesi
	MU.cyl(self, 0.011, 0.006, Vector3(0.0, H - 0.03, D / 2 + 0.002), MU.mat(Color(0.75, 0.75, 0.78), 0.9, 0.3), Vector3(90, 0, 0))
	MU.interactable(self, Vector3(0.04, 0.04, 0.02), Vector3(0.0, H - 0.03, D / 2 + 0.006),
		func(_p): return "Güç düğmesi  [E]" if not powered else "Bilgisayarı kapat  [E]",
		func(_p): power_button())
	# cam yan kapak (menteşe arka kenarda)
	panel_pivot = MU.no_merge(Node3D.new())
	panel_pivot.position = Vector3(W / 2 - 0.002, 0, -D / 2)
	add_child(panel_pivot)
	var panel = MU.interactable(panel_pivot, Vector3(0.006, H, D), Vector3(0, H / 2, D / 2),
		func(_p): return "Kapağı aç  [E]" if not panel_open else "Kapağı kapat  [E]",
		func(_p): toggle_panel())
	MU.box(panel, Vector3(0.004, H - 0.02, D - 0.02), Vector3.ZERO, MU.glass())
	var frame_m := shell_m
	MU.box(panel, Vector3(0.005, 0.01, D), Vector3(0, H / 2 - 0.005, 0), frame_m)
	MU.box(panel, Vector3(0.005, 0.01, D), Vector3(0, -H / 2 + 0.005, 0), frame_m)
	MU.box(panel, Vector3(0.005, H, 0.01), Vector3(0, 0, D / 2 - 0.005), frame_m)
	MU.box(panel, Vector3(0.005, H, 0.01), Vector3(0, 0, -D / 2 + 0.005), frame_m)
	MU.merge_static(panel_pivot)
	_build_board()
	# fanlar
	var fan_frame := MU.mat(Color(0.1, 0.1, 0.11))
	var blade := MU.mat(Color(0.18, 0.18, 0.2), 0.0, 0.5)
	case_fans.append(MU.fan(self, 0.05, Vector3(0.02, 0.36, -D / 2 + 0.02), Vector3(90, 0, 0), fan_frame, blade))
	for y in [0.15, 0.31]:
		var ring := MU.new_mat(Color(0.2, 0.6, 1.0), 0, 0.3, 0.0)
		rgb_mats.append(ring)
		case_fans.append(MU.fan(self, 0.06, Vector3(0.0, y, D / 2 - 0.022), Vector3(90, 0, 0), fan_frame, blade, ring))
	# yuvalar
	for name in SLOT_POS:
		var s = SLOT.new()
		s.name = name
		MU.no_merge(s)
		s.position = SLOT_POS[name]
		add_child(s)
		s.setup("ram" if name.begins_with("ram") else name, self)
		slots[name] = s
	# kasa içi LED şerit + ışık (parçalar karanlıkta kalmasın)
	var strip := MU.new_mat(Color(0.9, 0.95, 1.0), 0, 0.5, 2.0)
	rgb_mats.append(strip)
	MU.box(self, Vector3(0.006, 0.004, D - 0.04), Vector3(0.06, H - 0.01, 0), strip)
	inner_light = OmniLight3D.new()
	inner_light.position = Vector3(0.04, H - 0.06, 0.0)
	inner_light.omni_range = 0.6
	inner_light.light_energy = 0.35
	inner_light.light_color = Color(0.9, 0.95, 1.0)
	add_child(inner_light)
	for f in case_fans:
		MU.no_merge(f)
	MU.merge_static(self)
	hum = AudioStreamPlayer3D.new()
	hum.stream = Game.sfx.hum()
	hum.volume_db = -14.0
	hum.position = Vector3(0, 0.2, 0)
	add_child(hum)


func _build_board() -> void:
	var board := Node3D.new()
	add_child(board)
	var bx := -0.0875  # anakart ön yüzeyi
	MU.box(board, Vector3(0.005, 0.3, 0.3), Vector3(-0.09, 0.29, -0.02), MU.tex_mat(MU.pcb_texture(Color(0.06, 0.07, 0.09))))
	var dark := MU.mat(Color(0.05, 0.05, 0.06), 0.1, 0.5)
	var slot_m := MU.mat(Color(0.1, 0.1, 0.11), 0.1, 0.45)
	var metal := MU.mat(Color(0.5, 0.52, 0.56), 0.85, 0.3)
	var dark_metal := MU.mat(Color(0.18, 0.19, 0.21), 0.85, 0.35)
	var silver := MU.mat(Color(0.82, 0.83, 0.85), 0.95, 0.25)
	# CPU soketi
	var cpu: Vector3 = SLOT_POS.cpu
	MU.rbox(board, Vector3(0.003, 0.058, 0.058), cpu + Vector3(0.0015, 0, 0), MU.mat(Color(0.72, 0.7, 0.62), 0.6, 0.4), 0.002)
	MU.cyl(board, 0.0012, 0.05, cpu + Vector3(0.003, 0, 0.033), silver, Vector3.ZERO, 6)
	# VRM soğutucuları (oluklu)
	MU.rbox(board, Vector3(0.016, 0.022, 0.07), Vector3(bx + 0.008, 0.418, -0.06), dark_metal, 0.002)
	for i in 4:
		MU.box(board, Vector3(0.0165, 0.0015, 0.07), Vector3(bx + 0.008, 0.409 + i * 0.006, -0.06), metal)
	MU.rbox(board, Vector3(0.016, 0.07, 0.022), Vector3(bx + 0.008, 0.36, -0.122), dark_metal, 0.002)
	for i in 4:
		MU.box(board, Vector3(0.0165, 0.07, 0.0015), Vector3(bx + 0.008, 0.36, -0.131 + i * 0.006), metal)
	# kondansatörler
	for i in 6:
		MU.cyl(board, 0.003, 0.008, Vector3(bx + 0.004, 0.398, -0.088 + i * 0.011), silver, Vector3(0, 0, 90), 10)
	for i in 5:
		MU.cyl(board, 0.003, 0.008, Vector3(bx + 0.004, 0.33 - i * 0.011, -0.104), silver, Vector3(0, 0, 90), 10)
	# RAM yuvaları + mandallar
	for z in [SLOT_POS.ram1.z, SLOT_POS.ram2.z]:
		MU.box(board, Vector3(0.006, 0.14, 0.006), Vector3(bx + 0.003, 0.35, z), slot_m)
		for y in [0.279, 0.421]:
			MU.box(board, Vector3(0.008, 0.006, 0.006), Vector3(bx + 0.004, y, z), MU.mat(Color(0.6, 0.6, 0.62), 0.2, 0.5))
	# PCIe yuvaları (metal destekli)
	MU.box(board, Vector3(0.006, 0.006, 0.09), Vector3(bx + 0.003, 0.235, -0.07), slot_m)
	MU.box(board, Vector3(0.0065, 0.0068, 0.088), Vector3(bx + 0.0028, 0.235, -0.07), silver)
	MU.box(board, Vector3(0.006, 0.006, 0.09), Vector3(bx + 0.003, 0.152, -0.07), slot_m)
	MU.box(board, Vector3(0.006, 0.006, 0.025), Vector3(bx + 0.003, 0.205, -0.1), slot_m)
	# M.2 soğutucu
	MU.rbox(board, Vector3(0.004, 0.02, 0.08), Vector3(bx + 0.002, 0.18, -0.01), dark_metal, 0.0015)
	var m2 := MU.label(board, "M.2", Vector3(bx + 0.0042, 0.18, 0.015), 40, Color(0.75, 0.75, 0.78), Vector3(0, 90, 0), 0.0003)
	m2.double_sided = false
	# yonga seti soğutucusu + logo
	MU.rbox(board, Vector3(0.008, 0.045, 0.045), Vector3(bx + 0.004, 0.172, 0.085), dark_metal, 0.004)
	var logo := MU.label(board, "BİLGİ\nBOARD", Vector3(bx + 0.0082, 0.172, 0.085), 40, Color(0.85, 0.7, 0.3), Vector3(0, 90, 0), 0.00028)
	logo.double_sided = false
	# SATA portları (ön kenar)
	for i in 4:
		MU.rbox(board, Vector3(0.008, 0.006, 0.01), Vector3(bx + 0.004, 0.2 + i * 0.009, 0.122), MU.mat(Color(0.1, 0.12, 0.3), 0, 0.4), 0.001)
	# CMOS pili
	MU.cyl(board, 0.01, 0.003, Vector3(bx + 0.0015, 0.268, 0.1), silver, Vector3(0, 0, 90), 20)
	# 24-pin güç konnektörü
	MU.rbox(board, Vector3(0.01, 0.055, 0.012), Vector3(bx + 0.005, 0.35, 0.112), dark, 0.0015)
	for i in 6:
		MU.box(board, Vector3(0.0102, 0.004, 0.009), Vector3(bx + 0.005, 0.328 + i * 0.009, 0.112), MU.mat(Color(0.18, 0.18, 0.2)))
	# hata LED'leri (CPU / DRAM / VGA / BOOT)
	var names := ["CPU", "DRAM", "VGA", "BOOT"]
	for i in names.size():
		var lm := MU.new_mat(Color(0.25, 0.12, 0.05), 0, 0.4)
		debug_leds[names[i]] = lm
		MU.box(board, Vector3(0.002, 0.003, 0.005), Vector3(bx + 0.001, 0.432 - i * 0.008, 0.096), lm)
		var ll := MU.label(board, names[i], Vector3(bx + 0.0011, 0.432 - i * 0.008, 0.085), 24, Color(0.9, 0.9, 0.9), Vector3(0, 90, 0), 0.00022)
		ll.double_sided = false
	# arka I/O kapağı
	MU.rbox(board, Vector3(0.03, 0.08, 0.03), Vector3(-0.072, 0.38, -0.155), MU.mat(Color(0.22, 0.22, 0.25), 0.7, 0.35), 0.004)
	var io := MU.label(board, "GAMING", Vector3(-0.0565, 0.38, -0.155), 40, Color(0.85, 0.2, 0.25), Vector3(0, 90, 90), 0.00035)
	io.double_sided = false
	# ses kondansatörleri
	for i in 3:
		MU.cyl(board, 0.0035, 0.009, Vector3(bx + 0.0045, 0.155 + i * 0.012, 0.035), MU.mat(Color(0.85, 0.7, 0.25), 0.6, 0.35), Vector3(0, 0, 90), 10)
	# kablolar (24-pin ve CPU güç kablosu)
	var cable := MU.mat(Color(0.06, 0.06, 0.07), 0, 0.7)
	for i in 4:
		MU.cyl(board, 0.0035, 0.2, Vector3(-0.072 + i * 0.008, 0.2, 0.135), cable, Vector3.ZERO, 8)
	MU.cyl(board, 0.004, 0.25, Vector3(-0.08, 0.3, -0.19), cable, Vector3.ZERO, 8)
	MU.cyl(board, 0.004, 0.06, Vector3(-0.08, 0.425, -0.16), cable, Vector3(90, 0, 0), 8)
	# PCIe braketleri (arka)
	for i in 5:
		MU.box(board, Vector3(0.03, 0.012, 0.002), Vector3(-0.06, 0.25 - i * 0.02, -0.217), metal)


## Müşteri bilgisayarını doldurur. parts: [[slot_adı, tip, seviye, bozuk_mu], ...]
func fill(parts: Array) -> void:
	for p in parts:
		var part = PART.new().setup(p[1], p[2], p[3])
		slots[p[0]].install(part)


func part_in(slot_name: String):
	return slots[slot_name].part


func installed_parts() -> Array:
	var out := []
	for s in slots.values():
		if s.part:
			out.append(s.part)
	return out


func total_ram() -> int:
	var gb := 0
	for n in ["ram1", "ram2"]:
		var p = part_in(n)
		if p and not p.broken:
			gb += PM.ram_gb(p.tier)
	return gb


## Teşhis kodu: "nopower", "cpu", "ram", "gpu", "ssd" veya "ok"
func diagnose() -> String:
	var psu = part_in("psu")
	if psu == null or psu.broken:
		return "nopower"
	var cpu = part_in("cpu")
	if cpu == null or cpu.broken:
		return "cpu"
	var rams := []
	for n in ["ram1", "ram2"]:
		if part_in(n):
			rams.append(part_in(n))
	if rams.is_empty() or rams.any(func(r): return r.broken):
		return "ram"
	var gpu = part_in("gpu")
	if gpu == null or gpu.broken:
		return "gpu"
	var ssd = part_in("ssd")
	if ssd == null or ssd.broken:
		return "ssd"
	return "ok"


func toggle_panel() -> void:
	panel_open = not panel_open
	var tw := create_tween()
	tw.tween_property(panel_pivot, "rotation:y", deg_to_rad(100.0) if panel_open else 0.0, 0.45) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	Game.sfx.click()


func power_button() -> void:
	Game.sfx.click()
	if powered:
		power_off()
		Game.msg("Bilgisayar kapatıldı.")
		return
	var code := diagnose()
	if code == "nopower":
		Game.msg("Hiçbir tepki yok... Fanlar bile dönmüyor.", Color(1, 0.6, 0.4))
		return
	powered = true
	var led_name: String = {"cpu": "CPU", "ram": "DRAM", "gpu": "VGA", "ssd": "BOOT"}.get(code, "")
	if led_name != "":
		var lm: StandardMaterial3D = debug_leds[led_name]
		lm.albedo_color = Color(1.0, 0.45, 0.1)
		lm.emission_enabled = true
		lm.emission = Color(1.0, 0.45, 0.1)
		lm.emission_energy_multiplier = 6.0
	led_mat.emission_enabled = true
	led_mat.emission = Color(0.2, 0.6, 1.0)
	led_mat.emission_energy_multiplier = 3.0
	hum.play()
	match code:
		"cpu":
			monitor.show_no_signal()
			Game.msg("Fanlar dönüyor ama hiç bip sesi yok, ekran kapkara.", Color(1, 0.6, 0.4))
		"ram":
			monitor.show_no_signal()
			Game.msg("Bip! Bip! Bip! Sürekli tekrar eden kısa bipler...", Color(1, 0.6, 0.4))
			Game.sfx.beeps([0.12, 0.12, 0.12, 0.12, 0.12, 0.12, 0.12, 0.12])
		"gpu":
			monitor.show_no_signal()
			Game.msg("1 uzun 3 kısa bip! Ekrana görüntü gelmiyor.", Color(1, 0.6, 0.4))
			Game.sfx.beeps([0.7, 0.13, 0.13, 0.13])
		"ssd":
			Game.sfx.beeps([0.15])
			monitor.show_no_boot()
			Game.msg("Tek bip, BIOS açıldı ama 'boot device' bulunamadı.", Color(1, 0.8, 0.4))
		"ok":
			Game.sfx.beeps([0.15])
			monitor.boot(self)
			Game.msg("Tek kısa bip... Bilgisayar sorunsuz açıldı!", Color(0.5, 1, 0.5))


func power_off() -> void:
	powered = false
	for lm in debug_leds.values():
		lm.emission_enabled = false
		lm.albedo_color = Color(0.25, 0.12, 0.05)
	led_mat.emission_enabled = false
	hum.stop()
	for m in _all_rgb():
		m.emission_energy_multiplier = 0.0
	inner_light.light_color = Color(0.9, 0.95, 1.0)
	if monitor:
		monitor.show_off()


func on_parts_changed() -> void:
	if powered:
		power_off()
		Game.msg("Parça değişince bilgisayar kapandı.")


func _all_rgb() -> Array:
	var out := rgb_mats.duplicate()
	for p in installed_parts():
		out.append_array(p.rgb_mats)
	return out


func _process(delta: float) -> void:
	if not powered:
		return
	_hue = fmod(_hue + delta * 0.15, 1.0)
	for r in case_fans:
		r.rotate_object_local(Vector3.UP, delta * 30.0)
	for p in installed_parts():
		for r in p.rotors:
			r.rotate_object_local(Vector3.UP, delta * 28.0)
	var i := 0
	for m in _all_rgb():
		var c := Color.from_hsv(fmod(_hue + i * 0.12, 1.0), 0.85, 1.0)
		m.albedo_color = c
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = 2.5
		i += 1
	inner_light.light_color = Color.from_hsv(_hue, 0.6, 1.0)
