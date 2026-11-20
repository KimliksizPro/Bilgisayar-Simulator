extends Node3D
## Müşterinin bilgisayar kasası: form faktörü, anakart yuvası, tüm parça yuvaları, cam kapak, güç düğmesi, teşhis.

const MU := preload("res://scripts/mesh_util.gd")
const PM := preload("res://scripts/part_models.gd")
const SLOT := preload("res://scripts/slot.gd")
const PART := preload("res://scripts/part.gd")

# Varsayılan Mid-Tower ATX ölçüleri (statik PC.W/H/D referansları için korunur)
const W := 0.22
const H := 0.46
const D := 0.44
const BOARD_X := -0.0875

var case_id := "atx_mid"
var case_def: Dictionary = {}
var case_w := W
var case_h := H
var case_d := D
var board_x := BOARD_X
var slot_pos := {}

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
var _built := false


func _ready() -> void:
	_build()


func _build() -> void:
	case_def = DB.parts.case_def(case_id)
	if case_def.is_empty():
		case_def = DB.parts.case_def("atx_mid")
	var sz = case_def.get("size", Vector3(W, H, D))
	if sz is Vector3:
		case_w = sz.x
		case_h = sz.y
		case_d = sz.z
	elif sz is Array and sz.size() >= 3:
		case_w = float(sz[0])
		case_h = float(sz[1])
		case_d = float(sz[2])
	board_x = -case_w / 2.0 + 0.0225
	slot_pos = _compute_slot_positions()

	var white := randf() < 0.4
	var shell_m := MU.mat(Color(0.9, 0.9, 0.92) if white else Color(0.08, 0.08, 0.09), 0.4, 0.45)
	var inner_m := MU.mat(Color(0.8, 0.8, 0.82) if white else Color(0.11, 0.11, 0.12), 0.4, 0.5)
	var t := 0.006
	var body := StaticBody3D.new()
	body.collision_layer = 1
	add_child(body)
	var pieces := [
		[Vector3(case_w, t, case_d), Vector3(0, t / 2, 0), shell_m],
		[Vector3(case_w, t, case_d), Vector3(0, case_h - t / 2, 0), shell_m],
		[Vector3(case_w, case_h, t), Vector3(0, case_h / 2, -case_d / 2 + t / 2), inner_m],
		[Vector3(case_w, case_h, t), Vector3(0, case_h / 2, case_d / 2 - t / 2), shell_m],
		[Vector3(t, case_h, case_d), Vector3(-case_w / 2 + t / 2, case_h / 2, 0), shell_m],
	]
	for p in pieces:
		MU.rbox(body, p[0], p[1], p[2], 0.004)
		MU.add_box_shape(body, p[0], p[1])
	# dış kenar çerçevesi (yuvarlatılmış)
	for y in [0.0, case_h]:
		MU.rbox(self, Vector3(case_w + 0.004, 0.014, case_d + 0.004), Vector3(0, y, 0), shell_m, 0.006)
	# ön panel ızgarası
	var mesh_m := MU.mat(Color(0.2, 0.2, 0.22) if not white else Color(0.75, 0.75, 0.78), 0.6, 0.5)
	var bars := maxi(8, int(case_w * 64.0))
	for i in bars:
		var bx := -case_w * 0.14 + float(i) * (case_w * 0.55 / float(bars))
		MU.box(self, Vector3(0.002, case_h * 0.8, 0.003), Vector3(bx, case_h / 2, case_d / 2 + 0.002), mesh_m)
	# ayaklar
	var fx := case_w * 0.36
	var fz := case_d * 0.41
	for x in [-fx, fx]:
		for z in [-fz, fz]:
			MU.box(self, Vector3(0.03, 0.01, 0.03), Vector3(x, -0.005, z), MU.mat(Color(0.05, 0.05, 0.05)))
	# ön panel detayları
	MU.box(self, Vector3(0.006, case_h * 0.86, 0.004), Vector3(-case_w * 0.32, case_h / 2, case_d / 2 + 0.002), MU.mat(Color(0.3, 0.3, 0.32), 0.8, 0.3))
	led_mat = MU.new_mat(Color(0.1, 0.1, 0.1))
	MU.box(self, Vector3(0.008, 0.003, 0.003), Vector3(case_w * 0.18, case_h - 0.03, case_d / 2 + 0.001), led_mat)
	# güç düğmesi
	MU.cyl(self, 0.011, 0.006, Vector3(0.0, case_h - 0.03, case_d / 2 + 0.002), MU.mat(Color(0.75, 0.75, 0.78), 0.9, 0.3), Vector3(90, 0, 0))
	MU.interactable(self, Vector3(0.04, 0.04, 0.02), Vector3(0.0, case_h - 0.03, case_d / 2 + 0.006),
		func(_p): return "Güç düğmesi  [E]" if not powered else "Bilgisayarı kapat  [E]",
		func(_p): power_button())
	# cam yan kapak (menteşe arka kenarda)
	panel_pivot = MU.no_merge(Node3D.new())
	panel_pivot.position = Vector3(case_w / 2 - 0.002, 0, -case_d / 2)
	add_child(panel_pivot)
	var panel = MU.interactable(panel_pivot, Vector3(0.006, case_h, case_d), Vector3(0, case_h / 2, case_d / 2),
		func(_p): return "Kapağı aç  [E]" if not panel_open else "Kapağı kapat  [E]",
		func(_p): toggle_panel())
	MU.box(panel, Vector3(0.004, case_h - 0.02, case_d - 0.02), Vector3.ZERO, MU.glass())
	var frame_m := shell_m
	MU.box(panel, Vector3(0.005, 0.01, case_d), Vector3(0, case_h / 2 - 0.005, 0), frame_m)
	MU.box(panel, Vector3(0.005, 0.01, case_d), Vector3(0, -case_h / 2 + 0.005, 0), frame_m)
	MU.box(panel, Vector3(0.005, case_h, 0.01), Vector3(0, 0, case_d / 2 - 0.005), frame_m)
	MU.box(panel, Vector3(0.005, case_h, 0.01), Vector3(0, 0, -case_d / 2 + 0.005), frame_m)
	MU.merge_static(panel_pivot)
	_build_tray()
	_build_slots()
	# kasa içi LED şerit + ışık (parçalar karanlıkta kalmasın)
	var strip := MU.new_mat(Color(0.9, 0.95, 1.0), 0, 0.5, 2.0)
	rgb_mats.append(strip)
	MU.box(self, Vector3(0.006, 0.004, case_d - 0.04), Vector3(case_w * 0.27, case_h - 0.01, 0), strip)
	inner_light = OmniLight3D.new()
	inner_light.position = Vector3(0.04, case_h - 0.06, 0.0)
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
	_built = true
	_update_visuals()
	hum = AudioStreamPlayer3D.new()
	hum.stream = Game.sfx.hum()
	hum.bus = "SFX"
	hum.volume_db = -14.0
	hum.position = Vector3(0, case_h * 0.43, 0)
	add_child(hum)


