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
var dust := 0.0            # 0..1 toz miktarı
var socket_paste := false  # CPU soketinde taze termal macun var mı
var cpu_temp := 35.0
var paste_blob: MeshInstance3D
var cable_groups := {}     # parça adı -> kablo düğümü (parça takılıysa görünür)
var _dust_nodes: Array = []  # [MeshInstance3D, gereken_slot]
var _dust_mat: StandardMaterial3D
var _dust_vis := 0.0
var _dust_tween: Tween
var _last_temp_i := -1


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
	_build_cables()
	_build_rear_io()
	_build_dust()
	MU.merge_static(self)
	_update_visuals()
	hum = AudioStreamPlayer3D.new()
	hum.stream = Game.sfx.hum()
	hum.bus = "SFX"
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
	# PCIe braketleri (arka)
	for i in 5:
		MU.box(board, Vector3(0.03, 0.012, 0.002), Vector3(-0.06, 0.25 - i * 0.02, -0.217), metal)


## Gerçekçi eğrisel kablolar. PSU/GPU/SSD takılı değilse ilgili kablolar gizlenir (birleştirilmez).
func _build_cables() -> void:
	var sleeve := MU.mat(Color(0.07, 0.07, 0.08), 0.1, 0.75)
	var sleeve2 := MU.mat(Color(0.12, 0.12, 0.13), 0.1, 0.7)
	var plug_m := MU.mat(Color(0.04, 0.04, 0.045), 0.1, 0.5)
	var red := MU.mat(Color(0.75, 0.1, 0.1), 0, 0.6)
	var psu_g := MU.no_merge(Node3D.new())
	var gpu_g := MU.no_merge(Node3D.new())
	var ssd_g := MU.no_merge(Node3D.new())
	add_child(psu_g)
	add_child(gpu_g)
	add_child(ssd_g)
	cable_groups = {"psu": psu_g, "gpu": gpu_g, "ssd": ssd_g}
	var bx := BOARD_X
	# 24-pin: kalın, örgülü; PSU'dan ön kenardaki konnektöre
	var p24: Array[Vector3] = [Vector3(0.015, 0.118, -0.025), Vector3(0.025, 0.15, 0.04), Vector3(0.0, 0.22, 0.118),
		Vector3(-0.045, 0.31, 0.122), Vector3(-0.062, 0.352, 0.112)]
	MU.tube(psu_g, p24, 0.0085, sleeve2, 8)
	var p24b: Array[Vector3] = [Vector3(0.0, 0.118, -0.025), Vector3(0.012, 0.15, 0.045), Vector3(-0.012, 0.22, 0.126),
		Vector3(-0.05, 0.31, 0.13), Vector3(-0.064, 0.355, 0.118)]
	MU.tube(psu_g, p24b, 0.0055, sleeve, 6)
	MU.rbox(psu_g, Vector3(0.016, 0.056, 0.016), Vector3(bx + 0.016, 0.355, 0.114), plug_m, 0.002)
	# CPU 4+4 pin: PSU'dan sağ taraftan dolanıp kasa üstündeki konnektöre
	var pcpu: Array[Vector3] = [Vector3(-0.015, 0.118, -0.025), Vector3(0.05, 0.17, -0.05), Vector3(0.068, 0.28, -0.1),
		Vector3(0.03, 0.405, -0.13), Vector3(-0.03, 0.438, -0.128), Vector3(-0.068, 0.436, -0.125)]
	MU.tube(psu_g, pcpu, 0.0055, sleeve, 6)
	MU.rbox(psu_g, Vector3(0.014, 0.012, 0.03), Vector3(bx + 0.012, 0.43, -0.125), plug_m, 0.002)
	# SATA güç (SSD)
	var psata: Array[Vector3] = [Vector3(0.045, 0.0675, 0.0), Vector3(0.07, 0.05, 0.08), Vector3(0.05, 0.03, 0.18), Vector3(0.022, 0.012, 0.176)]
	MU.tube(ssd_g, psata, 0.003, sleeve, 5)
	MU.rbox(ssd_g, Vector3(0.012, 0.007, 0.012), Vector3(0.022, 0.012, 0.176), plug_m, 0.001)
	# SATA data (kırmızı): anakart SATA portundan SSD'ye
	var pdata: Array[Vector3] = [Vector3(bx + 0.012, 0.2, 0.124), Vector3(-0.05, 0.17, 0.16), Vector3(-0.02, 0.07, 0.195), Vector3(0.005, 0.02, 0.185), Vector3(0.006, 0.012, 0.176)]
	MU.tube(ssd_g, pdata, 0.0025, red, 5)
	MU.rbox(ssd_g, Vector3(0.008, 0.006, 0.012), Vector3(0.006, 0.012, 0.176), plug_m, 0.001)
	# PCIe güç (GPU 8-pin) ve GPU destek direği
	var pgpu: Array[Vector3] = [Vector3(-0.045, 0.118, -0.025), Vector3(0.0, 0.14, 0.01), Vector3(0.052, 0.2, 0.045),
		Vector3(0.05, 0.27, 0.04), Vector3(0.012, 0.275, 0.035), Vector3(0.0105, 0.258, 0.035)]
	MU.tube(gpu_g, pgpu, 0.0055, sleeve, 6)
	MU.rbox(gpu_g, Vector3(0.012, 0.014, 0.026), Vector3(0.0105, 0.252, 0.035), plug_m, 0.002)
	MU.cyl(gpu_g, 0.004, 0.2, Vector3(0.025, 0.105, 0.07), MU.mat(Color(0.7, 0.72, 0.75), 0.9, 0.3), Vector3.ZERO, 8)
	MU.rbox(gpu_g, Vector3(0.022, 0.003, 0.016), Vector3(0.025, 0.207, 0.07), plug_m, 0.001)
	MU.rbox(gpu_g, Vector3(0.026, 0.004, 0.026), Vector3(0.025, 0.002, 0.07), plug_m, 0.001)


