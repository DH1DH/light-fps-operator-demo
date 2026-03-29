extends Control

const OperatorDefinition = preload("res://scripts/operators/operator_definition.gd")
const OperatorListController = preload("res://scripts/ui/operator_list_controller.gd")
const HAND_LEFT := "left"
const HAND_RIGHT := "right"
const DRAG_HOLD_SECONDS: float = 0.22
const DRAG_FLOAT_OFFSET: Vector2 = Vector2(16.0, 14.0)
const LOADOUT_INDEX_WIDTH: float = 38.0
const LOADOUT_ROW_HEIGHT: float = 34.0
const TOOLTIP_CONFIRM_FRAMES: int = 3

signal overlay_close_requested

@export var overlay_mode: bool = false

const SPECIAL_FIELD_DOCS: Array[Dictionary] = [
	{"token": "OnFire", "label": "开火时", "display": "开火时", "doc": "开火时触发，修改本次射击参数。", "color": "#F6C764"},
	{"token": "OnHit", "label": "命中时", "display": "命中时", "doc": "命中时触发，结算命中上下文。", "color": "#FF9F5A"},
	{"token": "OnKill", "label": "击杀时", "display": "击杀时", "doc": "击杀时触发，常用于奖励结算。", "color": "#FF7F8A"},
	{"token": "ShotContext", "label": "ShotContext", "doc": "单次开火上下文，包含弹体、散布、伤害等。", "color": "#8ED2FF"},
	{"token": "HitContext", "label": "HitContext", "doc": "单次命中上下文，包含目标状态与附加结算。", "color": "#82C8FF"},
	{"token": "TargetStatus", "label": "TargetStatus", "doc": "目标状态容器，维护印记与异常层数。", "color": "#72B8FF"},
	{"token": "弹体", "label": "弹体", "doc": "一次开火生成的子弹数量。", "color": "#FFE082"},
	{"token": "散布", "label": "散布", "doc": "子弹偏离中心线的角度范围。", "color": "#FFD580"},
	{"token": "印记", "label": "印记", "doc": "用于清算爆发伤害的层数资源。", "color": "#E3A6FF"},
	{"token": "种子", "label": "种子", "doc": "召唤流资源，达到阈值可触发孵化。", "color": "#8DE57A"},
	{"token": "孵化", "label": "孵化", "doc": "消耗种子生成召唤物。", "color": "#7CDB6E"},
	{"token": "召唤", "label": "召唤", "doc": "生成临时单位协同作战。", "color": "#6ED2FF"},
	{"token": "附着", "label": "附着", "doc": "召唤物贴附目标执行持续攻击。", "color": "#6FB8FF"},
	{"token": "跑地", "label": "跑地", "doc": "召唤物在地面追击目标。", "color": "#9BC6FF"},
	{"token": "灼烧", "label": "灼烧", "doc": "持续伤害异常层数。", "color": "#FF8066"},
	{"token": "冻结", "label": "冻结", "doc": "控制类异常层数，可与灼烧触发反应。", "color": "#79D9FF"},
	{"token": "反应", "label": "反应", "doc": "灼烧与冻结并存时触发额外伤害。", "color": "#FFC7F0"},
	{"token": "贪婪", "label": "贪婪", "doc": "经济层数，常用于击杀结算金币。", "color": "#F6E17A"},
	{"token": "金币", "label": "金币", "doc": "资源货币，可用于商店购买算子。", "color": "#FFD768"},
	{"token": "电链", "label": "电链", "doc": "命中后向附近敌人跳链，只传递衰减伤害。", "color": "#FFD548"},
]

const DESCRIPTION_TEMPLATE_BY_ID: Dictionary = {
	"duplicate_x2": "OnFire：本次开火的弹体数量×2。",
	"add_one": "OnFire：本次开火的弹体数量+1。",
	"scatter": "OnFire：将散布固定为8°，扩大覆盖范围。",
	"focus": "OnFire：将散布×0.2，使弹道更集中。",
	"mark": "OnHit：对目标施加印记+1。",
	"mark_amplifier": "OnHit：若目标已有印记，额外施加印记+1。",
	"execute": "OnHit：消耗目标全部印记，按层数造成爆发伤害。",
	"converge": "OnHit：按1/弹体提升额外伤害，弹体越少越高。",
	"seed": "OnHit：对目标施加种子+1。",
	"seed_spread": "OnHit：若目标已有种子，向附近目标扩散种子+1。",
	"spawn": "OnHit：当种子达到阈值时触发孵化，生成召唤并消耗种子。",
	"burn": "OnHit：对目标施加灼烧+1。",
	"freeze": "OnHit：对目标施加冻结+1。",
	"reactor": "OnHit：若目标同时有灼烧与冻结，触发反应伤害并消耗部分层数。",
	"drop_coin": "OnHit：有概率获得金币。",
	"greed": "OnHit：对目标施加贪婪+1。",
	"cash_out": "OnKill：按目标贪婪层数结算金币并清空贪婪。",
	"chain_lightning": "OnHit：释放黄色电链，跳向附近敌人并造成衰减伤害（仅传递伤害）。",
	"summon_attach": "OnHit：若本次命中触发孵化，将本次召唤改为附着形态（建议放在孵化后）。",
	"summon_runner": "OnHit：若本次命中触发孵化，将本次召唤改为跑地形态（建议放在孵化后）。",
}

