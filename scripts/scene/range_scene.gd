extends Node3D
const TargetDummy = preload("res://scripts/combat/target_dummy.gd")
const HubUi = preload("res://scripts/ui/hub_ui.gd")

@onready var operator_overlay: Control = %OperatorOverlay

func _ready() -> void:
	if operator_overlay is HubUi:
		(operator_overlay as HubUi).overlay_close_requested.connect(func() -> void: _set_operator_menu(false))
	_set_operator_menu(false)
	DebugLog.add_entry("RangeScene ready")


func _process(_delta: float) -> void:
	pass


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_operator_menu") and not event.is_echo():
		_set_operator_menu(not GameState.operator_menu_open)
		return
	if GameState.operator_menu_open:
		return
	if event.is_action_pressed("reset_targets") and not event.is_echo():
		_reset_targets("action")
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R or event.physical_keycode == KEY_R:
			_reset_targets("raw_key")


func _reset_targets(source: String) -> void:
	var count: int = 0
	var seen: Dictionary = {}
	for target in get_tree().get_nodes_in_group("target_dummy"):
		if target is TargetDummy:
			target.reset_dummy()
			seen[target] = true
			count += 1
	count = _reset_targets_recursive(get_tree().current_scene, seen, count)
	DebugLog.add_entry("Targets reset from %s; count=%d" % [source, count])


func _reset_targets_recursive(node: Node, seen: Dictionary, count: int) -> int:
	if node is TargetDummy and not seen.has(node):
		node.reset_dummy()
		seen[node] = true
		count += 1
	for child in node.get_children():
		count = _reset_targets_recursive(child, seen, count)
	return count


func _set_operator_menu(open: bool) -> void:
	GameState.set_operator_menu_open(open)
	if operator_overlay != null:
		operator_overlay.visible = open
		if open and operator_overlay.has_method("refresh"):
			operator_overlay.call("refresh")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED
	DebugLog.add_entry("Operator menu: %s" % ("open" if open else "closed"))
