extends Node
## Geliştirici aracı: `godot -- --shot` ile çalıştırınca birkaç açıdan ekran görüntüsü alır.

var main
var jobs


func _ready() -> void:
	main = get_parent()
	await get_tree().create_timer(1.0).timeout
	var p = Game.player
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	jobs = main.get_children().filter(func(c): return c.has_method("_next_customer"))[0]
	await _shot(p, Vector3(2.8, 0, 1.0), 55, -12, "overview")
	await get_tree().create_timer(7.0).timeout
	await _shot(p, Vector3(-0.3, 0, 0.4), 180, -5, "customer")
	jobs._customer_talk(p)
	await _shot(p, Vector3(0.5, 0, -1.6), 0, -30, "desk")
	jobs.pc.toggle_panel()
	await get_tree().create_timer(0.8).timeout
	await _shot(p, Vector3(0.45, 0, -1.85), 0, -45, "inside")
	jobs.pc.power_button()
	await get_tree().create_timer(2.5).timeout
	await _shot(p, Vector3(0.0, 0, -1.7), 0, -25, "powered")
	await _shot(p, Vector3(-2.6, 0, -0.9), 90, -15, "shelf")
	p.cam.fov = 32
	await _shot(p, Vector3(0.48, 0, -1.75), 0, -40, "closeup")
	p.cam.fov = 72
	get_tree().quit()


func _shot(p, pos: Vector3, yaw: float, pitch: float, name: String) -> void:
	p.global_position = pos
	p.rotation_degrees.y = yaw
	p.cam.rotation_degrees.x = pitch
	await get_tree().create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(OS.get_user_data_dir() + "/shot_%s.png" % name)
	print("shot ", name, " -> ", OS.get_user_data_dir())
