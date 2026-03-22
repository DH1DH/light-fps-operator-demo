extends Control

@onready var chain_label: Label = %ChainLabel
@onready var shot_label: Label = %ShotLabel
@onready var performance_label: Label = %PerformanceLabel
@onready var controls_label: Label = $Panel/VBox/ControlsLabel

var _shooter: Node = null
var _reported_missing_shooter: bool = false
var resolve_label: Label = null


func _ready() -> void:
	%ReturnHubButton.pressed.connect(_return_hub)
	controls_label.text = "左键射击 | R换弹 | WASD移动 | Shift冲刺 | Space跳跃 | F1重置目标 | Tab背包商店 | Esc切换鼠标"
	_ensure_resolve_label()
	_try_bind_shooter()


func _process(delta: float) -> void:
	var fps: float = Engine.get_frames_per_second()
	var frame_ms: float = delta * 1000.0
	performance_label.text = "帧率: %.0f | 帧耗时: %.2f ms" % [fps, frame_ms]

	if _shooter == null or not is_instance_valid(_shooter):
		_try_bind_shooter()
		if _shooter == null:
			chain_label.text = "算子链: (未找到射击组件)"
			if resolve_label != null:
				resolve_label.text = "单发结算: --"
			shot_label.text = "预测射击: --"
			return

	chain_label.text = "算子链: %s" % str(_shooter.call("current_chain_text"))
	var shot: Variant = _shooter.get("last_predicted_shot")
	if shot == null:
		if resolve_label != null:
			resolve_label.text = "单发结算: --"
		shot_label.text = "预测射击: --"
		return

	var pellets: int = int(shot.get("pellet_count"))
	var spread: float = float(shot.get("spread_angle"))
	var damage: float = float(shot.get("damage"))
	var total_damage: float = float(pellets) * damage
	var ammo_text: String = ""
	if _shooter.has_method("ammo_status_text"):
		ammo_text = str(_shooter.call("ammo_status_text"))

	if resolve_label != null:
		resolve_label.text = "单发结算  弹体:%d  单弹伤害:%.1f  理论总伤害:%.1f" % [pellets, damage, total_damage]
	shot_label.text = "预测参数  散布:%.1f°  基础伤害:%.1f  %s" % [spread, damage, ammo_text]


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
		DebugLog.add_entry("RangeHUD: weapon_shooter not found")


func _ensure_resolve_label() -> void:
	if resolve_label != null and is_instance_valid(resolve_label):
		return
	var vbox: Node = chain_label.get_parent()
	if not (vbox is VBoxContainer):
		return
	resolve_label = Label.new()
	resolve_label.name = "ResolveLabel"
	resolve_label.text = "单发结算: --"
	resolve_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vbox.add_child(resolve_label)
	var shot_index: int = shot_label.get_index()
	vbox.move_child(resolve_label, shot_index)


func _return_hub() -> void:
	get_tree().change_scene_to_file("res://scenes/hub_scene.tscn")
