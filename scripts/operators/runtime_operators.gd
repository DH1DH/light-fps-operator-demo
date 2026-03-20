extends RefCounted
const RuntimeOperator = preload("res://scripts/operators/runtime_operator.gd")
const ShotContext = preload("res://scripts/operators/shot_context.gd")
const HitContext = preload("res://scripts/operators/hit_context.gd")
const StatusController = preload("res://scripts/combat/status_controller.gd")

class DuplicateOperator extends RuntimeOperator:
	var multiplier := 1

	func _init(value: int) -> void:
		multiplier = max(1, value)

	func on_fire(context: ShotContext) -> void:
		context.pellet_count *= multiplier
		context.add_effect("duplicate_x2")


class AddOneOperator extends RuntimeOperator:
	var amount := 1

	func _init(value: int) -> void:
		amount = max(1, value)

	func on_fire(context: ShotContext) -> void:
		context.pellet_count += amount
		context.add_effect("add_one")


class ScatterOperator extends RuntimeOperator:
	var spread_angle := 8.0

	func _init(value: float) -> void:
		spread_angle = maxf(0.0, value)

	func on_fire(context: ShotContext) -> void:
		context.spread_angle = spread_angle
		context.add_effect("scatter")


class FocusOperator extends RuntimeOperator:
	var multiplier := 0.2

	func _init(value: float) -> void:
		multiplier = clampf(value, 0.0, 1.0)

	func on_fire(context: ShotContext) -> void:
		context.spread_angle *= multiplier
		context.add_effect("focus")


class MarkOperator extends RuntimeOperator:
	var mark_stacks := 1

	func _init(value: int) -> void:
		mark_stacks = max(1, value)

	func on_hit(context: HitContext) -> void:
		if context.target_status == null:
			return
		context.target_status.add_marks(mark_stacks)
		context.add_effect("mark")


class MarkAmplifierOperator extends RuntimeOperator:
	var amount := 1

	func _init(value: int) -> void:
		amount = max(1, value)

	func on_hit(context: HitContext) -> void:
		if context.target_status == null:
			return
		if context.target_status.mark_stacks > 0:
			context.target_status.add_marks(amount)
			context.add_effect("mark_amplifier")


class ExecuteOperator extends RuntimeOperator:
	var bonus_damage_per_mark := 0.0

	func _init(value: float) -> void:
		bonus_damage_per_mark = maxf(0.0, value)

	func on_hit(context: HitContext) -> void:
		if context.target_status == null:
			return
		var consumed: int = context.target_status.consume_all_marks()
		if consumed <= 0:
			return
		context.damage += consumed * bonus_damage_per_mark
		context.add_effect("execute")


class ConvergeOperator extends RuntimeOperator:
	var base_bonus := 0.0

	func _init(value: float) -> void:
		base_bonus = maxf(0.0, value)

	func on_hit(context: HitContext) -> void:
		var pellets: int = max(1, context.shot_pellet_count)
		context.damage += base_bonus / float(pellets)
		context.add_effect("converge")


class SeedOperator extends RuntimeOperator:
	var amount := 1

	func _init(value: int) -> void:
		amount = max(1, value)

	func on_hit(context: HitContext) -> void:
		if context.target_status == null:
			return
		context.target_status.add_seed(amount)
		context.add_effect("seed")


class SeedSpreadOperator extends RuntimeOperator:
	var spread_radius := 5.0
	var spread_amount := 1

	func _init(radius: float, amount: int) -> void:
		spread_radius = maxf(0.1, radius)
		spread_amount = max(1, amount)

	func on_hit(context: HitContext) -> void:
		if context.target_status == null or context.target_status.seed_stacks <= 0:
			return
		var spread_applied: bool = false
		for status in context.all_statuses:
			if status == null or status == context.target_status:
				continue
			if status.is_dead():
				continue
			var owner_node := status.get_parent()
			if owner_node is Node3D and owner_node.global_position.distance_to(context.target_world_position) <= spread_radius:
				status.add_seed(spread_amount)
				spread_applied = true
		if spread_applied:
			context.add_effect("seed_spread")


class SpawnOperator extends RuntimeOperator:
	var seed_threshold := 3
	var spawn_power := 10.0

	func _init(threshold: int, power: float) -> void:
		seed_threshold = max(1, threshold)
		spawn_power = maxf(0.1, power)

	func on_hit(context: HitContext) -> void:
		if context.target_status == null:
			return
		if context.target_status.seed_stacks < seed_threshold:
			return
		context.target_status.consume_seed(seed_threshold)
		context.queue_spawn(spawn_power, context.target_status)
		context.add_effect("spawn")


class SummonRunnerFormOperator extends RuntimeOperator:
	func on_hit(context: HitContext) -> void:
		var applied: int = context.apply_form_to_pending_spawns("runner")
		if applied > 0:
			context.add_effect("summon_runner")


