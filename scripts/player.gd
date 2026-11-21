extends CharacterBody3D
## Birinci şahıs oyuncu: yürüme, bakma, etkileşim, parça taşıma.

const REACH := 2.2
const VM_LAYER := 1 << 19  # 20. görsel katman: elde tutulan eşya (viewmodel)
const TOUCH_CONTROLS := preload("res://scripts/touch_controls.gd")

const SAFE_POS := Vector3(0.9, 0.1, -0.9)  # dükkân içi güvenli nokta (main.gd başlangıç konumu)

var cam: Camera3D
var hold: Node3D
var held = null
var target = null
var hint := ""
var sensitivity := 0.0025
var _pitch := 0.0
var vm_cam: Camera3D
var vm_vp: SubViewport
var vm_rect: TextureRect
var touch_controls
var _held_layers := {}  # elde tutulan eşyanın orijinal görsel katmanları
var _held_xform := Transform3D.IDENTITY


func _ready() -> void:
	collision_layer = 4
	collision_mask = 1
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.7
	cs.shape = cap
	cs.position.y = 0.85
	add_child(cs)
	cam = Camera3D.new()
	cam.position.y = 1.6
	cam.fov = 72.0
	cam.near = 0.02
	add_child(cam)
	hold = Node3D.new()
	hold.position = Vector3(0.24, -0.2, -0.45)
	cam.add_child(hold)
	Game.player = self
	_build_viewmodel()
	touch_controls = TOUCH_CONTROLS.new()
	touch_controls.interact_pressed.connect(_on_touch_interact)
	touch_controls.interact_alt_pressed.connect(_on_touch_interact_alt)
	add_child(touch_controls)
	apply_settings()
	Settings.changed.connect(func(k): if k == "fov": apply_settings())


## Elde tutulan eşya ayrı bir alt görünümde (SubViewport) dünyanın üstüne çizilir:
## duvara/kasaya girip gizlenmez, kamera dönünce geride kalmaz.
func _build_viewmodel() -> void:
	cam.cull_mask = 0xFFFFF & ~VM_LAYER
	vm_vp = SubViewport.new()
	vm_vp.transparent_bg = true
	vm_vp.own_world_3d = false
	vm_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	vm_vp.handle_input_locally = false
	vm_vp.audio_listener_enable_3d = false
	vm_cam = Camera3D.new()
	vm_cam.near = 0.01
	vm_cam.far = 5.0
	vm_cam.cull_mask = VM_LAYER
	vm_cam.keep_aspect = cam.keep_aspect
	vm_cam.environment = _viewmodel_env()
	vm_vp.add_child(vm_cam)
	add_child(vm_vp)
	vm_cam.make_current()
	var cl := CanvasLayer.new()
	cl.layer = -1  # dünyanın üstünde, HUD'ın altında
	vm_rect = TextureRect.new()
	vm_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	vm_rect.stretch_mode = TextureRect.STRETCH_SCALE
	vm_rect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vm_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vm_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vm_rect.texture = vm_vp.get_texture()
	vm_rect.visible = false
	cl.add_child(vm_rect)
	vm_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(cl)
	_sync_viewmodel_vp()


func held_xform_for(p) -> Transform3D:
	var e: Vector3 = p.hold_euler()
	var b := Basis.from_euler(Vector3(deg_to_rad(e.x), deg_to_rad(e.y), deg_to_rad(e.z)))
	var off: Vector3 = p.hold_offset() if p.has_method("hold_offset") else Vector3.ZERO
	return Transform3D(b, off - (b * p.hold_center()))


func _sync_viewmodel_cam() -> void:
	if vm_cam == null or cam == null:
		return
	vm_cam.global_transform = cam.global_transform
	vm_cam.fov = cam.fov
	vm_cam.keep_aspect = cam.keep_aspect
	if is_instance_valid(held) and held.get_parent() == hold:
		held.transform = _held_xform


## Ana ortamın aynısı (gökyüzü aydınlatması, ton eşleme); yalnızca arka plan saydam, ekran-uzayı efektleri kapalı.
func _viewmodel_env() -> Environment:
	var src = get_parent().get("env") if get_parent() else null
	var e: Environment = src.duplicate() if src is Environment else Environment.new()
	e.background_mode = Environment.BG_CLEAR_COLOR
	e.sdfgi_enabled = false
	e.ssil_enabled = false
	e.ssr_enabled = false
	e.ssao_enabled = false
	e.volumetric_fog_enabled = false
	e.glow_enabled = false
	return e


func _sync_viewmodel_vp() -> void:
	var root := get_tree().root
	var sz := Vector2i(maxi(root.size.x, 2), maxi(root.size.y, 2))
	if vm_vp.size != sz:
		vm_vp.size = sz
	vm_vp.scaling_3d_scale = root.scaling_3d_scale
	vm_vp.scaling_3d_mode = root.scaling_3d_mode
	vm_vp.msaa_3d = root.msaa_3d


func _process(_delta: float) -> void:
	var on := held != null
	vm_rect.visible = on
	var mode := SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	if vm_vp.render_target_update_mode != mode:
		vm_vp.render_target_update_mode = mode
	if on:
		_sync_viewmodel_vp()
		_sync_viewmodel_cam()
	if _is_touch_active():
		if _is_mobile_os() and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if Game.started and not Game.paused and not Game.ui_modal:
			Game.running = true
			if not Game.bench_active:
				var look_delta: Vector2 = touch_controls.consume_look_delta()
				if look_delta != Vector2.ZERO:
					_apply_look(look_delta, 1.8)


