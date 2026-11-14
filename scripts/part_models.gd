extends RefCounted
## Bilgisayar parçalarının prosedürel modelleri ve bilgileri.
## Her model "takılı" pozisyonda kurulur: anakart yüzeyi = yerel X=0, parça +X yönüne çıkar.

const MU := preload("res://scripts/mesh_util.gd")
const DP := preload("res://scripts/device_parts.gd")  # laptop / telefon parçaları

const INFO := {
	"cpu": {"size": Vector3(0.064, 0.09, 0.09), "center": Vector3(0.032, 0, 0)},
	"ram": {"size": Vector3(0.037, 0.132, 0.008), "center": Vector3(0.018, 0, 0)},
	"gpu": {"size": Vector3(0.11, 0.042, 0.245), "center": Vector3(0.055, -0.016, 0)},
	"psu": {"size": Vector3(0.15, 0.085, 0.15), "center": Vector3.ZERO},
	"ssd": {"size": Vector3(0.07, 0.008, 0.1), "center": Vector3.ZERO},
	# --- laptop / telefon parçaları (modeller: device_parts.gd) ---
	"lap_ram": {"size": Vector3(0.068, 0.004, 0.03), "center": Vector3.ZERO},
	"lap_ssd": {"size": Vector3(0.08, 0.005, 0.022), "center": Vector3.ZERO},
	"lap_bat": {"size": Vector3(0.22, 0.008, 0.07), "center": Vector3.ZERO},
	"lap_scr": {"size": Vector3(0.31, 0.005, 0.19), "center": Vector3.ZERO},
	"tel_bat": {"size": Vector3(0.05, 0.004, 0.08), "center": Vector3.ZERO},
	"tel_scr": {"size": Vector3(0.072, 0.003, 0.152), "center": Vector3.ZERO},
	"tel_port": {"size": Vector3(0.05, 0.004, 0.014), "center": Vector3.ZERO},
}

const TYPE_NAMES := {
	"cpu": "İşlemci", "ram": "RAM", "gpu": "Ekran Kartı", "psu": "Güç Kaynağı", "ssd": "SSD",
	# --- laptop / telefon parçaları ---
	"lap_ram": "Laptop RAM", "lap_ssd": "M.2 SSD", "lap_bat": "Laptop Bataryası", "lap_scr": "Laptop Ekranı",
	"tel_bat": "Telefon Bataryası", "tel_scr": "Telefon Ekranı", "tel_port": "Şarj Soketi",
}


static func display_name(type: String, tier: int) -> String:
	match type:
		"cpu": return "İşlemci (6 Çekirdek)"
		"ram": return "RAM 8 GB" if tier == 1 else "RAM 16 GB RGB"
		"gpu": return "Ekran Kartı (Giriş)" if tier == 1 else "Ekran Kartı (Oyuncu RGB)"
		"psu": return "Güç Kaynağı 550W"
		"ssd": return "SSD 512 GB"
	if DP.has(type):  # laptop / telefon parçaları
		return DP.display_name(type, tier)
	return type


static func price(type: String, tier: int) -> int:
	match type:
		"cpu": return 120
		"ram": return 40 if tier == 1 else 80
		"gpu": return 100 if tier == 1 else 250
		"psu": return 60
		"ssd": return 50
	if DP.has(type):  # laptop / telefon parçaları
		return DP.price(type, tier)
	return 0


static func ram_gb(tier: int) -> int:
	return 8 if tier == 1 else 16


## Dönüş: {"node": Node3D, "rotors": [Node3D], "rgb": [StandardMaterial3D]}
static func build(type: String, tier: int) -> Dictionary:
	var out := {"node": Node3D.new(), "rotors": [], "rgb": []}
	match type:
		"cpu": _cpu(out)
		"ram": _ram(out, tier)
		"gpu": _gpu(out, tier)
		"psu": _psu(out)
		"ssd": _ssd(out)
	if DP.has(type):  # laptop / telefon parçaları
		DP.build(out, type, tier)
	MU.merge_static(out.node)
	return out


# ---------------------------------------------------------------- ortak malzemeler

