extends Node

signal state_changed

const OPERATOR_DIR: String = "res://data/operators"
const SAVE_RELATIVE_PATH: String = "data/save/player_save.json"
const OperatorDefinition = preload("res://scripts/operators/operator_definition.gd")
const HAND_LEFT: String = "left"
const HAND_RIGHT: String = "right"

@export var starting_gold: int = 999999

var gold: int = 0
var all_definitions: Array[OperatorDefinition] = []
var loadout_left: Array[OperatorDefinition] = []
var loadout_right: Array[OperatorDefinition] = []
var loadout: Array[OperatorDefinition] = [] # Legacy alias to right-hand queue.
var operator_menu_open: bool = false
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
	_ensure_legacy_alias()
	all_definitions = _load_definitions()
	_seed_free_inventory()
	if not _load_state():
		loadout_left.clear()
		loadout_right.clear()
		_ensure_legacy_alias()
	state_changed.emit()


func get_owned_count(definition: OperatorDefinition) -> int:
	if definition == null:
		return 0
	return _inventory.get(definition.id, 0)


func get_used_count(definition: OperatorDefinition) -> int:
	if definition == null:
		return 0
	return get_used_count_for_hand(definition, HAND_LEFT) + get_used_count_for_hand(definition, HAND_RIGHT)


func get_used_count_for_hand(definition: OperatorDefinition, hand: String) -> int:
	if definition == null:
		return 0
	var count: int = 0
	for item in get_loadout(hand):
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


func add_gold(amount: int) -> void:
	if amount <= 0:
		return
	gold += amount
	state_changed.emit()


func set_operator_menu_open(open: bool) -> void:
	operator_menu_open = open


func add_to_inventory(definition: OperatorDefinition, amount: int) -> void:
	if definition == null or amount <= 0:
		return
	_inventory[definition.id] = get_owned_count(definition) + amount


func add_to_loadout(definition: OperatorDefinition, hand: String = HAND_RIGHT) -> bool:
	if definition == null or get_unslotted_count(definition) <= 0:
		return false
	var target: Array[OperatorDefinition] = get_loadout(hand)
	target.append(definition)
	_ensure_legacy_alias()
	state_changed.emit()
	return true


func remove_loadout_at(index: int, hand: String = HAND_RIGHT) -> void:
	var target: Array[OperatorDefinition] = get_loadout(hand)
	if index < 0 or index >= target.size():
		return
	target.remove_at(index)
	_ensure_legacy_alias()
	state_changed.emit()


func move_loadout(from_index: int, to_index: int, hand: String = HAND_RIGHT) -> void:
	var target: Array[OperatorDefinition] = get_loadout(hand)
	if from_index < 0 or from_index >= target.size():
		return
	if to_index < 0 or to_index >= target.size():
		return
	if from_index == to_index:
		return
	var item: OperatorDefinition = target[from_index]
	target.remove_at(from_index)
	target.insert(to_index, item)
	_ensure_legacy_alias()
	state_changed.emit()


func get_loadout(hand: String = HAND_RIGHT) -> Array[OperatorDefinition]:
	var hand_key: String = _normalize_hand(hand)
	if hand_key == HAND_LEFT:
		return loadout_left
	return loadout_right


func clear_loadout(hand: String = HAND_RIGHT) -> void:
	var target: Array[OperatorDefinition] = get_loadout(hand)
	if target.is_empty():
		return
	target.clear()
	_ensure_legacy_alias()
	state_changed.emit()


func save_state() -> bool:
	var save_path: String = _save_path()
	_ensure_save_directory(save_path)
	var file: FileAccess = FileAccess.open(save_path, FileAccess.WRITE)
	if file == null:
		push_warning("save_state failed: %s" % save_path)
		return false
	var data: Dictionary = {
		"version": 1,
		"gold": gold,
		"inventory": _inventory,
		"loadout_left": _definitions_to_ids(loadout_left),
		"loadout_right": _definitions_to_ids(loadout_right),
	}
	file.store_string(JSON.stringify(data))
	return true


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


func _find_definition_by_id(op_id: String) -> OperatorDefinition:
	for definition in all_definitions:
		if definition != null and definition.id == op_id:
			return definition
	return null


func _normalize_hand(hand: String) -> String:
	if hand.to_lower() == HAND_LEFT:
		return HAND_LEFT
	return HAND_RIGHT


func _ensure_legacy_alias() -> void:
	loadout = loadout_right


func _seed_free_inventory() -> void:
	_inventory.clear()
	for definition in all_definitions:
		if definition == null:
			continue
		var free: int = max(0, definition.free_copies)
		if free > 0:
			_inventory[definition.id] = free


func _load_state() -> bool:
	var save_path: String = _save_path()
	if not FileAccess.file_exists(save_path):
		return false
	var file: FileAccess = FileAccess.open(save_path, FileAccess.READ)
	if file == null:
		return false
	var raw: String = file.get_as_text()
	var parsed: Variant = JSON.parse_string(raw)
	if not (parsed is Dictionary):
		return false
	var data: Dictionary = parsed

	gold = int(data.get("gold", starting_gold))
	_load_inventory_from_data(data.get("inventory", {}))
	loadout_left = _ids_to_definitions(data.get("loadout_left", []))
	loadout_right = _ids_to_definitions(data.get("loadout_right", []))
	_ensure_legacy_alias()
	return true


