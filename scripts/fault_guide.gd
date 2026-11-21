extends RefCounted
## Arıza rehberi: taşan Label3D satırları yerine sabit ölçülü tek baskı dokusu.

const MU := preload("res://scripts/mesh_util.gd")
const T := preload("res://scripts/ui_theme.gd")
const SIZE := Vector2i(2048, 1328)
const INK := Color("29363a")
const PAPER := Color("eee6d3")
const RED := Color("994334")
const ROWS := [
	["Hiç tepki yok", "PSU · Ön panel · 24-pin güç kablosu"],
	["Fan var, bip yok", "CPU · Eğik pin · CPU 8-pin kablosu"],
	["Sürekli kısa bip", "RAM · Gevşek modül     /     POST 53–55"],
	["1 uzun + 3 kısa bip", "GPU · PCIe güç · VRAM     /     POST 92–98"],
	["Boot device hatası", "SSD / HDD · SATA kablosu · Boot sırası"],
	["Mavi ekran / virüs", "USB ile teşhis · Monitörden [E] servis"],
	["Tek kısa bip", "Donanım testi tamam. Yazılımı da kontrol et."],
]


static func build(parent: Node3D) -> Node3D:
	var board := Node3D.new()
	board.name = "FaultGuide"
	board.position = Vector3(-0.1, 1.85, -2.975)
	parent.add_child(board)
	MU.rbox(board, Vector3(1.52, 1.015, 0.018), Vector3.ZERO, MU.mat(Color("4d514a"), 0.1, 0.85), 0.006)
	var material := MU.new_mat(Color.WHITE, 0, 0.95)
	var plane := QuadMesh.new()
	plane.size = Vector2(1.485, 0.963)
	var print_mesh := MeshInstance3D.new()
	print_mesh.name = "PrintedGuide"
	print_mesh.mesh = plane
	print_mesh.material_override = material
	print_mesh.position.z = 0.0105
	board.add_child(print_mesh)
	MU.bake_2d(board, SIZE, material, _print_layout)
	var pin := MU.mat(Color("767c77"), 0.6, 0.6)
	for x in [-0.733, 0.733]:
		for y in [-0.479, 0.479]:
			MU.cyl(board, 0.004, 0.004, Vector3(x, y, 0.013), pin, Vector3(90, 0, 0), 10)
	return board


static func _rect(root: Control, rect: Rect2, color: Color) -> void:
	var r := ColorRect.new()
	r.position = rect.position
	r.size = rect.size
	r.color = color
	root.add_child(r)


static func _text(root: Control, text: String, rect: Rect2, size: int, color: Color, font: Font) -> Label:
	var l := Label.new()
	l.text = text
	l.position = rect.position
	l.size = rect.size
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color.TRANSPARENT)
	root.add_child(l)
	return l


static func _print_layout(root: Control) -> void:
	var regular := T.font(500)
	var bold := T.font(750)
	_rect(root, Rect2(Vector2.ZERO, Vector2(SIZE)), PAPER)
	_rect(root, Rect2(56, 50, 1936, 211), RED)
	_text(root, "BİP & POST", Rect2(90, 60, 1860, 112), 88, PAPER, T.sign_font())
	_text(root, "ARIZA TESPİT REHBERİ", Rect2(95, 168, 1800, 66), 48, PAPER, bold)
	_text(root, "BELİRTİ / BİP", Rect2(96, 294, 624, 62), 36, RED, bold)
	_text(root, "İLK KONTROL EDİLECEKLER", Rect2(765, 294, 1200, 62), 36, RED, bold)
	for i in ROWS.size():
		var y := 371 + i * 112
		if i % 2 == 0:
			_rect(root, Rect2(64, y, 1920, 108), Color("e2dac6"))
		_rect(root, Rect2(725, y + 14, 2, 80), Color("bfb7a6"))
		_text(root, ROWS[i][0], Rect2(96, y + 4, 596, 100), 44, INK, bold)
		_text(root, ROWS[i][1], Rect2(765, y + 4, 1186, 100), 41, INK, regular)
	_rect(root, Rect2(96, 1180, 1856, 3), RED)
	_text(root, "Önce gücü kes. Kabloları kontrol et. Sonra parçayı değiştir.", Rect2(96, 1200, 1856, 70), 35, INK, bold)
