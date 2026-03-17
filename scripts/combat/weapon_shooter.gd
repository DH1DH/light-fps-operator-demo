extends Node3D
class_name WeaponShooter
const OperatorDefinition = preload("res://scripts/operators/operator_definition.gd")
const ShotContext = preload("res://scripts/operators/shot_context.gd")
const HitContext = preload("res://scripts/operators/hit_context.gd")
const OperatorChain = preload("res://scripts/operators/operator_chain.gd")
const StatusController = preload("res://scripts/combat/status_controller.gd")
const TargetDummy = preload("res://scripts/combat/target_dummy.gd")
const SeedlingSummon = preload("res://scripts/combat/seedling_summon.gd")

@export var base_damage: float = 10.0
@export var base_pellet_count: int = 1
@export var base_spread: float = 1.5
@export var fire_interval: float = 0.2
@export var hit_range: float = 150.0
@export var tracer_lifetime: float = 0.2
@export var tracer_width: float = 0.08
@export var impact_lifetime: float = 0.25
@export var tracer_muzzle_offset: Vector3 = Vector3(0.28, -0.18, -0.35)
@export var tracer_segments: int = 6
@export var tracer_segment_gap: float = 0.012
@export var max_total_tracer_segments_per_shot: int = 20
@export var verbose_fire_logs: bool = false

@onready var shoot_camera: Camera3D = $"../CameraPivot/Camera3D"

var last_predicted_shot: ShotContext = ShotContext.new()
var _chain: OperatorChain = OperatorChain.new()
var _next_fire_time: float = 0.0

func _ready() -> void:
	_rebuild_chain()
	GameState.state_changed.connect(_rebuild_chain)
	DebugLog.add_entry("WeaponShooter ready; camera=%s" % [str(shoot_camera != null)])


func _exit_tree() -> void:
	if GameState.state_changed.is_connected(_rebuild_chain):
		GameState.state_changed.disconnect(_rebuild_chain)


func _process(_delta: float) -> void:
	if GameState.operator_menu_open:
		return
	if (Input.is_action_pressed("shoot") or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)) and Time.get_ticks_msec() / 1000.0 >= _next_fire_time:
		fire()


func current_chain_text() -> String:
	return _chain.describe_order()


func fire() -> void:
	if GameState.operator_menu_open:
		return
	if shoot_camera == null:
		DebugLog.add_entry("Fire aborted: shoot_camera is null")
		return
	_next_fire_time = Time.get_ticks_msec() / 1000.0 + fire_interval
	var shot: ShotContext = ShotContext.new()
	shot.damage = base_damage
	shot.pellet_count = max(1, base_pellet_count)
	shot.spread_angle = maxf(0.0, base_spread)

	_chain.on_fire(shot)
	shot.pellet_count = max(1, shot.pellet_count)
	shot.spread_angle = maxf(0.0, shot.spread_angle)
	last_predicted_shot = shot
	_log_verbose("Fire executing: pellets=%d spread=%.2f damage=%.2f chain=%s" % [shot.pellet_count, shot.spread_angle, shot.damage, current_chain_text()])

	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var owner_body: Node = get_parent()
	var all_statuses: Array[StatusController] = _get_all_statuses()
	for _pellet_index in range(shot.pellet_count):
		var ray_start: Vector3 = shoot_camera.global_position
		var direction: Vector3 = _get_spread_direction(-shoot_camera.global_basis.z, shot.spread_angle)
		var end: Vector3 = ray_start + direction * hit_range
		var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(ray_start, end)
		query.exclude = [owner_body]
		var result: Dictionary = space_state.intersect_ray(query)
		if not result.is_empty():
			end = result.get("position", end)
			var collider: Variant = result.get("collider")
			_log_verbose("Ray hit: collider=%s point=%s" % [str(collider), str(end)])
			if collider is Node:
				var target: StatusController = _resolve_status(collider)
				if target != null:
					var hit_context: HitContext = HitContext.new()
					hit_context.damage = shot.damage
					hit_context.target_status = target
					hit_context.hit_point = end
					hit_context.target_world_position = _get_status_world_position(target)
					hit_context.shot_pellet_count = shot.pellet_count
					hit_context.all_statuses = all_statuses
					hit_context.effect_tags.assign(shot.effect_tags)
					var was_alive: bool = not target.is_dead()
					_chain.on_hit(hit_context)
					target.apply_damage(hit_context.damage)
					if was_alive and target.is_dead():
						_chain.on_kill(hit_context)
					_apply_context_side_effects(hit_context)
					var target_dummy: TargetDummy = _resolve_target_dummy(collider)
					if target_dummy != null:
						target_dummy.apply_operator_effects(hit_context.effect_tags)
					_log_verbose("Damage applied: hp=%.2f marks=%d" % [target.current_hp, target.mark_stacks])
				else:
					_log_verbose("Ray hit node but no StatusController resolved")
		else:
			_log_verbose("Ray missed")
		var tracer_start: Vector3 = _get_tracer_start()
		_spawn_tracer(tracer_start, end, shot.pellet_count)
		_spawn_impact_marker(end)


func _resolve_status(node: Node) -> StatusController:
	if node is TargetDummy:
		return node.status
	if node is StatusController:
		return node
	if node.has_node("StatusController"):
		return node.get_node("StatusController") as StatusController
	var parent: Node = node.get_parent()
	if parent != null and parent.has_node("StatusController"):
		return parent.get_node("StatusController") as StatusController
	return null


