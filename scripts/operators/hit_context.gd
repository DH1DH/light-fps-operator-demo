extends RefCounted
class_name HitContext
const StatusController = preload("res://scripts/combat/status_controller.gd")
const ShotContext = preload("res://scripts/operators/shot_context.gd")

var damage := 0.0
var target_status: StatusController = null
var hit_point := Vector3.ZERO
var target_world_position := Vector3.ZERO
var shot_pellet_count: int = 1
var all_statuses: Array[StatusController] = []
var effect_tags: Array[String] = []
var phase: int = ShotContext.ShotPhase.BUILD
var hand: String = "right"

var pending_coin_gain: int = 0
var pending_spawn_count: int = 0
var pending_spawn_power: float = 0.0
var pending_spawns: Array[Dictionary] = []
var pending_chain_arcs: Array[Dictionary] = []


func add_effect(tag: String) -> void:
	if tag.is_empty():
		return
	if not effect_tags.has(tag):
		effect_tags.append(tag)


func phase_text() -> String:
	return ShotContext.phase_to_string(phase)


func phase_with_role_text() -> String:
	return ShotContext.phase_with_role(phase)


func queue_spawn(power: float, target_status_ref: StatusController = null) -> void:
	var spawn_power: float = maxf(0.1, power)
	pending_spawns.append({
		"power": spawn_power,
		"form": "auto",
		"target_status": target_status_ref,
	})
	pending_spawn_count += 1
	pending_spawn_power += spawn_power


func apply_form_to_pending_spawns(form: String) -> int:
	var normalized: String = form.strip_edges().to_lower()
	if normalized != "runner" and normalized != "attached":
		return 0
	var applied: int = 0
	for index in range(pending_spawns.size()):
		var entry: Dictionary = pending_spawns[index]
		entry["form"] = normalized
		pending_spawns[index] = entry
		applied += 1
	return applied


func queue_chain_arc(from_world: Vector3, to_world: Vector3, damage_value: float, jump_index: int) -> void:
	pending_chain_arcs.append({
		"from": from_world,
		"to": to_world,
		"damage": maxf(0.0, damage_value),
		"jump": max(1, jump_index),
	})
