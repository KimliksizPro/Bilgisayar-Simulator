extends Node3D
## Masadaki monitör. Ekran içeriği bir SubViewport'tan (2D arayüz) çizilir.

const MU := preload("res://scripts/mesh_util.gd")
const PM := preload("res://scripts/part_models.gd")

var vp: SubViewport
var bg: ColorRect
var text: Label
var center_box: PanelContainer
var center_label: Label
var desktop: Control
var clock: Label
var _token := 0


func _ready() -> void:
	var dark := MU.mat(Color(0.06, 0.06, 0.07), 0.3, 0.5)
	MU.box(self, Vector3(0.24, 0.012, 0.17), Vector3(0, 0.006, 0), dark)
	MU.box(self, Vector3(0.045, 0.28, 0.025), Vector3(0, 0.15, -0.03), dark)
	MU.box(self, Vector3(0.62, 0.37, 0.025), Vector3(0, 0.43, 0), dark)
	MU.box(self, Vector3(0.62, 0.018, 0.026), Vector3(0, 0.255, 0.0005), MU.mat(Color(0.12, 0.12, 0.13), 0.5, 0.4))
	_build_screen()
	var q := QuadMesh.new()
	q.size = Vector2(0.592, 0.333)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = vp.get_texture()
	var screen := MeshInstance3D.new()
	screen.mesh = q
	screen.material_override = m
	screen.position = Vector3(0, 0.435, 0.0128)
	add_child(screen)
	show_off()


func _build_screen() -> void:
	vp = SubViewport.new()
	vp.size = Vector2i(640, 360)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var root := Control.new()
	root.size = Vector2(640, 360)
	vp.add_child(root)
	bg = ColorRect.new()
	bg.size = root.size
	root.add_child(bg)
	# masaüstü
	desktop = Control.new()
	desktop.size = root.size
	root.add_child(desktop)
	var grad := Gradient.new()
	grad.set_color(0, Color(0.1, 0.35, 0.75))
	grad.set_color(1, Color(0.45, 0.15, 0.6))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(1, 1)
	var wall := TextureRect.new()
	wall.texture = gt
	wall.size = root.size
	wall.stretch_mode = TextureRect.STRETCH_SCALE
	wall.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	desktop.add_child(wall)
	var icons := [["Bilgisayarım", Color(0.95, 0.8, 0.3)], ["Oyunlar", Color(0.4, 0.9, 0.4)], ["Çöp Kutusu", Color(0.8, 0.8, 0.85)]]
	for i in icons.size():
		var ic := ColorRect.new()
		ic.color = icons[i][1]
		ic.position = Vector2(28, 24 + i * 78)
		ic.size = Vector2(42, 36)
		desktop.add_child(ic)
		var il := Label.new()
		il.text = icons[i][0]
		il.position = Vector2(8, 62 + i * 78)
		il.add_theme_font_size_override("font_size", 13)
		desktop.add_child(il)
	var bar := ColorRect.new()
	bar.color = Color(0.08, 0.08, 0.12, 0.92)
	bar.position = Vector2(0, 328)
	bar.size = Vector2(640, 32)
	desktop.add_child(bar)
	var start := Label.new()
	start.text = "  ◆ Başlat"
	start.position = Vector2(0, 333)
	start.add_theme_font_size_override("font_size", 16)
	desktop.add_child(start)
	clock = Label.new()
	clock.position = Vector2(570, 333)
	clock.add_theme_font_size_override("font_size", 16)
	desktop.add_child(clock)
	var welcome := Label.new()
	welcome.text = "BilgiOS 11\nHoş geldiniz!"
	welcome.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	welcome.position = Vector2(220, 120)
	welcome.size = Vector2(200, 80)
	welcome.add_theme_font_size_override("font_size", 26)
	desktop.add_child(welcome)
	# BIOS / hata metni
	text = Label.new()
	text.position = Vector2(20, 16)
	text.size = Vector2(600, 330)
	text.add_theme_font_size_override("font_size", 18)
	text.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	root.add_child(text)
	center_box = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.1, 0.1, 0.15)
	sb.border_color = Color(0.4, 0.4, 0.5)
	sb.set_border_width_all(2)
	sb.set_content_margin_all(14)
	center_box.add_theme_stylebox_override("panel", sb)
	center_box.position = Vector2(220, 150)
	center_label = Label.new()
	center_label.text = "Sinyal Yok"
	center_label.add_theme_font_size_override("font_size", 26)
	center_box.add_child(center_label)
	root.add_child(center_box)


func _reset(color: Color) -> void:
	_token += 1
	bg.color = color
	desktop.visible = false
	text.text = ""
	center_box.visible = false


func show_off() -> void:
	_reset(Color(0.01, 0.01, 0.012))


func show_no_signal() -> void:
	_reset(Color(0, 0, 0))
	center_box.visible = true


func show_no_boot() -> void:
	_reset(Color(0, 0, 0))
	text.text = "BilgiBIOS v2.6\n\nReboot and Select proper Boot device\nor Insert Boot Media in selected Boot device\nand press a key_"


func boot(pc) -> void:
	_reset(Color(0, 0, 0))
	var my := _token
	var gpu = pc.part_in("gpu")
	var lines := [
		"BilgiBIOS v2.6  (C) Mahalle Bilgisayar",
		"",
		"CPU: 6 Çekirdek @ 3.8 GHz ........ OK",
		"RAM: %d GB ......................... OK" % pc.total_ram(),
		"GPU: %s ...... OK" % gpu.display_name,
		"Disk: SSD 512 GB .................. OK",
		"",
		"BilgiOS başlatılıyor...",
	]
	for l in lines:
		await get_tree().create_timer(0.18).timeout
		if my != _token:
			return
		text.text += l + "\n"
	await get_tree().create_timer(0.9).timeout
	if my != _token:
		return
	text.text = ""
	desktop.visible = true


func _process(_delta: float) -> void:
	if desktop.visible:
		var t := Time.get_time_dict_from_system()
		clock.text = "%02d:%02d" % [t.hour, t.minute]