## Kasa form faktörüne göre tüm yuva konumlarını hesaplar.
func _compute_slot_positions() -> Dictionary:
	var dy := maxf(case_h - H, -0.105)
	var z_lim := case_d * 0.40
	var bx := board_x
	var pos := {
		"mobo": Vector3(bx, 0.29 + dy, clampf(-0.02, -z_lim, z_lim)),
		"cpu": Vector3(bx, 0.36 + dy, clampf(-0.06, -z_lim, z_lim)),
		"cooler": Vector3(bx + 0.006, 0.36 + dy, clampf(-0.06, -z_lim, z_lim)),
		"ram1": Vector3(bx, 0.35 + dy, clampf(0.024, -z_lim, z_lim)),
		"ram2": Vector3(bx, 0.35 + dy, clampf(0.039, -z_lim, z_lim)),
		"ram3": Vector3(bx, 0.35 + dy, clampf(0.054, -z_lim, z_lim)),
		"ram4": Vector3(bx, 0.35 + dy, clampf(0.069, -z_lim, z_lim)),
		"gpu": Vector3(bx, 0.235 + dy, clampf(-0.04, -z_lim, z_lim)),
		"m2": Vector3(bx + 0.002, 0.18 + dy, clampf(-0.01, -z_lim, z_lim)),
		"cmos": Vector3(bx + 0.002, 0.268 + dy, clampf(0.092, -z_lim, z_lim)),
		"psu": Vector3(0.0, 0.0475, -case_d / 2.0 + 0.09),
		"ssd": Vector3(0.02, 0.015, case_d / 2.0 - 0.10),
		"fan1": Vector3(0.02, case_h - 0.10, -case_d / 2.0 + 0.02),
	}
	if int(case_def.get("fan_slots", 2)) >= 2:
		pos["fan2"] = Vector3(0.0, case_h * 0.55, case_d / 2.0 - 0.022)
	return pos


