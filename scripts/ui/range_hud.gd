extends Control

const HAND_LEFT := "left"
const HAND_RIGHT := "right"
const VIRTUAL_UI_MOUSE_DEVICE := -9001

@onready var chain_label: Label = %ChainLabel
@onready var shot_label: Label = %ShotLabel
@onready var performance_label: Label = %PerformanceLabel
@onready var controls_label: Label = $Panel/VBox/ControlsLabel
@onready var debug_panel: Control = $DebugPanel
@onready var target_overlay_layer: Control = $TargetOverlayLayer
@onready var crosshair: Control = $Crosshair

var _shooter: Node = null
var _player_controller: Node = null
var _reported_missing_shooter: bool = false
var _left_preview_label: Label = null
var _debug_visible: bool = false
var _sprint_energy_holder: Control = null
var _sprint_energy_bg: ColorRect = null
var _sprint_energy_fill: ColorRect = null
var _gamepad_ui_cursor: Panel = null
var _gamepad_ui_cursor_pos: Vector2 = Vector2.ZERO
var _last_virtual_mouse_pos: Vector2 = Vector2.ZERO
var _last_warped_mouse_position: Vector2 = Vector2.ZERO
var _ignore_warped_mouse_motion_until_msec: int = 0
var _gamepad_ui_cursor_active: bool = false
var _gamepad_ui_dragging: bool = false
var _ui_using_gamepad_cursor: bool = false
const GAMEPAD_UI_CURSOR_SPEED: float = 900.0
const GAMEPAD_UI_CURSOR_DEADZONE: float = 0.22


func _ready() -> void:
	%ReturnHubButton.pressed.connect(_return_hub)
	controls_label.text = "键鼠: 左键/右键开火 | R装弹 | WASD移动 | Shift冲刺 | Space跳跃 | Tab背包 | F1重置 | F3调试 | Esc鼠标 | 手柄: LT/RT开火 | LS移动/按下冲刺 | RS视角 | A跳跃 | X装弹 | Start背包 | Y重置 | Back鼠标"
	_ensure_left_preview_label()
	_ensure_sprint_energy_bar()
	_set_debug_overlay_visible(false)
	if target_overlay_layer != null:
		target_overlay_layer.visible = true
	_try_bind_shooter()
	_try_bind_player_controller()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug_overlay") and not event.is_echo():
		_set_debug_overlay_visible(not _debug_visible)
	if not GameState.operator_menu_open:
		return
	if event is InputEventMouseMotion:
		var mouse_motion: InputEventMouseMotion = event
		if mouse_motion.device == VIRTUAL_UI_MOUSE_DEVICE:
			return
		if _should_ignore_warped_mouse_event(mouse_motion.position):
			return
		if mouse_motion.relative.length() > 0.0:
			_set_ui_input_mode_mouse()
	if event is InputEventMouseButton:
		var mouse_button: InputEventMouseButton = event
		if mouse_button.device == VIRTUAL_UI_MOUSE_DEVICE:
			return
		if _should_ignore_warped_mouse_event(mouse_button.position):
			return
		if mouse_button.pressed:
			_set_ui_input_mode_mouse()
	if event is InputEventJoypadMotion:
		var joy_motion: InputEventJoypadMotion = event
		if absf(joy_motion.axis_value) >= GAMEPAD_UI_CURSOR_DEADZONE:
			_set_ui_input_mode_gamepad()
	if event is InputEventJoypadButton:
		var joy_button: InputEventJoypadButton = event
		if joy_button.pressed or joy_button.button_index == JOY_BUTTON_A:
			_set_ui_input_mode_gamepad()
	if _ui_using_gamepad_cursor and event.is_action_pressed("jump") and not event.is_echo():
		_press_gamepad_ui_cursor()
	if _ui_using_gamepad_cursor and event.is_action_released("jump") and not event.is_echo():
		_release_gamepad_ui_cursor()


func _process(delta: float) -> void:
	if _debug_visible:
		var fps: float = Engine.get_frames_per_second()
		var frame_ms: float = delta * 1000.0
		performance_label.text = "帧率: %.0f | 帧耗时: %.2f ms" % [fps, frame_ms]

	_update_gamepad_ui_cursor(delta)
	_update_sprint_energy_bar()
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
	var trigger_text: String = "左键->左手  右键->右手"
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


func _try_bind_player_controller() -> void:
	var candidate: Node = get_node_or_null("../../Player")
	if candidate != null and candidate.has_method("get_sprint_energy_ratio"):
		_player_controller = candidate
		return
	_player_controller = null


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


