extends Node
## ParçaNet kargo teslimatı: varış zamanı gelen siparişleri kurye dükkâna getirir,
## kapının yanına kargo kutusu bırakır. Kutuyu açınca (E) parçalar stoğa girer.

const MU := preload("res://scripts/mesh_util.gd")
const CUSTOMER := preload("res://scripts/customer.gd")

const SPAWN := Vector3(0.6, 0, 9.0)
const DOOR := Vector3(0.35, 0, 3.6)
const DROP := Vector3(1.0, 0, 2.55)
const BOX_SPOTS := [Vector3(1.35, 0, 2.45), Vector3(1.85, 0, 2.45), Vector3(1.35, 0, 1.95), Vector3(1.85, 0, 1.95),
	Vector3(2.35, 0, 2.45), Vector3(2.35, 0, 1.95)]

var world: Node3D
var courier = null
var boxes := {}            # sipariş id -> kutu düğümü
var _check_t := 0.0


func _ready() -> void:
	Game.day_ended.connect(func(_s): _end_of_day())
	Game.day_started.connect(_reset)


func _process(delta: float) -> void:
	if Game.phase != "day" or not Game.running:
		return
	_check_t += delta
	if _check_t < 0.5:
		return
	_check_t = 0.0
	if courier == null and not Game.due_orders().is_empty():
		_send_courier()


## Yeni gün: kapıda kalmış kutu/kurye temizlenir (açılmamış kutular gün sonunda stoğa alınır).
func _reset() -> void:
	if is_instance_valid(courier):
		courier.queue_free()
	courier = null
	for id in boxes:
		if is_instance_valid(boxes[id]):
			boxes[id].queue_free()
	boxes.clear()
	for o in Game.orders:
		o.state = "transit"


func _send_courier() -> void:
	var due := Game.due_orders()
	for o in due:
		o.state = "courier"
	Game.orders_changed.emit()
	courier = CUSTOMER.new()
	courier.position = SPAWN
	world.add_child(courier)
	courier.build(func(_p): return "", func(_p): pass, Color(0.95, 0.55, 0.12))
	courier.speed = 1.8
	# elinde koli
	var carried := MU.rbox(courier, Vector3(0.42, 0.3, 0.32), Vector3(0, 1.05, 0.26), MU.mat(Color(0.68, 0.52, 0.33), 0, 0.95), 0.012)
	courier.walk([DOOR, DROP], func(): _drop(due, carried))
	Game.msg("Kargo geliyor! Kurye kapıda.", Color(0.6, 0.9, 1.0))
	Game.sfx.ui_hover()


func _drop(due: Array, carried: Node3D) -> void:
	if not is_instance_valid(courier):
		return
	courier.face_angle = PI * 0.5
	courier.say("ParçaNet kargo! Kolileri buraya bırakıyorum usta, kolay gelsin.")
	if is_instance_valid(carried):
		carried.queue_free()
	for o in due:
		if Game.orders.has(o):
			o.state = "door"
			_spawn_box(o)
	Game.orders_changed.emit()
	Game.sfx.click()
	if Game.hud:
		Game.hud.tip("cargo", "Kargo geldi! Kapının yanındaki koliye bakıp E'ye bas: parçalar stoğa girer.")
	var c = courier
	await get_tree().create_timer(2.0).timeout
	if is_instance_valid(c):
		c.say("")
		c.walk([DOOR, SPAWN], func():
			c.queue_free()
			if courier == c:
				courier = null)


func _free_spot() -> Vector3:
	for sp in BOX_SPOTS:
		var used := false
		for id in boxes:
			if is_instance_valid(boxes[id]) and Vector2(boxes[id].position.x, boxes[id].position.z).distance_to(Vector2(sp.x, sp.z)) < 0.2:
				used = true
		if not used:
			return sp
	return BOX_SPOTS[0] + Vector3(randf_range(-0.2, 0.2), 0, randf_range(-0.2, 0.2))


func _spawn_box(o: Dictionary) -> void:
	var n := 0
	for k in o.items:
		n += int(o.items[k])
	var h := clampf(0.18 + n * 0.03, 0.2, 0.45)
	var size := Vector3(0.5, h, 0.4)
	var box := Node3D.new()
	box.position = _free_spot()
	box.rotation_degrees.y = randf_range(-12, 12)
	world.add_child(box)
	MU.rbox(box, size, Vector3(0, h / 2, 0), MU.mat(Color(0.68, 0.52, 0.33), 0, 0.95), 0.012)
	MU.box(box, Vector3(size.x + 0.004, 0.006, 0.07), Vector3(0, h + 0.001, 0), MU.mat(Color(0.82, 0.7, 0.45), 0, 0.4))
	MU.box(box, Vector3(0.18, 0.004, 0.12), Vector3(0.1, h + 0.003, 0.1), MU.mat(Color(0.97, 0.97, 0.95), 0, 0.7))
	var l := MU.label(box, "ParçaNet\n#%03d" % int(o.id), Vector3(0, h / 2, size.z / 2 + 0.002), 48, Color(0.15, 0.25, 0.6), Vector3.ZERO, 0.0012)
	l.double_sided = false
	var top := MU.label(box, "#%03d" % int(o.id), Vector3(0.1, h + 0.006, 0.1), 36, Color(0.1, 0.1, 0.1), Vector3(-90, 0, 0), 0.0012)
	top.double_sided = false
	var id := int(o.id)
	MU.interactable(box, size + Vector3(0.04, 0.04, 0.04), Vector3(0, h / 2, 0),
		func(p): return ("Koliyi aç (#%03d, %d parça)  [E]" % [id, n]) if p.held == null else "Önce elindekini bırak",
		func(p): open_box(id, p))
	box.scale = Vector3.ONE * 0.01
	box.create_tween().tween_property(box, "scale", Vector3.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	boxes[id] = box


func open_box(id: int, p = null) -> void:
	if p and p.held:
		return
	var o := Game.receive_order(id)
	if o.is_empty():
		return
	Game.sfx.click()
	Game.msg("Koli açıldı, stoğa eklendi: %s" % Game.items_text(o.items), Color(0.5, 1, 0.5))
	if Game.hud:
		Game.hud.dismiss_tip("cargo")
	var box: Node3D = boxes.get(id)
	boxes.erase(id)
	if is_instance_valid(box):
		var tw := box.create_tween()
		tw.tween_property(box, "scale", Vector3(1.1, 0.05, 1.1), 0.25)
		tw.tween_callback(box.queue_free)


## Gün bitti: kapıda açılmamış koliler otomatik stoğa alınır.
func _end_of_day() -> void:
	for id in boxes.keys():
		Game.receive_order(int(id))
		if is_instance_valid(boxes[id]):
			boxes[id].queue_free()
	boxes.clear()