## Anakart tepsisi, pirinç yükselticiler ve hata LED'leri (anakart artık ayrı yuva).
func _build_tray() -> void:
	var tray := Node3D.new()
	add_child(tray)
	var tray_x := board_x - 0.005
	var mobo_p: Vector3 = slot_pos.mobo
	var tray_m := MU.mat(Color(0.14, 0.15, 0.17), 0.5, 0.55)
	var brass := MU.mat(Color(0.82, 0.65, 0.25), 0.9, 0.3)
	var metal := MU.mat(Color(0.5, 0.52, 0.56), 0.85, 0.3)
	var tray_h := minf(0.28, case_h - 0.14)
	var tray_d := minf(0.26, case_d - 0.12)
	MU.box(tray, Vector3(0.003, tray_h, tray_d), Vector3(tray_x, mobo_p.y, mobo_p.z), tray_m)
	# pirinç yükselticiler (standoff)
	for sy in [-tray_h * 0.42, 0.0, tray_h * 0.42]:
		for sz in [-tray_d * 0.42, tray_d * 0.42]:
			MU.cyl(tray, 0.0028, 0.005, Vector3(tray_x + 0.003, mobo_p.y + sy, mobo_p.z + sz), brass, Vector3(0, 0, 90), 6)
	# PCIe braketleri (arka)
	var brackets := 5 if case_h >= 0.42 else (4 if case_h >= 0.36 else 2)
	for i in brackets:
		MU.box(tray, Vector3(0.03, 0.012, 0.002), Vector3(-case_w * 0.27, slot_pos.gpu.y + 0.015 - i * 0.02, -case_d / 2.0 + 0.003), metal)
	# hata LED'leri (CPU / DRAM / VGA / BOOT)
	var names := ["CPU", "DRAM", "VGA", "BOOT"]
	var led_y := minf(mobo_p.y + tray_h * 0.46, case_h - 0.03)
	var led_z := minf(mobo_p.z + tray_d * 0.40, case_d * 0.38)
	for i in names.size():
		var lm := MU.new_mat(Color(0.25, 0.12, 0.05), 0, 0.4)
		debug_leds[names[i]] = lm
		MU.box(tray, Vector3(0.002, 0.003, 0.005), Vector3(board_x + 0.004, led_y - i * 0.008, led_z), lm)
		var ll := MU.label(tray, names[i], Vector3(board_x + 0.0042, led_y - i * 0.008, led_z - 0.011), 24, Color(0.9, 0.9, 0.9), Vector3(0, 90, 0), 0.00022)
		ll.double_sided = false


