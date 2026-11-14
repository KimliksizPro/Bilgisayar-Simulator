extends Node
## Geliştirici aracı: `godot -- --partshot` her parçayı yakından çekip tek bir görselde birleştirir.

const PM := preload("res://scripts/part_models.gd")

func _ready() -> void:
	var p = Game.player
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Game.hud.visible = false
	p.global_position = Vector3(1.5, 0, 0.6)
	p.rotation_degrees.y = 0
	p.cam.rotation_degrees.x = -30
	var light := OmniLight3D.new()
	light.light_energy = 0.6
	light.omni_range = 2.0
	p.cam.add_child(light)
	light.position = Vector3(0.2, 0.3, 0)
	# [tip, seviye, mesafe, dönüş]
	var items := [["cpu", 1, 0.2, Vector3(20, -40, 0)], ["ram", 1, 0.2, Vector3(0, -70, -90)], ["ram", 2, 0.2, Vector3(0, -70, -90)],
		["gpu", 1, 0.38, Vector3(-150, -30, 0)], ["gpu", 2, 0.38, Vector3(25, -30, 0)], ["psu", 1, 0.32, Vector3(25, -40, 0)],
		["ssd", 1, 0.17, Vector3(60, 0, 0)]]
	var tiles := []
	for it in items:
		var b: Dictionary = PM.build(it[0], it[1])
		var n: Node3D = b.node
		var info: Dictionary = PM.info(it[0])
		var holder := Node3D.new()
		p.cam.add_child(holder)
		holder.position = Vector3(0, 0, -it[2])
		holder.rotation_degrees = it[3]
		holder.add_child(n)
		n.position = -info.center
		for m in b.rgb:
			m.emission_enabled = true
			m.emission_energy_multiplier = 2.5
		await get_tree().create_timer(0.8).timeout
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		img.resize(640, 360)
		tiles.append(img)
		holder.queue_free()
	var out := Image.create_empty(640 * 3, 360 * 3, false, tiles[0].get_format())
	for i in tiles.size():
		out.blit_rect(tiles[i], Rect2i(0, 0, 640, 360), Vector2i((i % 3) * 640, (i / 3) * 360))
	out.save_png(OS.get_user_data_dir() + "/shot_parts.png")
	get_tree().quit()