## Kasa arkası: I/O kalkanı, PSU girişi, PCIe kapakları (dış yüz).
func _build_rear_io() -> void:
	var z := -D / 2 - 0.0015
	var plate := MU.mat(Color(0.55, 0.57, 0.6), 0.9, 0.35)
	var black := MU.mat(Color(0.03, 0.03, 0.035), 0.2, 0.5)
	MU.box(self, Vector3(0.06, 0.09, 0.002), Vector3(-0.06, 0.38, z), plate)
	for i in 4:
		MU.box(self, Vector3(0.012, 0.007, 0.0025), Vector3(-0.08 + (i % 2) * 0.015, 0.415 - (i / 2) * 0.012, z - 0.0005), MU.mat(Color(0.1, 0.3, 0.9), 0, 0.5))
	MU.box(self, Vector3(0.014, 0.012, 0.0028), Vector3(-0.045, 0.415, z - 0.0005), black)
	MU.box(self, Vector3(0.012, 0.009, 0.0028), Vector3(-0.045, 0.395, z - 0.0005), MU.mat(Color(0.8, 0.8, 0.82), 0.9, 0.3))
	var jacks := [Color(0.2, 0.8, 0.3), Color(0.9, 0.3, 0.5), Color(0.2, 0.5, 0.9)]
	for i in 3:
		MU.cyl(self, 0.003, 0.003, Vector3(-0.085 + i * 0.01, 0.355, z - 0.0005), MU.mat(jacks[i]), Vector3(90, 0, 0), 8)
	for i in 5:
		MU.box(self, Vector3(0.05, 0.012, 0.002), Vector3(-0.06, 0.25 - i * 0.02, z), plate)
		MU.box(self, Vector3(0.04, 0.003, 0.0025), Vector3(-0.06, 0.25 - i * 0.02, z - 0.0004), black)
	# PSU girişi: IEC soket + anahtar + ızgara
	MU.box(self, Vector3(0.15, 0.085, 0.002), Vector3(0.0, 0.0475, z), black)
	MU.rbox(self, Vector3(0.03, 0.022, 0.004), Vector3(0.04, 0.035, z - 0.0015), MU.mat(Color(0.12, 0.12, 0.13), 0.2, 0.5), 0.002)
	MU.rbox(self, Vector3(0.012, 0.016, 0.004), Vector3(0.012, 0.035, z - 0.0015), MU.mat(Color(0.8, 0.1, 0.1), 0, 0.4), 0.002)
	for i in 6:
		MU.box(self, Vector3(0.08, 0.003, 0.0025), Vector3(-0.025, 0.02 + i * 0.01, z - 0.0005), MU.mat(Color(0.08, 0.08, 0.09)))


