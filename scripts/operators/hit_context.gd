extends RefCounted
class_name HitContext
const StatusController = preload("res://scripts/combat/status_controller.gd")

var damage := 0.0
var target_status: StatusController = null
var hit_point := Vector3.ZERO
var target_world_position := Vector3.ZERO
var shot_pellet_count: int = 1
var all_statuses: Array[StatusController] = []
var effect_tags: Array[String] = []

var pending_coin_gain: int = 0
var pending_spawn_count: int = 0
var pending_spawn_power: float = 0.0


func add_effect(tag: String) -> void:
	if tag.is_empty():
		return
	if not effect_tags.has(tag):
		effect_tags.append(tag)