func _is_mobile_os() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios")


func _is_touch_active() -> bool:
	return touch_controls != null and touch_controls.is_touch_active()


func _apply_look(delta_px: Vector2, mult := 1.0) -> void:
	var sens: float = sensitivity * Settings.sensitivity * mult
	rotate_y(-delta_px.x * sens)
	var dy: float = delta_px.y * (-1.0 if Settings.invert_y else 1.0)
	_pitch = clamp(_pitch - dy * sens, deg_to_rad(-85), deg_to_rad(85))
	cam.rotation.x = _pitch
	if held != null:
		_sync_viewmodel_cam()


func _on_touch_interact() -> void:
	if Game.bench_active or Game.ui_modal or not Game.started or Game.paused:
		return
	if target:
		target.interact(self)


func _on_touch_interact_alt() -> void:
	if Game.bench_active or Game.ui_modal or not Game.started or Game.paused:
		return
	if target and target.has_method("interact_alt"):
		target.interact_alt(self)
	elif held != null:
		drop()
	elif Game.is_carrying():
		var carry = Game.get("carry")
		if carry != null and carry.get("jobs") != null:
			carry.jobs.return_carried()


## Ayarlardan görüş alanını uygular (hassasiyet/ters Y her harekette okunur).
func apply_settings() -> void:
	cam.fov = Settings.fov
	if vm_cam:
		vm_cam.fov = cam.fov


func _unhandled_input(event: InputEvent) -> void:
	if Game.bench_active:  # tezgâh modunda fareyi bench_mode yönetir
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		if not _is_touch_active() and event is InputEventMouseButton and event.pressed and Game.started and not Game.ui_modal:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		_apply_look(event.relative)
	elif event.is_action_pressed("interact"):
		if target:
			target.interact(self)
	elif event.is_action_pressed("interact_alt"):
		if target and target.has_method("interact_alt"):
			target.interact_alt(self)
	elif event.is_action_pressed("drop"):
		drop()


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= 9.8 * delta
	var touch_on := _is_touch_active() and Game.started and not Game.paused and not Game.ui_modal and not Game.bench_active
	var active := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED or touch_on
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back") if active else Vector2.ZERO
	if touch_on:
		input += touch_controls.move_vector
		if input.length() > 1.0:
			input = input.normalized()
	var dir := (transform.basis * Vector3(input.x, 0, input.y)).normalized()
	var speed := 4.5 if Input.is_action_pressed("sprint") else 2.8
	velocity.x = move_toward(velocity.x, dir.x * speed, 30.0 * delta)
	velocity.z = move_toward(velocity.z, dir.z * speed, 30.0 * delta)
	move_and_slide()
	if global_position.y < -3.0:  # haritadan düştüyse dükkânın içine geri al
		global_position = SAFE_POS
		velocity = Vector3.ZERO
	if held != null:
		_sync_viewmodel_cam()
	_update_target()


func _update_target() -> void:
	var from := cam.global_position
	var to := from - cam.global_transform.basis.z * REACH
	var q := PhysicsRayQueryParameters3D.create(from, to, 3, [get_rid()])
	q.collide_with_areas = true
	var r := get_world_3d().direct_space_state.intersect_ray(q)
	target = null
	if r:
		var n = r.collider
		while n and not n.has_method("interact"):
			n = n.get_parent()
		target = n
	hint = target.get_hint(self) if target else ""


func pick_up(p) -> void:
	if held:
		return
	if p.slot:
		p.slot.detach()
	p.linear_velocity = Vector3.ZERO
	p.angular_velocity = Vector3.ZERO
	held = p
	# fizikten tamamen çık: statik dondur (kinematik dondurma ilk fizik karede eski dünya konumunu geri yazabiliyordu)
	p.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	p.freeze = true
	p.collision_layer = 0
	p.collision_mask = 0
	if p.get_parent():
		p.reparent(hold, false)
	else:
		hold.add_child(p)
	_set_viewmodel_layer(p, true)
	_held_xform = held_xform_for(p)
	p.transform = _held_xform
	if p.has_method("reset_physics_interpolation"):
		p.reset_physics_interpolation()
	vm_rect.visible = true
	vm_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_sync_viewmodel_vp()
	vm_cam.make_current()
	_sync_viewmodel_cam()
	Game.sfx.pickup()


## Eşyanın tüm görsel düğümlerini viewmodel katmanına alır / eski katmanlarına döndürür.
func _set_viewmodel_layer(n: Node, on: bool) -> void:
	if on:
		_held_layers.clear()
		_collect_layers(n)
		for v in _held_layers:
			v.layers = VM_LAYER
	else:
		for v in _held_layers:
			if is_instance_valid(v):
				v.layers = _held_layers[v]
		_held_layers.clear()


func _collect_layers(n: Node) -> void:
	if n is VisualInstance3D:
		_held_layers[n] = n.layers
	for c in n.get_children():
		_collect_layers(c)


## Elindeki parçayı bırakır ve döndürür (takma/çöpe atma için).
func release_held():
	var p = held
	held = null
	if p:
		_set_viewmodel_layer(p, false)
	return p


func drop() -> void:
	if held == null:
		return
	var p = release_held()
	var gt: Transform3D = p.global_transform
	p.reparent(get_tree().current_scene, false)
	p.global_transform = gt
	p.collision_layer = 2
	p.collision_mask = 1
	p.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	p.freeze = false
	p.linear_velocity = -cam.global_transform.basis.z * 1.5 + velocity
	Game.sfx.pickup()
