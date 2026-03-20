extends Node3D
class_name RunnerSummon

const StatusController = preload("res://scripts/combat/status_controller.gd")
const TargetDummy = preload("res://scripts/combat/target_dummy.gd")
const FX_GROUP := "runtime_vfx"

enum BrainState {
	IDLE,
	CHASE,
	ATTACK,
}

var lifetime: float = 7.0
var move_speed: float = 4.2
var sense_range: float = 22.0
var attack_range: float = 1.55
var attack_cooldown: float = 0.48
var attack_windup: float = 0.08
var pounce_distance: float = 0.9
var pounce_speed: float = 12.0
var preferred_attack_distance: float = 1.2
var post_attack_backstep: float = 0.38
var attack_damage: float = 0.85
var seed_add: int = 1
var mark_add: int = 1
var preferred_seed_cap: int = 4
var preferred_mark_cap: int = 3

var _life: float = 0.0
var _attack_timer: float = 0.0
var _brain_state: int = BrainState.IDLE
var _target_status: StatusController = null
var _body_root: Node3D
var _body_material: StandardMaterial3D
var _leg_left: Node3D
var _leg_right: Node3D
var _anim_time: float = 0.0
var _base_ground_y: float = 0.0
var _rng := RandomNumberGenerator.new()
var _ground_offset_y: float = 0.02
var _attack_flash_t: float = 0.0
var _base_visual_scale: float = 1.0
var _attack_windup_t: float = 0.0
var _pending_attack_target: StatusController = null


func _ready() -> void:
	add_to_group("seedling_summon")
	_rng.randomize()
	_build_visual()
	_base_ground_y = _sample_ground_height(global_position)
	global_position.y = _base_ground_y + _ground_offset_y


func configure(power: float) -> void:
	var p: float = maxf(1.0, power)
	attack_damage = 0.65 + p * 0.19
	move_speed = 3.8 + p * 0.10
	lifetime = 5.6 + minf(2.8, p * 0.08)
	attack_cooldown = clampf(0.58 - p * 0.004, 0.28, 0.58)
	attack_windup = clampf(0.1 - p * 0.0008, 0.045, 0.1)
	pounce_speed = 10.5 + p * 0.08
	preferred_attack_distance = clampf(1.15 + p * 0.002, 1.1, 1.35)
	preferred_seed_cap = 4 + int(minf(3.0, floor(p / 12.0)))
	preferred_mark_cap = 3 + int(minf(2.0, floor(p / 14.0)))
	if _body_root != null:
		var scale_mul: float = 0.88 + minf(0.4, p * 0.007)
		_base_visual_scale = scale_mul
		_body_root.scale = Vector3.ONE * scale_mul


func set_spawn_target(status: StatusController) -> void:
	if status == null or status.is_dead():
		return
	_target_status = status


func _process(delta: float) -> void:
	_life += delta
	_attack_timer = maxf(0.0, _attack_timer - delta)
	_attack_flash_t = maxf(0.0, _attack_flash_t - delta)
	_attack_windup_t = maxf(0.0, _attack_windup_t - delta)
	_anim_time += delta
	if _life >= lifetime:
		queue_free()
		return

	var perception: Dictionary = _sense_layer()
	_brain_state = _decision_layer(perception)
	_behavior_layer(_brain_state, perception, delta)
	_update_visual(delta, _brain_state)


func _sense_layer() -> Dictionary:
	if _target_status == null or _target_status.is_dead() or _distance_to_status(_target_status) > sense_range:
		_target_status = _find_target()
	var has_target: bool = _target_status != null and not _target_status.is_dead()
	var target_distance: float = INF
	var target_position: Vector3 = global_position
	if has_target:
		target_position = _status_world_position(_target_status)
		target_distance = global_position.distance_to(target_position)
	return {
		"has_target": has_target,
		"target_status": _target_status,
		"target_position": target_position,
		"distance": target_distance,
	}


func _decision_layer(perception: Dictionary) -> int:
	if not bool(perception.get("has_target", false)):
		return BrainState.IDLE
	if float(perception.get("distance", INF)) <= attack_range:
		return BrainState.ATTACK
	return BrainState.CHASE


func _behavior_layer(state: int, perception: Dictionary, delta: float) -> void:
	match state:
		BrainState.IDLE:
			_behavior_idle(delta)
		BrainState.CHASE:
			_behavior_chase(perception, delta)
		BrainState.ATTACK:
			_behavior_attack(perception, delta)
		_:
			_behavior_idle(delta)


func _behavior_idle(delta: float) -> void:
	_pending_attack_target = null
	_attack_windup_t = 0.0
	rotate_y(0.8 * delta)
	var idle_drift: Vector3 = Vector3(cos(_anim_time * 1.8), 0.0, sin(_anim_time * 1.8)) * 0.14 * delta
	global_position += idle_drift
	_keep_on_ground(delta)