func _load_inventory_from_data(value: Variant) -> void:
	_inventory.clear()
	if value is Dictionary:
		var source: Dictionary = value
		for key in source.keys():
			var id: String = str(key)
			var amount: int = max(0, int(source.get(key, 0)))
			if _find_definition_by_id(id) != null and amount > 0:
				_inventory[id] = amount
	for definition in all_definitions:
		if definition == null:
			continue
		var free: int = max(0, definition.free_copies)
		if free <= 0:
			continue
		var existing: int = int(_inventory.get(definition.id, 0))
		_inventory[definition.id] = maxi(existing, free)


func _definitions_to_ids(items: Array[OperatorDefinition]) -> Array[String]:
	var ids: Array[String] = []
	for definition in items:
		if definition == null:
			continue
		ids.append(definition.id)
	return ids


func _ids_to_definitions(value: Variant) -> Array[OperatorDefinition]:
	var output: Array[OperatorDefinition] = []
	if not (value is Array):
		return output
	for id_value in value:
		var op_id: String = str(id_value)
		var definition: OperatorDefinition = _find_definition_by_id(op_id)
		if definition != null:
			output.append(definition)
	return output


func _ensure_input_map() -> void:
	_add_key_action("move_forward", KEY_W)
	_add_key_action("move_back", KEY_S)
	_add_key_action("move_left", KEY_A)
	_add_key_action("move_right", KEY_D)
	_add_key_action("sprint", KEY_SHIFT)
	_add_key_action("jump", KEY_SPACE)
	_set_single_key_action("reset_targets", KEY_F1)
	_set_single_key_action("toggle_debug_overlay", KEY_F3)
	_set_single_key_action("reload", KEY_R)
	_add_key_action("toggle_cursor", KEY_ESCAPE)
	_add_key_action("toggle_operator_menu", KEY_TAB)
	_ensure_mouse_action("shoot_left", MOUSE_BUTTON_LEFT)
	_ensure_mouse_action("shoot_right", MOUSE_BUTTON_RIGHT)
	_ensure_joy_axis_action("move_left", JOY_AXIS_LEFT_X, -1.0)
	_ensure_joy_axis_action("move_right", JOY_AXIS_LEFT_X, 1.0)
	_ensure_joy_axis_action("move_forward", JOY_AXIS_LEFT_Y, -1.0)
	_ensure_joy_axis_action("move_back", JOY_AXIS_LEFT_Y, 1.0)
	_ensure_joy_button_action("jump", JOY_BUTTON_A)
	_ensure_joy_button_action("reload", JOY_BUTTON_X)
	_ensure_joy_button_action("sprint", JOY_BUTTON_LEFT_STICK)
	_ensure_joy_button_action("toggle_operator_menu", JOY_BUTTON_START)
	_ensure_joy_button_action("reset_targets", JOY_BUTTON_Y)
	_ensure_joy_button_action("toggle_cursor", JOY_BUTTON_BACK)
	_ensure_joy_axis_action("shoot_left", JOY_AXIS_TRIGGER_LEFT, 1.0)
	_ensure_joy_axis_action("shoot_right", JOY_AXIS_TRIGGER_RIGHT, 1.0)
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


func _set_single_key_action(action_name: String, keycode: Key) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	for existing in InputMap.action_get_events(action_name):
		if existing is InputEventKey:
			InputMap.action_erase_event(action_name, existing)
	var event: InputEventKey = InputEventKey.new()
	event.keycode = keycode
	event.physical_keycode = keycode
	InputMap.action_add_event(action_name, event)


func _ensure_mouse_action(action_name: String, button: MouseButton) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	var event: InputEventMouseButton = InputEventMouseButton.new()
	event.button_index = button
	if not InputMap.action_has_event(action_name, event):
		InputMap.action_add_event(action_name, event)


func _ensure_joy_button_action(action_name: String, button: JoyButton) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	var event := InputEventJoypadButton.new()
	event.button_index = button
	if not InputMap.action_has_event(action_name, event):
		InputMap.action_add_event(action_name, event)


func _ensure_joy_axis_action(action_name: String, axis: JoyAxis, axis_value: float) -> void:
	if not InputMap.has_action(action_name):
		InputMap.add_action(action_name)
	var event := InputEventJoypadMotion.new()
	event.axis = axis
	event.axis_value = axis_value
	if not InputMap.action_has_event(action_name, event):
		InputMap.action_add_event(action_name, event)


func _save_path() -> String:
	return ProjectSettings.globalize_path("res://%s" % SAVE_RELATIVE_PATH)


func _ensure_save_directory(path: String) -> void:
	var base_dir: String = path.get_base_dir()
	if base_dir.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(base_dir)
