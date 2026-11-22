extends RigidBody3D
## Masadaki aletler: başlangıç aletleri (macun, hava, tornavida, IPA) ve satın alınabilen teşhis aletleri.

const MU := preload("res://scripts/mesh_util.gd")

const NAMES := {
	"paste": "Termal Macun",
	"air": "Basınçlı Hava",
	"screwdriver": "Tornavida",
	"ipa": "IPA Temizleyici",
	"psu_tester": "PSU Test Cihazı",
	"multimeter": "Dijital Multimetre",
	"post_card": "POST Teşhis Kartı",
	"thermal_cam": "Termal Kamera",
	"ram_usb": "RAM Test USB'si",
	"smart_usb": "Disk SMART USB'si",
	"antivirus_usb": "Antivirüs USB'si",
	"install_usb": "Kurulum & BIOS USB'si",
}

var tool_type := ""
var display_name := ""
var slot = null  # parçalarla uyumluluk için (alet yuvaya takılmaz)
var home_transform := Transform3D.IDENTITY
var has_home := false
var _center := Vector3.ZERO
var _euler := Vector3.ZERO
var _cool := 0.0
var _return_tw: Tween = null


func setup(type: String):
	tool_type = type
	display_name = NAMES.get(type, type)
	var size := Vector3.ONE * 0.04
	match type:
		"paste":
			_build_paste()
			size = Vector3(0.13, 0.03, 0.03)
			_euler = Vector3(10, 90, 0)
		"air":
			_build_air()
			size = Vector3(0.062, 0.19, 0.062)
			_euler = Vector3(-35, 25, 0)
		"screwdriver":
			_build_screwdriver()
			size = Vector3(0.22, 0.03, 0.03)
			_euler = Vector3(15, 85, 0)
		"ipa":
			_build_ipa()
			size = Vector3(0.055, 0.15, 0.055)
			_euler = Vector3(-30, 20, 0)
		"psu_tester":
			_build_psu_tester()
			size = Vector3(0.095, 0.03, 0.065)
			_euler = Vector3(30, -25, 0)
		"multimeter":
			_build_multimeter()
			size = Vector3(0.08, 0.035, 0.13)
			_euler = Vector3(38, -25, 0)
		"post_card":
			_build_post_card()
			size = Vector3(0.075, 0.02, 0.06)
			_euler = Vector3(25, -45, 0)
		"thermal_cam":
			_build_thermal_cam()
			size = Vector3(0.075, 0.12, 0.095)
			_euler = Vector3(-15, -35, 0)
		"ram_usb", "smart_usb", "antivirus_usb", "install_usb":
			_build_usb(type)
			size = Vector3(0.025, 0.012, 0.068)
			_euler = Vector3(25, -60, 0)
	MU.merge_static(self)
	MU.add_box_shape(self, size, _center)
	mass = 0.3
	continuous_cd = true
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	collision_layer = 2
	collision_mask = 1
	return self


## Aletin masadaki düzenli başlangıç konumunu kaydeder.
func set_home(xf: Transform3D) -> void:
	home_transform = xf
	has_home = true


func cancel_return() -> void:
	if _return_tw != null and _return_tw.is_valid():
		_return_tw.kill()
	_return_tw = null


## Aleti yere atmak yerine masadaki düzenli yerine yumuşakça geri döndürür.
func return_home(parent: Node, smooth := true) -> void:
	cancel_return()
	var dest := home_transform if has_home else global_transform
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	freeze = true
	collision_layer = 2
	collision_mask = 1
	visible = true
	if get_parent() != parent:
		if get_parent() != null:
			reparent(parent, true)
		else:
			parent.add_child(self)
	if smooth and is_inside_tree() and global_position.distance_to(dest.origin) <= 2.4:
		_return_tw = create_tween()
		_return_tw.tween_property(self, "global_transform", dest, 0.22).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		_return_tw.tween_callback(_sync_physics_body)
	else:
		global_transform = dest
		_sync_physics_body()


func _sync_physics_body() -> void:
	if not is_inside_tree():
		return
	force_update_transform()
	PhysicsServer3D.body_set_state(get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, global_transform)
	if has_method("reset_physics_interpolation"):
		reset_physics_interpolation()


func is_tool() -> bool:
	return true


## Elde tutulurken merkez ve dönüş (player.pick_up kullanır).
func hold_center() -> Vector3:
	return _center


func hold_euler() -> Vector3:
	return _euler