func _behavior_chase(perception: Dictionary, delta: float) -> void:
	_pending_attack_target = null
	_attack_windup_t = 0.0
	var target_pos: Vector3 = perception.get("target_position", global_position)
	var to_target: Vector3 = target_pos - global_position
	var planar: Vector3 = Vector3(to_target.x, 0.0, to_target.z)
	var move_gap: float = planar.length() - preferred_attack_distance
	if move_gap > 0.02:
		var step_len: float = minf(move_gap, move_speed * delta)
		var step: Vector3 = planar.normalized() * step_len
		global_position += step
		look_at(global_position + planar, Vector3.UP, true)
	_keep_on_ground(delta)


func _behavior_attack(perception: Dictionary, delta: float) -> void:
	var status: StatusController = perception.get("target_status", null) as StatusController
	if status == null or status.is_dead():
		_pending_attack_target = null
		_attack_windup_t = 0.0
		return
	var target_pos: Vector3 = perception.get("target_position", global_position)
	var planar: Vector3 = Vector3(target_pos.x - global_position.x, 0.0, target_pos.z - global_position.z)
	if planar.length() > 0.01:
		look_at(global_position + planar, Vector3.UP, true)
	_maintain_attack_distance(target_pos, delta)
	_keep_on_ground(delta)
	if _attack_timer > 0.0:
		_pending_attack_target = null
		_attack_windup_t = 0.0
		return
	if _pending_attack_target != status:
		_pending_attack_target = status
		_attack_windup_t = attack_windup
		return
	if _attack_windup_t > 0.0:
		return
	_attack_timer = attack_cooldown
	_pounce_toward_target(target_pos, delta)
	_execute_attack(status)
	_pull_back_from_target(target_pos, delta)
	_pending_attack_target = null


func _pounce_toward_target(target_pos: Vector3, delta: float) -> void:
	var planar: Vector3 = Vector3(target_pos.x - global_position.x, 0.0, target_pos.z - global_position.z)
	if planar.length() <= 0.02:
		return
	var desired_min: float = maxf(0.8, preferred_attack_distance * 0.78)
	var move_gap: float = planar.length() - desired_min
	if move_gap <= 0.01:
		return
	var max_step: float = pounce_speed * maxf(delta, 0.016)
	var step_len: float = minf(pounce_distance, minf(move_gap, max_step))
	global_position += planar.normalized() * step_len
	_keep_on_ground(delta)


func _pull_back_from_target(target_pos: Vector3, delta: float) -> void:
	var away: Vector3 = global_position - target_pos
	var planar: Vector3 = Vector3(away.x, 0.0, away.z)
	if planar.length() <= 0.001:
		return
	var step: float = minf(post_attack_backstep, move_speed * 0.26 * maxf(delta, 0.016))
	global_position += planar.normalized() * step
	_keep_on_ground(delta)


func _maintain_attack_distance(target_pos: Vector3, delta: float) -> void:
	var to_target: Vector3 = target_pos - global_position
	var planar: Vector3 = Vector3(to_target.x, 0.0, to_target.z)
	var dist: float = planar.length()
	if dist <= 0.001:
		return
	var min_dist: float = maxf(0.9, preferred_attack_distance * 0.82)
	var max_dist: float = preferred_attack_distance * 1.12
	if dist < min_dist:
		var back_step: float = minf(min_dist - dist, move_speed * 0.30 * delta)
		global_position -= planar.normalized() * back_step
	elif dist > max_dist:
		var fwd_step: float = minf(dist - max_dist, move_speed * 0.22 * delta)
		global_position += planar.normalized() * fwd_step


func _execute_attack(target: StatusController) -> void:
	if target == null or target.is_dead():
		return
	target.apply_damage(attack_damage)
	_attack_flash_t = 0.13

	var effect_tags: Array[String] = ["summon_runner", "summon_hit"]
	if target.seed_stacks < preferred_seed_cap:
		target.add_seed(seed_add)
		effect_tags.append("seed")
	if target.mark_stacks < preferred_mark_cap:
		target.add_marks(mark_add)
		effect_tags.append("mark")

	var target_dummy: TargetDummy = _resolve_target_dummy(target)
	if target_dummy != null:
		target_dummy.apply_operator_effects(effect_tags)

	var hit_pos: Vector3 = _status_world_position(target) + Vector3(0.0, 0.95, 0.0)
	var attack_origin: Vector3 = global_position + Vector3(0.0, 0.26, 0.0)
	_spawn_attack_link(attack_origin, hit_pos)
	_spawn_origin_flash(attack_origin)
	_spawn_hit_spark(hit_pos)