## Toz katmanları (yarı saydam gri tüylü quad'lar): gizlenebilir, birleştirilmez.
func _build_dust() -> void:
	_dust_mat = MU.new_mat(Color(1, 1, 1, 0.0), 0, 1.0)
	_dust_mat.albedo_texture = MU.dust_texture()
	_dust_mat.uv1_scale = Vector3(2, 2, 1)
	_dust_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_dust_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var holder := MU.no_merge(Node3D.new())
	holder.name = "Dust"
	add_child(holder)
	var specs := [
		[Vector2(0.3, 0.3), Vector3(BOARD_X + 0.0007, 0.29, -0.02), Vector3(0, 90, 0), ""],
		[Vector2(0.2, 0.42), Vector3(0.0, 0.009, 0.0), Vector3(-90, 0, 0), ""],
		[Vector2(0.088, 0.088), SLOT_POS.cpu + Vector3(0.0605, 0, 0), Vector3(0, 90, 0), "cpu"],
		[Vector2(0.088, 0.088), SLOT_POS.cpu + Vector3(0.0545, 0, 0), Vector3(0, 90, 0), "cpu"],
		[Vector2(0.24, 0.028), SLOT_POS.gpu + Vector3(0.1085, -0.013, 0), Vector3(0, 90, 0), "gpu"],
		[Vector2(0.104, 0.24), SLOT_POS.gpu + Vector3(0.053, -0.0335, 0), Vector3(90, 0, 0), "gpu"],
		[Vector2(0.12, 0.12), SLOT_POS.psu + Vector3(0, 0.0446, 0), Vector3(-90, 0, 0), "psu"],
		[Vector2(0.11, 0.11), Vector3(0.02, 0.36, -D / 2 + 0.036), Vector3.ZERO, ""],
		[Vector2(0.125, 0.125), Vector3(0.0, 0.15, D / 2 - 0.038), Vector3(0, 180, 0), ""],
		[Vector2(0.125, 0.125), Vector3(0.0, 0.31, D / 2 - 0.038), Vector3(0, 180, 0), ""],
	]
	for sp in specs:
		var qm := QuadMesh.new()
		qm.size = sp[0]
		var mi := MeshInstance3D.new()
		mi.mesh = qm
		mi.material_override = _dust_mat
		mi.position = sp[1]
		mi.rotation_degrees = sp[2]
		mi.visible = false
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		holder.add_child(mi)
		_dust_nodes.append([mi, sp[3]])
	# macun lekesi (CPU soketinde)
	paste_blob = MU.sphere(self, 0.011, SLOT_POS.cpu + Vector3(0.0045, 0, 0), MU.mat(Color(0.7, 0.72, 0.76), 0.8, 0.25), Vector3(0.22, 1, 1))
	MU.no_merge(paste_blob)
	paste_blob.visible = false


func set_dust(v: float) -> void:
	dust = clampf(v, 0.0, 1.0)
	_dust_vis = dust
	_apply_dust(dust)


## Basınçlı hava ile temizle: toz yavaşça kaybolur.
func clean_dust() -> void:
	var from := _dust_vis
	dust = 0.0
	_dust_vis = 0.0
	if _dust_tween:
		_dust_tween.kill()
	_dust_tween = create_tween()
	_dust_tween.tween_method(_apply_dust, from, 0.0, 0.8)


func _apply_dust(v: float) -> void:
	if _dust_mat == null:
		return
	_dust_mat.albedo_color.a = clampf(v * 1.1, 0.0, 1.0) * 0.5
	_update_visuals(v > 0.04)


func _update_visuals(dust_on = null) -> void:
	var on: bool = (dust > 0.04) if dust_on == null else dust_on
	for d in _dust_nodes:
		var req: String = d[1]
		d[0].visible = on and (req == "" or slots[req].part != null)
	for k in cable_groups:
		cable_groups[k].visible = slots[k].part != null
	if paste_blob:
		paste_blob.visible = socket_paste and slots.cpu.part == null


