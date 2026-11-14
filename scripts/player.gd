extends CharacterBody3D
## Birinci şahıs oyuncu: yürüme, bakma, etkileşim, parça taşıma.

const REACH := 2.2

var cam: Camera3D
var hold: Node3D
var held = null
var target = null
var hint := ""
var sensitivity := 0.0025
var _pitch := 0.0


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


func _unhandled_input(event: InputEvent) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		if event is InputEventMouseButton and event.pressed:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * sensitivity)
		_pitch = clamp(_pitch - event.relative.y * sensitivity, deg_to_rad(-85), deg_to_rad(85))
		cam.rotation.x = _pitch
	elif event.is_action_pressed("interact"):
		if target:
			target.interact(self)
	elif event.is_action_pressed("drop"):
		drop()
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= 9.8 * delta
	var active := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back") if active else Vector2.ZERO
	var dir := (transform.basis * Vector3(input.x, 0, input.y)).normalized()
	var speed := 4.5 if Input.is_action_pressed("sprint") else 2.8
	velocity.x = move_toward(velocity.x, dir.x * speed, 30.0 * delta)
	velocity.z = move_toward(velocity.z, dir.z * speed, 30.0 * delta)
	move_and_slide()
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
	p.freeze = true
	p.collision_layer = 0
	p.collision_mask = 0
	p.reparent(hold, false)
	var e: Vector3 = p.hold_euler()
	var b := Basis.from_euler(Vector3(deg_to_rad(e.x), deg_to_rad(e.y), deg_to_rad(e.z)))
	p.transform = Transform3D(b, -(b * p.hold_center()))
	Game.sfx.pickup()


## Elindeki parçayı bırakır ve döndürür (takma/çöpe atma için).
func release_held():
	var p = held
	held = null
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
	p.freeze = false
	p.linear_velocity = -cam.global_transform.basis.z * 1.5 + velocity
	Game.sfx.pickup()