func _find_target() -> StatusController:
	var best: StatusController = null
	var best_dist: float = sense_range
	for node in get_tree().get_nodes_in_group("target_dummy"):
		if not (node is TargetDummy):
			continue
		var status: StatusController = (node as TargetDummy).status
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


func _resolve_target_dummy(status: StatusController) -> TargetDummy:
	if status == null:
		return null
	var owner_node: Node = status.get_parent()
	if owner_node is TargetDummy:
		return owner_node as TargetDummy
	return null


func _keep_on_ground(delta: float) -> void:
	var ground_y: float = _sample_ground_height(global_position)
	global_position.y = move_toward(global_position.y, ground_y + _ground_offset_y, 5.8 * delta)


func _sample_ground_height(origin: Vector3) -> float:
	var world := get_world_3d()
	if world == null:
		return _base_ground_y
	var state: PhysicsDirectSpaceState3D = world.direct_space_state
	if state == null:
		return _base_ground_y
	var from: Vector3 = origin + Vector3(0.0, 2.0, 0.0)
	var to: Vector3 = origin + Vector3(0.0, -5.0, 0.0)
	var excludes: Array = [self]
	for _attempt in range(6):
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(from, to)
		query.exclude = excludes
		var result: Dictionary = state.intersect_ray(query)
		if result.is_empty():
			break
		var collider: Variant = result.get("collider", null)
		if _is_walkable_ground_collider(collider):
			var point: Vector3 = result.get("position", origin)
			_base_ground_y = point.y
			return _base_ground_y
		if collider != null:
			excludes.append(collider)
	return _base_ground_y


func _is_walkable_ground_collider(collider: Variant) -> bool:
	if not (collider is Node):
		return false
	var node: Node = collider as Node
	if node == self:
		return false
	if node.is_in_group("target_dummy") or node.is_in_group("seedling_summon"):
		return false
	var parent: Node = node.get_parent()
	if parent != null and (parent.is_in_group("target_dummy") or parent.is_in_group("seedling_summon")):
		return false
	return true


func _build_visual() -> void:
	_body_root = Node3D.new()
	_body_root.name = "RunnerBody"
	add_child(_body_root)
	_base_visual_scale = 1.0

	_body_material = StandardMaterial3D.new()
	_body_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_body_material.albedo_color = Color(0.35, 0.95, 0.64, 0.98)
	_body_material.emission_enabled = true
	_body_material.emission = Color(0.35, 0.95, 0.64, 1.0)
	_body_material.emission_energy_multiplier = 2.6
	_body_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	var torso := MeshInstance3D.new()
	var torso_mesh := BoxMesh.new()
	torso_mesh.size = Vector3(0.46, 0.24, 0.74)
	torso.mesh = torso_mesh
	torso.position = Vector3(0.0, 0.23, 0.0)
	torso.set_surface_override_material(0, _body_material)
	_body_root.add_child(torso)

	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.14
	head_mesh.height = 0.28
	head.mesh = head_mesh
	head.position = Vector3(0.0, 0.34, -0.35)
	head.set_surface_override_material(0, _body_material)
	_body_root.add_child(head)

	_leg_left = _create_leg(Vector3(-0.14, 0.08, 0.16))
	_leg_right = _create_leg(Vector3(0.14, 0.08, 0.16))
	_body_root.add_child(_leg_left)
	_body_root.add_child(_leg_right)


func _create_leg(pos: Vector3) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	var leg := MeshInstance3D.new()
	var leg_mesh := BoxMesh.new()
	leg_mesh.size = Vector3(0.1, 0.18, 0.1)
	leg.mesh = leg_mesh
	leg.position = Vector3(0.0, -0.08, 0.0)
	leg.set_surface_override_material(0, _body_material)
	root.add_child(leg)
	return root


func _update_visual(delta: float, state: int) -> void:
	if _body_material != null:
		var pulse: float = 0.84 + 0.2 * sin(Time.get_ticks_msec() / 90.0)
		var state_boost: float = 1.6 if state == BrainState.ATTACK else 0.9
		var windup_boost: float = 1.4 * (_attack_windup_t / maxf(0.001, attack_windup))
		var attack_boost: float = 2.6 * (_attack_flash_t / 0.13)
		_body_material.emission_energy_multiplier = 2.6 + pulse * state_boost + attack_boost + windup_boost

	if _body_root != null:
		var run_weight: float = 0.0
		if state == BrainState.CHASE:
			run_weight = 1.0
		elif state == BrainState.ATTACK:
			run_weight = 0.4
		var bob: float = sin(_anim_time * 13.0) * 0.03 * run_weight
		_body_root.position.y = bob
		var windup_scale: float = 1.0 + 0.06 * (_attack_windup_t / maxf(0.001, attack_windup))
		var flash_scale: float = (1.0 + 0.12 * (_attack_flash_t / 0.13)) * windup_scale
		_body_root.scale = Vector3.ONE * (_base_visual_scale * flash_scale)

	if _leg_left != null and _leg_right != null:
		var swing: float = sin(_anim_time * 16.0) * 0.45
		_leg_left.rotation.x = swing
		_leg_right.rotation.x = -swing


