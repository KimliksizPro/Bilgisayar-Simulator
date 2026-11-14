extends Control
## 5 yıldızlı itibar göstergesi (font bağımsız, çizilir).

const AMBER := Color("ffb52e")
const DIM := Color(1, 1, 1, 0.16)

var px := 22:
	set(v):
		px = v
		custom_minimum_size = Vector2(px * 5.4, px)
		queue_redraw()
var value := 3.0:
	set(v):
		value = v
		queue_redraw()


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(px * 5.4, px)


func _star_points(c: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 10:
		var a := -PI / 2.0 + i * PI / 5.0
		var rr := r if i % 2 == 0 else r * 0.45
		pts.append(c + Vector2(cos(a), sin(a)) * rr)
	return pts


func _draw() -> void:
	var r := px * 0.5
	for i in 5:
		var c := Vector2(r + i * px * 1.1, r)
		var pts := _star_points(c, r)
		var fill := clampf(value - i, 0.0, 1.0)
		draw_colored_polygon(pts, DIM)
		if fill >= 0.5:
			draw_colored_polygon(pts, AMBER)
