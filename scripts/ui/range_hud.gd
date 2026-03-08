extends Control

@onready var chain_label: Label = %ChainLabel
@onready var shot_label: Label = %ShotLabel
@onready var performance_label: Label = %PerformanceLabel

var _shooter: WeaponShooter

func _ready() -> void:
	%ReturnHubButton.pressed.connect(_return_hub)
	_shooter = get_tree().get_first_node_in_group("weapon_shooter") as WeaponShooter


func _process(delta: float) -> void:
	var fps: float = Engine.get_frames_per_second()
	var frame_ms: float = delta * 1000.0
	performance_label.text = "FPS: %.0f | Frame: %.2f ms" % [fps, frame_ms]
	if _shooter == null:
		_shooter = get_tree().get_first_node_in_group("weapon_shooter") as WeaponShooter
		return
	chain_label.text = "Chain: %s" % _shooter.current_chain_text()
	var shot: ShotContext = _shooter.last_predicted_shot
	shot_label.text = "Predicted Shot  Pellets:%d  Spread:%.1f  Damage:%.1f" % [shot.pellet_count, shot.spread_angle, shot.damage]


func _return_hub() -> void:
	get_tree().change_scene_to_file("res://scenes/hub_scene.tscn")