func _spawn_hit_spark(position: Vector3) -> void:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return
	var root := Node3D.new()
	root.name = "RunnerHitSpark"
	root.add_to_group(FX_GROUP)
	scene.add_child(root)
	root.global_position = position

	var core := MeshInstance3D.new()
	var core_mesh := SphereMesh.new()
	core_mesh.radius = 0.14
	core_mesh.height = 0.28
	core.mesh = core_mesh
	var core_mat := StandardMaterial3D.new()
	core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core_mat.albedo_color = Color(0.5, 1.0, 0.72, 1.0)
	core_mat.emission_enabled = true
	core_mat.emission = Color(0.5, 1.0, 0.72, 1.0)
	core_mat.emission_energy_multiplier = 6.4
	core_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	core.set_surface_override_material(0, core_mat)
	root.add_child(core)

	var ring := MeshInstance3D.new()
	var ring_mesh := CylinderMesh.new()
	ring_mesh.top_radius = 0.16
	ring_mesh.bottom_radius = 0.16
	ring_mesh.height = 0.03
	ring_mesh.radial_segments = 18
	ring.mesh = ring_mesh
	ring.rotate_x(deg_to_rad(90.0))
	var ring_mat := StandardMaterial3D.new()
	ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring_mat.albedo_color = Color(0.66, 1.0, 0.84, 0.95)
	ring_mat.emission_enabled = true
	ring_mat.emission = Color(0.66, 1.0, 0.84, 1.0)
	ring_mat.emission_energy_multiplier = 5.2
	ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ring_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ring.set_surface_override_material(0, ring_mat)
	root.add_child(ring)

	var tween := create_tween()
	tween.parallel().tween_property(core, "scale", Vector3.ONE * 1.75, 0.17)
	tween.parallel().tween_property(core_mat, "albedo_color:a", 0.0, 0.17)
	tween.parallel().tween_property(ring, "scale", Vector3.ONE * 2.25, 0.2)
	tween.parallel().tween_property(ring_mat, "albedo_color:a", 0.0, 0.2)
	tween.finished.connect(root.queue_free)


func _spawn_attack_link(start_pos: Vector3, end_pos: Vector3) -> void:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return
	var beam := MeshInstance3D.new()
	beam.name = "RunnerAttackLink"
	beam.add_to_group(FX_GROUP)

	var distance: float = start_pos.distance_to(end_pos)
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.03
	mesh.bottom_radius = 0.03
	mesh.height = maxf(0.1, distance)
	mesh.radial_segments = 8
	mesh.rings = 1
	beam.mesh = mesh

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.52, 1.0, 0.76, 0.96)
	mat.emission_enabled = true
	mat.emission = Color(0.52, 1.0, 0.76, 1.0)
	mat.emission_energy_multiplier = 8.2
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = false
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	beam.set_surface_override_material(0, mat)

	scene.add_child(beam)
	var center: Vector3 = start_pos.lerp(end_pos, 0.5)
	var direction: Vector3 = (end_pos - start_pos).normalized()
	beam.global_position = center
	beam.look_at(center + direction, Vector3.UP, true)
	beam.rotate_object_local(Vector3.RIGHT, deg_to_rad(90.0))

	var tween := create_tween()
	tween.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.11)
	tween.parallel().tween_property(beam, "scale", Vector3(1.0, 1.0, 0.82), 0.11)
	tween.finished.connect(beam.queue_free)


func _spawn_origin_flash(position: Vector3) -> void:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return
	var flash := MeshInstance3D.new()
	flash.name = "RunnerOriginFlash"
	flash.add_to_group(FX_GROUP)
	var mesh := SphereMesh.new()
	mesh.radius = 0.08
	mesh.height = 0.16
	flash.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.62, 1.0, 0.82, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.62, 1.0, 0.82, 1.0)
	mat.emission_energy_multiplier = 6.6
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash.set_surface_override_material(0, mat)
	scene.add_child(flash)
	flash.global_position = position
	var tween := create_tween()
	tween.parallel().tween_property(flash, "scale", Vector3.ONE * 1.65, 0.11)
	tween.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.11)
	tween.finished.connect(flash.queue_free)