static func _gold() -> Material: return MU.mat(Color(0.95, 0.75, 0.3), 1.0, 0.22)
static func _alu() -> Material: return MU.mat(Color(0.78, 0.8, 0.83), 0.9, 0.32)
static func _copper() -> Material: return MU.mat(Color(0.85, 0.48, 0.28), 1.0, 0.28)
static func _black() -> Material: return MU.mat(Color(0.05, 0.05, 0.06), 0.2, 0.5)
static func _chip() -> Material: return MU.mat(Color(0.03, 0.03, 0.035), 0.1, 0.35)


static func _text(n: Node3D, txt: String, pos: Vector3, size: int, color: Color, rot: Vector3, px := 0.0004) -> void:
	var l := MU.label(n, txt, pos, size, color, rot, px)
	l.double_sided = false


# ---------------------------------------------------------------- İŞLEMCİ + SOĞUTUCU

static func _cpu(out: Dictionary) -> void:
	var n: Node3D = out.node
	MU.box(n, Vector3(0.002, 0.045, 0.045), Vector3(0.001, 0, 0), MU.tex_mat(MU.pcb_texture(Color(0.08, 0.3, 0.14))))
	MU.rbox(n, Vector3(0.003, 0.036, 0.036), Vector3(0.0035, 0, 0), _alu(), 0.002)
	# bakır taban + ısı boruları
	MU.rbox(n, Vector3(0.006, 0.05, 0.05), Vector3(0.008, 0, 0), _copper(), 0.002)
	for y in [-0.028, -0.01, 0.01, 0.028]:
		MU.cyl(n, 0.0028, 0.04, Vector3(0.026, y, 0.0), _copper(), Vector3(0, 0, 90), 10)
		MU.sphere(n, 0.0028, Vector3(0.046, y, 0.0), _copper())
	# alüminyum kanatçıklar
	var fin := _alu()
	for i in 13:
		MU.box(n, Vector3(0.026, 0.084, 0.0012), Vector3(0.025, 0, -0.042 + i * 0.007), fin)
	MU.rbox(n, Vector3(0.003, 0.084, 0.088), Vector3(0.0395, 0, 0), _black(), 0.002)
	# fan çerçevesi (kare) + fan
	var frame := MU.mat(Color(0.1, 0.1, 0.11), 0.1, 0.6)
	var fx := 0.051
	for y in [-0.041, 0.041]:
		MU.rbox(n, Vector3(0.016, 0.008, 0.09), Vector3(fx, y, 0), frame, 0.003)
	for z in [-0.041, 0.041]:
		MU.rbox(n, Vector3(0.016, 0.09, 0.008), Vector3(fx, 0, z), frame, 0.003)
	for y in [-0.04, 0.04]:
		for z in [-0.04, 0.04]:
			MU.cyl(n, 0.0025, 0.002, Vector3(fx + 0.0085, y, z), _alu(), Vector3(0, 0, 90), 8)
	out.rotors.append(MU.fan(n, 0.037, Vector3(fx, 0, 0), Vector3(0, 0, 90), frame,
		MU.mat(Color(0.14, 0.14, 0.16), 0, 0.45), null, MU.mat(Color(0.85, 0.2, 0.15), 0, 0.4)))


# ---------------------------------------------------------------- RAM

