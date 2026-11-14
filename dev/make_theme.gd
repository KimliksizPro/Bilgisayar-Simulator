extends SceneTree
## Tek seferlik: `godot --headless --script dev/make_theme.gd` ile assets/ui/theme.res üretir.

func _init() -> void:
	var T := load("res://scripts/ui_theme.gd")
	var err := ResourceSaver.save(T.build(), "res://assets/ui/theme.res", ResourceSaver.FLAG_COMPRESS)
	print("tema kaydedildi: ", err)
	quit()
