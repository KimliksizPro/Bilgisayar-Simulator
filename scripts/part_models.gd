extends RefCounted
## Bilgisayar parçalarının prosedürel modelleri ve bilgileri.
## Her model "takılı" pozisyonda kurulur: anakart yüzeyi = yerel X=0, parça +X yönüne çıkar.

const MU := preload("res://scripts/mesh_util.gd")

const INFO := {
	"cpu": {"size": Vector3(0.064, 0.09, 0.09), "center": Vector3(0.032, 0, 0)},
	"ram": {"size": Vector3(0.037, 0.132, 0.008), "center": Vector3(0.018, 0, 0)},
	"gpu": {"size": Vector3(0.11, 0.042, 0.245), "center": Vector3(0.055, -0.016, 0)},
	"psu": {"size": Vector3(0.15, 0.085, 0.15), "center": Vector3.ZERO},
	"ssd": {"size": Vector3(0.07, 0.008, 0.1), "center": Vector3.ZERO},
}

const TYPE_NAMES := {
	"cpu": "İşlemci", "ram": "RAM", "gpu": "Ekran Kartı", "psu": "Güç Kaynağı", "ssd": "SSD",
}


static func display_name(type: String, tier: int) -> String:
	match type:
		"cpu": return "İşlemci (6 Çekirdek)"
		"ram": return "RAM 8 GB" if tier == 1 else "RAM 16 GB RGB"
		"gpu": return "Ekran Kartı (Giriş)" if tier == 1 else "Ekran Kartı (Oyuncu RGB)"
		"psu": return "Güç Kaynağı 550W"
		"ssd": return "SSD 512 GB"
	return type


static func price(type: String, tier: int) -> int:
	match type:
		"cpu": return 120
		"ram": return 40 if tier == 1 else 80
		"gpu": return 100 if tier == 1 else 250
		"psu": return 60
		"ssd": return 50
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
	return out


static func _cpu(out: Dictionary) -> void:
	var n: Node3D = out.node
	MU.box(n, Vector3(0.002, 0.045, 0.045), Vector3(0.001, 0, 0), MU.mat(Color(0.1, 0.35, 0.15)))
	MU.box(n, Vector3(0.003, 0.036, 0.036), Vector3(0.0035, 0, 0), MU.mat(Color(0.8, 0.8, 0.82), 0.9, 0.3))
	MU.box(n, Vector3(0.006, 0.05, 0.05), Vector3(0.008, 0, 0), MU.mat(Color(0.8, 0.45, 0.25), 0.9, 0.35))
	var fin := MU.mat(Color(0.75, 0.77, 0.8), 0.85, 0.35)
	for i in 12:
		MU.box(n, Vector3(0.026, 0.086, 0.0015), Vector3(0.024, 0, -0.04 + i * 0.0073), fin)
	var black := MU.mat(Color(0.08, 0.08, 0.09), 0.1, 0.6)
	out.rotors.append(MU.fan(n, 0.036, Vector3(0.049, 0, 0), Vector3(0, 0, 90), black, MU.mat(Color(0.15, 0.15, 0.17))))


static func _ram(out: Dictionary, tier: int) -> void:
	var n: Node3D = out.node
	MU.box(n, Vector3(0.03, 0.13, 0.0015), Vector3(0.017, 0, 0), MU.tex_mat(MU.pcb_texture(), Vector3.ONE, 0.6))
	MU.box(n, Vector3(0.004, 0.122, 0.0019), Vector3(0.003, 0, 0), MU.mat(Color(0.95, 0.75, 0.3), 1.0, 0.25))
	var spreader := MU.mat(Color(0.12, 0.12, 0.14), 0.6, 0.4) if tier == 1 else MU.mat(Color(0.7, 0.1, 0.12), 0.7, 0.3)
	for side in [-1, 1]:
		MU.box(n, Vector3(0.025, 0.128, 0.0018), Vector3(0.02, 0, side * 0.0018), spreader)
	if tier >= 2:
		var rgb := MU.new_mat(Color(0.3, 0.8, 1.0), 0, 0.3, 2.0)
		MU.box(n, Vector3(0.004, 0.126, 0.004), Vector3(0.034, 0, 0), rgb)
		out.rgb.append(rgb)