@onready var gold_label: Label = %GoldLabel
@onready var inventory_list: VBoxContainer = %InventoryList
@onready var shop_list: VBoxContainer = %ShopList
@onready var loadout_list: VBoxContainer = %LoadoutList
@onready var enter_range_button: Button = %EnterRangeButton
@onready var hint_label: Label = $Margin/Root/Hint
@onready var backdrop: ColorRect = $Backdrop

var _tooltip_panel: PanelContainer
var _tooltip_scroll: ScrollContainer
var _tooltip_content: VBoxContainer
var _tooltip_title: Label
var _current_tooltip_operator_id: String = ""
var _tooltip_font_regular: SystemFont
var _tooltip_font_bold: SystemFont
var _preserve_tooltip_during_refresh: bool = false
var _tooltip_hover_candidate_id: String = ""
var _tooltip_hover_frames: int = 0
var _tooltip_absent_frames: int = 0

var _save_tip: Label
var _closing_with_save: bool = false

var _drag_candidate_active: bool = false
var _drag_candidate_hand: String = ""
var _drag_candidate_index: int = -1
var _drag_candidate_definition: OperatorDefinition = null
var _drag_candidate_start_time: float = 0.0
var _drag_candidate_start_mouse: Vector2 = Vector2.ZERO
var _ui_pointer_position: Vector2 = Vector2.ZERO
var _ui_pointer_has_position: bool = false
var _ui_pointer_left_pressed: bool = false

var _drag_active: bool = false
var _drag_hand: String = ""
var _drag_from_index: int = -1
var _drag_to_index: int = -1
var _drag_floating: PanelContainer
var _drag_floating_label: Label
var _drag_rows_by_hand: Dictionary = {HAND_LEFT: [], HAND_RIGHT: []}
var _drag_floating_anchor_x: float = 0.0
var _drag_floating_min_y: float = 0.0
var _drag_floating_max_y: float = 0.0


func _ready() -> void:
	GameState.initialize_if_needed()
	GameState.state_changed.connect(refresh)
	if overlay_mode:
		enter_range_button.text = "关闭（Tab）"
		enter_range_button.pressed.connect(request_overlay_close_with_save)
		hint_label.text = "长按算子可拖动排序，按 Tab 关闭并保存。"
		backdrop.color = Color(0.05, 0.07, 0.1, 0.86)
	else:
		enter_range_button.text = "进入靶场"
		enter_range_button.pressed.connect(_enter_range)
		hint_label.text = "长按并拖动算子可调整顺序。"
	_setup_tooltip_fonts()
	_setup_tooltip_panel()
	_setup_save_tip()
	refresh()


func _process(_delta: float) -> void:
	_update_drag_state()
	_update_tooltip_visibility_state()
	if _tooltip_panel != null and _tooltip_panel.visible:
		_position_tooltip(_get_ui_pointer_position())


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event
		_ui_pointer_position = motion.position
		_ui_pointer_has_position = true
		if _tooltip_panel != null and _tooltip_panel.visible:
			_position_tooltip(motion.position)
	elif event is InputEventMouseButton:
		var mouse_button: InputEventMouseButton = event
		_ui_pointer_position = mouse_button.position
		_ui_pointer_has_position = true
		if mouse_button.button_index == MOUSE_BUTTON_LEFT:
			_ui_pointer_left_pressed = mouse_button.pressed
			if mouse_button.pressed and not _closing_with_save and not _drag_active:
				var hovered: Control = get_viewport().gui_get_hovered_control()
				var drag_payload: Dictionary = _drag_payload_from_control(hovered)
				if not drag_payload.is_empty():
					_start_drag_candidate(
						str(drag_payload.get("hand", "")),
						int(drag_payload.get("index", -1)),
						drag_payload.get("definition", null) as OperatorDefinition
					)


func _exit_tree() -> void:
	if GameState.state_changed.is_connected(refresh):
		GameState.state_changed.disconnect(refresh)


func refresh() -> void:
	gold_label.text = "金币：%d" % GameState.gold
	_rebuild_inventory()
	_rebuild_shop()
	_rebuild_loadout()


func request_overlay_close_with_save() -> void:
	if not overlay_mode:
		return
	if _closing_with_save:
		return
	_closing_with_save = true
	_cancel_drag_interaction()
	_set_save_tip("保存中...")
	call_deferred("_save_then_close_async")


func _save_then_close_async() -> void:
	await get_tree().process_frame
	var ok: bool = false
	if GameState.has_method("save_state"):
		ok = bool(GameState.call("save_state"))
	_set_save_tip("保存完成" if ok else "保存失败")
	await get_tree().create_timer(0.15).timeout
	_set_save_tip("")
	_closing_with_save = false
	overlay_close_requested.emit()


func _rebuild_inventory() -> void:
	_clear_children(inventory_list)
	for definition in GameState.all_definitions:
		var row: HBoxContainer = _create_basic_row(
			"%s  持有:%d  可装:%d" % [definition.display_name, GameState.get_owned_count(definition), GameState.get_unslotted_count(definition)],
			definition
		)

		var add_left_button: Button = Button.new()
		add_left_button.text = "装左"
		add_left_button.disabled = GameState.get_unslotted_count(definition) <= 0
		add_left_button.pressed.connect(func() -> void:
			GameState.add_to_loadout(definition, HAND_LEFT)
		)
		row.add_child(add_left_button)

		var add_right_button: Button = Button.new()
		add_right_button.text = "装右"
		add_right_button.disabled = GameState.get_unslotted_count(definition) <= 0
		add_right_button.pressed.connect(func() -> void:
			GameState.add_to_loadout(definition, HAND_RIGHT)
		)
		row.add_child(add_right_button)

		inventory_list.add_child(row)