## Kasa yuvalarını kurar (mobo, cpu, cooler, ram1..4, gpu, psu, ssd/hdd, m2, fan1..2, cmos).
func _build_slots() -> void:
	var defs := [
		["mobo", "mobo", [], 0],
		["cpu", "cpu", [], 0],
		["cooler", "cooler", [], 0],
		["ram1", "ram", [], 0],
		["ram2", "ram", [], 1],
		["ram3", "ram", [], 2],
		["ram4", "ram", [], 3],
		["gpu", "gpu", [], 0],
		["psu", "psu", [], 0],
		["ssd", "ssd", ["hdd"], 0],
		["m2", "nvme", [], 0],
		["fan1", "fan", [], 0],
		["fan2", "fan", [], 1],
		["cmos", "cmos", [], 0],
	]
	for d in defs:
		var sn: String = d[0]
		if not slot_pos.has(sn):
			continue
		var s = SLOT.new()
		s.name = sn
		MU.no_merge(s)
		s.position = slot_pos[sn]
		add_child(s)
		s.setup(d[1], self, d[2], d[3])
		slots[sn] = s


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
	var bx := board_x
	var dy := maxf(case_h - H, -0.105)
	var psu_z: float = slot_pos.psu.z + 0.105
	var ssd_z: float = slot_pos.ssd.z + 0.056
	# 24-pin: kalın, örgülü; PSU'dan anakart ön kenarına
	var p24: Array[Vector3] = [Vector3(0.015, 0.118, psu_z), Vector3(0.025, 0.15 + dy * 0.4, 0.04), Vector3(0.0, 0.22 + dy * 0.6, 0.10),
		Vector3(-0.045, 0.31 + dy, 0.105), Vector3(bx + 0.025, 0.352 + dy, 0.10)]
	MU.tube(psu_g, p24, 0.0085, sleeve2, 8)
	MU.rbox(psu_g, Vector3(0.016, 0.056, 0.016), Vector3(bx + 0.016, 0.355 + dy, 0.102), plug_m, 0.002)
	# CPU 4+4 pin
	var pcpu: Array[Vector3] = [Vector3(-0.015, 0.118, psu_z), Vector3(0.045, 0.17 + dy * 0.4, -0.05),
		Vector3(0.055, 0.28 + dy * 0.8, -0.09), Vector3(bx + 0.02, case_h - 0.025, -0.10)]
	MU.tube(psu_g, pcpu, 0.0055, sleeve, 6)
	MU.rbox(psu_g, Vector3(0.014, 0.012, 0.03), Vector3(bx + 0.012, case_h - 0.03, -0.10), plug_m, 0.002)
	# SATA güç + data (SSD/HDD)
	var psata: Array[Vector3] = [Vector3(0.045, 0.0675, 0.0), Vector3(0.06, 0.05, ssd_z * 0.5), Vector3(0.022, 0.015, ssd_z)]
	MU.tube(ssd_g, psata, 0.003, sleeve, 5)
	MU.rbox(ssd_g, Vector3(0.012, 0.007, 0.012), Vector3(0.022, 0.015, ssd_z), plug_m, 0.001)
	var pdata: Array[Vector3] = [Vector3(bx + 0.012, 0.2 + dy, 0.10), Vector3(-0.03, 0.11, ssd_z * 0.85), Vector3(0.006, 0.015, ssd_z)]
	MU.tube(ssd_g, pdata, 0.0025, red, 5)
	MU.rbox(ssd_g, Vector3(0.008, 0.006, 0.012), Vector3(0.006, 0.015, ssd_z), plug_m, 0.001)
	# PCIe güç (GPU)
	var gy: float = slot_pos.gpu.y
	var pgpu: Array[Vector3] = [Vector3(-0.04, 0.118, psu_z), Vector3(0.0, 0.13, 0.01),
		Vector3(0.045, gy, 0.04), Vector3(0.0105, gy + 0.023, 0.035)]
	MU.tube(gpu_g, pgpu, 0.0055, sleeve, 6)
	MU.rbox(gpu_g, Vector3(0.012, 0.014, 0.026), Vector3(0.0105, gy + 0.017, 0.035), plug_m, 0.002)