## Elde tutuş kaydırması (kamera altı "hold" düğümüne göre).
func hold_offset() -> Vector3:
	match tool_type:
		"paste", "screwdriver":
			return Vector3(0.0, 0.0, 0.05)
		"air", "ipa", "thermal_cam":
			return Vector3(0.0, -0.02, 0.0)
		"ram_usb", "smart_usb", "antivirus_usb", "install_usb":
			return Vector3(0.0, 0.0, 0.08)
	return Vector3(0.0, -0.01, 0.03)


func get_hint(player) -> String:
	if not visible:
		return ""
	if player.held == null:
		return "Elin dolu (cihaz taşıyorsun)" if Game.is_carrying() else "Al: %s  [E]" % display_name
	return ""


func interact(player) -> void:
	if not visible:
		return
	if player.held == null and not Game.is_carrying():
		player.pick_up(self)


# ---------------------------------------------------------------- modeller

func _build_paste() -> void:
	# yatay şırınga: gövde +X'e bakar, ucu +X
	var body := MU.mat(Color(0.92, 0.93, 0.95), 0.1, 0.35)
	MU.cyl(self, 0.011, 0.085, Vector3(-0.012, 0, 0), body, Vector3(0, 0, 90), 14)
	MU.cyl(self, 0.011, 0.012, Vector3(-0.0585, 0, 0), MU.mat(Color(0.08, 0.08, 0.09), 0.2, 0.5), Vector3(0, 0, 90), 14)
	MU.cyl(self, 0.006, 0.01, Vector3(0.0375, 0, 0), body, Vector3(0, 0, 90), 10, 0.0025)
	MU.cyl(self, 0.0028, 0.016, Vector3(0.0505, 0, 0), MU.mat(Color(0.85, 0.5, 0.15), 0.6, 0.35), Vector3(0, 0, 90), 8, 0.0018)
	MU.cyl(self, 0.0112, 0.03, Vector3(-0.005, 0, 0), MU.mat(Color(0.15, 0.4, 0.85), 0, 0.5), Vector3(0, 0, 90), 14)
	# gümüş macun görünür halka
	MU.cyl(self, 0.0113, 0.006, Vector3(0.022, 0, 0), MU.mat(Color(0.72, 0.74, 0.78), 0.9, 0.3), Vector3(0, 0, 90), 14)
	var l := MU.label(self, "MACUN", Vector3(-0.005, 0, 0.0114), 32, Color.WHITE, Vector3.ZERO, 0.00032)
	l.double_sided = false
	var l2 := MU.label(self, "MACUN", Vector3(-0.005, 0, -0.0114), 32, Color.WHITE, Vector3(0, 180, 0), 0.00032)
	l2.double_sided = false


func _build_air() -> void:
	# dikey sprey kutusu, nozul üstte
	var can := MU.mat(Color(0.1, 0.3, 0.7), 0.7, 0.3)
	var steel := MU.mat(Color(0.8, 0.82, 0.85), 0.9, 0.28)
	MU.lathe(self, PackedVector2Array([Vector2(0, -0.064), Vector2(0.026, -0.064), Vector2(0.028, -0.06), Vector2(0.028, 0.058),
		Vector2(0.026, 0.066), Vector2(0.019, 0.075), Vector2(0.0, 0.079)]), Vector3.ZERO, can, 24)
	MU.lathe(self, PackedVector2Array([Vector2(0, -0.071), Vector2(0.024, -0.071), Vector2(0.0285, -0.066), Vector2(0.0285, -0.061),
		Vector2(0.026, -0.06), Vector2(0, -0.06)]), Vector3.ZERO, steel, 24)
	MU.lathe(self, PackedVector2Array([Vector2(0.0, 0.074), Vector2(0.02, 0.074), Vector2(0.021, 0.079), Vector2(0.019, 0.084),
		Vector2(0.013, 0.088), Vector2(0, 0.088)]), Vector3.ZERO, steel, 20)
	MU.cyl(self, 0.012, 0.012, Vector3(0, 0.096, 0), MU.mat(Color(0.9, 0.2, 0.15), 0, 0.4), Vector3.ZERO, 12)
	MU.cyl(self, 0.0025, 0.03, Vector3(0.012, 0.102, 0), steel, Vector3(0, 0, -90), 6)
	MU.cyl(self, 0.0015, 0.05, Vector3(0.04, 0.102, 0), MU.mat(Color(0.9, 0.9, 0.92), 0.3, 0.4), Vector3(0, 0, -90), 6)
	MU.cyl(self, 0.0287, 0.05, Vector3(0, 0.0, 0), MU.mat(Color(0.95, 0.95, 0.95), 0, 0.5), Vector3.ZERO, 18)
	var l := MU.label(self, "BASINÇLI\nHAVA", Vector3(0, 0.0, 0.0292), 32, Color(0.1, 0.25, 0.6), Vector3.ZERO, 0.00055)
	l.double_sided = false
	var l2 := MU.label(self, "BASINÇLI\nHAVA", Vector3(0, 0.0, -0.0292), 32, Color(0.1, 0.25, 0.6), Vector3(0, 180, 0), 0.00055)
	l2.double_sided = false