static func _gpu(out: Dictionary, tier: int) -> void:
	var n: Node3D = out.node
	var pcb_col := Color(0.04, 0.2, 0.11) if tier == 1 else Color(0.05, 0.05, 0.06)
	MU.box(n, Vector3(0.1, 0.002, 0.24), Vector3(0.052, 0, 0), MU.tex_mat(MU.pcb_texture(pcb_col)))
	MU.box(n, Vector3(0.006, 0.0025, 0.07), Vector3(0.003, -0.001, -0.05), MU.mat(Color(0.95, 0.75, 0.3), 1.0, 0.25))
	var shroud := MU.mat(Color(0.25, 0.26, 0.28), 0.3, 0.5) if tier == 1 else MU.mat(Color(0.07, 0.07, 0.08), 0.5, 0.35)
	MU.box(n, Vector3(0.1, 0.028, 0.235), Vector3(0.053, -0.016, 0), shroud)
	MU.box(n, Vector3(0.1, 0.002, 0.235), Vector3(0.053, 0.0025, 0), MU.mat(Color(0.2, 0.2, 0.22), 0.8, 0.3))
	MU.box(n, Vector3(0.1, 0.04, 0.002), Vector3(0.052, -0.014, -0.121), MU.mat(Color(0.75, 0.76, 0.78), 0.9, 0.3))
	var fan_count := 2 if tier == 1 else 3
	var radius := 0.042 if tier == 1 else 0.034
	var black := MU.mat(Color(0.06, 0.06, 0.07))
	for i in fan_count:
		var z := (i - (fan_count - 1) / 2.0) * (0.235 / fan_count)
		out.rotors.append(MU.fan(n, radius, Vector3(0.053, -0.031, z), Vector3.ZERO, black, MU.mat(Color(0.12, 0.12, 0.14))))
	var edge_col := Color(0.6, 0.6, 0.62) if tier == 1 else Color(1.0, 0.25, 0.6)
	if tier >= 2:
		var rgb := MU.new_mat(edge_col, 0, 0.3, 2.5)
		MU.box(n, Vector3(0.002, 0.006, 0.2), Vector3(0.104, -0.006, 0), rgb)
		out.rgb.append(rgb)
	var lbl := MU.label(n, "TURBO" if tier == 1 else "ULTRA RGB", Vector3(0.1035, -0.02, 0.0), 40, Color(0.9, 0.9, 0.9), Vector3(0, 90, 0), 0.0005)
	lbl.double_sided = false
	MU.box(n, Vector3(0.012, 0.01, 0.02), Vector3(0.095, 0.007, 0.08), black)


static func _psu(out: Dictionary) -> void:
	var n: Node3D = out.node
	MU.box(n, Vector3(0.15, 0.085, 0.15), Vector3.ZERO, MU.mat(Color(0.07, 0.07, 0.08), 0.4, 0.55))
	MU.box(n, Vector3(0.001, 0.05, 0.09), Vector3(0.0755, 0, 0), MU.mat(Color(0.85, 0.85, 0.82)))
	var l := MU.label(n, "550W\n80+ BRONZ", Vector3(0.0765, 0, 0), 36, Color(0.1, 0.1, 0.1), Vector3(0, 90, 0), 0.0007)
	l.double_sided = false
	var grill := MU.mat(Color(0.2, 0.2, 0.22), 0.7, 0.4)
	MU.torus(n, 0.05, 0.055, Vector3(0, 0.0426, 0), grill)
	MU.box(n, Vector3(0.1, 0.002, 0.004), Vector3(0, 0.0428, 0), grill)
	MU.box(n, Vector3(0.004, 0.002, 0.1), Vector3(0, 0.0428, 0), grill)
	var cable := MU.mat(Color(0.05, 0.05, 0.05))
	for i in 3:
		MU.cyl(n, 0.006, 0.05, Vector3(-0.05 + i * 0.015, 0.065, 0.06), cable, Vector3.ZERO, 8)


static func _ssd(out: Dictionary) -> void:
	var n: Node3D = out.node
	MU.box(n, Vector3(0.07, 0.007, 0.1), Vector3.ZERO, MU.mat(Color(0.22, 0.22, 0.25), 0.7, 0.35))
	MU.box(n, Vector3(0.06, 0.0008, 0.075), Vector3(0, 0.0038, 0), MU.mat(Color(0.15, 0.45, 0.9)))
	var l := MU.label(n, "SSD\n512 GB", Vector3(0, 0.0045, 0), 40, Color.WHITE, Vector3(-90, 0, 0), 0.0005)
	l.double_sided = false