static func _ram(out: Dictionary, tier: int) -> void:
	var n: Node3D = out.node
	MU.box(n, Vector3(0.03, 0.133, 0.0014), Vector3(0.017, 0, 0), MU.tex_mat(MU.pcb_texture(Color(0.05, 0.25, 0.12)), Vector3(1, 1, 1), 0.5))
	# altın kontaklar (çentikli)
	MU.box(n, Vector3(0.004, 0.07, 0.0018), Vector3(0.003, -0.026, 0), _gold())
	MU.box(n, Vector3(0.004, 0.05, 0.0018), Vector3(0.003, 0.038, 0), _gold())
	if tier == 1:
		# çıplak modül: görünür bellek çipleri + etiket
		for side in [-1, 1]:
			for i in 8:
				MU.box(n, Vector3(0.011, 0.011, 0.0012), Vector3(0.019, -0.054 + i * 0.0155, side * 0.0013), _chip())
		MU.box(n, Vector3(0.007, 0.06, 0.0003), Vector3(0.029, 0, 0.0021), MU.mat(Color(0.92, 0.92, 0.9), 0, 0.6))
		_text(n, "8GB DDR4", Vector3(0.029, 0, 0.0024), 28, Color(0.1, 0.1, 0.1), Vector3(0, 0, 90), 0.00022)
	else:
		# soğutuculu RGB modül
		var spreader := MU.mat(Color(0.62, 0.08, 0.1), 0.75, 0.28)
		for side in [-1, 1]:
			MU.rbox(n, Vector3(0.026, 0.13, 0.0018), Vector3(0.019, 0, side * 0.0018), spreader, 0.0008)
			MU.box(n, Vector3(0.01, 0.12, 0.0004), Vector3(0.016, 0, side * 0.0029), MU.mat(Color(0.12, 0.12, 0.13), 0.6, 0.35))
		_text(n, "ULTRA 16GB", Vector3(0.016, 0, 0.0032), 30, Color(0.95, 0.9, 0.9), Vector3(0, 0, 90), 0.00025)
		var rgb := MU.new_mat(Color(0.85, 0.9, 1.0), 0, 0.3, 2.0)
		MU.rbox(n, Vector3(0.005, 0.128, 0.0055), Vector3(0.0345, 0, 0), rgb, 0.0015)
		out.rgb.append(rgb)


# ---------------------------------------------------------------- EKRAN KARTI

static func _gpu(out: Dictionary, tier: int) -> void:
	var n: Node3D = out.node
	var pcb_col := Color(0.04, 0.2, 0.11) if tier == 1 else Color(0.05, 0.05, 0.06)
	MU.box(n, Vector3(0.1, 0.002, 0.24), Vector3(0.052, 0, 0), MU.tex_mat(MU.pcb_texture(pcb_col)))
	MU.box(n, Vector3(0.006, 0.0025, 0.07), Vector3(0.003, -0.001, -0.06), _gold())
	MU.box(n, Vector3(0.006, 0.0025, 0.012), Vector3(0.003, -0.001, -0.016), _gold())
	# arka plaka + havalandırma yarıkları
	var bp := MU.mat(Color(0.18, 0.18, 0.2), 0.8, 0.3) if tier == 1 else MU.mat(Color(0.08, 0.08, 0.09), 0.8, 0.3)
	MU.rbox(n, Vector3(0.1, 0.002, 0.236), Vector3(0.053, 0.0025, 0), bp, 0.001)
	for i in 6:
		MU.box(n, Vector3(0.05, 0.0004, 0.003), Vector3(0.06, 0.0037, 0.04 + i * 0.01), _black())
	_text(n, "TURBO" if tier == 1 else "ULTRA", Vector3(0.05, 0.0038, -0.05), 60, Color(0.85, 0.85, 0.88), Vector3(-90, 0, 0), 0.0004)
	# soğutucu kanatçıkları (yandan görünür)
	var fin := _alu()
	for i in 46:
		MU.box(n, Vector3(0.092, 0.016, 0.0009), Vector3(0.053, -0.011, -0.112 + i * 0.005), fin)
	for x in [0.02, 0.05, 0.08]:
		MU.cyl(n, 0.003, 0.22, Vector3(x, -0.01, 0), _copper(), Vector3(90, 0, 0), 8)
	# koruyucu kaplama (shroud)
	var shroud := MU.mat(Color(0.3, 0.31, 0.33), 0.4, 0.45) if tier == 1 else MU.mat(Color(0.06, 0.06, 0.07), 0.5, 0.3)
	var accent := MU.mat(Color(0.7, 0.72, 0.75), 0.8, 0.3) if tier == 1 else MU.mat(Color(0.75, 0.1, 0.25), 0.6, 0.3)
	MU.rbox(n, Vector3(0.104, 0.006, 0.24), Vector3(0.053, -0.024, 0), shroud, 0.003)
	MU.rbox(n, Vector3(0.006, 0.026, 0.24), Vector3(0.104, -0.013, 0), shroud, 0.002)
	MU.rbox(n, Vector3(0.004, 0.004, 0.2), Vector3(0.107, -0.02, 0), accent, 0.0015)
	for z in [-0.115, 0.115]:
		MU.rbox(n, Vector3(0.104, 0.026, 0.006), Vector3(0.053, -0.013, z), shroud, 0.002)
	# fanlar
	var fan_count := 2 if tier == 1 else 3
	var radius := 0.042 if tier == 1 else 0.034
	var hub := MU.mat(Color(0.8, 0.8, 0.82), 0.6, 0.3) if tier == 1 else MU.mat(Color(0.75, 0.1, 0.25), 0.4, 0.3)
	for i in fan_count:
		var z := (i - (fan_count - 1) / 2.0) * (0.232 / fan_count)
		var ring: Material = null
		if tier >= 2:
			ring = MU.new_mat(Color(1.0, 0.25, 0.6), 0, 0.3, 2.0)
			out.rgb.append(ring)
		MU.torus(n, radius * 1.02, radius * 1.1, Vector3(0.053, -0.027, z), shroud)
		out.rotors.append(MU.fan(n, radius, Vector3(0.053, -0.031, z), Vector3.ZERO, _black(), MU.mat(Color(0.12, 0.12, 0.14), 0, 0.45), ring, hub))
	if tier >= 2:
		var rgb := MU.new_mat(Color(1.0, 0.25, 0.6), 0, 0.3, 2.5)
		MU.rbox(n, Vector3(0.002, 0.005, 0.16), Vector3(0.1075, -0.008, 0.02), rgb, 0.001)
		out.rgb.append(rgb)
	_text(n, "TURBO 4GB" if tier == 1 else "ULTRA RGB 12GB", Vector3(0.1072, -0.014, -0.06), 40, Color(0.92, 0.92, 0.92), Vector3(0, 90, 0), 0.00045)
	# braket + görüntü çıkışları
	var bracket := MU.mat(Color(0.75, 0.76, 0.78), 0.9, 0.3)
	MU.box(n, Vector3(0.1, 0.04, 0.0015), Vector3(0.052, -0.012, -0.121), bracket)
	for i in 4:
		MU.rbox(n, Vector3(0.012, 0.006, 0.002), Vector3(0.02 + i * 0.018, -0.006, -0.122), _black(), 0.0015)
	for i in 5:
		MU.box(n, Vector3(0.008, 0.012, 0.0018), Vector3(0.025 + i * 0.016, -0.022, -0.122), _black())
	# 8-pin güç girişi
	MU.rbox(n, Vector3(0.008, 0.009, 0.02), Vector3(0.098, 0.007, 0.075), _black(), 0.0015)
	if tier >= 2:
		MU.rbox(n, Vector3(0.008, 0.009, 0.02), Vector3(0.098, 0.007, 0.05), _black(), 0.0015)


