extends Node3D
class_name SeedlingSummon

const StatusController = preload("res://scripts/combat/status_controller.gd")
const CombatTargeting = preload("res://scripts/combat/combat_targeting.gd")
const FX_GROUP := "runtime_vfx"

enum SummonMode {
	RUNNER,
	ATTACHED,
}

enum SummonForm {
	AUTO,
	RUNNER,
	ATTACHED,
}

var lifetime: float = 4.2
var move_speed: float = 5.8
var acquire_range: float = 18.0
var runner_fire_interval: float = 0.26
var attached_fire_interval: float = 0.18
var shot_damage: float = 0.95
var preferred_seed_cap: int = 4
var preferred_mark_cap: int = 3
var status_add_amount: int = 1
var attach_trigger_burn_stacks: int = 1
var attach_duration: float = 1.8
var attach_orbit_speed: float = 5.0
var attach_distance: float = 1.6

var _life: float = 0.0
var _cooldown: float = 0.0
var _mode: int = SummonMode.RUNNER
var _form: int = SummonForm.AUTO
var _mesh_root: Node3D
var _core_mesh: MeshInstance3D
var _tip_mesh: MeshInstance3D
var _material: StandardMaterial3D
var _target_status: StatusController = null
var _attach_elapsed: float = 0.0
var _attach_angle: float = 0.0
var _attach_y: float = 1.05
var _rng := RandomNumberGenerator.new()
var _attack_flash_t: float = 0.0
var _base_visual_scale: float = 1.0


func _ready() -> void:
	add_to_group("seedling_summon")
	_rng.randomize()
	_build_visual()
	_set_mode_visual()


func configure(power: float) -> void:
	var p: float = maxf(1.0, power)
	shot_damage = 0.65 + p * 0.22
	move_speed = 4.8 + p * 0.15
	lifetime = 3.4 + minf(2.6, p * 0.08)
	runner_fire_interval = clampf(0.30 - p * 0.004, 0.15, 0.30)
	attached_fire_interval = clampf(0.22 - p * 0.003, 0.12, 0.22)
	preferred_seed_cap = 4 + int(minf(3.0, floor(p / 10.0)))
	preferred_mark_cap = 3 + int(minf(2.0, floor(p / 12.0)))
	if _mesh_root != null:
		var scale_mul: float = 0.86 + minf(0.42, p * 0.008)
		_base_visual_scale = scale_mul
		_mesh_root.scale = Vector3.ONE * scale_mul


func apply_form(form: String, preferred_target: StatusController = null) -> void:
	var normalized: String = form.strip_edges().to_lower()
	match normalized:
		"runner":
			_form = SummonForm.RUNNER
			_mode = SummonMode.RUNNER
		"attached":
			_form = SummonForm.ATTACHED
			_mode = SummonMode.RUNNER
		_:
			_form = SummonForm.AUTO
			_mode = SummonMode.RUNNER
	if preferred_target != null and not preferred_target.is_dead():
		_target_status = preferred_target
		if _form == SummonForm.ATTACHED and _distance_to_status(preferred_target) <= attach_distance * 1.7:
			_enter_attached_mode()
	_set_mode_visual()


func _process(delta: float) -> void:
	_life += delta
	_attack_flash_t = maxf(0.0, _attack_flash_t - delta)
	if _life >= lifetime:
		queue_free()
		return

	_cooldown += delta
	if _target_status == null or _target_status.is_dead() or _distance_to_status(_target_status) > acquire_range:
		_target_status = _find_target()
		if _target_status == null:
			_mode = SummonMode.RUNNER

	if _target_status != null:
		if _mode == SummonMode.RUNNER and _wants_attached_mode() and _can_attach_to_target(_target_status) and _distance_to_status(_target_status) <= attach_distance:
			_enter_attached_mode()
		if _mode == SummonMode.ATTACHED:
			_update_attached_motion(delta)
		else:
			_update_runner_motion(delta)
	else:
		_idle_motion(delta)

	if _target_status != null and _cooldown >= _active_fire_interval():
		_cooldown = 0.0
		_fire_needle(_target_status)

	_update_visual(delta)