## Kasa arkası: I/O kalkanı, PSU girişi, PCIe kapakları (dış yüz).
func _build_rear_io() -> void:
	var z := -case_d / 2.0 - 0.0015
	var io_y: float = slot_pos.cpu.y + 0.02
	var plate := MU.mat(Color(0.55, 0.57, 0.6), 0.9, 0.35)
	var black := MU.mat(Color(0.03, 0.03, 0.035), 0.2, 0.5)
	var rx := -case_w * 0.27
	MU.box(self, Vector3(0.06, 0.09, 0.002), Vector3(rx, io_y, z), plate)
	for i in 4:
		MU.box(self, Vector3(0.012, 0.007, 0.0025), Vector3(rx - 0.02 + (i % 2) * 0.015, io_y + 0.035 - (i / 2) * 0.012, z - 0.0005), MU.mat(Color(0.1, 0.3, 0.9), 0, 0.5))
	MU.box(self, Vector3(0.014, 0.012, 0.0028), Vector3(rx + 0.015, io_y + 0.035, z - 0.0005), black)
	MU.box(self, Vector3(0.012, 0.009, 0.0028), Vector3(rx + 0.015, io_y + 0.015, z - 0.0005), MU.mat(Color(0.8, 0.8, 0.82), 0.9, 0.3))
	var jacks := [Color(0.2, 0.8, 0.3), Color(0.9, 0.3, 0.5), Color(0.2, 0.5, 0.9)]
	for i in 3:
		MU.cyl(self, 0.003, 0.003, Vector3(rx - 0.025 + i * 0.01, io_y - 0.025, z - 0.0005), MU.mat(jacks[i]), Vector3(90, 0, 0), 8)
	var brackets := 5 if case_h >= 0.42 else (4 if case_h >= 0.36 else 2)
	for i in brackets:
		MU.box(self, Vector3(0.05, 0.012, 0.002), Vector3(rx, slot_pos.gpu.y + 0.015 - i * 0.02, z), plate)
		MU.box(self, Vector3(0.04, 0.003, 0.0025), Vector3(rx, slot_pos.gpu.y + 0.015 - i * 0.02, z - 0.0004), black)
	# PSU girişi: IEC soket + anahtar + ızgara
	MU.box(self, Vector3(minf(0.15, case_w - 0.03), 0.085, 0.002), Vector3(0.0, 0.0475, z), black)
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
		[Vector2(minf(0.28, case_h - 0.14), minf(0.28, case_d - 0.12)), slot_pos.mobo + Vector3(0.005, 0, 0), Vector3(0, 90, 0), ""],
		[Vector2(case_w - 0.02, case_d - 0.02), Vector3(0.0, 0.009, 0.0), Vector3(-90, 0, 0), ""],
		[Vector2(0.088, 0.088), slot_pos.cpu + Vector3(0.0605, 0, 0), Vector3(0, 90, 0), "cpu"],
		[Vector2(0.22, 0.028), slot_pos.gpu + Vector3(0.1085, -0.013, 0), Vector3(0, 90, 0), "gpu"],
		[Vector2(0.104, 0.22), slot_pos.gpu + Vector3(0.053, -0.0335, 0), Vector3(90, 0, 0), "gpu"],
		[Vector2(0.12, 0.12), slot_pos.psu + Vector3(0, 0.0446, 0), Vector3(-90, 0, 0), "psu"],
		[Vector2(0.11, 0.11), slot_pos.fan1 + Vector3(0, 0, 0.016), Vector3.ZERO, ""],
	]
	if slot_pos.has("fan2"):
		specs.append([Vector2(0.12, 0.12), slot_pos.fan2 + Vector3(0, 0, -0.016), Vector3(0, 180, 0), ""])
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
	paste_blob = MU.sphere(self, 0.011, slot_pos.cpu + Vector3(0.0045, 0, 0), MU.mat(Color(0.7, 0.72, 0.76), 0.8, 0.25), Vector3(0.22, 1, 1))
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
	if not _built:
		return
	var on: bool = (dust > 0.04) if dust_on == null else dust_on
	for d in _dust_nodes:
		var req: String = d[1]
		d[0].visible = on and (req == "" or (slots.has(req) and slots[req].part != null))
	for k in cable_groups:
		if slots.has(k):
			cable_groups[k].visible = slots[k].part != null
	if paste_blob and slots.has("cpu"):
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


# ---------------------------------------------------------------- parça doldurma ve sorgular

## Müşteri bilgisayarını doldurur.
## v3 dizi biçimi: [[slot_adı, tip, seviye, bozuk_mu, (macun_ok), (muadil)], ...]
## v4 sözlük biçimi: [{"slot", "sku", "broken", "paste_ok", "cheap", "health"}, ...]
## Eski çağrılar (mobo/cooler/fan1/cmos olmadan) uyumlu varsayılanlarla tamamlanır; boş [] kasa boş kalır.
func fill(parts: Array) -> void:
	var seen := {}
	var has_any_part := false
	for entry in parts:
		if entry is Dictionary:
			var sn := str(entry.get("slot", ""))
			if sn == "dust" or entry.has("dust"):
				set_dust(float(entry.get("amount", entry.get("dust", 0.0))))
				continue
			if sn.is_empty():
				continue
			seen[sn] = true
			var sku_id := str(entry.get("sku", ""))
			if sku_id.is_empty() or bool(entry.get("omit", false)):
				continue
			if not slots.has(sn):
				continue
			var part = PART.new().setup_sku(sku_id, bool(entry.get("broken", false)))
			if entry.has("paste_ok"):
				part.paste_ok = bool(entry.get("paste_ok", true))
			if entry.has("health"):
				part.health = int(entry.get("health", 100))
			slots[sn].install(part)
			if bool(entry.get("cheap", false)):
				part.make_cheap()
			has_any_part = true
		elif entry is Array and entry.size() >= 4:
			var sn := str(entry[0])
			if sn == "dust":  # ["dust", "", miktar, false]: kasa tozu
				set_dust(float(entry[2]))
				continue
			seen[sn] = true
			if not slots.has(sn):
				continue
			var part = PART.new().setup(str(entry[1]), int(entry[2]), bool(entry[3]))
			if entry.size() > 4:  # 5. eleman: CPU macunu sağlam mı
				part.paste_ok = bool(entry[4])
			slots[sn].install(part)
			if entry.size() > 5 and bool(entry[5]):
				part.make_cheap()
			has_any_part = true
	# Geriye dönük uyumluluk: eski işler/testler mobo/cooler/fan1/cmos vermediyse uyumlu varsayılanları tak
	if has_any_part:
		_fill_legacy_defaults(seen)


