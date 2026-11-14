extends Node
## Global oyun durumu (autoload): para, HUD, ses ve oyuncu referansları.

signal money_changed(value: int)

const SFX := preload("res://scripts/sfx.gd")

var money := 300
var jobs_done := 0
var high_quality := true
var hud = null
var player = null
var sfx = null


func _ready() -> void:
	sfx = SFX.new()
	add_child(sfx)


func add_money(amount: int) -> void:
	money += amount
	money_changed.emit(money)


func spend(amount: int) -> bool:
	if money < amount:
		return false
	money -= amount
	money_changed.emit(money)
	return true


func msg(text: String, color := Color.WHITE) -> void:
	if hud:
		hud.show_message(text, color)