func _idle_motion(delta: float) -> void:
	global_position += Vector3(0.0, 0.35 * delta, 0.0)
	rotate_y(1.6 * delta)


func _update_runner_motion(delta: float) -> void:
	if _target_status == null:
		return
	var anchor: Vector3 = _status_world_position(_target_status) + Vector3(0.0, 0.08, 0.0)
	var to_anchor: Vector3 = anchor - global_position
	var planar: Vector3 = Vector3(to_anchor.x, 0.0, to_anchor.z)
	if planar.length() > 0.03:
		global_position += planar.normalized() * move_speed * delta
		look_at(global_position + planar, Vector3.UP, true)
	global_position.y = move_toward(global_position.y, anchor.y, 2.4 * delta)
	var bob: float = 0.05 * sin(Time.get_ticks_msec() / 120.0)
	global_position.y += bob * delta


func _update_attached_motion(delta: float) -> void:
	if _target_status == null:
		_exit_attached_mode()
		return
	_attach_elapsed += delta
	if _attach_elapsed >= attach_duration or _target_status.is_dead() or not _can_attach_to_target(_target_status):
		_exit_attached_mode()
		return
	_attach_angle += attach_orbit_speed * delta
	var base: Vector3 = _status_world_position(_target_status) + Vector3(0.0, _attach_y, 0.0)
	var orbit: Vector3 = Vector3(cos(_attach_angle), 0.0, sin(_attach_angle)) * 0.35
	var desired: Vector3 = base + orbit
	global_position = global_position.lerp(desired, clampf(delta * 14.0, 0.0, 1.0))
	look_at(base, Vector3.UP, true)


func _enter_attached_mode() -> void:
	_mode = SummonMode.ATTACHED
	_attach_elapsed = 0.0
	_attach_angle = _rng.randf_range(0.0, TAU)
	_attach_y = _rng.randf_range(0.95, 1.28)
	_set_mode_visual()


func _exit_attached_mode() -> void:
	_mode = SummonMode.RUNNER
	_set_mode_visual()
	if _target_status != null and _target_status.is_dead():
		_target_status = _find_target()


func _active_fire_interval() -> float:
	return attached_fire_interval if _mode == SummonMode.ATTACHED else runner_fire_interval


func _wants_attached_mode() -> bool:
	if _form == SummonForm.RUNNER:
		return false
	return true


func _can_attach_to_target(target: StatusController) -> bool:
	if target == null or target.is_dead():
		return false
	if _form == SummonForm.ATTACHED:
		return true
	return _should_attach_to_target(target)


func _should_attach_to_target(target: StatusController) -> bool:
	if target == null or target.is_dead():
		return false
	return target.burn_stacks >= attach_trigger_burn_stacks


func _fire_needle(target: StatusController) -> void:
	if target == null or target.is_dead():
		return
	_attack_flash_t = 0.12
	var hit_pos: Vector3 = _status_world_position(target) + Vector3(0.0, 1.0, 0.0)
	target.apply_damage(shot_damage)
	var tags: Array[String] = _apply_support_status(target)
	tags.append("summon_hit")
	if not tags.is_empty():
		CombatTargeting.apply_operator_effects_to_status(target, tags)
	var origin: Vector3 = global_position + Vector3(0.0, 0.18, 0.0)
	_spawn_origin_flash(origin)
	_spawn_needle_trace(origin, hit_pos)
	_spawn_hit_spark(hit_pos)


func _apply_support_status(target: StatusController) -> Array[String]:
	var tags: Array[String] = []
	if _mode == SummonMode.ATTACHED:
		if target.burn_stacks < 6:
			target.add_burn(status_add_amount)
			tags.append("burn")
		if target.mark_stacks < preferred_mark_cap:
			target.add_marks(status_add_amount)
			tags.append("mark")
		elif target.seed_stacks < preferred_seed_cap:
			target.add_seed(status_add_amount)
			tags.append("seed")
		return tags

	if target.seed_stacks < preferred_seed_cap:
		target.add_seed(status_add_amount)
		tags.append("seed")
	if target.mark_stacks < preferred_mark_cap:
		target.add_marks(status_add_amount)
		tags.append("mark")
	if tags.is_empty():
		if target.seed_stacks <= target.mark_stacks:
			target.add_seed(status_add_amount)
			tags.append("seed")
		else:
			target.add_marks(status_add_amount)
			tags.append("mark")
	return tags


