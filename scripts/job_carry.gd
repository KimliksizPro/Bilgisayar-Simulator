extends Node
## Cihaz taşıma: oyuncu bir PC kasasını / laptopu / telefonu rafdan ya da tezgâhtan alıp kameranın önünde taşır.
## Parça tutma sisteminden (player.held) ayrıdır: cihaz kameranın çocuğu olur, çarpışmaları kapalıdır.
## Bırakma: rafın boş gözüne / tezgâh yerine E; G ya da sağ tık = geldiği yere geri koy.

const ST := preload("res://scripts/job_store.gd")

var rec: Dictionary = {}
var node = null
var origin := ""            # "rack:N" ya da "bench"
var jobs                     # job_manager
var _tw: Tween


func active() -> bool:
	return node != null and is_instance_valid(node)


func ticket() -> int:
	return int(rec.ticket) if active() else 0


## Elde taşınırken cihazın kameraya göre duruşu: ekranın alt köşesinde, küçültülmüş (görüşü kapatmasın).
## Kasa camı öne bakar; laptop/telefon eğik tutulur.
static func pose(dev) -> Transform3D:
	if dev.has_method("slot_open"):
		var phone: bool = dev.device_name.to_lower().begins_with("tel")
		if phone:
			return Transform3D(Basis.from_euler(Vector3(deg_to_rad(40), 0, 0)), Vector3(0.14, -0.2, -0.45))
		return Transform3D(Basis.from_euler(Vector3(deg_to_rad(28), 0, 0)).scaled(Vector3.ONE * 0.6), Vector3(0.18, -0.34, -0.7))
	return Transform3D(Basis.from_euler(Vector3(deg_to_rad(8), deg_to_rad(-62), 0)).scaled(Vector3.ONE * 0.62), Vector3(0.24, -0.52, -0.9))


## Cihazı al: sönük, kapağı kapalı, çarpışmasız; kameraya takılır.
func start(r: Dictionary, dev, from: String) -> void:
	rec = r
	node = dev
	origin = from
	if dev.powered:
		dev.power_off()
	if dev.panel_open:
		dev.toggle_panel()
	ST.lock(dev, true)
	var cam: Camera3D = Game.player.cam
	dev.reparent(cam, true)
	_glide(dev, pose(dev), 0.25)
	Game.sfx.pickup()


## Taşınan cihazı bırakır (yeni yerine yerleştiren çağıran yapar); düğümü döndürür.
func release():
	var d = node
	node = null
	rec = {}
	origin = ""
	return d


## Cihazı yeni üst düğüme yumuşakça yerleştirir.
func settle(dev, parent: Node, xform: Transform3D, dur := 0.22) -> void:
	dev.reparent(parent, true)
	_glide(dev, xform, dur)


func _glide(dev, xform: Transform3D, dur: float) -> void:
	if _tw and _tw.is_valid():
		_tw.kill()
	if not dev.is_inside_tree():
		dev.transform = xform
		return
	_tw = dev.create_tween()
	_tw.tween_property(dev, "transform", xform, dur).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _unhandled_input(event: InputEvent) -> void:
	if not active() or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event.is_action_pressed("drop"):
		jobs.return_carried()
		get_viewport().set_input_as_handled()