func _ensure_sprint_energy_bar() -> void:
	if _sprint_energy_bg != null and is_instance_valid(_sprint_energy_bg):
		return
	var holder := Control.new()
	holder.name = "SprintEnergyHolder"
	holder.anchor_left = 0.5
	holder.anchor_top = 0.5
	holder.anchor_right = 0.5
	holder.anchor_bottom = 0.5
	holder.offset_left = -42.0
	holder.offset_top = 16.0
	holder.offset_right = 42.0
	holder.offset_bottom = 21.0
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.z_index = -50
	add_child(holder)
	_sprint_energy_holder = holder
	var overlay: Control = get_node_or_null("OperatorOverlay")
	if overlay != null:
		move_child(holder, overlay.get_index())

	var border := Panel.new()
	border.name = "SprintEnergyBorder"
	border.anchor_left = 0.0
	border.anchor_top = 0.0
	border.anchor_right = 1.0
	border.anchor_bottom = 1.0
	border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var border_style := StyleBoxFlat.new()
	border_style.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	border_style.draw_center = false
	border_style.border_width_left = 1
	border_style.border_width_top = 1
	border_style.border_width_right = 1
	border_style.border_width_bottom = 1
	border_style.border_color = Color(0.0, 0.0, 0.0, 0.95)
	border.add_theme_stylebox_override("panel", border_style)

	_sprint_energy_bg = ColorRect.new()
	_sprint_energy_bg.name = "SprintEnergyBg"
	_sprint_energy_bg.anchor_left = 0.0
	_sprint_energy_bg.anchor_top = 0.0
	_sprint_energy_bg.anchor_right = 1.0
	_sprint_energy_bg.anchor_bottom = 1.0
	_sprint_energy_bg.offset_left = 1.0
	_sprint_energy_bg.offset_top = 1.0
	_sprint_energy_bg.offset_right = -1.0
	_sprint_energy_bg.offset_bottom = -1.0
	_sprint_energy_bg.color = Color(0.34, 0.34, 0.34, 0.9)
	_sprint_energy_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(_sprint_energy_bg)

	_sprint_energy_fill = ColorRect.new()
	_sprint_energy_fill.name = "SprintEnergyFill"
	_sprint_energy_fill.anchor_left = 0.0
	_sprint_energy_fill.anchor_top = 0.0
	_sprint_energy_fill.anchor_right = 1.0
	_sprint_energy_fill.anchor_bottom = 1.0
	_sprint_energy_fill.color = Color(0.96, 0.96, 0.96, 0.95)
	_sprint_energy_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(_sprint_energy_fill)
	holder.add_child(border)


func _ensure_gamepad_ui_cursor() -> void:
	if _gamepad_ui_cursor != null and is_instance_valid(_gamepad_ui_cursor):
		return
	_gamepad_ui_cursor = Panel.new()
	_gamepad_ui_cursor.name = "GamepadUiCursor"
	_gamepad_ui_cursor.visible = false
	_gamepad_ui_cursor.size = Vector2(18.0, 18.0)
	_gamepad_ui_cursor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gamepad_ui_cursor.z_index = 3000
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	style.draw_center = false
	style.border_color = Color(1.0, 1.0, 1.0, 0.96)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 9
	style.corner_radius_top_right = 9
	style.corner_radius_bottom_left = 9
	style.corner_radius_bottom_right = 9
	_gamepad_ui_cursor.add_theme_stylebox_override("panel", style)
	add_child(_gamepad_ui_cursor)


func _update_gamepad_ui_cursor(delta: float) -> void:
	_ensure_gamepad_ui_cursor()
	if _gamepad_ui_cursor == null:
		return
	var should_show: bool = GameState.operator_menu_open and not Input.get_connected_joypads().is_empty()
	if not should_show:
		_release_gamepad_ui_cursor()
		_gamepad_ui_cursor.visible = false
		_gamepad_ui_cursor_active = false
		_ui_using_gamepad_cursor = false
		return
	if not _gamepad_ui_cursor_active:
		var viewport_size: Vector2 = get_viewport_rect().size
		_gamepad_ui_cursor_pos = viewport_size * 0.5
		_last_virtual_mouse_pos = _gamepad_ui_cursor_pos
		_gamepad_ui_cursor_active = true
	if not _ui_using_gamepad_cursor:
		_gamepad_ui_cursor.visible = false
		return
	if Input.mouse_mode != Input.MOUSE_MODE_HIDDEN:
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	var device_id: int = Input.get_connected_joypads()[0]
	var move_vec := Vector2(
		Input.get_joy_axis(device_id, JOY_AXIS_LEFT_X),
		Input.get_joy_axis(device_id, JOY_AXIS_LEFT_Y)
	)
	if move_vec.length() < GAMEPAD_UI_CURSOR_DEADZONE:
		move_vec = Vector2.ZERO
	else:
		var strength: float = inverse_lerp(GAMEPAD_UI_CURSOR_DEADZONE, 1.0, minf(1.0, move_vec.length()))
		move_vec = move_vec.normalized() * strength
	_gamepad_ui_cursor_pos += move_vec * GAMEPAD_UI_CURSOR_SPEED * delta
	var viewport_rect: Rect2 = get_viewport_rect()
	_gamepad_ui_cursor_pos.x = clampf(_gamepad_ui_cursor_pos.x, 0.0, viewport_rect.size.x)
	_gamepad_ui_cursor_pos.y = clampf(_gamepad_ui_cursor_pos.y, 0.0, viewport_rect.size.y)
	_gamepad_ui_cursor.visible = true
	_gamepad_ui_cursor.position = _gamepad_ui_cursor_pos - _gamepad_ui_cursor.size * 0.5
	_emit_virtual_mouse_motion(_gamepad_ui_cursor_pos)