func _find_target() -> StatusController:
	var best: StatusController = null
	var best_dist: float = acquire_range
	for node in get_tree().get_nodes_in_group(CombatTargeting.COMBAT_TARGET_GROUP):
		var status: StatusController = CombatTargeting.resolve_status_from_node(node)
		if status == null or status.is_dead():
			continue
		var dist: float = _distance_to_status(status)
		if dist < best_dist:
			best_dist = dist
			best = status
	return best


func _distance_to_status(status: StatusController) -> float:
	return global_position.distance_to(_status_world_position(status))


func _status_world_position(status: StatusController) -> Vector3:
	if status == null:
		return global_position
	var owner_node: Node = status.get_parent()
	if owner_node is Node3D:
		return (owner_node as Node3D).global_position
	return global_position


func _build_visual() -> void:
	_mesh_root = Node3D.new()
	_mesh_root.name = "NeedleRoot"
	add_child(_mesh_root)
	_base_visual_scale = 1.0

	_core_mesh = MeshInstance3D.new()
	var core := CapsuleMesh.new()
	core.radius = 0.11
	core.mid_height = 0.32
	_core_mesh.mesh = core
	_mesh_root.add_child(_core_mesh)

	_tip_mesh = MeshInstance3D.new()
	var tip := SphereMesh.new()
	tip.radius = 0.07
	tip.height = 0.14
	_tip_mesh.mesh = tip
	_tip_mesh.position = Vector3(0.0, 0.0, -0.26)
	_mesh_root.add_child(_tip_mesh)

	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.albedo_color = Color(0.55, 1.0, 0.78, 0.96)
	_material.emission_enabled = true
	_material.emission = Color(0.55, 1.0, 0.78, 1.0)
	_material.emission_energy_multiplier = 5.0
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_core_mesh.set_surface_override_material(0, _material)
	_tip_mesh.set_surface_override_material(0, _material)


func _set_mode_visual() -> void:
	if _material == null:
		return
	if _mode == SummonMode.ATTACHED:
		_material.albedo_color = Color(1.0, 0.67, 0.32, 0.95)
		_material.emission = Color(1.0, 0.67, 0.32, 1.0)
	else:
		_material.albedo_color = Color(0.55, 1.0, 0.78, 0.96)
		_material.emission = Color(0.55, 1.0, 0.78, 1.0)


func _update_visual(delta: float) -> void:
	if _material != null:
		var pulse: float = 0.86 + 0.22 * sin(Time.get_ticks_msec() / 95.0)
		var base_energy: float = 6.2 if _mode == SummonMode.ATTACHED else 4.8
		var attack_boost: float = 2.4 * (_attack_flash_t / 0.12)
		_material.emission_energy_multiplier = base_energy + pulse * 2.1 + attack_boost
	if _mesh_root != null:
		var spin_speed: float = 3.4 if _mode == SummonMode.ATTACHED else 2.2
		_mesh_root.rotate_y(spin_speed * delta)
		var flash_scale: float = 1.0 + 0.1 * (_attack_flash_t / 0.12)
		_mesh_root.scale = Vector3.ONE * (_base_visual_scale * flash_scale)