func _rebuild_shop() -> void:
	_clear_children(shop_list)
	for definition in GameState.all_definitions:
		var row: HBoxContainer = _create_basic_row("%s  价格:%d" % [definition.display_name, definition.cost], definition)
		var buy_button: Button = Button.new()
		buy_button.text = "购买"
		buy_button.disabled = GameState.gold < definition.cost
		buy_button.pressed.connect(func() -> void:
			GameState.buy_operator(definition)
		)
		row.add_child(buy_button)
		shop_list.add_child(row)


func _rebuild_loadout() -> void:
	_clear_children(loadout_list)
	_add_loadout_section_new("左手队列", HAND_LEFT)
	var separator := HSeparator.new()
	loadout_list.add_child(separator)
	_add_loadout_section_new("右手队列", HAND_RIGHT)

	var hint: Label = Label.new()
	hint.text = "按住并拖动算子卡片可实时重排。"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	loadout_list.add_child(hint)


func _add_loadout_section_new(title: String, hand: String) -> void:
	var title_label := Label.new()
	title_label.text = title
	loadout_list.add_child(title_label)

	var hand_loadout: Array[OperatorDefinition] = _get_loadout_by_hand(hand)
	if hand_loadout.is_empty():
		var empty_label := Label.new()
		empty_label.text = "（空）"
		loadout_list.add_child(empty_label)
		return

	var list_controller := OperatorListController.new()
	list_controller.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_controller.custom_minimum_size = Vector2(0.0, 60.0)
	list_controller.remove_requested.connect(func(index: int) -> void:
		GameState.remove_loadout_at(index, hand)
	)
	list_controller.move_committed.connect(func(from_index: int, to_index: int) -> void:
		GameState.move_loadout(from_index, to_index, hand)
	)
	list_controller.hover_bind_requested.connect(func(control: Control, definition: OperatorDefinition) -> void:
		_bind_operator_hover(control, definition)
	)
	loadout_list.add_child(list_controller)
	list_controller.setup_items(hand_loadout)


func _add_loadout_section(title: String, hand: String) -> void:
	var title_label: Label = Label.new()
	title_label.text = title
	loadout_list.add_child(title_label)

	var hand_loadout: Array[OperatorDefinition] = _get_loadout_by_hand(hand)
	if hand_loadout.is_empty():
		var empty_label: Label = Label.new()
		empty_label.text = "（空）"
		loadout_list.add_child(empty_label)
		return

	var id_occurrence: Dictionary = {}
	if _drag_active and _drag_hand == hand and _drag_from_index >= 0 and _drag_from_index < hand_loadout.size():
		var reduced_count: int = hand_loadout.size() - 1
		var insert_index: int = clampi(_drag_to_index, 0, reduced_count)
		for display_index in range(reduced_count + 1):
			if display_index == insert_index:
				loadout_list.add_child(_create_drag_placeholder_row(display_index + 1))
			if display_index >= reduced_count:
				continue
			var source_index: int = display_index if display_index < _drag_from_index else display_index + 1
			var definition: OperatorDefinition = hand_loadout[source_index]
			var occurrence: int = int(id_occurrence.get(definition.id, 0))
			id_occurrence[definition.id] = occurrence + 1
			var row_uid: String = _build_row_uid(hand, definition.id, occurrence)
			var row: HBoxContainer = _create_loadout_row(definition, source_index, display_index + 1, hand, row_uid)
			loadout_list.add_child(row)
			_record_drag_row(hand, row)
		return

	for display_index in range(hand_loadout.size()):
		var definition: OperatorDefinition = hand_loadout[display_index]
		var occurrence: int = int(id_occurrence.get(definition.id, 0))
		id_occurrence[definition.id] = occurrence + 1
		var row_uid: String = _build_row_uid(hand, definition.id, occurrence)
		var row: HBoxContainer = _create_loadout_row(definition, display_index, display_index + 1, hand, row_uid)
		loadout_list.add_child(row)
		_record_drag_row(hand, row)


