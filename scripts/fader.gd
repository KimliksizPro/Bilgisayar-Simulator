extends CanvasLayer
## Ekran kararma geçişi (sahne değişimleri için).

var rect: ColorRect


func _init() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS
	rect = ColorRect.new()
	rect.color = Color(0.02, 0.03, 0.06, 1.0)
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.modulate.a = 0.0
	add_child(rect)


## Karartmayı hedef değere (0 = açık, 1 = tam siyah) götürür; beklenebilir.
func fade(to: float, dur := 0.5) -> void:
	var tw := create_tween()
	tw.tween_property(rect, "modulate:a", to, dur)
	rect.mouse_filter = Control.MOUSE_FILTER_STOP if to > 0.01 else Control.MOUSE_FILTER_IGNORE
	await tw.finished
