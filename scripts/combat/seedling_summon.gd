extends Node3D
class_name SeedlingSummon

const StatusController = preload("res://scripts/combat/status_controller.gd")
const TargetDummy = preload("res://scripts/combat/target_dummy.gd")

var lifetime: float = 3.0
var move_speed: float = 5.0
var hit_radius: float = 0.8
var tick_interval: float = 0.3
var hit_damage: float = 6.0

var _life: float = 0.0
var _tick: float = 0.0
var _mesh: MeshInstance3D
var _material: StandardMaterial3D


func _ready() -> void:
	add_to_group("seedling_summon")
	_build_visual()


func configure(power: float) -> void:
	var p: float = maxf(1.0, power)
	hit_damage = 3.0 + p * 0.5
	move_speed = 4.0 + p * 0.1
	lifetime = 2.6 + minf(2.4, p * 0.05)
	if _mesh != null:
		var s: float = 0.22 + minf(0.35, p * 0.008)
		_mesh.scale = Vector3.ONE * s


func _process(delta: float) -> void:
	_life += delta
	if _life >= lifetime:
		queue_free()
		return

	_tick += delta
	var target: StatusController = _find_target()
	if target == null:
		position.y += 0.35 * delta
		rotate_y(1.6 * delta)
		_update_visual(delta)
		return

	var target_pos: Vector3 = _status_world_position(target) + Vector3(0.0, 0.9, 0.0)
	var to_target: Vector3 = target_pos - global_position
	var dist: float = to_target.length()
	if dist > 0.001:
		global_position += to_target.normalized() * move_speed * delta
		look_at(target_pos, Vector3.UP, true)
	rotate_object_local(Vector3.RIGHT, deg_to_rad(90.0))

	if dist <= hit_radius and _tick >= tick_interval:
		_tick = 0.0
		target.apply_damage(hit_damage)
		_spawn_hit_spark(target_pos)

	_update_visual(delta)


func _find_target() -> StatusController:
	var best: StatusController = null
	var best_dist := INF
	for node in get_tree().get_nodes_in_group("target_dummy"):
		if not (node is TargetDummy):
			continue
		var status: StatusController = (node as TargetDummy).status
		if status == null or status.is_dead():
			continue
		var d: float = node.global_position.distance_to(global_position)
		if d < best_dist:
			best_dist = d
			best = status
	return best


func _status_world_position(status: StatusController) -> Vector3:
	if status == null:
		return global_position
	var owner_node := status.get_parent()
	if owner_node is Node3D:
		return owner_node.global_position
	return global_position


func _build_visual() -> void:
	_mesh = MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.22
	mesh.height = 0.44
	_mesh.mesh = mesh

	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.albedo_color = Color(0.72, 1.0, 0.35, 0.95)
	_material.emission_enabled = true
	_material.emission = Color(0.72, 1.0, 0.35, 1.0)
	_material.emission_energy_multiplier = 4.2
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mesh.set_surface_override_material(0, _material)
	add_child(_mesh)


func _update_visual(delta: float) -> void:
	if _material == null:
		return
	var pulse: float = 0.8 + 0.2 * sin(Time.get_ticks_msec() / 120.0)
	_material.emission_energy_multiplier = 3.8 + pulse * 1.8
	if _mesh != null:
		var spin: float = 2.0 + delta * 3.0
		_mesh.rotate_y(spin * delta)


func _spawn_hit_spark(position: Vector3) -> void:
	var spark := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.1
	mesh.height = 0.2
	spark.mesh = mesh

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.9, 1.0, 0.5, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.9, 1.0, 0.5, 1.0)
	mat.emission_energy_multiplier = 5.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	spark.set_surface_override_material(0, mat)

	get_tree().current_scene.add_child(spark)
	spark.global_position = position

	var tween := create_tween()
	tween.parallel().tween_property(spark, "scale", Vector3.ONE * 1.8, 0.25)
	tween.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.25)
	tween.finished.connect(spark.queue_free)
