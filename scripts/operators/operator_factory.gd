extends RefCounted
class_name OperatorFactory

const RuntimeOperators = preload("res://scripts/operators/runtime_operators.gd")
const OperatorDefinition = preload("res://scripts/operators/operator_definition.gd")
const RuntimeOperator = preload("res://scripts/operators/runtime_operator.gd")

static func create(definition: OperatorDefinition) -> RuntimeOperator:
	if definition == null:
		return RuntimeOperator.new()

	match definition.kind:
		OperatorDefinition.OperatorKind.DUPLICATE_X2:
			return RuntimeOperators.DuplicateOperator.new(_int_default(definition.int_value, 2))
		OperatorDefinition.OperatorKind.ADD_ONE:
			return RuntimeOperators.AddOneOperator.new(_int_default(definition.int_value, 1))
		OperatorDefinition.OperatorKind.SCATTER:
			return RuntimeOperators.ScatterOperator.new(_float_default(definition.float_value, 8.0))
		OperatorDefinition.OperatorKind.FOCUS:
			return RuntimeOperators.FocusOperator.new(_float_default(definition.float_value, 0.2))
		OperatorDefinition.OperatorKind.MARK:
			return RuntimeOperators.MarkOperator.new(_int_default(definition.int_value, 1))
		OperatorDefinition.OperatorKind.MARK_AMPLIFIER:
			return RuntimeOperators.MarkAmplifierOperator.new(_int_default(definition.int_value, 1))
		OperatorDefinition.OperatorKind.EXECUTE:
			return RuntimeOperators.ExecuteOperator.new(_float_default(definition.float_value, 12.0))
		OperatorDefinition.OperatorKind.CONVERGE:
			return RuntimeOperators.ConvergeOperator.new(_float_default(definition.float_value, 8.0))
		OperatorDefinition.OperatorKind.SEED:
			return RuntimeOperators.SeedOperator.new(_int_default(definition.int_value, 1))
		OperatorDefinition.OperatorKind.SEED_SPREAD:
			return RuntimeOperators.SeedSpreadOperator.new(_float_default(definition.float_value, 5.0), _int_default(definition.int_value, 1))
		OperatorDefinition.OperatorKind.SPAWN:
			return RuntimeOperators.SpawnOperator.new(_int_default(definition.int_value, 3), _float_default(definition.float_value, 10.0))
		OperatorDefinition.OperatorKind.BURN:
			return RuntimeOperators.BurnOperator.new(_int_default(definition.int_value, 1))
		OperatorDefinition.OperatorKind.FREEZE:
			return RuntimeOperators.FreezeOperator.new(_int_default(definition.int_value, 1))
		OperatorDefinition.OperatorKind.REACTOR:
			return RuntimeOperators.ReactorOperator.new(_float_default(definition.float_value, 16.0), _int_default(definition.int_value, 1))
		OperatorDefinition.OperatorKind.DROP_COIN:
			return RuntimeOperators.DropCoinOperator.new(_float_default(definition.float_value, 0.15), _int_default(definition.int_value, 1))
		OperatorDefinition.OperatorKind.GREED:
			return RuntimeOperators.GreedOperator.new(_int_default(definition.int_value, 1))
		OperatorDefinition.OperatorKind.CASH_OUT:
			return RuntimeOperators.CashOutOperator.new(_int_default(definition.int_value, 2))
		OperatorDefinition.OperatorKind.CHAIN_LIGHTNING:
			return RuntimeOperators.ChainLightningOperator.new(
				_int_default(definition.int_value, 2),
				_float_default(definition.float_value, 0.55),
				5.6,
				0.75
			)
		OperatorDefinition.OperatorKind.SUMMON_RUNNER:
			return RuntimeOperators.SummonRunnerFormOperator.new()
		OperatorDefinition.OperatorKind.SUMMON_ATTACH:
			return RuntimeOperators.SummonAttachFormOperator.new()
		_:
			return RuntimeOperator.new()


static func _int_default(value: int, fallback: int) -> int:
	return fallback if value <= 0 else value


static func _float_default(value: float, fallback: float) -> float:
	return fallback if value <= 0.0 else value