# ---------------------------------------------------------------- GÜÇ KAYNAĞI

static func _psu(out: Dictionary) -> void:
	var n: Node3D = out.node
	var body := MU.mat(Color(0.06, 0.06, 0.07), 0.45, 0.5)
	MU.rbox(n, Vector3(0.15, 0.085, 0.15), Vector3.ZERO, body, 0.004)
	# fan ızgarası (üst)
	var grill := MU.mat(Color(0.16, 0.16, 0.18), 0.8, 0.35)
	MU.cyl(n, 0.058, 0.001, Vector3(0, 0.0426, 0), MU.mat(Color(0.02, 0.02, 0.02)), Vector3.ZERO, 24)
	for r in [0.058, 0.044, 0.03, 0.016]:
		MU.torus(n, r - 0.0015, r, Vector3(0, 0.0435, 0), grill)
	MU.box(n, Vector3(0.116, 0.0016, 0.003), Vector3(0, 0.0438, 0), grill)
	MU.box(n, Vector3(0.003, 0.0016, 0.116), Vector3(0, 0.0438, 0), grill)
	MU.cyl(n, 0.012, 0.002, Vector3(0, 0.044, 0), MU.mat(Color(0.8, 0.65, 0.2), 0.6, 0.3), Vector3.ZERO, 16)
	# yan etiket
	MU.box(n, Vector3(0.001, 0.055, 0.1), Vector3(0.0755, 0, 0), MU.mat(Color(0.88, 0.88, 0.85), 0, 0.6))
	MU.box(n, Vector3(0.0012, 0.012, 0.1), Vector3(0.0756, 0.021, 0), MU.mat(Color(0.8, 0.6, 0.15), 0, 0.5))
	_text(n, "550W", Vector3(0.0763, 0.021, 0), 64, Color(0.08, 0.08, 0.08), Vector3(0, 90, 0), 0.00035)
	_text(n, "80+ BRONZ\nAC 220-240V ~ 5A\n+12V ═ 45A", Vector3(0.0763, -0.008, 0), 30, Color(0.15, 0.15, 0.15), Vector3(0, 90, 0), 0.0003)
	# arka yüz: güç soketi + anahtar + petek ızgara
	MU.rbox(n, Vector3(0.026, 0.02, 0.003), Vector3(0.04, -0.015, -0.0755), _black(), 0.002)
	for x in [0.033, 0.04, 0.047]:
		MU.box(n, Vector3(0.003, 0.006, 0.001), Vector3(x, -0.015, -0.0772), MU.mat(Color(0.15, 0.15, 0.15)))
	MU.rbox(n, Vector3(0.012, 0.016, 0.004), Vector3(0.012, -0.015, -0.076), MU.mat(Color(0.15, 0.15, 0.16), 0, 0.4), 0.002, Vector3(15, 0, 0))
	for i in 5:
		for j in 3:
			MU.cyl(n, 0.004, 0.001, Vector3(-0.055 + i * 0.011 + (j % 2) * 0.0055, 0.01 + j * 0.009, -0.0757), MU.mat(Color(0.02, 0.02, 0.02)), Vector3(90, 0, 0), 6)
	# ön yüz: modüler soketler + kablolar
	for i in 4:
		MU.rbox(n, Vector3(0.022, 0.012, 0.003), Vector3(-0.045 + i * 0.03, 0.02, 0.0755), MU.mat(Color(0.1, 0.1, 0.11)), 0.0015)
	var cable := MU.mat(Color(0.03, 0.03, 0.035), 0, 0.75)
	for i in 3:
		var x := -0.045 + i * 0.03
		MU.cyl(n, 0.005, 0.03, Vector3(x, 0.02, 0.09), cable, Vector3(90, 0, 0), 8)
		MU.sphere(n, 0.005, Vector3(x, 0.02, 0.105), cable)
		MU.cyl(n, 0.005, 0.05, Vector3(x, 0.045, 0.105), cable, Vector3.ZERO, 8)


