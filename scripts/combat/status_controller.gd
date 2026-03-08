extends Node
class_name StatusController

signal damaged(amount: float)
signal status_reset

@export var max_hp: float = 500.0

var current_hp: float = 500.0
var mark_stacks: int = 0
var last_damage_time: float = -1.0

func _ready() -> void:
	reset_status()


func is_dead() -> bool:
	return current_hp <= 0.0


func reset_status() -> void:
	current_hp = max_hp
	mark_stacks = 0
	last_damage_time = -1.0
	status_reset.emit()


func apply_damage(amount: float) -> void:
	if amount <= 0.0 or is_dead():
		return
	current_hp = maxf(0.0, current_hp - amount)
	last_damage_time = Time.get_ticks_msec() / 1000.0
	damaged.emit(amount)


func add_marks(amount: int) -> void:
	if amount <= 0 or is_dead():
		return
	mark_stacks += amount


func consume_all_marks() -> int:
	var consumed: int = mark_stacks
	mark_stacks = 0
	return consumed
