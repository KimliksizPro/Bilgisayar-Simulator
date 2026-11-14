extends Control
## Nişangah: küçük nokta; hedefteyken amber olur ve vizör köşeleri içeri kapanır.

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
	var col := Color(1, 1, 1, 0.85).lerp(Color("ffb52e"), _t)
	var shadow := Color(0, 0, 0, 0.5)
	draw_circle(c, 2.6, shadow)
	draw_circle(c, 1.9, col)
	if _t <= 0.01:
		return
	# hedefte: vizör köşeleri içeri kapanır
	var r := lerpf(20.0, 11.0, _t)
	var l := 5.0
	var a := Color(col.r, col.g, col.b, _t)
	var sa := Color(0, 0, 0, 0.45 * _t)
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			var p := c + Vector2(sx * r, sy * r)
			for pass_ in 2:
				var off := Vector2(1, 1) if pass_ == 0 else Vector2.ZERO
				var cc := sa if pass_ == 0 else a
				draw_line(p + off, p + off + Vector2(-sx * l, 0), cc, 2.0, true)
				draw_line(p + off, p + off + Vector2(0, -sy * l), cc, 2.0, true)