func _spawn_needle_trace(start_pos: Vector3, end_pos: Vector3) -> void:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return
	var beam := MeshInstance3D.new()
	beam.name = "NeedleTrace"
	beam.add_to_group(FX_GROUP)

	var distance: float = start_pos.distance_to(end_pos)
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.03
	mesh.bottom_radius = 0.03
	mesh.height = maxf(0.1, distance)
	mesh.radial_segments = 6
	mesh.rings = 1
	beam.mesh = mesh

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if _mode == SummonMode.ATTACHED:
		mat.albedo_color = Color(1.0, 0.78, 0.42, 0.95)
		mat.emission = Color(1.0, 0.78, 0.42, 1.0)
	else:
		mat.albedo_color = Color(0.72, 1.0, 0.86, 0.95)
		mat.emission = Color(0.72, 1.0, 0.86, 1.0)
	mat.emission_enabled = true
	mat.emission_energy_multiplier = 9.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	beam.set_surface_override_material(0, mat)

	scene.add_child(beam)
	var center: Vector3 = start_pos.lerp(end_pos, 0.5)
	var direction: Vector3 = (end_pos - start_pos).normalized()
	beam.global_position = center
	beam.look_at(center + direction, Vector3.UP, true)
	beam.rotate_object_local(Vector3.RIGHT, deg_to_rad(90.0))

	var tween := beam.create_tween()
	tween.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.15)
	tween.parallel().tween_property(beam, "scale", Vector3(1.0, 1.0, 0.86), 0.15)
	tween.finished.connect(beam.queue_free)


func _spawn_hit_spark(position: Vector3) -> void:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return
	var root := Node3D.new()
	root.name = "SeedHitSpark"
	root.add_to_group(FX_GROUP)
	scene.add_child(root)
	root.global_position = position

	var base_color: Color = Color(1.0, 0.78, 0.38, 1.0) if _mode == SummonMode.ATTACHED else Color(0.88, 1.0, 0.72, 1.0)
	var ring_color: Color = Color(1.0, 0.82, 0.52, 0.95) if _mode == SummonMode.ATTACHED else Color(0.76, 1.0, 0.86, 0.95)

	var core := MeshInstance3D.new()
	var core_mesh := SphereMesh.new()
	core_mesh.radius = 0.11
	core_mesh.height = 0.22
	core.mesh = core_mesh
	var core_mat := StandardMaterial3D.new()
	core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core_mat.albedo_color = base_color
	core_mat.emission_enabled = true
	core_mat.emission = base_color
	core_mat.emission_energy_multiplier = 6.4
	core_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	core.set_surface_override_material(0, core_mat)
	root.add_child(core)

	var ring := MeshInstance3D.new()
	var ring_mesh := CylinderMesh.new()
	ring_mesh.top_radius = 0.14
	ring_mesh.bottom_radius = 0.14
	ring_mesh.height = 0.025
	ring_mesh.radial_segments = 16
	ring.mesh = ring_mesh
	ring.rotate_x(deg_to_rad(90.0))
	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.albedo_color = ring_color
	ring_mat.emission_enabled = true
	ring_mat.emission = ring_color
	ring_mat.emission_energy_multiplier = 5.2
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ring.set_surface_override_material(0, ring_mat)
	root.add_child(ring)

	var tween := root.create_tween()
	tween.parallel().tween_property(core, "scale", Vector3.ONE * 1.7, 0.16)
	tween.parallel().tween_property(core_mat, "albedo_color:a", 0.0, 0.16)
	tween.parallel().tween_property(ring, "scale", Vector3.ONE * 2.2, 0.2)
	tween.parallel().tween_property(ring_mat, "albedo_color:a", 0.0, 0.2)
	tween.finished.connect(root.queue_free)


func _spawn_origin_flash(position: Vector3) -> void:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return
	var flash := MeshInstance3D.new()
	flash.name = "SeedOriginFlash"
	flash.add_to_group(FX_GROUP)
	var mesh := SphereMesh.new()
	mesh.radius = 0.07
	mesh.height = 0.14
	flash.mesh = mesh
	var color: Color = Color(1.0, 0.8, 0.42, 1.0) if _mode == SummonMode.ATTACHED else Color(0.84, 1.0, 0.78, 1.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 6.2
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash.set_surface_override_material(0, mat)
	scene.add_child(flash)
	flash.global_position = position
	var tween := flash.create_tween()
	tween.parallel().tween_property(flash, "scale", Vector3.ONE * 1.55, 0.1)
	tween.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.1)
	tween.finished.connect(flash.queue_free)