func _resolve_target_dummy(node: Node) -> TargetDummy:
	if node is TargetDummy:
		return node
	var parent: Node = node.get_parent()
	while parent != null:
		if parent is TargetDummy:
			return parent
		parent = parent.get_parent()
	return null


func _get_spread_direction(forward: Vector3, spread_angle: float) -> Vector3:
	if spread_angle <= 0.0:
		return forward.normalized()
	var yaw: float = randf_range(-spread_angle, spread_angle)
	var pitch: float = randf_range(-spread_angle, spread_angle)
	var basis: Basis = Basis.from_euler(Vector3(deg_to_rad(pitch), deg_to_rad(yaw), 0.0))
	return (basis * forward).normalized()


func _get_tracer_start() -> Vector3:
	return shoot_camera.to_global(tracer_muzzle_offset)


func _spawn_tracer(start: Vector3, end: Vector3, pellet_count: int) -> void:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return
	var distance: float = start.distance_to(end)
	if distance <= 0.001:
		return
	var direction: Vector3 = (end - start).normalized()
	var base_segments: int = clampi(tracer_segments, 2, 10)
	var per_shot_cap: int = maxi(2, int(floor(float(max(2, max_total_tracer_segments_per_shot)) / float(max(1, pellet_count)))))
	var distance_segments: int = clampi(int(ceil(distance / 9.0)), 2, base_segments)
	var segment_count: int = mini(base_segments, mini(per_shot_cap, distance_segments))
	var segment_length: float = maxf(0.08, distance / float(segment_count))
	for index in range(segment_count):
		var segment := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = tracer_width * 0.5
		mesh.bottom_radius = tracer_width * 0.5
		mesh.height = segment_length
		mesh.radial_segments = 6
		mesh.rings = 1
		segment.mesh = mesh

		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Color(1.0, 0.97, 0.55, 1.0)
		material.emission_enabled = true
		material.emission = Color(1.0, 0.95, 0.55, 1.0)
		material.emission_energy_multiplier = 10.0
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.no_depth_test = true
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		segment.set_surface_override_material(0, material)

		scene.add_child(segment)
		var center_ratio: float = (float(index) + 0.5) / float(segment_count)
		var center: Vector3 = start.lerp(end, center_ratio)
		segment.global_position = center
		segment.look_at(center + direction, Vector3.UP, true)
		segment.rotate_object_local(Vector3.RIGHT, deg_to_rad(90.0))

		var tween := create_tween()
		tween.tween_interval(float(index) * tracer_segment_gap)
		tween.tween_property(material, "albedo_color:a", 0.0, tracer_lifetime)
		tween.finished.connect(segment.queue_free)


func _spawn_impact_marker(position: Vector3) -> void:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return
	var marker := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.12
	mesh.height = 0.24
	marker.mesh = mesh

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.4, 1.0, 1.0, 1.0)
	material.emission_enabled = true
	material.emission = Color(0.4, 1.0, 1.0, 1.0)
	material.emission_energy_multiplier = 8.0
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	marker.set_surface_override_material(0, material)

	scene.add_child(marker)
	marker.global_position = position

	var tween := create_tween()
	tween.parallel().tween_property(marker, "scale", Vector3.ONE * 1.8, impact_lifetime)
	tween.parallel().tween_property(material, "albedo_color:a", 0.0, impact_lifetime)
	tween.finished.connect(marker.queue_free)


func _rebuild_chain() -> void:
	var definitions: Array[OperatorDefinition] = []
	definitions.assign(GameState.loadout)
	_chain.rebuild(definitions)
	DebugLog.add_entry("Chain rebuilt: %s" % _chain.describe_order())


func _get_all_statuses() -> Array[StatusController]:
	var out: Array[StatusController] = []
	for node in get_tree().get_nodes_in_group("target_dummy"):
		if node is TargetDummy:
			out.append(node.status)
	return out


func _get_status_world_position(status: StatusController) -> Vector3:
	if status == null:
		return Vector3.ZERO
	var owner_node := status.get_parent()
	if owner_node is Node3D:
		return owner_node.global_position
	return Vector3.ZERO


func _apply_context_side_effects(context: HitContext) -> void:
	if context == null:
		return
	if context.pending_coin_gain > 0:
		GameState.add_gold(context.pending_coin_gain)
		DebugLog.add_entry("Coin gain: +%d" % context.pending_coin_gain)
	if context.pending_spawn_count > 0:
		var spawn_power: float = context.pending_spawn_power / float(max(1, context.pending_spawn_count))
		for _index in range(context.pending_spawn_count):
			_spawn_seedling(context.target_world_position + Vector3(randf_range(-0.8, 0.8), 0.9, randf_range(-0.8, 0.8)), spawn_power)
		DebugLog.add_entry("Spawn trigger: count=%d" % context.pending_spawn_count)


func _spawn_seedling(position: Vector3, power: float) -> void:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return
	var summon := SeedlingSummon.new()
	scene.add_child(summon)
	summon.global_position = position
	summon.configure(power)


func _log_verbose(message: String) -> void:
	if verbose_fire_logs:
		DebugLog.add_entry(message)