func _create_loadout_row(definition: OperatorDefinition, index: int, display_number: int, hand: String, row_uid: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 6)
	row.custom_minimum_size = Vector2(0.0, LOADOUT_ROW_HEIGHT)
	row.set_meta("row_uid", row_uid)

	var index_label := Label.new()
	index_label.custom_minimum_size = Vector2(LOADOUT_INDEX_WIDTH, LOADOUT_ROW_HEIGHT)
	index_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	index_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	index_label.text = "%d." % display_number
	index_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(index_label)

	var drag_area := PanelContainer.new()
	drag_area.name = "DragArea"
	drag_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	drag_area.mouse_filter = Control.MOUSE_FILTER_STOP
	drag_area.set_meta("loadout_drag_hand", hand)
	drag_area.set_meta("loadout_drag_index", index)
	_bind_operator_hover(drag_area, definition)
	var drag_style := StyleBoxFlat.new()
	drag_style.bg_color = Color(0.12, 0.15, 0.2, 0.86)
	drag_style.border_color = Color(0.35, 0.47, 0.72, 0.8)
	drag_style.border_width_left = 1
	drag_style.border_width_top = 1
	drag_style.border_width_right = 1
	drag_style.border_width_bottom = 1
	drag_style.corner_radius_top_left = 4
	drag_style.corner_radius_top_right = 4
	drag_style.corner_radius_bottom_left = 4
	drag_style.corner_radius_bottom_right = 4
	drag_area.add_theme_stylebox_override("panel", drag_style)
	row.add_child(drag_area)

	var drag_margin := MarginContainer.new()
	drag_margin.add_theme_constant_override("margin_left", 8)
	drag_margin.add_theme_constant_override("margin_top", 4)
	drag_margin.add_theme_constant_override("margin_right", 8)
	drag_margin.add_theme_constant_override("margin_bottom", 4)
	drag_area.add_child(drag_margin)

	var drag_label := Label.new()
	drag_label.text = definition.display_name
	drag_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drag_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	drag_label.set_meta("loadout_drag_hand", hand)
	drag_label.set_meta("loadout_drag_index", index)
	drag_margin.add_child(drag_label)
	_bind_operator_hover(drag_label, definition)

	drag_area.gui_input.connect(func(event: InputEvent) -> void:
		_on_drag_area_input(event, hand, index, definition)
	)

	var remove_button := Button.new()
	remove_button.text = "移除"
	remove_button.pressed.connect(func() -> void:
		GameState.remove_loadout_at(index, hand)
	)
	_bind_operator_hover(remove_button, definition)
	row.add_child(remove_button)
	return row


func _create_drag_placeholder_row(display_number: int) -> Control:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 6)
	row.custom_minimum_size = Vector2(0.0, LOADOUT_ROW_HEIGHT)

	var index_label := Label.new()
	index_label.custom_minimum_size = Vector2(LOADOUT_INDEX_WIDTH, LOADOUT_ROW_HEIGHT)
	index_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	index_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	index_label.text = "%d." % display_number
	index_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(index_label)

	var placeholder := PanelContainer.new()
	placeholder.custom_minimum_size = Vector2(0.0, LOADOUT_ROW_HEIGHT)
	placeholder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.32, 0.44, 0.62, 0.12)
	style.border_color = Color(0.62, 0.78, 1.0, 0.78)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	placeholder.add_theme_stylebox_override("panel", style)
	row.add_child(placeholder)

	var remove_spacer := Control.new()
	remove_spacer.custom_minimum_size = Vector2(58.0, LOADOUT_ROW_HEIGHT)
	row.add_child(remove_spacer)
	return row


func _record_drag_row(hand: String, row: Control) -> void:
	var rows: Array = _drag_rows_by_hand.get(hand, [])
	rows.append(row)
	_drag_rows_by_hand[hand] = rows


func _build_row_uid(hand: String, operator_id: String, occurrence: int) -> String:
	return "%s|%s|%d" % [hand, operator_id, occurrence]


func _capture_loadout_row_positions() -> Dictionary:
	var out: Dictionary = {}
	for child in loadout_list.get_children():
		if not (child is Control):
			continue
		var control: Control = child
		if not control.has_meta("row_uid"):
			continue
		var uid: String = str(control.get_meta("row_uid"))
		if uid.is_empty():
			continue
		out[uid] = control.global_position.y
	return out


func _apply_loadout_row_position_transition(previous_positions: Dictionary) -> void:
	if previous_positions.is_empty():
		return
	for child in loadout_list.get_children():
		if not (child is Control):
			continue
		var row: Control = child
		if not row.has_meta("row_uid"):
			continue
		var uid: String = str(row.get_meta("row_uid"))
		if not previous_positions.has(uid):
			continue
		var old_global_y: float = float(previous_positions[uid])
		var target_global_y: float = row.global_position.y
		var delta_y: float = old_global_y - target_global_y
		if absf(delta_y) < 0.5:
			continue
		var target_local_y: float = row.position.y
		row.position.y = target_local_y + delta_y
		var tween := create_tween()
		tween.set_ease(Tween.EASE_OUT)
		tween.set_trans(Tween.TRANS_CUBIC)
		tween.tween_property(row, "position:y", target_local_y, 0.13)


func _on_drag_area_input(event: InputEvent, hand: String, index: int, definition: OperatorDefinition) -> void:
	if _closing_with_save:
		return
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event
		_ui_pointer_position = mouse_event.position
		_ui_pointer_has_position = true
		if mouse_event.button_index != MOUSE_BUTTON_LEFT:
			return
		_ui_pointer_left_pressed = mouse_event.pressed
		if mouse_event.pressed:
			_start_drag_candidate(hand, index, definition)
		else:
			if _drag_active:
				_finish_drag()
			_clear_drag_candidate()


func _start_drag_candidate(hand: String, index: int, definition: OperatorDefinition) -> void:
	_drag_candidate_active = true
	_drag_candidate_hand = hand
	_drag_candidate_index = index
	_drag_candidate_definition = definition
	_drag_candidate_start_time = Time.get_ticks_msec() / 1000.0
	_drag_candidate_start_mouse = _get_ui_pointer_position()


func _clear_drag_candidate() -> void:
	_drag_candidate_active = false
	_drag_candidate_hand = ""
	_drag_candidate_index = -1
	_drag_candidate_definition = null
	_drag_candidate_start_time = 0.0
	_drag_candidate_start_mouse = Vector2.ZERO


