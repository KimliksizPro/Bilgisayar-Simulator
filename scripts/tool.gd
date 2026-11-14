extends RigidBody3D
## Masadaki alet: termal macun tüpü veya basınçlı hava spreyi. Alınır, bırakılır, kasada kullanılır.

const MU := preload("res://scripts/mesh_util.gd")

const NAMES := {"paste": "Termal Macun", "air": "Basınçlı Hava"}

var tool_type := ""
var display_name := ""
var slot = null  # parçalarla uyumluluk için (alet yuvaya takılmaz)
var _center := Vector3.ZERO
var _euler := Vector3.ZERO
var _cool := 0.0


func setup(type: String):
	tool_type = type
	display_name = NAMES[type]
	var size := Vector3.ONE * 0.03
	match type:
		"paste":
			_build_paste()
			size = Vector3(0.13, 0.03, 0.03)
			_euler = Vector3(10, 90, 0)
		"air":
			_build_air()
			size = Vector3(0.062, 0.19, 0.062)
			_euler = Vector3(-35, 25, 0)
	MU.merge_static(self)
	MU.add_box_shape(self, size, _center)
	mass = 0.3
	continuous_cd = true
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	collision_layer = 2
	collision_mask = 1
	return self


func is_tool() -> bool:
	return true


## Elde tutulurken merkez ve dönüş (player.pick_up kullanır).
func hold_center() -> Vector3:
	return _center


func hold_euler() -> Vector3:
	return _euler


## Elde tutuş kaydırması (kamera altı "hold" düğümüne göre).
func hold_offset() -> Vector3:
	return Vector3(0, 0.0, 0.05) if tool_type == "paste" else Vector3(0.0, -0.02, 0.0)


func get_hint(player) -> String:
	if player.held == null:
		return "Elin dolu (cihaz taşıyorsun)" if Game.is_carrying() else "Al: %s  [E]" % display_name
	return ""


func interact(player) -> void:
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


# ---------------------------------------------------------------- kullanım

## Basınçlı hava püskürtür: elde tutulan kutudan kameraya doğru toz bulutu.
func puff(player) -> void:
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
	pm.albedo_color = Color(0.85, 0.87, 0.9, 0.35)
	sm.material = pm
	p.mesh = sm
	var from: Vector3 = player.cam.global_position + player.cam.global_transform.basis * Vector3(0.1, -0.12, -0.5)
	var parent: Node = get_tree().current_scene
	parent.add_child(p)
	p.global_position = from
	p.look_at(from - player.cam.global_transform.basis.z * 2.0 + Vector3(0, 0, 0.0001), Vector3.UP)
	p.emitting = true
	Game.sfx.hiss()
	get_tree().create_timer(1.3).timeout.connect(p.queue_free)
