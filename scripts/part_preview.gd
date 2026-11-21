extends SubViewport
## Envanter görselleri: aynı gerçek parça modellerini izole dünyada gösterir.
## Kart küçük resimleri bir kez pişirilir; yalnız seçili parçanın önizlemesi döner.

const PM := preload("res://scripts/part_models.gd")

var _rig: Node3D
var _spin := false
var _sku := ""
var _angle := 0.0


func _ready() -> void:
	size = Vector2i(384, 240)
	transparent_bg = true
	own_world_3d = true
	handle_input_locally = false
	render_target_update_mode = SubViewport.UPDATE_DISABLED
	msaa_3d = Viewport.MSAA_2X
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.87, 0.92, 1.0)
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = env
	add_child(environment)
	for item in [[Vector3(-40, -35, 0), 1.6], [Vector3(25, 140, 0), 0.8]]:
		var light := DirectionalLight3D.new()
		light.rotation_degrees = item[0]
		light.light_energy = item[1]
		add_child(light)
	_rig = Node3D.new()
	add_child(_rig)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 1.65
	add_child(cam)
	cam.look_at_from_position(Vector3(2.6, 1.5, 1.8), Vector3.ZERO)
	cam.make_current()
	set_process(false)


func show_sku(sku: String) -> void:
	if sku == _sku:
		return
	_sku = sku
	for child in _rig.get_children():
		child.free()
	_rig.rotation = Vector3.ZERO
	_angle = 0.0
	var model: Node3D = PM.build_sku(sku).node
	_rig.add_child(model)
	var d: PartDef = DB.parts.get_def(sku)
	if d != null and d.category == "gpu":
		model.rotation_degrees.z = 180.0  # fanlar aşağı değil kameraya baksın
	elif d != null and d.category == "ram":
		model.rotation_degrees.z = 90.0
	var bounds := AABB()
	var first := true
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null:
			continue
		var local: Transform3D = _rig.global_transform.affine_inverse() * mesh.global_transform
		var box: AABB = local * mesh.get_aabb()
		bounds = box if first else bounds.merge(box)
		first = false
	var k := 1.30 / maxf(maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z)), 0.001)
	model.scale = Vector3.ONE * k
	model.position = -bounds.get_center() * k


func set_active(active: bool, spin := false) -> void:
	_spin = spin
	render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
	set_process(active and spin)


func _process(delta: float) -> void:
	if _spin:
		_angle += delta * 0.45
		_rig.rotation.y = sin(_angle) * 0.32
