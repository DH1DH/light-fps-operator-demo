extends Node
class_name StatusController

signal damaged(amount: float)
signal status_reset

@export var max_hp: float = 500.0
@export var burn_damage_per_stack: float = 1.0

var current_hp: float = 500.0
var mark_stacks: int = 0
var seed_stacks: int = 0
var burn_stacks: int = 0
var freeze_stacks: int = 0
var greed_stacks: int = 0
var last_damage_time: float = -1.0

func _ready() -> void:
	reset_status()


func _process(delta: float) -> void:
	if is_dead():
		return
	if burn_stacks <= 0:
		return
	var burn_damage: float = burn_damage_per_stack * float(burn_stacks) * delta
	apply_damage(burn_damage)


func is_dead() -> bool:
	return current_hp <= 0.0


func reset_status() -> void:
	current_hp = max_hp
	mark_stacks = 0
	seed_stacks = 0
	burn_stacks = 0
	freeze_stacks = 0
	greed_stacks = 0
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


func add_seed(amount: int) -> void:
	if amount <= 0 or is_dead():
		return
	seed_stacks += amount


func consume_seed(amount: int) -> int:
	if amount <= 0:
		return 0
	var consumed: int = mini(seed_stacks, amount)
	seed_stacks -= consumed
	return consumed


func add_burn(amount: int) -> void:
	if amount <= 0 or is_dead():
		return
	burn_stacks += amount


func add_freeze(amount: int) -> void:
	if amount <= 0 or is_dead():
		return
	freeze_stacks += amount


func add_greed(amount: int) -> void:
	if amount <= 0 or is_dead():
		return
	greed_stacks += amount


func consume_reactor_pairs(max_pairs: int) -> int:
	if max_pairs <= 0:
		return 0
	var pairs: int = mini(max_pairs, mini(burn_stacks, freeze_stacks))
	if pairs <= 0:
		return 0
	burn_stacks -= pairs
	freeze_stacks -= pairs
	return pairs


func consume_all_greed() -> int:
	var consumed: int = greed_stacks
	greed_stacks = 0
	return consumed
