extends Node
## Geliştirici aracı: `godot -- --propshot` dükkândaki detaylı eşyaları yakından çeker (shot_prop_*.png).

const VIEWS := {
	"keyboard": [Vector3(-0.45, 1.12, -1.95), Vector3(-0.42, 0.75, -2.32), 40.0],
	"mouse_phone": [Vector3(-0.5, 1.05, -1.95), Vector3(-0.5, 0.75, -2.3), 55.0],
	"lamp": [Vector3(0.85, 1.15, -2.0), Vector3(1.25, 0.95, -2.7), 50.0],
	"mug_tools": [Vector3(0.95, 1.0, -1.95), Vector3(0.95, 0.76, -2.3), 45.0],
	"laptop": [Vector3(0.3, 1.45, 0.75), Vector3(0.3, 1.1, 1.25), 45.0],
	"register": [Vector3(-1.75, 1.5, 0.75), Vector3(-1.8, 1.1, 1.3), 55.0],
	"monitor_back": [Vector3(-0.2, 1.35, -1.9), Vector3(-0.5, 1.1, -2.72), 50.0],
	"crt": [Vector3(-1.2, 1.5, 0.75), Vector3(-1.4, 1.2, 1.33), 50.0],
	"mouse": [Vector3(-0.05, 0.95, -2.1), Vector3(-0.12, 0.76, -2.27), 40.0],
	"customers": [Vector3(-0.5, 1.5, 1.2), Vector3(-0.5, 1.25, -0.6), 50.0],
	"faces": [Vector3(-0.5, 1.68, 0.1), Vector3(-0.5, 1.6, -0.6), 50.0],
	"counter_phone": [Vector3(-0.8, 1.35, 0.85), Vector3(-0.72, 1.03, 1.18), 35.0],
	"shelf": [Vector3(-1.6, 1.3, -0.7), Vector3(-3.75, 1.0, -0.7), 85.0],
	"rack": [Vector3(-2.35, 1.35, -1.6), Vector3(-2.35, 1.35, -2.95), 55.0],
}


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Game.hud.visible = false
	var cam := Camera3D.new()
	cam.near = 0.02
	get_tree().current_scene.add_child(cam)
	cam.make_current()
	const CUST := preload("res://scripts/customer.gd")
	var names := ["Ayşe Teyze", "Hasan Amca", "Zeynep", "Burak", "Mustafa Amca"]
	for i in names.size():
		var c = CUST.new()
		c.position = Vector3(-1.5 + i * 0.5, 0, -0.6)
		get_tree().current_scene.add_child(c)
		c.build(func(_p): return "", func(_p): pass, names[i])
		c.face_angle = 0.0
		c.rotation.y = 0.0
	await get_tree().create_timer(1.0).timeout
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7)
	for v in VIEWS:
		if only != "" and not v in only.split(","):
			continue
		cam.fov = VIEWS[v][2]
		cam.look_at_from_position(VIEWS[v][0], VIEWS[v][1])
		await get_tree().create_timer(0.4).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/shot_prop_%s.png" % v)
	get_tree().quit()
