extends RefCounted
class_name RuntimeOperator
const ShotContext = preload("res://scripts/operators/shot_context.gd")
const HitContext = preload("res://scripts/operators/hit_context.gd")

func on_fire(_context: ShotContext) -> void:
	pass


func on_hit(_context: HitContext) -> void:
	pass


func on_kill(_context: HitContext) -> void:
	pass
