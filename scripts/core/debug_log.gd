extends Node

signal log_changed(lines: PackedStringArray)

const LOG_PATH := "user://debug.log"
const MAX_LINES := 24
const FLUSH_INTERVAL_SEC := 0.25

var _lines: PackedStringArray = []
var _dirty: bool = false
var _next_flush_at: float = 0.0

func _ready() -> void:
	_ensure_log_dir()
	clear()


func _process(_delta: float) -> void:
	_flush_if_due()


func _exit_tree() -> void:
	_flush_now()


func clear() -> void:
	_lines = PackedStringArray()
	_write_file("")
	add_entry("DebugLog ready")


func add_entry(message: String) -> void:
	var timestamp := Time.get_datetime_string_from_system()
	var line := "[%s] %s" % [timestamp, message]
	_lines.append(line)
	while _lines.size() > MAX_LINES:
		_lines.remove_at(0)
	_dirty = true
	_flush_if_due()
	log_changed.emit(_lines)


func get_lines() -> PackedStringArray:
	return _lines


func _write_file(contents: String) -> void:
	var file := FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("Failed to open debug log file")
		return
	file.store_string(contents)


func _ensure_log_dir() -> void:
	var absolute_dir := ProjectSettings.globalize_path("user://")
	DirAccess.make_dir_recursive_absolute(absolute_dir)


func _flush_if_due() -> void:
	if not _dirty:
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	if now < _next_flush_at:
		return
	_flush_now()
	_next_flush_at = now + FLUSH_INTERVAL_SEC


func _flush_now() -> void:
	if not _dirty:
		return
	_write_file("\n".join(_lines))
	_dirty = false