func _build_screwdriver() -> void:
	var handle := Node3D.new()
	handle.rotation_degrees.z = 90
	add_child(handle)
	MU.lathe(handle, PackedVector2Array([Vector2(0, 0), Vector2(0.009, 0), Vector2(0.012, 0.006), Vector2(0.013, 0.03),
		Vector2(0.011, 0.07), Vector2(0.0115, 0.082), Vector2(0.008, 0.09), Vector2(0.0055, 0.094), Vector2(0, 0.094)]),
		Vector3(0, -0.094, 0), MU.mat(Color(0.88, 0.18, 0.14), 0, 0.32), 16)
	MU.lathe(handle, PackedVector2Array([Vector2(0.0132, 0.0), Vector2(0.0135, 0.022)]), Vector3(0, -0.07, 0), MU.mat(Color(0.08, 0.08, 0.09), 0, 0.85), 16)
	var steel := MU.mat(Color(0.8, 0.82, 0.86), 0.9, 0.22)
	MU.cyl(self, 0.0028, 0.1, Vector3(-0.05, 0, 0), steel, Vector3(0, 0, 90), 10)
	MU.cyl(self, 0.0028, 0.012, Vector3(-0.106, 0, 0), steel, Vector3(0, 0, 90), 4, 0.0004)


func _build_ipa() -> void:
	var bottle := MU.mat(Color(0.16, 0.62, 0.36), 0.1, 0.35)
	var cap := MU.mat(Color(0.92, 0.93, 0.95), 0.0, 0.4)
	MU.cyl(self, 0.024, 0.10, Vector3(0, -0.01, 0), bottle, Vector3.ZERO, 18)
	MU.cyl(self, 0.012, 0.022, Vector3(0, 0.05, 0), cap, Vector3.ZERO, 14)
	MU.rbox(self, Vector3(0.016, 0.014, 0.036), Vector3(0, 0.065, 0.008), cap, 0.003)
	MU.cyl(self, 0.049 / 2.0, 0.045, Vector3(0, -0.01, 0), MU.mat(Color(0.95, 0.95, 0.94), 0, 0.55), Vector3.ZERO, 18)
	var l := MU.label(self, "IPA\n%99", Vector3(0, -0.01, 0.0252), 34, Color(0.1, 0.45, 0.22), Vector3.ZERO, 0.00045)
	l.double_sided = false


func _build_psu_tester() -> void:
	var body := MU.mat(Color(0.1, 0.11, 0.14), 0.35, 0.45)
	MU.rbox(self, Vector3(0.095, 0.024, 0.065), Vector3.ZERO, body, 0.004)
	MU.box(self, Vector3(0.052, 0.002, 0.036), Vector3(-0.012, 0.0125, 0), MU.mat(Color(0.08, 0.32, 0.48), 0, 0.3, 0.8))
	MU.rbox(self, Vector3(0.018, 0.012, 0.052), Vector3(0.032, 0.004, 0), MU.mat(Color(0.04, 0.04, 0.05)), 0.001)
	var l := MU.label(self, "12.0V  5.0V\n3.3V   OK", Vector3(-0.012, 0.014, 0), 22, Color(0.75, 0.96, 1.0), Vector3(-90, 0, 0), 0.00022)
	l.double_sided = false


func _build_multimeter() -> void:
	var yellow := MU.mat(Color(0.92, 0.68, 0.12), 0.1, 0.45)
	var dark := MU.mat(Color(0.12, 0.13, 0.15), 0.2, 0.55)
	MU.rbox(self, Vector3(0.075, 0.03, 0.125), Vector3.ZERO, yellow, 0.006)
	MU.rbox(self, Vector3(0.064, 0.024, 0.114), Vector3(0, 0.006, 0), dark, 0.004)
	MU.box(self, Vector3(0.048, 0.002, 0.032), Vector3(0, 0.0185, -0.032), MU.mat(Color(0.42, 0.52, 0.42), 0, 0.4))
	MU.cyl(self, 0.018, 0.006, Vector3(0, 0.019, 0.014), MU.mat(Color(0.24, 0.25, 0.28), 0.3, 0.4), Vector3.ZERO, 16)
	var l := MU.label(self, "0.00 V", Vector3(0, 0.020, -0.032), 28, Color(0.08, 0.14, 0.08), Vector3(-90, 0, 0), 0.00025)
	l.double_sided = false