func _update_drag_state() -> void:
	if _drag_candidate_active and not _drag_active:
		if not _ui_pointer_left_pressed:
			_clear_drag_candidate()
		else:
			var now: float = Time.get_ticks_msec() / 1000.0
			if now - _drag_candidate_start_time >= DRAG_HOLD_SECONDS:
				_start_drag_from_candidate()

	if not _drag_active:
		return

	if not _ui_pointer_left_pressed:
		_finish_drag()
		return

	_update_drag_floating_position()
	var drag_center_y: float = _drag_floating.global_position.y + _drag_floating.size.y * 0.5
	var predicted_index: int = _predict_drag_index(drag_center_y)
	if predicted_index != _drag_to_index:
		_drag_to_index = predicted_index
		_rebuild_loadout()


func _start_drag_from_candidate() -> void:
	if _drag_candidate_definition == null:
		return
	_drag_active = true
	_drag_hand = _drag_candidate_hand
	_drag_from_index = _drag_candidate_index
	_drag_to_index = _drag_from_index
	_drag_floating_label.text = _drag_candidate_definition.display_name
	_drag_floating.visible = true
	_drag_floating.reset_size()
	_refresh_drag_floating_bounds()
	_update_drag_floating_position()
	_clear_drag_candidate()
	_hide_tooltip_immediately()
	_rebuild_loadout()


func _predict_drag_index(drag_center_y: float) -> int:
	var rows: Array = _drag_rows_by_hand.get(_drag_hand, [])
	var insertion_index: int = 0
	for row in rows:
		if not (row is Control) or not is_instance_valid(row):
			continue
		var control: Control = row
		var midpoint: float = control.global_position.y + control.size.y * 0.5
		if drag_center_y > midpoint:
			insertion_index += 1
		else:
			break
	var total: int = _get_loadout_by_hand(_drag_hand).size()
	return clampi(insertion_index, 0, maxi(0, total - 1))


func _finish_drag() -> void:
	if not _drag_active:
		return
	var hand: String = _drag_hand
	var from_index: int = _drag_from_index
	var to_index: int = _drag_to_index
	_cancel_drag_interaction(false)
	if from_index >= 0 and to_index >= 0 and from_index != to_index:
		_preserve_tooltip_during_refresh = true
		GameState.move_loadout(from_index, to_index, hand)
		call_deferred("_restore_tooltip_after_refresh")
	else:
		refresh()


func _cancel_drag_interaction(refresh_after: bool = true) -> void:
	_clear_drag_candidate()
	_drag_active = false
	_drag_hand = ""
	_drag_from_index = -1
	_drag_to_index = -1
	_drag_rows_by_hand[HAND_LEFT] = []
	_drag_rows_by_hand[HAND_RIGHT] = []
	if _drag_floating != null:
		_drag_floating.visible = false
	_drag_floating_anchor_x = 0.0
	_drag_floating_min_y = 0.0
	_drag_floating_max_y = 0.0
	if refresh_after:
		_refresh_if_alive()


func _refresh_if_alive() -> void:
	if not is_inside_tree():
		return
	call_deferred("refresh")


func _setup_drag_floating() -> void:
	_drag_floating = PanelContainer.new()
	_drag_floating.visible = false
	_drag_floating.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drag_floating.z_index = 2000
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.17, 0.24, 0.35, 0.95)
	style.border_color = Color(0.62, 0.8, 1.0, 0.95)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 5
	style.corner_radius_top_right = 5
	style.corner_radius_bottom_left = 5
	style.corner_radius_bottom_right = 5
	_drag_floating.add_theme_stylebox_override("panel", style)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 6)
	_drag_floating.add_child(margin)
	_drag_floating_label = Label.new()
	_drag_floating_label.text = ""
	margin.add_child(_drag_floating_label)
	add_child(_drag_floating)


func _refresh_drag_floating_bounds() -> void:
	if not _drag_active:
		return
	var rows: Array = _drag_rows_by_hand.get(_drag_hand, [])
	if rows.is_empty():
		return
	var min_y: float = 1.0e20
	var max_bottom: float = -1.0e20
	var anchor_x: float = 0.0
	var source_index: int = clampi(_drag_from_index, 0, rows.size() - 1)
	var source_row: Control = rows[source_index] as Control
	if source_row != null and is_instance_valid(source_row):
		anchor_x = source_row.global_position.x + LOADOUT_INDEX_WIDTH + 4.0
	for row_any in rows:
		if not (row_any is Control):
			continue
		var row: Control = row_any
		if not is_instance_valid(row):
			continue
		min_y = minf(min_y, row.global_position.y)
		max_bottom = maxf(max_bottom, row.global_position.y + row.size.y)
	if min_y > max_bottom:
		return
	var floating_h: float = maxf(LOADOUT_ROW_HEIGHT, _drag_floating.size.y)
	_drag_floating_anchor_x = floor(anchor_x)
	_drag_floating_min_y = floor(min_y)
	_drag_floating_max_y = floor(maxf(min_y, max_bottom - floating_h))


func _update_drag_floating_position() -> void:
	if _drag_floating == null or not _drag_floating.visible:
		return
	var mouse_pos: Vector2 = _get_ui_pointer_position()
	var target_y: float = mouse_pos.y + DRAG_FLOAT_OFFSET.y
	var clamped_y: float = clampf(target_y, _drag_floating_min_y, _drag_floating_max_y)
	_drag_floating.position = Vector2(_drag_floating_anchor_x, clamped_y)


