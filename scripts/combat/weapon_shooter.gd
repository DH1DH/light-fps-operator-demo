extends Node3D
class_name WeaponShooter

@export var base_damage: float = 10.0
@export var base_pellet_count: int = 1
@export var base_spread: float = 1.5
@export var fire_interval: float = 0.2
@export var hit_range: float = 150.0
@export var tracer_lifetime: float = 0.2
@export var tracer_width: float = 0.08
@export var impact_lifetime: float = 0.25
@export var tracer_muzzle_offset: Vector3 = Vector3(0.28, -0.18, -0.35)
@export var tracer_segments: int = 8
@export var tracer_segment_gap: float = 0.012

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
	if (Input.is_action_pressed("shoot") or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)) and Time.get_ticks_msec() / 1000.0 >= _next_fire_time:
		DebugLog.add_entry("Fire requested from _process")
		fire()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if Time.get_ticks_msec() / 1000.0 >= _next_fire_time:
			DebugLog.add_entry("Fire requested from _unhandled_input")
			fire()


func current_chain_text() -> String:
	return _chain.describe_order()


func fire() -> void:
	if shoot_camera == null:
		DebugLog.add_entry("Fire aborted: shoot_camera is null")
		return
	_next_fire_time = Time.get_ticks_msec() / 1000.0 + fire_interval
	var shot: ShotContext = ShotContext.new()
	shot.damage = base_damage
	shot.pellet_count = max(1, base_pellet_count)
	shot.spread_angle = maxf(0.0, base_spread)

	_chain.on_before_fire(shot)
	shot.pellet_count = max(1, shot.pellet_count)
	shot.spread_angle = maxf(0.0, shot.spread_angle)
	last_predicted_shot = shot
	DebugLog.add_entry("Fire executing: pellets=%d spread=%.2f damage=%.2f chain=%s" % [shot.pellet_count, shot.spread_angle, shot.damage, current_chain_text()])

	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var owner_body: Node = get_parent()
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
			DebugLog.add_entry("Ray hit: collider=%s point=%s" % [str(collider), str(end)])
			if collider is Node:
				var target: StatusController = _resolve_status(collider)
				if target != null:
					var hit_context: HitContext = HitContext.new()
					hit_context.damage = shot.damage
					hit_context.target_status = target
					hit_context.hit_point = end
					_chain.on_hit(hit_context)
					target.apply_damage(hit_context.damage)
					DebugLog.add_entry("Damage applied: hp=%.2f marks=%d" % [target.current_hp, target.mark_stacks])
				else:
					DebugLog.add_entry("Ray hit node but no StatusController resolved")
		else:
			DebugLog.add_entry("Ray missed")
		var tracer_start: Vector3 = _get_tracer_start()
		_spawn_tracer(tracer_start, end)
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


func _get_spread_direction(forward: Vector3, spread_angle: float) -> Vector3:
	if spread_angle <= 0.0:
		return forward.normalized()
	var yaw: float = randf_range(-spread_angle, spread_angle)
	var pitch: float = randf_range(-spread_angle, spread_angle)
	var basis: Basis = Basis.from_euler(Vector3(deg_to_rad(pitch), deg_to_rad(yaw), 0.0))
	return (basis * forward).normalized()


func _get_tracer_start() -> Vector3:
	return shoot_camera.to_global(tracer_muzzle_offset)


func _spawn_tracer(start: Vector3, end: Vector3) -> void:
	var distance: float = start.distance_to(end)
	var direction: Vector3 = (end - start).normalized()
	var segment_count: int = max(2, tracer_segments)
	var segment_length: float = maxf(0.08, distance / float(segment_count))
	for index in range(segment_count):
		var segment := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = tracer_width * 0.5
		mesh.bottom_radius = tracer_width * 0.5
		mesh.height = segment_length
		mesh.radial_segments = 10
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

		get_tree().current_scene.add_child(segment)
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

	get_tree().current_scene.add_child(marker)
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