func _fill_legacy_defaults(seen: Dictionary) -> void:
	if not seen.has("mobo") and slots.has("mobo") and slots["mobo"].part == null:
		var mobo_sku := _default_mobo_for_installed()
		slots["mobo"].install(PART.new().setup_sku(mobo_sku, false))
	if not seen.has("cooler") and slots.has("cooler") and slots["cooler"].part == null:
		slots["cooler"].install(PART.new().setup_sku("cooler_stock", false))
	if not seen.has("fan1") and slots.has("fan1") and slots["fan1"].part == null:
		slots["fan1"].install(PART.new().setup_sku("fan_120_std", false))
	if not seen.has("cmos") and slots.has("cmos") and slots["cmos"].part == null:
		slots["cmos"].install(PART.new().setup_sku("cmos_cr2032", false))


func _default_mobo_for_installed() -> String:
	var cpu = part_in("cpu")
	if cpu != null:
		var cdef: PartDef = cpu.def()
		if cdef != null:
			match str(cdef.compat.get("socket", "")):
				"AM5": return "mobo_am5_atx"
				"LGA1700": return "mobo_lga1700_matx"
				"LGA1851": return "mobo_lga1851_itx"
	if case_id == "itx_compact":
		return "mobo_lga1851_itx"
	return "mobo_am4_matx"


func part_in(slot_name: String):
	return slots[slot_name].part if slots.has(slot_name) else null


func installed_parts() -> Array:
	var out := []
	for s in slots.values():
		if s.part:
			out.append(s.part)
	return out


func total_ram() -> int:
	var gb := 0
	for n in ["ram1", "ram2", "ram3", "ram4"]:
		var p = part_in(n)
		if p and not p.broken:
			var d: PartDef = p.def()
			gb += int(d.specs.get("gb", 0)) if d != null else PM.ram_gb(p.tier)
	return gb


## Standart kasa durum sözlüğü (Compatibility motoru ile tam uyumlu).
func case_state() -> Dictionary:
	return Compatibility.case_state_of(self)


## Canlı güç tüketimi özeti: {"draw", "psu", "recommended", "ok"}.
func watt_summary() -> Dictionary:
	return Compatibility.calc_watts(case_state())


# ---------------------------------------------------------------- teşhis ve güç