func _get_ui_pointer_position() -> Vector2:
	if not _ui_pointer_has_position:
		return get_viewport().get_mouse_position()
	return _ui_pointer_position


func _setup_save_tip() -> void:
	_save_tip = Label.new()
	_save_tip.visible = false
	_save_tip.text = ""
	_save_tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_save_tip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_save_tip.anchors_preset = Control.PRESET_CENTER_TOP
	_save_tip.offset_left = -120
	_save_tip.offset_top = 24
	_save_tip.offset_right = 120
	_save_tip.offset_bottom = 56
	_save_tip.add_theme_color_override("font_color", Color(1.0, 0.96, 0.85, 1.0))
	_save_tip.add_theme_color_override("font_outline_color", Color(0.05, 0.07, 0.11, 0.95))
	_save_tip.add_theme_constant_override("outline_size", 6)
	add_child(_save_tip)


func _set_save_tip(text: String) -> void:
	if _save_tip == null:
		return
	_save_tip.text = text
	_save_tip.visible = not text.is_empty()


func _get_loadout_by_hand(hand: String) -> Array[OperatorDefinition]:
	if GameState.has_method("get_loadout"):
		var out: Array[OperatorDefinition] = []
		out.assign(GameState.get_loadout(hand))
		return out
	var fallback: Array[OperatorDefinition] = []
	fallback.assign(GameState.loadout)
	return fallback


func _create_basic_row(text: String, definition: OperatorDefinition) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(340.0, 28.0)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	_bind_operator_hover(label, definition)
	row.add_child(label)
	return row


func _build_operator_segments(definition: OperatorDefinition) -> Array[String]:
	var out: Array[String] = []
	if definition == null:
		return out
	var desc: String = _normalized_operator_description(definition)
	if desc.is_empty():
		desc = "（暂无描述）"
	out.append(desc)
	var field_lines: Array[String] = _collect_special_field_lines([definition.display_name, desc])
	for line in field_lines:
		if not out.has(line):
			out.append(line)
	return out


func _normalized_operator_description(definition: OperatorDefinition) -> String:
	var raw_desc: String = definition.description.strip_edges()
	if _is_hearthstone_style_description(raw_desc):
		return raw_desc
	var fallback: String = str(DESCRIPTION_TEMPLATE_BY_ID.get(definition.id, "")).strip_edges()
	if not fallback.is_empty():
		return fallback
	return raw_desc


func _is_hearthstone_style_description(desc: String) -> bool:
	if desc.is_empty():
		return false
	var has_trigger: bool = _contains_token(desc, "OnFire") or _contains_token(desc, "OnHit") or _contains_token(desc, "OnKill")
	if not has_trigger:
		return false
	for item in SPECIAL_FIELD_DOCS:
		var token: String = str(item.get("token", ""))
		if token == "OnFire" or token == "OnHit" or token == "OnKill":
			continue
		if _contains_token(desc, token):
			return true
	return false


func _collect_special_field_lines(seed_texts: Array[String]) -> Array[String]:
	var queue: Array[String] = []
	queue.assign(seed_texts)
	var visited_tokens: Dictionary = {}
	var seen_lines: Dictionary = {}
	var out: Array[String] = []

	while not queue.is_empty():
		var text: String = queue.pop_front()
		for item in SPECIAL_FIELD_DOCS:
			var token: String = str(item.get("token", ""))
			if token.is_empty() or visited_tokens.has(token):
				continue
			if token == "OnFire" or token == "OnHit" or token == "OnKill":
				continue
			if not _contains_token(text, token):
				continue
			visited_tokens[token] = true
			var line: String = "%s：%s" % [str(item.get("label", token)), str(item.get("doc", ""))]
			if seen_lines.has(line):
				continue
			seen_lines[line] = true
			out.append(line)
			queue.append(line)
	return out


func _contains_token(text: String, token: String) -> bool:
	if text.is_empty() or token.is_empty():
		return false
	return text.to_lower().find(token.to_lower()) >= 0


func _format_segment_bbcode(segment: String) -> String:
	var escaped: String = _escape_bbcode(segment)
	var docs: Array[Dictionary] = []
	docs.assign(SPECIAL_FIELD_DOCS)
	docs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("token", "")).length() > str(b.get("token", "")).length()
	)
	var output: String = escaped
	for item in docs:
		var token: String = str(item.get("token", ""))
		if token.is_empty():
			continue
		var escaped_token: String = _escape_bbcode(token)
		var display_text: String = str(item.get("display", token))
		var escaped_display: String = _escape_bbcode(display_text)
		var color: String = str(item.get("color", "#9CC9FF"))
		var highlighted: String = "[color=%s][b]%s[/b][/color]" % [color, escaped_display]
		output = output.replace(escaped_token, highlighted)
	return output


func _escape_bbcode(value: String) -> String:
	return value.replace("[", "[lb]").replace("]", "[rb]")


