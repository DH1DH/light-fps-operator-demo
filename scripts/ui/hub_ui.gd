extends Control
const OperatorDefinition = preload("res://scripts/operators/operator_definition.gd")

signal overlay_close_requested

@export var overlay_mode: bool = false

const SPECIAL_FIELD_DOCS: Array[Dictionary] = [
	{"token": "OnFire", "label": "OnFire", "doc": "开火触发，修改本次射击参数（ShotContext）。"},
	{"token": "OnHit", "label": "OnHit", "doc": "命中触发，结算命中上下文（HitContext）。"},
	{"token": "OnKill", "label": "OnKill", "doc": "击杀触发，通常用于奖励或终结结算。"},
	{"token": "ShotContext", "label": "ShotContext", "doc": "单次开火上下文，包含弹体数、散布、伤害等。"},
	{"token": "HitContext", "label": "HitContext", "doc": "单次命中上下文，包含目标状态、命中点与附加结算。"},
	{"token": "TargetStatus", "label": "TargetStatus", "doc": "目标状态容器，维护印记/异常/资源层数。"},
	{"token": "弹体", "label": "弹体", "doc": "一次开火生成的子弹数量。"},
	{"token": "散布", "label": "散布", "doc": "弹道偏离中心线的角度范围。"},
	{"token": "印记", "label": "印记", "doc": "用于清算类爆发结算的层数资源。"},
	{"token": "清算", "label": "清算", "doc": "读取并消耗印记，转化为额外伤害。"},
	{"token": "收束", "label": "收束", "doc": "弹体越少，单次命中额外伤害越高。"},
	{"token": "种子", "label": "种子", "doc": "召唤流资源，达到阈值可触发孵化。"},
	{"token": "扩散", "label": "扩散", "doc": "将当前状态传播给附近其他目标。"},
	{"token": "孵化", "label": "孵化", "doc": "消耗种子生成召唤单位。"},
	{"token": "召唤", "label": "召唤", "doc": "生成临时单位协同作战。"},
	{"token": "灼烧", "label": "灼烧", "doc": "持续伤害异常层数。"},
	{"token": "冻结", "label": "冻结", "doc": "控制类异常层数，可参与反应。"},
	{"token": "反应", "label": "反应", "doc": "当灼烧与冻结并存时触发额外结算。"},
	{"token": "贪婪", "label": "贪婪", "doc": "击杀兑现前的金币倍率层数。"},
	{"token": "兑现", "label": "兑现", "doc": "击杀时按贪婪层数转化金币。"},
	{"token": "掉钱", "label": "掉钱", "doc": "命中后按概率获得金币。"},
	{"token": "概率", "label": "概率", "doc": "随机触发，不保证每次生效。"},
	{"token": "阈值", "label": "阈值", "doc": "达到指定层数后才会触发效果。"},
	{"token": "金币", "label": "金币", "doc": "用于商店购买算子。"},
	{"token": "算子链", "label": "算子链", "doc": "有序执行列表，顺序会改变结果。"},
]

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


func _ready() -> void:
	GameState.initialize_if_needed()
	GameState.state_changed.connect(refresh)
	if overlay_mode:
		enter_range_button.text = "关闭（Tab）"
		enter_range_button.pressed.connect(_request_overlay_close)
		hint_label.text = "按 Tab 随时关闭并返回战斗"
		backdrop.color = Color(0.05, 0.07, 0.1, 0.86)
	else:
		enter_range_button.pressed.connect(_enter_range)
	_setup_tooltip_panel()
	refresh()


func _process(_delta: float) -> void:
	if _tooltip_panel != null and _tooltip_panel.visible:
		_position_tooltip(get_viewport().get_mouse_position())


func _exit_tree() -> void:
	if GameState.state_changed.is_connected(refresh):
		GameState.state_changed.disconnect(refresh)


func refresh() -> void:
	gold_label.text = "金币：%d" % GameState.gold
	_rebuild_inventory()
	_rebuild_shop()
	_rebuild_loadout()


func _rebuild_inventory() -> void:
	_clear_children(inventory_list)
	for definition in GameState.all_definitions:
		var row: HBoxContainer = _create_row("%s  持有:%d 可装:%d" % [definition.display_name, GameState.get_owned_count(definition), GameState.get_unslotted_count(definition)], definition)
		var add_button: Button = Button.new()
		add_button.text = "装配"
		add_button.disabled = GameState.get_unslotted_count(definition) <= 0
		add_button.pressed.connect(func() -> void: GameState.add_to_loadout(definition))
		_bind_operator_hover(add_button, definition)
		row.add_child(add_button)
		inventory_list.add_child(row)


func _rebuild_shop() -> void:
	_clear_children(shop_list)
	for definition in GameState.all_definitions:
		var row: HBoxContainer = _create_row("%s  价格:%d" % [definition.display_name, definition.cost], definition)
		var buy_button: Button = Button.new()
		buy_button.text = "购买"
		buy_button.disabled = GameState.gold < definition.cost
		buy_button.pressed.connect(func() -> void: GameState.buy_operator(definition))
		_bind_operator_hover(buy_button, definition)
		row.add_child(buy_button)
		shop_list.add_child(row)


