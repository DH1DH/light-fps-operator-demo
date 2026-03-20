extends RefCounted
class_name OperatorChain
const OperatorDefinition = preload("res://scripts/operators/operator_definition.gd")
const OperatorFactory = preload("res://scripts/operators/operator_factory.gd")
const RuntimeOperator = preload("res://scripts/operators/runtime_operator.gd")
const ShotContext = preload("res://scripts/operators/shot_context.gd")
const HitContext = preload("res://scripts/operators/hit_context.gd")

var _operators: Array[RuntimeOperator] = []
var _definitions: Array[OperatorDefinition] = []
var _phase_filter_enabled: bool = false

enum PhaseBucket {
	FLEX,
	BUILD,
	RESOLVE,
}


func set_phase_filter_enabled(enabled: bool) -> void:
	_phase_filter_enabled = enabled

func rebuild(definitions: Array[OperatorDefinition]) -> void:
	_operators.clear()
	_definitions.clear()
	for definition in definitions:
		_definitions.append(definition)
		_operators.append(OperatorFactory.create(definition))


func on_fire(context: ShotContext) -> void:
	for index in range(_operators.size()):
		if not _allows_phase(_definitions[index], context.phase):
			continue
		_operators[index].on_fire(context)


func on_hit(context: HitContext) -> void:
	for index in range(_operators.size()):
		if not _allows_phase(_definitions[index], context.phase):
			continue
		_operators[index].on_hit(context)


func on_kill(context: HitContext) -> void:
	for index in range(_operators.size()):
		if not _allows_phase(_definitions[index], context.phase):
			continue
		_operators[index].on_kill(context)


func describe_order() -> String:
	if _definitions.is_empty():
		return "(empty)"
	return " -> ".join(_definitions.map(func(definition: OperatorDefinition) -> String:
		return definition.display_name if definition != null else "Null"
	))


func describe_for_phase(phase: int) -> String:
	if _definitions.is_empty():
		return "(empty)"
	var out: Array[String] = []
	for definition in _definitions:
		if not _allows_phase(definition, phase):
			continue
		out.append(definition.display_name if definition != null else "Null")
	if out.is_empty():
		return "(none)"
	return " -> ".join(out)


func _allows_phase(definition: OperatorDefinition, phase: int) -> bool:
	if not _phase_filter_enabled:
		return true
	var bucket: int = _phase_bucket(definition)
	if bucket == PhaseBucket.FLEX:
		return true
	if bucket == PhaseBucket.BUILD:
		return phase == ShotContext.ShotPhase.BUILD
	return phase == ShotContext.ShotPhase.RESOLVE


func _phase_bucket(definition: OperatorDefinition) -> int:
	if definition == null:
		return PhaseBucket.FLEX
	match definition.kind:
		OperatorDefinition.OperatorKind.DUPLICATE_X2, \
		OperatorDefinition.OperatorKind.ADD_ONE, \
		OperatorDefinition.OperatorKind.SCATTER, \
		OperatorDefinition.OperatorKind.FOCUS, \
		OperatorDefinition.OperatorKind.SUMMON_RUNNER, \
		OperatorDefinition.OperatorKind.SUMMON_ATTACH:
			return PhaseBucket.FLEX
		OperatorDefinition.OperatorKind.MARK, \
		OperatorDefinition.OperatorKind.MARK_AMPLIFIER, \
		OperatorDefinition.OperatorKind.SEED, \
		OperatorDefinition.OperatorKind.SEED_SPREAD, \
		OperatorDefinition.OperatorKind.BURN, \
		OperatorDefinition.OperatorKind.FREEZE, \
		OperatorDefinition.OperatorKind.GREED, \
		OperatorDefinition.OperatorKind.DROP_COIN:
			return PhaseBucket.BUILD
		OperatorDefinition.OperatorKind.EXECUTE, \
		OperatorDefinition.OperatorKind.CONVERGE, \
		OperatorDefinition.OperatorKind.SPAWN, \
		OperatorDefinition.OperatorKind.REACTOR, \
		OperatorDefinition.OperatorKind.CASH_OUT, \
		OperatorDefinition.OperatorKind.CHAIN_LIGHTNING:
			return PhaseBucket.RESOLVE
		_:
			return PhaseBucket.FLEX