func _setup_tooltip_panel() -> void:
	_tooltip_panel = PanelContainer.new()
	_tooltip_panel.visible = false
	_tooltip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip_panel.z_index = 1800
	_tooltip_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_tooltip_panel.custom_minimum_size = Vector2(320.0, 40.0)

	var root_style := StyleBoxFlat.new()
	root_style.bg_color = Color(0.04, 0.06, 0.08, 0.95)
	root_style.border_color = Color(0.52, 0.72, 0.95, 0.92)
	root_style.border_width_left = 2
	root_style.border_width_top = 2
	root_style.border_width_right = 2
	root_style.border_width_bottom = 2
	root_style.corner_radius_top_left = 6
	root_style.corner_radius_top_right = 6
	root_style.corner_radius_bottom_left = 6
	root_style.corner_radius_bottom_right = 6
	_tooltip_panel.add_theme_stylebox_override("panel", root_style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 8)
	_tooltip_panel.add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	margin.add_child(vbox)

	_tooltip_title = Label.new()
	_tooltip_title.text = ""
	_tooltip_title.add_theme_font_size_override("font_size", 17)
	if _tooltip_font_bold != null:
		_tooltip_title.add_theme_font_override("font", _tooltip_font_bold)
	vbox.add_child(_tooltip_title)

	_tooltip_scroll = ScrollContainer.new()
	_tooltip_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tooltip_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	vbox.add_child(_tooltip_scroll)

	_tooltip_content = VBoxContainer.new()
	_tooltip_content.add_theme_constant_override("separation", 4)
	_tooltip_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tooltip_scroll.add_child(_tooltip_content)

	add_child(_tooltip_panel)


func _setup_tooltip_fonts() -> void:
	var font_names := PackedStringArray([
		"Microsoft YaHei UI",
		"Microsoft YaHei",
		"Noto Sans CJK SC",
		"Arial Unicode MS",
	])
	_tooltip_font_regular = SystemFont.new()
	_tooltip_font_regular.font_names = font_names
	_tooltip_font_regular.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	_tooltip_font_bold = SystemFont.new()
	_tooltip_font_bold.font_names = font_names
	_tooltip_font_bold.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	_tooltip_font_bold.set("font_weight", 700)


func _bind_operator_hover(control: Control, definition: OperatorDefinition) -> void:
	if control == null or definition == null:
		return
	var bound_id: String = str(control.get_meta("hover_bound_operator_id", ""))
	if bound_id == definition.id:
		return
	control.set_meta("hover_bound_operator_id", definition.id)
	control.set_meta("operator_def_id", definition.id)


func _show_operator_tooltip(definition: OperatorDefinition, source_control: Control) -> void:
	if _tooltip_panel == null or _tooltip_content == null or _tooltip_title == null:
		return
	if definition == null or _drag_active:
		return
	if _tooltip_panel.visible and _current_tooltip_operator_id == definition.id:
		_position_tooltip(_get_ui_pointer_position())
		return
	_current_tooltip_operator_id = definition.id
	_tooltip_title.text = definition.display_name
	_clear_children(_tooltip_content)

	var segments: Array[String] = _build_operator_segments(definition)
	for segment in segments:
		var box := PanelContainer.new()
		var box_style := StyleBoxFlat.new()
		box_style.bg_color = Color(0.1, 0.14, 0.2, 0.96)
		box_style.border_color = Color(0.45, 0.63, 0.9, 0.85)
		box_style.border_width_left = 1
		box_style.border_width_top = 1
		box_style.border_width_right = 1
		box_style.border_width_bottom = 1
		box_style.corner_radius_top_left = 4
		box_style.corner_radius_top_right = 4
		box_style.corner_radius_bottom_left = 4
		box_style.corner_radius_bottom_right = 4
		box.add_theme_stylebox_override("panel", box_style)

		var margin := MarginContainer.new()
		margin.add_theme_constant_override("margin_left", 8)
		margin.add_theme_constant_override("margin_top", 6)
		margin.add_theme_constant_override("margin_right", 8)
		margin.add_theme_constant_override("margin_bottom", 6)
		box.add_child(margin)

		var rich_label := RichTextLabel.new()
		rich_label.bbcode_enabled = true
		rich_label.fit_content = true
		rich_label.scroll_active = false
		rich_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if _tooltip_font_regular != null:
			rich_label.add_theme_font_override("normal_font", _tooltip_font_regular)
		if _tooltip_font_bold != null:
			rich_label.add_theme_font_override("bold_font", _tooltip_font_bold)
		rich_label.text = _format_segment_bbcode(segment)
		margin.add_child(rich_label)
		_tooltip_content.add_child(box)

	_tooltip_panel.visible = true
	_fit_tooltip_size_to_viewport(segments)
	var pos: Vector2 = _get_ui_pointer_position()
	_position_tooltip(pos)


func _fit_tooltip_size_to_viewport(segments: Array[String]) -> void:
	if _tooltip_panel == null:
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	var min_width: float = clampf(viewport_size.x * 0.24, 320.0, 430.0)
	var max_width: float = clampf(viewport_size.x * 0.68, 460.0, 760.0)
	var longest_segment: int = 0
	for segment in segments:
		longest_segment = maxi(longest_segment, segment.length())
	var desired_width: float = clampf(230.0 + float(longest_segment) * 7.0, min_width, max_width)

	_tooltip_panel.custom_minimum_size = Vector2(260.0, 40.0)
	_tooltip_panel.size = Vector2(desired_width, 100.0)
	_tooltip_panel.reset_size()

	var content_height: float = _estimate_tooltip_content_height(segments, desired_width)
	var title_height: float = _tooltip_title.get_combined_minimum_size().y
	var max_height: float = clampf(viewport_size.y * 0.68, 260.0, 620.0)
	var max_content_height: float = maxf(120.0, max_height - title_height - 30.0)
	var visible_content_height: float = minf(content_height, max_content_height)
	_tooltip_scroll.custom_minimum_size = Vector2(0.0, visible_content_height)

	var desired_height: float = clampf(title_height + visible_content_height + 24.0, 90.0, max_height)
	_tooltip_panel.size = Vector2(desired_width, desired_height)
	_tooltip_scroll.scroll_vertical = 0


