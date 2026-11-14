extends Control
## Nişangah: normalde küçük nokta + ince halka, hedefteyken büyüyüp amber olur.

var target := false:
	set(v):
		if v != target:
			target = v
			set_process(true)
var _t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(48, 48)
	set_process(false)


func _process(delta: float) -> void:
	var goal := 1.0 if target else 0.0
	_t = move_toward(_t, goal, delta * 8.0)
	queue_redraw()
	if is_equal_approx(_t, goal):
		set_process(false)


func _draw() -> void:
	var c := size * 0.5
	var col := Color(1, 1, 1, 0.8).lerp(Color("ffb52e"), _t)
	var shadow := Color(0, 0, 0, 0.45)
	var r := lerpf(5.0, 11.0, _t)
	draw_circle(c, 2.4 + _t * 0.8, shadow)
	draw_circle(c, 1.8 + _t * 0.8, col)
	draw_arc(c, r + 1.0, 0, TAU, 40, shadow, 3.0, true)
	draw_arc(c, r, 0, TAU, 40, Color(col.r, col.g, col.b, 0.35 + 0.65 * _t), 1.8, true)