func _rebuild_loadout() -> void:
	_clear_children(loadout_list)
	for index in range(GameState.loadout.size()):
		var definition: OperatorDefinition = GameState.loadout[index]
		var row: HBoxContainer = _create_row("%d. %s" % [index + 1, definition.display_name], definition)

		var up_button: Button = Button.new()
		up_button.text = "上移"
		up_button.disabled = index == 0
		up_button.pressed.connect(func() -> void: GameState.move_loadout(index, index - 1))
		_bind_operator_hover(up_button, definition)
		row.add_child(up_button)

		var down_button: Button = Button.new()
		down_button.text = "下移"
		down_button.disabled = index >= GameState.loadout.size() - 1
		down_button.pressed.connect(func() -> void: GameState.move_loadout(index, index + 1))
		_bind_operator_hover(down_button, definition)
		row.add_child(down_button)

		var remove_button: Button = Button.new()
		remove_button.text = "移除"
		remove_button.pressed.connect(func() -> void: GameState.remove_loadout_at(index))
		_bind_operator_hover(remove_button, definition)
		row.add_child(remove_button)
		loadout_list.add_child(row)

	var hint: Label = Label.new()
	hint.text = "顺序即执行顺序。"
	loadout_list.add_child(hint)


func _create_row(text: String, definition: OperatorDefinition) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bind_operator_hover(row, definition)

	var label: Label = Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(320, 28)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	_bind_operator_hover(label, definition)
	row.add_child(label)
	return row


func _build_operator_segments(definition: OperatorDefinition) -> Array[String]:
	var out: Array[String] = []
	if definition == null:
		return out
	var desc: String = definition.description.strip_edges()
	if desc.is_empty():
		desc = "（暂无描述）"
	out.append(desc)
	var field_lines: Array[String] = _collect_special_field_lines([definition.display_name, desc])
	for line in field_lines:
		if not out.has(line):
			out.append(line)
	return out


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


func _setup_tooltip_panel() -> void:
	_tooltip_panel = PanelContainer.new()
	_tooltip_panel.visible = false
	_tooltip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip_panel.z_index = 999
	_tooltip_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_tooltip_panel.custom_minimum_size = Vector2(320, 40)

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


func _bind_operator_hover(control: Control, definition: OperatorDefinition) -> void:
	if control == null or definition == null:
		return
	control.set_meta("operator_def_id", definition.id)
	control.mouse_entered.connect(func() -> void:
		_show_operator_tooltip(definition, control)
	)
	control.mouse_exited.connect(func() -> void:
		call_deferred("_hide_tooltip_if_needed")
	)


func _show_operator_tooltip(definition: OperatorDefinition, source_control: Control) -> void:
	if _tooltip_panel == null or _tooltip_content == null or _tooltip_title == null:
		return
	if definition == null:
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

		var label := Label.new()
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.text = segment
		margin.add_child(label)

		_tooltip_content.add_child(box)

	_tooltip_panel.visible = true
	_fit_tooltip_size_to_viewport(segments)
	var pos: Vector2 = source_control.get_global_mouse_position()
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

	_tooltip_panel.custom_minimum_size = Vector2(260, 40)
	_tooltip_panel.size = Vector2(desired_width, 100.0)
	_tooltip_panel.reset_size()

	var content_height: float = _estimate_tooltip_content_height(segments, desired_width)
	var title_height: float = _tooltip_title.get_combined_minimum_size().y
	var max_height: float = clampf(viewport_size.y * 0.68, 260.0, 620.0)
	var max_content_height: float = maxf(120.0, max_height - title_height - 30.0)
	var visible_content_height: float = minf(content_height, max_content_height)
	_tooltip_scroll.custom_minimum_size = Vector2(0.0, visible_content_height)

	var desired_height: float = clampf(title_height + visible_content_height + 24.0, 90.0, max_height)
	_tooltip_panel.size = Vector2(
		desired_width,
		desired_height
	)
	if _tooltip_scroll != null:
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
	var hovered: Control = get_viewport().gui_get_hovered_control()
	if hovered != null:
		var definition: OperatorDefinition = _definition_from_control(hovered)
		if definition != null and definition.id == _current_tooltip_operator_id:
			return
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


func _position_tooltip(mouse_pos: Vector2) -> void:
	if _tooltip_panel == null:
		return
	var viewport_size: Vector2 = get_viewport_rect().size
	var panel_size: Vector2 = _tooltip_panel.size
	var pos: Vector2 = mouse_pos + Vector2(16, 18)
	if pos.x + panel_size.x > viewport_size.x - 8.0:
		pos.x = maxf(8.0, viewport_size.x - panel_size.x - 8.0)
	if pos.y + panel_size.y > viewport_size.y - 8.0:
		pos.y = maxf(8.0, viewport_size.y - panel_size.y - 8.0)
	_tooltip_panel.position = pos


func _clear_children(root: Node) -> void:
	for child in root.get_children():
		child.queue_free()


func _enter_range() -> void:
	get_tree().change_scene_to_file("res://scenes/range_scene.tscn")


func _request_overlay_close() -> void:
	overlay_close_requested.emit()