func _emit_virtual_mouse_motion(pos: Vector2) -> void:
	_last_warped_mouse_position = pos
	_ignore_warped_mouse_motion_until_msec = Time.get_ticks_msec() + 80
	Input.warp_mouse(pos)
	var motion := InputEventMouseMotion.new()
	motion.device = VIRTUAL_UI_MOUSE_DEVICE
	motion.position = pos
	motion.global_position = pos
	motion.relative = pos - _last_virtual_mouse_pos
	if _gamepad_ui_dragging:
		motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	_last_virtual_mouse_pos = pos
	Input.parse_input_event(motion)


func _should_ignore_warped_mouse_event(pos: Vector2) -> bool:
	if not _ui_using_gamepad_cursor:
		return false
	if Time.get_ticks_msec() > _ignore_warped_mouse_motion_until_msec:
		return false
	return pos.distance_to(_last_warped_mouse_position) <= 2.0


func _press_gamepad_ui_cursor() -> void:
	if _gamepad_ui_dragging:
		return
	_gamepad_ui_dragging = true
	var pos: Vector2 = _gamepad_ui_cursor_pos
	var press := InputEventMouseButton.new()
	press.device = VIRTUAL_UI_MOUSE_DEVICE
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = pos
	press.global_position = pos
	Input.parse_input_event(press)
	_emit_virtual_mouse_motion(pos)


func _release_gamepad_ui_cursor() -> void:
	if not _gamepad_ui_dragging:
		return
	_gamepad_ui_dragging = false
	var pos: Vector2 = _gamepad_ui_cursor_pos
	var release := InputEventMouseButton.new()
	release.device = VIRTUAL_UI_MOUSE_DEVICE
	release.button_index = MOUSE_BUTTON_LEFT
	release.pressed = false
	release.position = pos
	release.global_position = pos
	Input.parse_input_event(release)


func _set_ui_input_mode_mouse() -> void:
	_ui_using_gamepad_cursor = false
	if _gamepad_ui_cursor != null:
		_gamepad_ui_cursor.visible = false
	_release_gamepad_ui_cursor()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _set_ui_input_mode_gamepad() -> void:
	if not GameState.operator_menu_open:
		return
	_ui_using_gamepad_cursor = true
	if _gamepad_ui_cursor != null:
		_gamepad_ui_cursor.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN


func force_ui_input_mode_gamepad() -> void:
	_set_ui_input_mode_gamepad()


func force_ui_input_mode_mouse() -> void:
	_set_ui_input_mode_mouse()


func _update_sprint_energy_bar() -> void:
	if _sprint_energy_bg == null or _sprint_energy_fill == null:
		return
	if _player_controller == null or not is_instance_valid(_player_controller):
		_try_bind_player_controller()
		if _player_controller == null:
			return
	var ratio: float = 0.0
	if _player_controller.has_method("get_sprint_energy_ratio"):
		ratio = float(_player_controller.call("get_sprint_energy_ratio"))
	var overloaded: bool = false
	if _player_controller.has_method("is_sprint_overloaded"):
		overloaded = bool(_player_controller.call("is_sprint_overloaded"))
	_sprint_energy_bg.color = Color(0.65, 0.16, 0.16, 0.95) if overloaded else Color(0.34, 0.34, 0.34, 0.9)
	if overloaded:
		var flash_t: float = Time.get_ticks_msec() / 1000.0
		var flash_alpha: float = 0.45 + 0.53 * (0.5 + 0.5 * sin(flash_t * 14.4))
		_sprint_energy_fill.color = Color(0.96, 0.84, 0.2, flash_alpha)
	else:
		_sprint_energy_fill.color = Color(0.96, 0.96, 0.96, 0.95)
	_sprint_energy_fill.anchor_right = clampf(ratio, 0.0, 1.0)


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
	return value.substr(0, max_len - 3) + "..."
