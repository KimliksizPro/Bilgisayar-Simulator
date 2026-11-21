extends Node
## Geliştirici aracı: `godot -- --holdshot` elde parça tutarken duvara yakın ekran görüntüsü alır (viewmodel açık/kapalı).

func _ready() -> void:
	var main = get_parent()
	var p = Game.player
	await get_tree().create_timer(1.0).timeout
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	Game.hud.visible = false
	Game.new_game()
	p.global_position = Vector3(-2.6, 0, -0.6)
	p.rotation_degrees.y = 90
	p.cam.rotation_degrees.x = -10
	main._on_cabinet_pick("ram_ddr4_8g", false)
	await get_tree().create_timer(0.2).timeout
	p.rotation_degrees.y = 185
	p.cam.rotation_degrees.x = -18
	await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/hold_ram_vm.png")
	p.release_held().queue_free()

	p.global_position = Vector3(0.9, 0, -2.2)
	p.rotation_degrees.y = 0
	p.cam.rotation_degrees.x = -25
	for t in ["cpu"]:
		main._buy(p, t, 1)
		await get_tree().create_timer(0.6).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/hold_%s_vm.png" % t)
		if t == "gpu":
			# karşılaştırma: viewmodel kapalı
			p.cam.cull_mask = 0xFFFFF
			for v in p.held.find_children("*", "VisualInstance3D", true, false):
				v.layers = 1
			p.vm_rect.visible = false
			p.set_process(false)
			await get_tree().create_timer(0.3).timeout
			await RenderingServer.frame_post_draw
			get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/hold_gpu_novm.png")
			p.cam.cull_mask = 0xFFFFF & ~p.VM_LAYER
			p.set_process(true)
		p.release_held().queue_free()
	get_tree().quit()
