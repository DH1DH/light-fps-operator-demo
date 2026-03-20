extends Control
class_name OperatorListController

const OperatorDefinition = preload("res://scripts/operators/operator_definition.gd")
const OperatorItemDrag = preload("res://scripts/ui/operator_item_drag.gd")

signal remove_requested(index: int)
signal move_committed(from_index: int, to_index: int)
signal hover_bind_requested(control: Control, definition: OperatorDefinition)

@export var row_height: float = 34.0
@export var row_gap: float = 6.0
@export var index_width: float = 34.0
@export var index_gap: float = 8.0
@export var bottom_padding: float = 8.0
@export var smooth_speed: float = 22.0
@export var drag_smooth_speed: float = 34.0

var _ordered_items: Array[OperatorItemDrag] = []
var _index_labels: Array[Label] = []
var _drag_item: OperatorItemDrag = null
var _drag_start_index: int = -1
var _drag_current_index: int = -1
var _drag_pointer_offset_y: float = 0.0
var _drag_target_y: float = 0.0
var _card_x: float = 0.0
var _card_width: float = 160.0


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_PASS


func _process(delta: float) -> void:
	if _drag_item != null:
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_finish_drag()
		else:
			_update_drag_from_mouse()
	_step_layout(delta)


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_refresh_horizontal_layout()


func setup_items(definitions: Array[OperatorDefinition]) -> void:
	_clear_all()
	if definitions.is_empty():
		custom_minimum_size = Vector2(0.0, row_height)
		return
	var index: int = 0
	for definition in definitions:
		var index_label := Label.new()
		index_label.text = "%d." % (index + 1)
		index_label.custom_minimum_size = Vector2(index_width, row_height)
		index_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		index_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		index_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(index_label)
		_index_labels.append(index_label)

		var item := OperatorItemDrag.new()
		item.setup(definition)
		item.drag_started.connect(_on_item_drag_started)
		item.remove_requested.connect(_on_item_remove_requested)
		item.hover_bind_requested.connect(func(control: Control, def: OperatorDefinition) -> void:
			hover_bind_requested.emit(control, def)
		)
		item.set_meta("current_y", _slot_y(index))
		item.set_meta("target_y", _slot_y(index))
		add_child(item)
		_ordered_items.append(item)
		index += 1

	custom_minimum_size = Vector2(0.0, _total_height())
	_refresh_horizontal_layout()
	_step_layout(1.0)


func _on_item_drag_started(item: OperatorItemDrag, pointer_offset_y: float) -> void:
	if _drag_item != null:
		return
	_drag_item = item
	_drag_start_index = _ordered_items.find(item)
	_drag_current_index = _drag_start_index
	_drag_pointer_offset_y = pointer_offset_y
	_drag_target_y = float(item.get_meta("current_y", _slot_y(_drag_start_index)))
	item.set_drag_visual(true)
	move_child(item, get_child_count() - 1)


func _on_item_remove_requested(item: OperatorItemDrag) -> void:
	if _drag_item != null:
		return
	var index: int = _ordered_items.find(item)
	if index >= 0:
		remove_requested.emit(index)


func _update_drag_from_mouse() -> void:
	if _drag_item == null:
		return
	var local_mouse_y: float = get_local_mouse_position().y
	var min_y: float = _slot_y(0)
	var max_y: float = _slot_y(maxi(0, _ordered_items.size() - 1))
	_drag_target_y = clampf(local_mouse_y - _drag_pointer_offset_y, min_y, max_y)
	var center_y: float = _drag_target_y + row_height * 0.5
	var target_index: int = _index_from_center(center_y)
	if target_index != _drag_current_index:
		_ordered_items.erase(_drag_item)
		_ordered_items.insert(target_index, _drag_item)
		_drag_current_index = target_index


func _finish_drag() -> void:
	if _drag_item == null:
		return
	var from_index: int = _drag_start_index
	var to_index: int = _drag_current_index
	_drag_item.set_drag_visual(false)
	_drag_item = null
	_drag_start_index = -1
	_drag_current_index = -1
	_drag_pointer_offset_y = 0.0
	if from_index >= 0 and to_index >= 0 and from_index != to_index:
		move_committed.emit(from_index, to_index)


func _step_layout(delta: float) -> void:
	if _ordered_items.is_empty():
		return
	_update_index_labels()
	var normal_alpha: float = 1.0 - exp(-smooth_speed * delta)
	var drag_alpha: float = 1.0 - exp(-drag_smooth_speed * delta)
	for i in range(_ordered_items.size()):
		var item: OperatorItemDrag = _ordered_items[i]
		var target_y: float = _slot_y(i)
		if item == _drag_item:
			target_y = _drag_target_y
		var current_y: float = float(item.get_meta("current_y", target_y))
		var alpha: float = drag_alpha if item == _drag_item else normal_alpha
		current_y = lerpf(current_y, target_y, alpha)
		item.set_meta("current_y", current_y)
		item.set_meta("target_y", target_y)
		item.position = Vector2(floor(_card_x), current_y)
		item.size = Vector2(_card_width, row_height)


func _update_index_labels() -> void:
	for i in range(_index_labels.size()):
		var label: Label = _index_labels[i]
		label.text = "%d." % (i + 1)
		label.position = Vector2(0.0, _slot_y(i))
		label.size = Vector2(index_width, row_height)


func _refresh_horizontal_layout() -> void:
	_card_x = index_width + index_gap
	_card_width = maxf(120.0, size.x - _card_x - 2.0)
	for item in _ordered_items:
		item.size = Vector2(_card_width, row_height)
	for label in _index_labels:
		label.size = Vector2(index_width, row_height)


func _index_from_center(center_y: float) -> int:
	var stride: float = row_height + row_gap
	var relative: float = center_y - (row_height * 0.5)
	var idx: int = int(floor((relative + stride * 0.5) / stride))
	return clampi(idx, 0, maxi(0, _ordered_items.size() - 1))


func _slot_y(index: int) -> float:
	return float(index) * (row_height + row_gap)


func _total_height() -> float:
	if _ordered_items.is_empty():
		return row_height + bottom_padding
	return _slot_y(_ordered_items.size() - 1) + row_height + bottom_padding


func _clear_all() -> void:
	_drag_item = null
	_drag_start_index = -1
	_drag_current_index = -1
	_drag_pointer_offset_y = 0.0
	_drag_target_y = 0.0
	_ordered_items.clear()
	_index_labels.clear()
	for child in get_children():
		child.queue_free()
