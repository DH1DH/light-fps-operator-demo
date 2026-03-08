extends RefCounted
class_name OperatorChain

var _operators: Array[RuntimeOperator] = []
var _definitions: Array[OperatorDefinition] = []

func rebuild(definitions: Array[OperatorDefinition]) -> void:
	_operators.clear()
	_definitions.clear()
	for definition in definitions:
		_definitions.append(definition)
		_operators.append(OperatorFactory.create(definition))


func on_before_fire(context: ShotContext) -> void:
	for operator in _operators:
		operator.on_before_fire(context)


func on_hit(context: HitContext) -> void:
	for operator in _operators:
		operator.on_hit(context)


func describe_order() -> String:
	if _definitions.is_empty():
		return "(empty)"
	return " -> ".join(_definitions.map(func(definition: OperatorDefinition) -> String:
		return definition.display_name if definition != null else "Null"
	))
