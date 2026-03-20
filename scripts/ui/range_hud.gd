extends Control

const HAND_LEFT := "left"
const HAND_RIGHT := "right"

@onready var chain_label: Label = %ChainLabel
@onready var shot_label: Label = %ShotLabel
@onready var performance_label: Label = %PerformanceLabel
@onready var controls_label: Label = $Panel/VBox/ControlsLabel
@onready var debug_panel: Control = $DebugPanel
@onready var target_overlay_layer: Control = $TargetOverlayLayer

var _shooter: Node = null
var _reported_missing_shooter: bool = false
var _left_preview_label: Label = null
var _debug_visible: bool = false


func _ready() -> void:
	%ReturnHubButton.pressed.connect(_return_hub)
	controls_label.text = "左键=左手开火 | 右键=右手开火 | R换弹 | WASD移动 | Shift冲刺 | Space跳跃 | F1重置目标 | Tab背包商店 | F3调试 | Esc切换鼠标"
	_ensure_left_preview_label()
	_set_debug_overlay_visible(false)
	if target_overlay_layer != null:
		target_overlay_layer.visible = true
	_try_bind_shooter()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug_overlay") and not event.is_echo():
		_set_debug_overlay_visible(not _debug_visible)


func _process(delta: float) -> void:
	if _debug_visible:
		var fps: float = Engine.get_frames_per_second()
		var frame_ms: float = delta * 1000.0
		performance_label.text = "帧率: %.0f | 帧耗时: %.2f ms" % [fps, frame_ms]

	if _shooter == null or not is_instance_valid(_shooter):
		_try_bind_shooter()
		if _shooter == null:
			chain_label.text = "左手链: --\n右手链: --\n开火映射: --"
			if _left_preview_label != null:
				_left_preview_label.text = "左手预判: --"
			shot_label.text = "右手预判: --"
			return

	var left_chain: String = "(空)"
	var right_chain: String = "(空)"
	if _shooter.has_method("left_chain_text"):
		left_chain = str(_shooter.call("left_chain_text"))
	if _shooter.has_method("right_chain_text"):
		right_chain = str(_shooter.call("right_chain_text"))
	var trigger_text: String = "左键->左手 右键->右手"
	if _shooter.has_method("trigger_hand_text"):
		trigger_text = str(_shooter.call("trigger_hand_text"))

	chain_label.text = "左手链: %s\n右手链: %s\n开火映射: %s" % [
		_shorten(left_chain, 52),
		_shorten(right_chain, 52),
		trigger_text,
	]

	var left_shot: Variant = null
	var right_shot: Variant = null
	if _shooter.has_method("predict_shot_for_hand"):
		left_shot = _shooter.call("predict_shot_for_hand", HAND_LEFT)
		right_shot = _shooter.call("predict_shot_for_hand", HAND_RIGHT)
	elif _shooter.has_method("predict_next_shot"):
		var fallback: Variant = _shooter.call("predict_next_shot")
		left_shot = fallback
		right_shot = fallback

	var ammo_text: String = ""
	if _shooter.has_method("ammo_status_text"):
		ammo_text = str(_shooter.call("ammo_status_text"))

	if _left_preview_label != null:
		_left_preview_label.text = _format_shot_line("左手预判", left_shot, HAND_LEFT)
	shot_label.text = "%s  %s" % [_format_shot_line("右手预判", right_shot, HAND_RIGHT), ammo_text]


func _try_bind_shooter() -> void:
	var candidate: Node = get_tree().get_first_node_in_group("weapon_shooter")
	if candidate == null:
		candidate = get_node_or_null("../../Player/WeaponShooter")
	if candidate != null and candidate.has_method("current_chain_text"):
		_shooter = candidate
		_reported_missing_shooter = false
		return
	_shooter = null
	if not _reported_missing_shooter:
		_reported_missing_shooter = true
		DebugLog.add_entry("RangeHUD: 未找到 weapon_shooter")


func _ensure_left_preview_label() -> void:
	if _left_preview_label != null and is_instance_valid(_left_preview_label):
		return
	var vbox: Node = chain_label.get_parent()
	if not (vbox is VBoxContainer):
		return
	_left_preview_label = Label.new()
	_left_preview_label.name = "LeftPreviewLabel"
	_left_preview_label.text = "左手预判: --"
	_left_preview_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(_left_preview_label)
	var shot_index: int = shot_label.get_index()
	vbox.move_child(_left_preview_label, shot_index)


func _format_shot_line(prefix: String, shot: Variant, hand: String) -> String:
	if shot == null:
		return "%s: --" % prefix
	var pellets: int = int(shot.get("pellet_count"))
	var spread: float = float(shot.get("spread_angle"))
	var damage: float = float(shot.get("damage"))
	var total_damage: float = float(pellets) * damage
	var phase_hint: String = ""
	if _shooter != null and _shooter.has_method("current_phase_with_role_text_for_hand"):
		var raw_phase: String = str(_shooter.call("current_phase_with_role_text_for_hand", hand))
		if raw_phase != "自由":
			phase_hint = " 相位:%s" % raw_phase
	return "%s  弹体:%d  散布:%.1f°  单弹:%.1f  总计:%.1f%s" % [
		prefix,
		pellets,
		spread,
		damage,
		total_damage,
		phase_hint,
	]


func _set_debug_overlay_visible(visible: bool) -> void:
	_debug_visible = visible
	if performance_label != null:
		performance_label.visible = visible
	if debug_panel != null:
		debug_panel.visible = visible


func _return_hub() -> void:
	if GameState.has_method("save_state"):
		GameState.save_state()
	get_tree().change_scene_to_file("res://scenes/hub_scene.tscn")


func _shorten(value: String, max_len: int) -> String:
	if value.length() <= max_len:
		return value
	return value.substr(0, max_len - 1) + "…"
