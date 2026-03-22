extends Control
const CombatTargeting = preload("res://scripts/combat/combat_targeting.gd")

var _labels: Dictionary = {}
var _font: SystemFont
var _pulse_time: float = 0.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = SystemFont.new()
	_font.font_names = PackedStringArray(["Lucida Console", "Consolas", "Courier New"])
	_font.antialiasing = TextServer.FONT_ANTIALIASING_NONE


func _process(_delta: float) -> void:
	_pulse_time += _delta
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return
	var active: Dictionary = {}
	for node in get_tree().get_nodes_in_group(CombatTargeting.COMBAT_TARGET_GROUP):
		if not (node is Node3D):
			continue
		var target: Node3D = node as Node3D
		if not target.has_method("get_overlay_text") or not target.has_method("get_overlay_color"):
			continue
		var label: Label = _ensure_label(target)
		var world_pos: Vector3 = target.global_position + Vector3(0.0, 2.35, 0.0)
		if target.has_method("get_overlay_world_position"):
			world_pos = target.call("get_overlay_world_position")
		if camera.is_position_behind(world_pos):
			label.visible = false
			continue
		var screen_pos: Vector2 = camera.unproject_position(world_pos)
		label.position = screen_pos - Vector2(label.size.x * 0.5, label.size.y)
		label.text = str(target.call("get_overlay_text"))
		label.modulate = target.call("get_overlay_color")
		var execute_ready: bool = false
		if target.has_method("is_execute_ready"):
			execute_ready = bool(target.call("is_execute_ready"))
		if execute_ready:
			var pulse: float = 1.0 + 0.1 * sin(_pulse_time * 9.0)
			label.scale = Vector2.ONE * pulse
		else:
			label.scale = Vector2.ONE
		label.visible = true
		active[target] = true
	for target in _labels.keys():
		if not active.has(target):
			var stale: Label = _labels[target]
			if is_instance_valid(stale):
				stale.queue_free()
			_labels.erase(target)


func _ensure_label(target: Node3D) -> Label:
	if _labels.has(target) and is_instance_valid(_labels[target]):
		return _labels[target]
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.label_settings = _build_label_settings()
	label.text = ""
	add_child(label)
	_labels[target] = label
	return label


func _build_label_settings() -> LabelSettings:
	var settings := LabelSettings.new()
	settings.font = _font
	settings.font_size = 18
	settings.font_color = Color(0.93, 0.97, 0.86, 1.0)
	settings.outline_size = 10
	settings.outline_color = Color(0.03, 0.05, 0.03, 0.95)
	settings.shadow_size = 0
	return settings
