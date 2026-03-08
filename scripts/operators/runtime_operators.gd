extends RefCounted

class DuplicateOperator extends RuntimeOperator:
	var multiplier := 1

	func _init(value: int) -> void:
		multiplier = max(1, value)

	func on_before_fire(context: ShotContext) -> void:
		context.pellet_count *= multiplier


class AddOneOperator extends RuntimeOperator:
	var amount := 1

	func _init(value: int) -> void:
		amount = max(1, value)

	func on_before_fire(context: ShotContext) -> void:
		context.pellet_count += amount


class ScatterOperator extends RuntimeOperator:
	var extra_spread := 0.0

	func _init(value: float) -> void:
		extra_spread = maxf(0.0, value)

	func on_before_fire(context: ShotContext) -> void:
		context.spread_angle += extra_spread


class FocusOperator extends RuntimeOperator:
	var reduce_spread := 0.0

	func _init(value: float) -> void:
		reduce_spread = maxf(0.0, value)

	func on_before_fire(context: ShotContext) -> void:
		context.spread_angle = maxf(0.0, context.spread_angle - reduce_spread)


class MarkOnHitOperator extends RuntimeOperator:
	var mark_stacks := 1

	func _init(value: int) -> void:
		mark_stacks = max(1, value)

	func on_hit(context: HitContext) -> void:
		if context.target_status == null:
			return
		context.target_status.add_marks(mark_stacks)


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