class SummonAttachFormOperator extends RuntimeOperator:
	func on_hit(context: HitContext) -> void:
		var applied: int = context.apply_form_to_pending_spawns("attached")
		if applied > 0:
			context.add_effect("summon_attach")


class BurnOperator extends RuntimeOperator:
	var amount := 1

	func _init(value: int) -> void:
		amount = max(1, value)

	func on_hit(context: HitContext) -> void:
		if context.target_status == null:
			return
		context.target_status.add_burn(amount)
		context.add_effect("burn")


class FreezeOperator extends RuntimeOperator:
	var amount := 1

	func _init(value: int) -> void:
		amount = max(1, value)

	func on_hit(context: HitContext) -> void:
		if context.target_status == null:
			return
		context.target_status.add_freeze(amount)
		context.add_effect("freeze")


class ReactorOperator extends RuntimeOperator:
	var reaction_damage := 0.0
	var consume_stacks := 1

	func _init(damage: float, consume: int) -> void:
		reaction_damage = maxf(0.0, damage)
		consume_stacks = max(1, consume)

	func on_hit(context: HitContext) -> void:
		if context.target_status == null:
			return
		var reaction_pairs: int = context.target_status.consume_reactor_pairs(consume_stacks)
		if reaction_pairs <= 0:
			return
		context.damage += float(reaction_pairs) * reaction_damage
		context.add_effect("reactor")


class ChainLightningOperator extends RuntimeOperator:
	var max_jumps := 2
	var first_jump_ratio := 0.55
	var jump_falloff := 0.75
	var chain_range := 6.0

	func _init(jumps: int, first_ratio: float, range_value: float, falloff_value: float = 0.75) -> void:
		max_jumps = max(1, jumps)
		first_jump_ratio = clampf(first_ratio, 0.05, 1.0)
		jump_falloff = clampf(falloff_value, 0.2, 1.0)
		chain_range = maxf(0.5, range_value)

	func on_hit(context: HitContext) -> void:
		if context.target_status == null:
			return
		if context.all_statuses.is_empty():
			return
		var source_pos: Vector3 = context.target_world_position
		var visited: Array[StatusController] = [context.target_status]
		var chain_damage: float = maxf(0.0, context.damage * first_jump_ratio)
		var chained: bool = false
		for jump in range(max_jumps):
			if chain_damage <= 0.01:
				break
			var next_status: StatusController = _find_next_target(context.all_statuses, visited, source_pos)
			if next_status == null:
				break
			var next_pos: Vector3 = _status_world_position(next_status)
			next_status.apply_damage(chain_damage)
			context.queue_chain_arc(
				source_pos,
				next_pos,
				chain_damage,
				jump + 1
			)
			visited.append(next_status)
			source_pos = next_pos
			chain_damage *= jump_falloff
			chained = true
		if chained:
			context.add_effect("chain_lightning")

	func _find_next_target(all_statuses: Array[StatusController], visited: Array[StatusController], source_pos: Vector3) -> StatusController:
		var best: StatusController = null
		var best_dist: float = chain_range
		for status in all_statuses:
			if status == null or status.is_dead() or visited.has(status):
				continue
			var pos: Vector3 = _status_world_position(status)
			var dist: float = source_pos.distance_to(pos)
			if dist < best_dist:
				best_dist = dist
				best = status
		return best

	func _status_world_position(status: StatusController) -> Vector3:
		if status == null:
			return Vector3.ZERO
		var owner_node: Node = status.get_parent()
		if owner_node is Node3D:
			return (owner_node as Node3D).global_position
		return Vector3.ZERO


class DropCoinOperator extends RuntimeOperator:
	var chance := 0.15
	var amount := 1

	func _init(probability: float, value: int) -> void:
		chance = clampf(probability, 0.0, 1.0)
		amount = max(1, value)

	func on_hit(context: HitContext) -> void:
		if randf() <= chance:
			context.pending_coin_gain += amount
			context.add_effect("drop_coin")


class GreedOperator extends RuntimeOperator:
	var amount := 1

	func _init(value: int) -> void:
		amount = max(1, value)

	func on_hit(context: HitContext) -> void:
		if context.target_status == null:
			return
		context.target_status.add_greed(amount)
		context.add_effect("greed")


class CashOutOperator extends RuntimeOperator:
	var coin_per_stack := 1

	func _init(value: int) -> void:
		coin_per_stack = max(1, value)

	func on_kill(context: HitContext) -> void:
		if context.target_status == null:
			return
		var stacks: int = context.target_status.consume_all_greed()
		context.add_effect("cash_out")
		if stacks <= 0:
			return
		context.pending_coin_gain += stacks * coin_per_stack
