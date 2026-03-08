extends RefCounted
class_name OperatorFactory

const RuntimeOperators = preload("res://scripts/operators/runtime_operators.gd")

static func create(definition: OperatorDefinition) -> RuntimeOperator:
	if definition == null:
		return RuntimeOperator.new()

	match definition.kind:
		OperatorDefinition.OperatorKind.DUPLICATE_X2:
			return RuntimeOperators.DuplicateOperator.new(_int_default(definition.int_value, 2))
		OperatorDefinition.OperatorKind.ADD_ONE:
			return RuntimeOperators.AddOneOperator.new(_int_default(definition.int_value, 1))
		OperatorDefinition.OperatorKind.SCATTER:
			return RuntimeOperators.ScatterOperator.new(_float_default(definition.float_value, 2.0))
		OperatorDefinition.OperatorKind.FOCUS:
			return RuntimeOperators.FocusOperator.new(_float_default(definition.float_value, 1.0))
		OperatorDefinition.OperatorKind.MARK_ON_HIT:
			return RuntimeOperators.MarkOnHitOperator.new(_int_default(definition.int_value, 1))
		OperatorDefinition.OperatorKind.EXECUTE:
			return RuntimeOperators.ExecuteOperator.new(_float_default(definition.float_value, 3.0))
		_:
			return RuntimeOperator.new()


static func _int_default(value: int, fallback: int) -> int:
	return fallback if value <= 0 else value


static func _float_default(value: float, fallback: float) -> float:
	return fallback if value <= 0.0 else value
