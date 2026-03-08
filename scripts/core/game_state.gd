extends Node

signal state_changed

const OPERATOR_DIR: String = "res://data/operators"

@export var starting_gold: int = 200

var gold: int = 0
var all_definitions: Array[OperatorDefinition] = []
var loadout: Array[OperatorDefinition] = []
var _inventory: Dictionary = {}
var _initialized: bool = false

func _ready() -> void:
	_ensure_input_map()
	initialize_if_needed()


func initialize_if_needed() -> void:
	if _initialized:
		return
	_initialized = true
	gold = starting_gold
	all_definitions = _load_definitions()
	for definition in all_definitions:
		var free: int = max(0, definition.free_copies)
		if free > 0:
			_inventory[definition.id] = free
	_seed_default_loadout()
	state_changed.emit()


func get_owned_count(definition: OperatorDefinition) -> int:
	if definition == null:
		return 0
	return _inventory.get(definition.id, 0)


func get_used_count(definition: OperatorDefinition) -> int:
	if definition == null:
		return 0
	var count: int = 0
	for item in loadout:
		if item == definition:
			count += 1
	return count


func get_unslotted_count(definition: OperatorDefinition) -> int:
	return max(0, get_owned_count(definition) - get_used_count(definition))


func buy_operator(definition: OperatorDefinition) -> bool:
	if definition == null or gold < definition.cost:
		return false
	gold -= definition.cost
	add_to_inventory(definition, 1)
	state_changed.emit()
	return true


func add_to_inventory(definition: OperatorDefinition, amount: int) -> void:
	if definition == null or amount <= 0:
		return
	_inventory[definition.id] = get_owned_count(definition) + amount


func add_to_loadout(definition: OperatorDefinition) -> bool:
	if definition == null or get_unslotted_count(definition) <= 0:
		return false
	loadout.append(definition)
	state_changed.emit()
	return true


func remove_loadout_at(index: int) -> void:
	if index < 0 or index >= loadout.size():
		return
	loadout.remove_at(index)
	state_changed.emit()


func move_loadout(from_index: int, to_index: int) -> void:
	if from_index < 0 or from_index >= loadout.size():
		return
	if to_index < 0 or to_index >= loadout.size():
		return
	if from_index == to_index:
		return
	var item: OperatorDefinition = loadout[from_index]
	loadout.remove_at(from_index)
	loadout.insert(to_index, item)
	state_changed.emit()


func _load_definitions() -> Array[OperatorDefinition]:
	var definitions: Array[OperatorDefinition] = []
	var dir: DirAccess = DirAccess.open(OPERATOR_DIR)
	if dir == null:
		return definitions
	dir.list_dir_begin()
	while true:
		var file_name: String = dir.get_next()
		if file_name.is_empty():
			break
		if dir.current_is_dir() or not file_name.ends_with(".tres"):
			continue
		var definition: OperatorDefinition = load("%s/%s" % [OPERATOR_DIR, file_name]) as OperatorDefinition
		if definition != null:
			definitions.append(definition)
	dir.list_dir_end()
	definitions.sort_custom(func(a: OperatorDefinition, b: OperatorDefinition) -> bool:
		return a.display_name.naturalnocasecmp_to(b.display_name) < 0
	)
	return definitions


func _seed_default_loadout() -> void:
	if not loadout.is_empty():
		return
	for definition in all_definitions:
		if get_unslotted_count(definition) > 0:
			loadout.append(definition)
			return


func _ensure_input_map() -> void:
	_add_key_action("move_forward", KEY_W)
	_add_key_action("move_back", KEY_S)
	_add_key_action("move_left", KEY_A)
	_add_key_action("move_right", KEY_D)
	_add_key_action("reset_targets", KEY_R)
	_add_key_action("toggle_cursor", KEY_ESCAPE)
	if not InputMap.has_action("shoot"):
		InputMap.add_action("shoot")
	var mouse: InputEventMouseButton = InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	if not InputMap.action_has_event("shoot", mouse):
		InputMap.action_add_event("shoot", mouse)


func _add_key_action(action_name: String, keycode: Key) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	var event: InputEventKey = InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	if not InputMap.action_has_event(action_name, event):
		InputMap.action_add_event(action_name, event)