func _estimate_tooltip_content_height(segments: Array[String], panel_width: float) -> float:
	if segments.is_empty():
		return 40.0
	var inner_width: float = maxf(220.0, panel_width - 56.0)
	var chars_per_line: int = maxi(12, int(floor(inner_width / 12.0)))
	var total: float = 0.0
	for segment in segments:
		var hard_lines: int = segment.split("\n", false).size()
		var wrapped_lines: int = int(ceil(float(maxi(1, segment.length())) / float(chars_per_line)))
		var line_count: int = maxi(hard_lines, wrapped_lines)
		total += 16.0 + float(line_count) * 20.0 + 12.0
	total += float(maxi(0, segments.size() - 1)) * 4.0
	return total


func _hide_tooltip_if_needed() -> void:
	if _tooltip_panel == null:
		return
	if _preserve_tooltip_during_refresh:
		return
	var hovered: Control = get_viewport().gui_get_hovered_control()
	if hovered != null:
		var definition: OperatorDefinition = _definition_from_control(hovered)
		if definition != null and definition.id == _current_tooltip_operator_id:
			return
	_hide_tooltip_immediately()


func _hide_tooltip_immediately() -> void:
	if _tooltip_panel != null:
		_tooltip_panel.visible = false
	_current_tooltip_operator_id = ""


func _definition_from_control(control: Control) -> OperatorDefinition:
	var cursor: Node = control
	while cursor != null:
		if cursor is Control and (cursor as Control).has_meta("operator_def_id"):
			var op_id: String = str((cursor as Control).get_meta("operator_def_id"))
			for definition in GameState.all_definitions:
				if definition != null and definition.id == op_id:
					return definition
		cursor = cursor.get_parent()
	return null


func _drag_payload_from_control(control: Control) -> Dictionary:
	var cursor: Node = control
	while cursor != null:
		if cursor is Control and (cursor as Control).has_meta("loadout_drag_hand"):
			var payload: Dictionary = {}
			payload["hand"] = str((cursor as Control).get_meta("loadout_drag_hand", ""))
			payload["index"] = int((cursor as Control).get_meta("loadout_drag_index", -1))
			payload["definition"] = _definition_from_control(cursor as Control)
			return payload
		cursor = cursor.get_parent()
	return {}


func _restore_tooltip_after_refresh() -> void:
	_preserve_tooltip_during_refresh = false
	var hovered: Control = get_viewport().gui_get_hovered_control()
	if hovered != null:
		var definition: OperatorDefinition = _definition_from_control(hovered)
		if definition != null:
			_tooltip_hover_candidate_id = definition.id
			_tooltip_hover_frames = TOOLTIP_CONFIRM_FRAMES
			_tooltip_absent_frames = 0
			_show_operator_tooltip(definition, hovered)
			return
	_hide_tooltip_immediately()


func _update_tooltip_visibility_state() -> void:
	if _tooltip_panel == null:
		return
	if _preserve_tooltip_during_refresh:
		_tooltip_absent_frames = 0
		return
	var hovered: Control = null
	var definition: OperatorDefinition = null
	if not _drag_active:
		hovered = get_viewport().gui_get_hovered_control()
		if hovered != null:
			definition = _definition_from_control(hovered)
	if definition != null:
		_tooltip_absent_frames = 0
		if definition.id == _tooltip_hover_candidate_id:
			_tooltip_hover_frames += 1
		else:
			_tooltip_hover_candidate_id = definition.id
			_tooltip_hover_frames = 1
		if _tooltip_hover_frames >= TOOLTIP_CONFIRM_FRAMES:
			_show_operator_tooltip(definition, hovered)
		return
	_tooltip_hover_candidate_id = ""
	_tooltip_hover_frames = 0
	_tooltip_absent_frames += 1
	if _tooltip_panel.visible and _tooltip_absent_frames >= TOOLTIP_CONFIRM_FRAMES:
		_hide_tooltip_immediately()


func _position_tooltip(mouse_pos: Vector2) -> void:
	if _tooltip_panel == null:
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	var panel_size: Vector2 = _tooltip_panel.size
	var pos: Vector2 = mouse_pos + Vector2(16.0, 18.0)
	if pos.x + panel_size.x > viewport_size.x - 8.0:
		pos.x = mouse_pos.x - panel_size.x - 16.0
	if pos.x < 8.0:
		pos.x = 8.0
	if pos.y + panel_size.y > viewport_size.y - 8.0:
		pos.y = maxf(8.0, viewport_size.y - panel_size.y - 8.0)
	_tooltip_panel.position = Vector2(floor(pos.x), floor(pos.y))


func _clear_children(root: Node) -> void:
	for child in root.get_children():
		child.queue_free()


func _enter_range() -> void:
	if GameState.has_method("save_state"):
		GameState.save_state()
	get_tree().change_scene_to_file("res://scenes/range_scene.tscn")