func _build_post_card() -> void:
	MU.box(self, Vector3(0.072, 0.002, 0.056), Vector3.ZERO, MU.tex_mat(MU.pcb_texture(Color(0.08, 0.12, 0.38))))
	MU.box(self, Vector3(0.046, 0.003, 0.005), Vector3(0, -0.001, 0.028), MU.mat(Color(0.95, 0.75, 0.3), 1.0, 0.22))
	MU.rbox(self, Vector3(0.028, 0.006, 0.020), Vector3(-0.012, 0.004, -0.005), MU.mat(Color(0.04, 0.04, 0.05)), 0.001)
	var l := MU.label(self, "FF", Vector3(-0.012, 0.0075, -0.005), 36, Color(1.0, 0.25, 0.2), Vector3(-90, 0, 0), 0.00024)
	l.double_sided = false


func _build_thermal_cam() -> void:
	var body := MU.mat(Color(0.14, 0.15, 0.18), 0.2, 0.5)
	var grip := MU.mat(Color(0.92, 0.45, 0.1), 0.1, 0.6)
	MU.rbox(self, Vector3(0.068, 0.055, 0.085), Vector3(0, 0.02, 0), body, 0.006)
	MU.rbox(self, Vector3(0.034, 0.065, 0.032), Vector3(0, -0.03, 0.012), grip, 0.005, Vector3(14, 0, 0))
	MU.cyl(self, 0.016, 0.018, Vector3(0, 0.02, -0.046), MU.mat(Color(0.06, 0.06, 0.08), 0.8, 0.2), Vector3(90, 0, 0), 16)
	MU.box(self, Vector3(0.05, 0.038, 0.002), Vector3(0, 0.022, 0.043), MU.mat(Color(0.85, 0.28, 0.12), 0, 0.4, 0.8))


func _build_usb(type: String) -> void:
	var col := Color(0.16, 0.45, 0.88)
	var tag := "USB"
	match type:
		"ram_usb":
			col = Color(0.18, 0.52, 0.88)
			tag = "RAM"
		"smart_usb":
			col = Color(0.22, 0.68, 0.42)
			tag = "SMART"
		"antivirus_usb":
			col = Color(0.86, 0.22, 0.22)
			tag = "AV"
		"install_usb":
			col = Color(0.92, 0.62, 0.14)
			tag = "OS/BIOS"
	MU.rbox(self, Vector3(0.020, 0.008, 0.048), Vector3(0, 0, 0.006), MU.mat(col, 0.25, 0.4), 0.002)
	MU.rbox(self, Vector3(0.014, 0.006, 0.016), Vector3(0, 0, -0.024), MU.mat(Color(0.82, 0.84, 0.88), 0.9, 0.25), 0.001)
	var l := MU.label(self, tag, Vector3(0, 0.0046, 0.006), 20, Color.WHITE, Vector3(-90, 0, 0), 0.00018)
	l.double_sided = false


# ---------------------------------------------------------------- kullanım

## Basınçlı hava / IPA püskürtür: elde tutulan kutudan kameraya doğru bulut.
func puff(player, tint := Color(0.85, 0.87, 0.9, 0.35)) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.amount = 36
	p.lifetime = 0.7
	p.explosiveness = 0.85
	p.direction = Vector3(0, 0, -1)
	p.spread = 16.0
	p.initial_velocity_min = 0.7
	p.initial_velocity_max = 1.5
	p.gravity = Vector3(0, 0.1, 0)
	p.scale_amount_min = 0.6
	p.scale_amount_max = 1.5
	var sm := SphereMesh.new()
	sm.radius = 0.012
	sm.height = 0.024
	sm.radial_segments = 6
	sm.rings = 3
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.albedo_color = tint
	sm.material = pm
	p.mesh = sm
	var from: Vector3 = player.cam.global_position + player.cam.global_transform.basis * Vector3(0.1, -0.12, -0.5)
	var parent: Node = get_tree().current_scene
	parent.add_child(p)
	p.global_position = from
	p.look_at(from - player.cam.global_transform.basis.z * 2.0 + Vector3(0, 0, 0.0001), Vector3.UP)
	p.emitting = true
	if tool_type == "ipa":
		Game.sfx.spray()
	else:
		Game.sfx.hiss()
	get_tree().create_timer(1.3).timeout.connect(p.queue_free)
