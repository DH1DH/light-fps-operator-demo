extends PanelContainer

@onready var debug_text: RichTextLabel = %DebugText

func _ready() -> void:
	DebugLog.log_changed.connect(_refresh)
	_refresh(DebugLog.get_lines())


func _exit_tree() -> void:
	if DebugLog.log_changed.is_connected(_refresh):
		DebugLog.log_changed.disconnect(_refresh)


func _refresh(lines: PackedStringArray) -> void:
	debug_text.clear()
	for line in lines:
		debug_text.append_text("%s\n" % line)