func cpu_installed(p) -> void:
	if socket_paste:
		p.paste_ok = true
		socket_paste = false
		Game.msg("İşlemci macunla takıldı.", Color(0.7, 0.9, 1.0))


# ---------------------------------------------------------------- aletler

func tool_hint(tool, slot) -> String:
	match tool.tool_type:
		"paste":
			if slot == null or slot.accepts != "cpu":
				return "Termal macun: boş işlemci soketine sürülür"
			if slot.part:
				return "Macun için önce işlemciyi sök"
			if socket_paste:
				return "Soket zaten macunlu, işlemciyi tak"
			return "Termal macun sür  [E]"
		"air":
			return "Tozu üfle  [E]" if dust > 0.02 else "Üfle  [E] (zaten temiz)"
	return ""


func tool_use(player, tool, slot) -> void:
	match tool.tool_type:
		"paste":
			if slot == null or slot.accepts != "cpu":
				Game.msg("Macunu boş işlemci soketine sürmelisin.", Color(1, 0.8, 0.4))
			elif slot.part:
				Game.msg("Önce işlemciyi sökmelisin.", Color(1, 0.8, 0.4))
			elif socket_paste:
				Game.msg("Soket zaten macunlu.", Color(1, 0.8, 0.4))
			else:
				socket_paste = true
				Game.sfx.squish()
				_update_visuals()
				Game.msg("Termal macun sürüldü. Şimdi işlemciyi tak.", Color(0.7, 0.9, 1.0))
		"air":
			tool.puff(player)
			if dust > 0.02:
				clean_dust()
				Game.msg("Kasanın içi tozdan arındı!", Color(0.7, 0.9, 1.0))
			else:
				Game.msg("İçerisi zaten temiz.")


func get_hint(player) -> String:
	if player.held and player.held.is_tool():
		if not panel_open:
			return "Aleti kullanmak için kapağı aç"
		return tool_hint(player.held, null)
	return ""


func interact(player) -> void:
	if player.held and player.held.is_tool() and panel_open:
		tool_use(player, player.held, null)


## Müşteri bilgisayarını doldurur. parts: [[slot_adı, tip, seviye, bozuk_mu], ...]
func fill(parts: Array) -> void:
	for p in parts:
		if p[0] == "dust":  # ["dust", "", miktar, false]: kasa tozu
			set_dust(p[2])
			continue
		var part = PART.new().setup(p[1], p[2], p[3])
		if p.size() > 4:  # 5. eleman: CPU macunu sağlam mı
			part.paste_ok = p[4]
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


## Teşhis kodu: "nopower", "cpu", "ram", "gpu", "ssd", "overheat" veya "ok"
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
	if dust > 0.5 or not cpu.paste_ok:
		return "overheat"
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
	cpu_temp = 36.0
	_last_temp_i = -1
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
		"overheat":
			Game.sfx.beeps([0.15])
			monitor.boot(self)
			Game.msg("Tek kısa bip... Bilgisayar açıldı ama fanlar çok yüksek sesle dönüyor.", Color(1, 0.85, 0.5))


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
	if slots.size() == 6:
		_update_visuals(null if dust <= 0.0 else dust > 0.04)
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
		cpu_temp = move_toward(cpu_temp, 30.0, 8.0 * delta)
		return
	_heat(delta)
	if not powered:
		return
	_hue = fmod(_hue + delta * 0.15, 1.0)
	var spin := 1.0 + maxf(cpu_temp - 50.0, 0.0) / 40.0
	for r in case_fans:
		r.rotate_object_local(Vector3.UP, delta * 30.0 * spin)
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


## CPU sıcaklığı: masaüstü açıkken ısınma/soğuma; aşırı ısınırsa bilgisayar kapanır.
func _heat(delta: float) -> void:
	if monitor == null or not monitor.desktop.visible:
		return
	var hot := diagnose() == "overheat"
	var target := 99.0 if hot else 45.0
	cpu_temp = move_toward(cpu_temp, target, (14.0 if hot else 18.0) * delta)
	var ti := int(cpu_temp)
	if ti != _last_temp_i:
		_last_temp_i = ti
		monitor.set_temp(ti)
	if cpu_temp >= 98.5:
		power_off()
		Game.sfx.error()
		Game.msg("Bilgisayar aşırı ısınıp kapandı!", Color(1, 0.4, 0.3))
