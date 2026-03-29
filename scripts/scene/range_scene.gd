extends Node3D
const TargetDummy = preload("res://scripts/combat/target_dummy.gd")
const SeedlingSummon = preload("res://scripts/combat/seedling_summon.gd")
const HubUi = preload("res://scripts/ui/hub_ui.gd")
const FX_GROUP := "runtime_vfx"

@onready var operator_overlay: Control = %OperatorOverlay
@onready var hud: Control = $CanvasLayer/HUD

func _ready() -> void:
	if operator_overlay is HubUi:
		(operator_overlay as HubUi).overlay_close_requested.connect(func() -> void: _set_operator_menu(false))
	_set_operator_menu(false)
	DebugLog.add_entry("RangeScene ready")


func _process(_delta: float) -> void:
	pass


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_operator_menu") and not event.is_echo():
		if GameState.operator_menu_open:
			_request_overlay_close_with_save()
		else:
			_set_operator_menu(true, _event_prefers_gamepad_ui(event))
		return
	if GameState.operator_menu_open:
		return
	if event.is_action_pressed("reset_targets") and not event.is_echo():
		_reset_targets("action")
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F1 or event.physical_keycode == KEY_F1:
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
	var summon_cleared: int = _clear_seedling_summons()
	var fx_cleared: int = _clear_runtime_fx()
	DebugLog.add_entry("Targets reset from %s; count=%d summons_cleared=%d fx_cleared=%d" % [source, count, summon_cleared, fx_cleared])


func _reset_targets_recursive(node: Node, seen: Dictionary, count: int) -> int:
	if node is TargetDummy and not seen.has(node):
		node.reset_dummy()
		seen[node] = true
		count += 1
	for child in node.get_children():
		count = _reset_targets_recursive(child, seen, count)
	return count


func _set_operator_menu(open: bool, prefer_gamepad_ui: bool = false) -> void:
	GameState.set_operator_menu_open(open)
	if operator_overlay != null:
		operator_overlay.visible = open
		if open and operator_overlay.has_method("refresh"):
			operator_overlay.call("refresh")
	if open:
		if hud != null and hud.has_method("reset_ui_pointer_session"):
			hud.call("reset_ui_pointer_session")
		if prefer_gamepad_ui and hud != null and hud.has_method("force_ui_input_mode_gamepad"):
			hud.call("force_ui_input_mode_gamepad")
		else:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			if hud != null and hud.has_method("force_ui_input_mode_mouse"):
				hud.call("force_ui_input_mode_mouse")
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	DebugLog.add_entry("Operator menu: %s" % ("open" if open else "closed"))


func _event_prefers_gamepad_ui(event: InputEvent) -> bool:
	return event is InputEventJoypadButton or event is InputEventJoypadMotion


func _request_overlay_close_with_save() -> void:
	if operator_overlay != null and operator_overlay.has_method("request_overlay_close_with_save"):
		operator_overlay.call("request_overlay_close_with_save")
		return
	_set_operator_menu(false)


func _clear_seedling_summons() -> int:
	var cleared: int = 0
	var seen: Dictionary = {}
	for node in get_tree().get_nodes_in_group("seedling_summon"):
		if node != null and is_instance_valid(node) and not seen.has(node):
			node.queue_free()
			seen[node] = true
			cleared += 1
	var scene: Node = get_tree().current_scene
	if scene != null:
		cleared = _clear_seedling_summons_recursive(scene, seen, cleared)
	return cleared


func _clear_seedling_summons_recursive(node: Node, seen: Dictionary, cleared: int) -> int:
	if node is SeedlingSummon and not seen.has(node):
		node.queue_free()
		seen[node] = true
		cleared += 1
	for child in node.get_children():
		cleared = _clear_seedling_summons_recursive(child, seen, cleared)
	return cleared


func _clear_runtime_fx() -> int:
	var cleared: int = 0
	var seen: Dictionary = {}
	for node in get_tree().get_nodes_in_group(FX_GROUP):
		if node != null and is_instance_valid(node) and not seen.has(node):
			node.queue_free()
			seen[node] = true
			cleared += 1
	var scene: Node = get_tree().current_scene
	if scene != null:
		cleared = _clear_runtime_fx_recursive(scene, seen, cleared)
	return cleared


func _clear_runtime_fx_recursive(node: Node, seen: Dictionary, cleared: int) -> int:
	var node_name: String = node.name
	var is_known_fx: bool = node_name.begins_with("TracerSegment") or node_name.begins_with("ImpactMarker") or node_name.begins_with("SeedHitSpark")
	if is_known_fx and not seen.has(node):
		node.queue_free()
		seen[node] = true
		cleared += 1
	for child in node.get_children():
		cleared = _clear_runtime_fx_recursive(child, seen, cleared)
	return cleared
