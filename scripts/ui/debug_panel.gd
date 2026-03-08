extends PanelContainer

@onready var toggle_button: Button = %DebugToggleButton
@onready var content_root: Control = %DebugContent
@onready var debug_text: RichTextLabel = %DebugText

var _expanded: bool = false

func _ready() -> void:
	toggle_button.pressed.connect(_toggle)
	DebugLog.log_changed.connect(_refresh)
	_apply_state()
	_refresh(DebugLog.get_lines())


func _exit_tree() -> void:
	if DebugLog.log_changed.is_connected(_refresh):
		DebugLog.log_changed.disconnect(_refresh)


func _refresh(lines: PackedStringArray) -> void:
	debug_text.clear()
	for line in lines:
		debug_text.append_text("%s\n" % line)


func _toggle() -> void:
	_expanded = not _expanded
	_apply_state()


func _apply_state() -> void:
	content_root.visible = _expanded
	toggle_button.text = "Debug -" if _expanded else "Debug +"
	custom_minimum_size = Vector2(610, 350) if _expanded else Vector2(120, 34)
	size = custom_minimum_size
