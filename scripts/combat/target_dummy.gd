extends StaticBody3D
class_name TargetDummy

@export var auto_reset_delay: float = 3.0
@export var dps_window: float = 1.0

@onready var status: StatusController = $StatusController
@onready var mesh_instance: MeshInstance3D = $Visual

var _damage_events: Array[Dictionary] = []

func _ready() -> void:
	add_to_group("target_dummy")
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.albedo_color = Color.FIREBRICK
	mesh_instance.set_surface_override_material(0, material)
	status.damaged.connect(_on_damaged)
	status.status_reset.connect(_on_status_reset)


func _process(_delta: float) -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	_prune_damage_events(now)
	if status.current_hp < status.max_hp and status.last_damage_time >= 0.0:
		if now - status.last_damage_time >= auto_reset_delay:
			reset_dummy()
	var material: Material = mesh_instance.get_active_material(0)
	if material is StandardMaterial3D:
		material.albedo_color = Color.GRAY if status.is_dead() else Color.FIREBRICK


func reset_dummy() -> void:
	status.reset_status()


func _on_damaged(amount: float) -> void:
	_damage_events.append({
		"time": Time.get_ticks_msec() / 1000.0,
		"amount": amount,
	})


func _on_status_reset() -> void:
	_damage_events.clear()


func _prune_damage_events(now: float) -> void:
	while not _damage_events.is_empty() and now - float(_damage_events[0]["time"]) > dps_window:
		_damage_events.remove_at(0)


func _calculate_dps() -> float:
	var total: float = 0.0
	for event in _damage_events:
		total += float(event["amount"])
	return total / maxf(0.1, dps_window)


func get_overlay_text() -> String:
	return "HP %d/%d\nMK %d | DPS %.1f" % [
		int(round(status.current_hp)),
		int(round(status.max_hp)),
		status.mark_stacks,
		_calculate_dps()
	]