# ---------------------------------------------------------------- SSD

static func _ssd(out: Dictionary) -> void:
	var n: Node3D = out.node
	MU.rbox(n, Vector3(0.07, 0.007, 0.1), Vector3.ZERO, MU.mat(Color(0.26, 0.27, 0.3), 0.8, 0.3), 0.002)
	MU.rbox(n, Vector3(0.062, 0.0008, 0.078), Vector3(0, 0.0036, -0.006), MU.mat(Color(0.08, 0.3, 0.75), 0, 0.45), 0.0004)
	MU.box(n, Vector3(0.062, 0.0009, 0.014), Vector3(0, 0.0037, 0.026), MU.mat(Color(0.95, 0.95, 0.95), 0, 0.5))
	_text(n, "BİLGİ SSD", Vector3(0, 0.0042, -0.012), 34, Color.WHITE, Vector3(-90, 0, 0), 0.00035)
	_text(n, "512 GB", Vector3(0, 0.0043, 0.026), 40, Color(0.1, 0.1, 0.12), Vector3(-90, 0, 0), 0.00028)
	# SATA konnektör
	MU.box(n, Vector3(0.04, 0.004, 0.003), Vector3(-0.008, 0, 0.0505), _black())
	MU.box(n, Vector3(0.036, 0.0012, 0.0015), Vector3(-0.008, 0, 0.0515), _gold())
	# vida delikleri
	for x in [-0.0352, 0.0352]:
		for z in [-0.03, 0.03]:
			MU.cyl(n, 0.0015, 0.004, Vector3(x, 0, z), MU.mat(Color(0.02, 0.02, 0.02)), Vector3(0, 0, 90), 8)
