extends Node
## Geliştirici aracı: `godot -- --perf` ile birkaç bakış açısında çizim istatistiklerini yazdırır.

func _ready() -> void:
	var p = Game.player
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var jobs = Game.job_mgr
	await get_tree().create_timer(9.0).timeout
	if jobs.dev_bench_job(jobs._make_job_of("repair_gpu")) != null:
		jobs.pc.toggle_panel()
	var views := {"genel": [Vector3(2.8, 0, 1.0), 55, -12], "masa": [Vector3(0.45, 0, -1.85), 0, -45], "raf": [Vector3(-2.6, 0, -0.9), 90, -15]}
	var meshes := get_tree().root.find_children("*", "MeshInstance3D", true, false).size()
	var lights := get_tree().root.find_children("*", "Light3D", true, false).size()
	print("PERF sahnedeki mesh: %d, ışık: %d" % [meshes, lights])
	var live := {}
	var tris := {}
	for mi in get_tree().root.find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null:
			continue
		var key: PackedStringArray = str(mi.get_path()).split("/").slice(0, 4)
		var k: String = "/".join(key) + " :: " + mi.mesh.get_class()
		live[k] = live.get(k, 0) + 1
		var t := 0
		for si in mi.mesh.get_surface_count():
			var arr = mi.mesh.surface_get_arrays(si)
			t += (arr[Mesh.ARRAY_INDEX].size() if arr[Mesh.ARRAY_INDEX] else arr[Mesh.ARRAY_VERTEX].size()) / 3
		tris[k] = tris.get(k, 0) + t
	for k in live:
		print("PERF  %4d adet  %7d üçgen  %s" % [live[k], tris[k], k])
	print("PERF Label3D: %d" % get_tree().root.find_children("*", "Label3D", true, false).size())
	for v in views:
		p.global_position = views[v][0]
		p.rotation_degrees.y = views[v][1]
		p.cam.rotation_degrees.x = views[v][2]
		await get_tree().create_timer(1.5).timeout
		var dc := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		var obj := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME)
		var prim := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
		print("PERF %s: draw call %d, nesne %d, üçgen %d, fps(yazılım GPU) %d" % [v, dc, obj, prim, Engine.get_frames_per_second()])
	get_tree().quit()
