extends PanelContainer
class_name OperatorItemDrag

const OperatorDefinition = preload("res://scripts/operators/operator_definition.gd")

signal drag_started(item: OperatorItemDrag, pointer_offset_y: float)
signal remove_requested(item: OperatorItemDrag)
signal hover_bind_requested(control: Control, definition: OperatorDefinition)

var definition: OperatorDefinition = null

var _title_label: Label
var _remove_button: Button


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(0.0, 34.0)


func _ready() -> void:
	_build_ui()
	_apply_definition_to_ui()
	_emit_hover_bindings()


func setup(definition_value: OperatorDefinition) -> void:
	definition = definition_value
	_apply_definition_to_ui()
	if is_inside_tree():
		_emit_hover_bindings()


func set_drag_visual(enabled: bool) -> void:
	if enabled:
		z_index = 300
		scale = Vector2(1.015, 1.015)
		modulate = Color(1.0, 1.0, 1.0, 0.98)
	else:
		z_index = 1
		scale = Vector2.ONE
		modulate = Color(1.0, 1.0, 1.0, 1.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button_event := event as InputEventMouseButton
		if button_event.button_index == MOUSE_BUTTON_LEFT and button_event.pressed:
			var local := get_local_mouse_position()
			drag_started.emit(self, local.y)
			accept_event()


func _build_ui() -> void:
	if get_child_count() > 0:
		return
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.12, 0.15, 0.2, 0.9)
	style.border_color = Color(0.35, 0.47, 0.72, 0.86)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	add_theme_stylebox_override("panel", style)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 4)
	add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	margin.add_child(row)

	_title_label = Label.new()
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(_title_label)

	_remove_button = Button.new()
	_remove_button.text = "移除"
	_remove_button.pressed.connect(func() -> void:
		remove_requested.emit(self)
	)
	row.add_child(_remove_button)


func _apply_definition_to_ui() -> void:
	if definition == null:
		return
	if _title_label != null:
		_title_label.text = definition.display_name


func _emit_hover_bindings() -> void:
	if definition == null:
		return
	hover_bind_requested.emit(self, definition)
	if _title_label != null:
		hover_bind_requested.emit(_title_label, definition)