## Teşhis kodu: "nopower", "mobo", "cpu", "ram", "gpu", "ssd", "cooler", "cmos",
## uyumluluk kodları ("psu_watts", "psu_connectors", "no_display", ...), "overheat" veya "ok".
func diagnose() -> String:
	var psu = part_in("psu")
	if psu == null or psu.broken:
		return "nopower"
	var mobo = part_in("mobo")
	if mobo == null or mobo.broken:
		return "mobo"
	var cpu = part_in("cpu")
	if cpu == null or cpu.broken:
		return "cpu"
	var rams := []
	for n in ["ram1", "ram2", "ram3", "ram4"]:
		var r = part_in(n)
		if r:
			rams.append(r)
	if rams.is_empty() or rams.any(func(r): return r.broken):
		return "ram"
	var gpu = part_in("gpu")
	if gpu != null and gpu.broken:
		return "gpu"
	var storages := []
	for n in ["ssd", "m2"]:
		var st = part_in(n)
		if st:
			storages.append(st)
	if storages.is_empty() or storages.any(func(s): return s.broken):
		return "ssd"
	var cooler = part_in("cooler")
	if cooler == null or cooler.broken:
		return "cooler"
	var cmos = part_in("cmos")
	if cmos == null or cmos.broken:
		return "cmos"
	var sys := Compatibility.check_system(case_state())
	if not sys.ok and not sys.issues.is_empty():
		return str(sys.issues[0].code)
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
	var fdef = DB.jobs.fault_by_code(code)  # belirti verisi (LED, bip, ekran, mesaj) arıza tanımından
	var sym: Dictionary = fdef.symptoms if fdef != null else {}
	if code == "nopower" or code == "mobo":
		var fb := "Hiçbir tepki yok... Anakart takılı değil veya arızalı." if code == "mobo" else "Hiçbir tepki yok... Fanlar bile dönmüyor."
		_symptom_msg(sym, fb)
		return
	if code == "psu_watts" or code == "psu_connectors":
		Game.sfx.error()
		var fb := "Güç kaynağı yetersiz! Sistem açılmadan koruma kapattı." if code == "psu_watts" else "Ekran kartı güç kablosu uyumsuz! PSU konnektörü yetmiyor."
		_symptom_msg(sym, fb)
		return
	powered = true
	cpu_temp = 36.0
	_last_temp_i = -1
	var led_name: String = str(sym.get("led", _fallback_led(code)))
	if led_name != "" and debug_leds.has(led_name):
		var lm: StandardMaterial3D = debug_leds[led_name]
		lm.albedo_color = Color(1.0, 0.45, 0.1)
		lm.emission_enabled = true
		lm.emission = Color(1.0, 0.45, 0.1)
		lm.emission_energy_multiplier = 6.0
	led_mat.emission_enabled = true
	led_mat.emission = Color(0.2, 0.6, 1.0)
	led_mat.emission_energy_multiplier = 3.0
	hum.play()
	if code == "ok":
		Game.sfx.beeps([0.15])
		if monitor:
			monitor.boot(self)
		Game.msg("Tek kısa bip... Bilgisayar sorunsuz açıldı!", Color(0.5, 1, 0.5))
		return
	var beeps: Array = []
	for b in sym.get("beep", []):
		beeps.append(float(b))
	if not beeps.is_empty():
		Game.sfx.beeps(beeps)
	var screen := str(sym.get("screen", _fallback_screen(code)))
	if monitor:
		match screen:
			"no_signal": monitor.show_no_signal()
			"no_boot": monitor.show_no_boot()
			"boot": monitor.boot(self)
	_symptom_msg(sym, _fallback_msg(code))


func _fallback_led(code: String) -> String:
	match code:
		"socket", "cooler", "cooler_socket", "cooler_height", "cooler_rad": return "CPU"
		"ddr_notch", "ram_slot_limit": return "DRAM"
		"no_display", "gpu_length": return "VGA"
		"cmos", "m2_limit", "sata_limit": return "BOOT"
	return ""


func _fallback_screen(code: String) -> String:
	match code:
		"cooler": return "boot"
		"cmos": return "no_boot"
		"no_display", "ddr_notch", "socket", "ram_slot_limit", "gpu_length": return "no_signal"
	return "no_signal"


func _fallback_msg(code: String) -> String:
	match code:
		"no_display": return "Ekrana görüntü gelmiyor: bu işlemcide dahili grafik yok, ekran kartı gerekli."
		"cooler": return "CPU soğutucu takılı değil veya arızalı! İşlemci hızla ısınıyor."
		"cmos": return "CMOS pili eksik veya bitik — BIOS ayarları sıfırlandı."
		"ddr_notch": return "RAM çentiği anakartla uyumsuz, sistem açılmıyor."
		"socket": return "İşlemci soketi anakartla uyumsuz!"
	return "Sistem uyumsuzluk nedeniyle açılmadı (%s)." % code


## Belirti mesajı (sym.msg, sym.msg_color); boşsa fallback.
func _symptom_msg(sym: Dictionary, fallback: String) -> void:
	var c: Array = sym.get("msg_color", [1.0, 0.6, 0.4])
	var msg := str(sym.get("msg", fallback))
	if msg != "":
		Game.msg(msg, Color(float(c[0]), float(c[1]), float(c[2])))


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
	if _built:
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
	var code := diagnose()
	var hot := code == "overheat" or code == "cooler"
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
