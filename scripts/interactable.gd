extends StaticBody3D
## Genel etkileşim objesi: oyuncu bakınca ipucu gösterir, E'ye basınca action çalışır.

var hint_fn: Callable
var action: Callable


func get_hint(player) -> String:
	return hint_fn.call(player) if hint_fn.is_valid() else ""


func interact(player) -> void:
	if action.is_valid():
		action.call(player)
