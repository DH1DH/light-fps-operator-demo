extends Resource
class_name OperatorDefinition

enum OperatorKind {
	DUPLICATE_X2,
	ADD_ONE,
	SCATTER,
	FOCUS,
	MARK,
	MARK_AMPLIFIER,
	EXECUTE,
	CONVERGE,
	SEED,
	SEED_SPREAD,
	SPAWN,
	BURN,
	FREEZE,
	REACTOR,
	DROP_COIN,
	GREED,
	CASH_OUT,
}

@export var id := ""
@export var display_name := ""
@export_multiline var description := ""
@export var cost := 10
@export var free_copies := 1
@export var kind: OperatorKind = OperatorKind.ADD_ONE
@export var int_value := 1
@export var float_value := 1.0
