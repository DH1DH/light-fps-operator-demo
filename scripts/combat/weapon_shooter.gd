extends Node3D
class_name WeaponShooter
const OperatorDefinition = preload("res://scripts/operators/operator_definition.gd")
const ShotContext = preload("res://scripts/operators/shot_context.gd")
const HitContext = preload("res://scripts/operators/hit_context.gd")
const OperatorChain = preload("res://scripts/operators/operator_chain.gd")
const StatusController = preload("res://scripts/combat/status_controller.gd")
const CombatTargeting = preload("res://scripts/combat/combat_targeting.gd")
const SeedlingSummon = preload("res://scripts/combat/seedling_summon.gd")
const RunnerSummon = preload("res://scripts/combat/runner_summon.gd")
const FX_GROUP := "runtime_vfx"
const HAND_LEFT := "left"
const HAND_RIGHT := "right"
const INVALID_POS := Vector3(1e20, 1e20, 1e20)

@export var base_damage: float = 1.0
@export var base_pellet_count: int = 1
@export var base_spread: float = 1.5
@export var fire_interval: float = 0.2
@export var enforce_phase_cycle: bool = false
@export var build_phase_damage_multiplier: float = 0.12
@export var resolve_phase_damage_multiplier: float = 2.2
@export var magazine_capacity: int = 10
@export var reload_duration: float = 0.4
@export var hit_range: float = 150.0
@export var tracer_lifetime: float = 0.2
@export var tracer_width: float = 0.08
@export var impact_lifetime: float = 0.25
@export var tracer_muzzle_offset: Vector3 = Vector3(0.28, -0.18, -0.35)
@export var tracer_segments: int = 6
@export var tracer_segment_gap: float = 0.012
@export var max_total_tracer_segments_per_shot: int = 20
@export var verbose_fire_logs: bool = false
@export var enable_builtin_viewmodel: bool = true
@export var viewmodel_offset: Vector3 = Vector3(0.34, -0.30, -0.60)
@export var viewmodel_rotation_deg: Vector3 = Vector3.ZERO
@export var recoil_kick_distance: float = 0.07
@export var recoil_pitch_deg: float = 5.5
@export var recoil_yaw_deg: float = 1.2
@export var recoil_roll_deg: float = 0.9
@export var recoil_position_recover_speed: float = 11.0
@export var recoil_rotation_recover_speed: float = 16.0
@export var camera_shake_impulse: float = 0.35
@export var camera_shake_position: float = 0.008
@export var camera_shake_rotation_deg: float = 0.7
@export var camera_shake_decay: float = 8.0
@export var fire_jitter_position: float = 0.01
@export var fire_jitter_rotation_deg: float = 0.8
@export var fire_jitter_decay: float = 7.0
@export var fire_jitter_frequency: float = 34.0

@onready var shoot_camera: Camera3D = $"../CameraPivot/Camera3D"

var last_predicted_shot: ShotContext = ShotContext.new()
var _left_chain: OperatorChain = OperatorChain.new()
var _right_chain: OperatorChain = OperatorChain.new()
var _next_fire_time_by_hand: Dictionary = {HAND_LEFT: 0.0, HAND_RIGHT: 0.0}
var _camera_base_transform: Transform3D = Transform3D.IDENTITY
var _viewmodel_root: Node3D = null
var _viewmodel_left: Node3D = null
var _viewmodel_right: Node3D = null
var _gun_kick_back: float = 0.0
var _gun_kick_rotation: Vector3 = Vector3.ZERO
var _camera_trauma: float = 0.0
var _ammo_by_hand: Dictionary = {HAND_LEFT: 0, HAND_RIGHT: 0}
var _reloading_by_hand: Dictionary = {HAND_LEFT: false, HAND_RIGHT: false}
var _reload_elapsed_by_hand: Dictionary = {HAND_LEFT: 0.0, HAND_RIGHT: 0.0}
var _reload_spin_by_hand: Dictionary = {HAND_LEFT: 0.0, HAND_RIGHT: 0.0}
var _fire_jitter_strength: float = 0.0
var _fire_jitter_phase: float = 0.0
var _last_shot_hand: String = HAND_RIGHT
var _hand_kick: Dictionary = {HAND_LEFT: 0.0, HAND_RIGHT: 0.0}
var _phase_state_by_hand: Dictionary = {
	HAND_LEFT: ShotContext.ShotPhase.BUILD,
	HAND_RIGHT: ShotContext.ShotPhase.BUILD,
}


func _ready() -> void:
	_rebuild_chain()
	GameState.state_changed.connect(_rebuild_chain)
	var cap: int = max(1, magazine_capacity)
	_ammo_by_hand[HAND_LEFT] = cap
	_ammo_by_hand[HAND_RIGHT] = cap
	if shoot_camera != null:
		_camera_base_transform = shoot_camera.transform
		if enable_builtin_viewmodel:
			_ensure_builtin_viewmodel()
	DebugLog.add_entry("WeaponShooter ready; camera=%s" % [str(shoot_camera != null)])


func _exit_tree() -> void:
	if GameState.state_changed.is_connected(_rebuild_chain):
		GameState.state_changed.disconnect(_rebuild_chain)


func _process(delta: float) -> void:
	_update_reload(delta)
	if GameState.operator_menu_open:
		return
	if Input.is_action_just_pressed("reload"):
		_start_reload_all_hands()
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	var fired: bool = false
	if Input.is_action_pressed("shoot_left") or Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		fired = _try_fire_hand(HAND_LEFT, now) or fired
	if Input.is_action_pressed("shoot_right") or Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		fired = _try_fire_hand(HAND_RIGHT, now) or fired
	_auto_reload_empty_hands()


func _physics_process(delta: float) -> void:
	_update_recoil(delta)


func current_chain_text() -> String:
	return "L[%s] | R[%s]" % [left_chain_text(), right_chain_text()]


func left_chain_text() -> String:
	return _left_chain.describe_order()


func right_chain_text() -> String:
	return _right_chain.describe_order()


func build_chain_text() -> String:
	return right_build_chain_text()


func resolve_chain_text() -> String:
	return right_resolve_chain_text()


func left_build_chain_text() -> String:
	return _left_chain.describe_for_phase(ShotContext.ShotPhase.BUILD)


func left_resolve_chain_text() -> String:
	return _left_chain.describe_for_phase(ShotContext.ShotPhase.RESOLVE)


func right_build_chain_text() -> String:
	return _right_chain.describe_for_phase(ShotContext.ShotPhase.BUILD)


func right_resolve_chain_text() -> String:
	return _right_chain.describe_for_phase(ShotContext.ShotPhase.RESOLVE)


func next_hand_text() -> String:
	return "LMB->Left  RMB->Right"


func trigger_hand_text() -> String:
	return "LMB->Left  RMB->Right"


func hand_to_text(hand: String) -> String:
	return "左手" if _normalize_hand(hand) == HAND_LEFT else "右手"


func current_phase_with_role_text_for_hand(hand: String) -> String:
	if not enforce_phase_cycle:
		return "自由"
	return ShotContext.phase_with_role(_phase_for_hand(hand))


func next_phase_text_for_hand(hand: String) -> String:
	if not enforce_phase_cycle:
		return "自由"
	return ShotContext.phase_to_string(_phase_for_hand(hand))



func fire(hand: String = "") -> void:
	if GameState.operator_menu_open:
		return
	if shoot_camera == null:
		DebugLog.add_entry("Fire aborted: shoot_camera is null")
		return

	var shot_hand: String = _normalize_hand(hand)
	if hand.is_empty():
		shot_hand = _choose_preview_hand()
	if _is_hand_reloading(shot_hand):
		return
	if _ammo_for_hand(shot_hand) <= 0:
		_start_reload_for_hand(shot_hand)
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	if now < _next_fire_time_for_hand(shot_hand):
		return
	_consume_ammo(shot_hand)
	_set_next_fire_time_for_hand(shot_hand, maxf(_next_fire_time_for_hand(shot_hand), now + fire_interval))
	_apply_recoil_impulse(shot_hand)

	var shot_phase: int = ShotContext.ShotPhase.BUILD
	if enforce_phase_cycle:
		shot_phase = _phase_for_hand(shot_hand)
		_set_phase_for_hand(
			shot_hand,
			ShotContext.ShotPhase.RESOLVE if shot_phase == ShotContext.ShotPhase.BUILD else ShotContext.ShotPhase.BUILD
		)
	var shot: ShotContext = _build_base_shot(shot_hand, shot_phase)
	var chain: OperatorChain = _chain_for_hand(shot_hand)
	chain.on_fire(shot)
	shot.pellet_count = max(1, shot.pellet_count)
	shot.spread_angle = maxf(0.0, shot.spread_angle)
	last_predicted_shot = shot
	_last_shot_hand = shot_hand
	_log_verbose(
		"Fire hand=%s phase=%s pellets=%d spread=%.2f damage=%.2f chain=%s" % [
			hand_to_text(shot.hand),
			ShotContext.phase_with_role(shot.phase),
			shot.pellet_count,
			shot.spread_angle,
			shot.damage,
			chain.describe_order(),
		]
	)

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
					hit_context.phase = shot.phase
					hit_context.hand = shot.hand
					hit_context.effect_tags.assign(shot.effect_tags)
					var was_alive: bool = not target.is_dead()
					chain.on_hit(hit_context)
					target.apply_damage(hit_context.damage)
					if was_alive and target.is_dead():
						chain.on_kill(hit_context)
					_apply_context_side_effects(hit_context)
					CombatTargeting.apply_operator_effects_to_node(collider, hit_context.effect_tags)
					_log_verbose("Damage applied: hp=%.2f marks=%d" % [target.current_hp, target.mark_stacks])
				else:
					_log_verbose("Ray hit node but no StatusController resolved")
		else:
			_log_verbose("Ray missed")
		var tracer_start: Vector3 = _get_tracer_start(shot.hand)
		_spawn_tracer(tracer_start, end, shot.pellet_count, shot.phase, shot.hand)
		_spawn_impact_marker(end, shot.phase, shot.hand)


func predict_next_shot() -> ShotContext:
	var preview_hand: String = _choose_preview_hand()
	return predict_shot_for_hand(preview_hand)


func predict_shot_for_hand(hand: String) -> ShotContext:
	var hand_key: String = _normalize_hand(hand)
	var preview_phase: int = ShotContext.ShotPhase.BUILD
	if enforce_phase_cycle:
		preview_phase = _phase_for_hand(hand_key)
	var preview: ShotContext = _build_base_shot(hand_key, preview_phase)
	_chain_for_hand(hand_key).on_fire(preview)
	preview.pellet_count = max(1, preview.pellet_count)
	preview.spread_angle = maxf(0.0, preview.spread_angle)
	return preview


func _build_base_shot(hand: String, phase: int) -> ShotContext:
	var phase_damage_mul: float = _damage_multiplier_for_phase(phase)
	var shot: ShotContext = ShotContext.new()
	shot.hand = _normalize_hand(hand)
	shot.phase = phase
	shot.damage = base_damage * phase_damage_mul
	shot.pellet_count = max(1, base_pellet_count)
	shot.spread_angle = maxf(0.0, base_spread)
	return shot


func _damage_multiplier_for_phase(phase: int) -> float:
	if not enforce_phase_cycle:
		return 1.0
	return build_phase_damage_multiplier if phase == ShotContext.ShotPhase.BUILD else resolve_phase_damage_multiplier


func _normalize_hand(hand: String) -> String:
	if hand.to_lower() == HAND_LEFT:
		return HAND_LEFT
	return HAND_RIGHT


func _try_fire_hand(hand: String, now: float) -> bool:
	var hand_key: String = _normalize_hand(hand)
	if _is_hand_reloading(hand_key):
		return false
	if _ammo_for_hand(hand_key) <= 0:
		return false
	if now < _next_fire_time_for_hand(hand_key):
		return false
	fire(hand_key)
	return true


func _choose_preview_hand() -> String:
	var left_ready: bool = _ammo_for_hand(HAND_LEFT) > 0
	var right_ready: bool = _ammo_for_hand(HAND_RIGHT) > 0
	if left_ready and right_ready:
		var left_time: float = _next_fire_time_for_hand(HAND_LEFT)
		var right_time: float = _next_fire_time_for_hand(HAND_RIGHT)
		return HAND_LEFT if left_time <= right_time else HAND_RIGHT
	if left_ready:
		return HAND_LEFT
	return HAND_RIGHT


func _next_fire_time_for_hand(hand: String) -> float:
	return float(_next_fire_time_by_hand.get(_normalize_hand(hand), 0.0))


func _set_next_fire_time_for_hand(hand: String, value: float) -> void:
	_next_fire_time_by_hand[_normalize_hand(hand)] = maxf(0.0, value)


func _chain_for_hand(hand: String) -> OperatorChain:
	return _left_chain if _normalize_hand(hand) == HAND_LEFT else _right_chain


func _phase_for_hand(hand: String) -> int:
	return int(_phase_state_by_hand.get(_normalize_hand(hand), ShotContext.ShotPhase.BUILD))


func _set_phase_for_hand(hand: String, phase: int) -> void:
	_phase_state_by_hand[_normalize_hand(hand)] = phase


func _ammo_for_hand(hand: String) -> int:
	return int(_ammo_by_hand.get(_normalize_hand(hand), 0))


func _consume_ammo(hand: String) -> void:
	var key: String = _normalize_hand(hand)
	_ammo_by_hand[key] = max(0, _ammo_for_hand(key) - 1)
	if _ammo_for_hand(key) <= 0:
		_start_reload_for_hand(key)


func _is_all_hands_empty() -> bool:
	return _ammo_for_hand(HAND_LEFT) <= 0 and _ammo_for_hand(HAND_RIGHT) <= 0


func _auto_reload_empty_hands() -> void:
	if _ammo_for_hand(HAND_LEFT) <= 0:
		_start_reload_for_hand(HAND_LEFT)
	if _ammo_for_hand(HAND_RIGHT) <= 0:
		_start_reload_for_hand(HAND_RIGHT)


func _resolve_status(node: Node) -> StatusController:
	return CombatTargeting.resolve_status_from_node(node)


func _get_spread_direction(forward: Vector3, spread_angle: float) -> Vector3:
	if spread_angle <= 0.0:
		return forward.normalized()
	var yaw: float = randf_range(-spread_angle, spread_angle)
	var pitch: float = randf_range(-spread_angle, spread_angle)
	var basis: Basis = Basis.from_euler(Vector3(deg_to_rad(pitch), deg_to_rad(yaw), 0.0))
	return (basis * forward).normalized()


func _get_tracer_start(hand: String) -> Vector3:
	var muzzle_pos: Vector3 = _get_viewmodel_muzzle_position(hand)
	if muzzle_pos != INVALID_POS:
		return muzzle_pos
	var offset: Vector3 = tracer_muzzle_offset
	offset.x = absf(offset.x) if _normalize_hand(hand) == HAND_RIGHT else -absf(offset.x)
	return shoot_camera.to_global(offset)


func _get_viewmodel_muzzle_position(hand: String) -> Vector3:
	var hand_node: Node3D = _viewmodel_left if _normalize_hand(hand) == HAND_LEFT else _viewmodel_right
	if hand_node == null or not is_instance_valid(hand_node):
		return INVALID_POS
	var barrel_node := hand_node.get_node_or_null("GunBarrel")
	if not (barrel_node is MeshInstance3D):
		return INVALID_POS
	var barrel: MeshInstance3D = barrel_node as MeshInstance3D
	# Box depth is 0.30, so half is 0.15; a little extra to move to muzzle tip.
	return barrel.to_global(Vector3(0.0, 0.0, -0.17))


func _spawn_tracer(start: Vector3, end: Vector3, pellet_count: int, phase: int = ShotContext.ShotPhase.BUILD, hand: String = HAND_RIGHT) -> void:
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
	var is_resolve: bool = enforce_phase_cycle and phase == ShotContext.ShotPhase.RESOLVE
	var tracer_color: Color = Color(1.0, 0.46, 0.26, 1.0) if _normalize_hand(hand) == HAND_RIGHT else Color(0.42, 1.0, 0.96, 1.0)
	if enforce_phase_cycle:
		tracer_color = Color(1.0, 0.46, 0.26, 1.0) if is_resolve else Color(0.42, 1.0, 0.96, 1.0)
	var tracer_energy: float = 12.0 if is_resolve else 8.0
	var width_mul: float = 1.0 if is_resolve else 0.8
	for index in range(segment_count):
		var segment := MeshInstance3D.new()
		segment.name = "TracerSegment"
		segment.add_to_group(FX_GROUP)
		var mesh := CylinderMesh.new()
		mesh.top_radius = tracer_width * width_mul * 0.5
		mesh.bottom_radius = tracer_width * width_mul * 0.5
		mesh.height = segment_length
		mesh.radial_segments = 6
		mesh.rings = 1
		segment.mesh = mesh

		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = tracer_color
		material.emission_enabled = true
		material.emission = tracer_color
		material.emission_energy_multiplier = tracer_energy
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.no_depth_test = false
		material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_ALWAYS
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		segment.set_surface_override_material(0, material)

		scene.add_child(segment)
		var center_ratio: float = (float(index) + 0.5) / float(segment_count)
		var center: Vector3 = start.lerp(end, center_ratio)
		segment.global_position = center
		segment.look_at(center + direction, Vector3.UP, true)
		segment.rotate_object_local(Vector3.RIGHT, deg_to_rad(90.0))

		var tween := segment.create_tween()
		tween.tween_interval(float(index) * tracer_segment_gap)
		tween.tween_property(material, "albedo_color:a", 0.0, tracer_lifetime)
		tween.finished.connect(segment.queue_free)


func _spawn_impact_marker(position: Vector3, phase: int = ShotContext.ShotPhase.BUILD, hand: String = HAND_RIGHT) -> void:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return
	var marker := MeshInstance3D.new()
	marker.name = "ImpactMarker"
	marker.add_to_group(FX_GROUP)
	var mesh := SphereMesh.new()
	mesh.radius = 0.12
	mesh.height = 0.24
	marker.mesh = mesh
	var impact_color: Color = Color(1.0, 0.35, 0.3, 1.0) if _normalize_hand(hand) == HAND_RIGHT else Color(0.3, 0.95, 1.0, 1.0)
	var impact_scale: float = 1.6
	if enforce_phase_cycle:
		impact_color = Color(1.0, 0.35, 0.3, 1.0) if phase == ShotContext.ShotPhase.RESOLVE else Color(0.3, 0.95, 1.0, 1.0)
		impact_scale = 2.1 if phase == ShotContext.ShotPhase.RESOLVE else 1.4

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = impact_color
	material.emission_enabled = true
	material.emission = impact_color
	material.emission_energy_multiplier = 10.0 if enforce_phase_cycle and phase == ShotContext.ShotPhase.RESOLVE else 6.0
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	marker.set_surface_override_material(0, material)

	scene.add_child(marker)
	marker.global_position = position

	var tween := marker.create_tween()
	tween.parallel().tween_property(marker, "scale", Vector3.ONE * impact_scale, impact_lifetime)
	tween.parallel().tween_property(material, "albedo_color:a", 0.0, impact_lifetime)
	tween.finished.connect(marker.queue_free)


func _rebuild_chain() -> void:
	var left_definitions: Array[OperatorDefinition] = []
	var right_definitions: Array[OperatorDefinition] = []
	if GameState.has_method("get_loadout"):
		left_definitions.assign(GameState.get_loadout(HAND_LEFT))
		right_definitions.assign(GameState.get_loadout(HAND_RIGHT))
	else:
		right_definitions.assign(GameState.loadout)
	_left_chain.rebuild(left_definitions)
	_right_chain.rebuild(right_definitions)
	if _left_chain.has_method("set_phase_filter_enabled"):
		_left_chain.call("set_phase_filter_enabled", enforce_phase_cycle)
	if _right_chain.has_method("set_phase_filter_enabled"):
		_right_chain.call("set_phase_filter_enabled", enforce_phase_cycle)
	DebugLog.add_entry("Chain rebuilt: L=%s | R=%s" % [_left_chain.describe_order(), _right_chain.describe_order()])


func _get_all_statuses() -> Array[StatusController]:
	return CombatTargeting.collect_statuses(get_tree())


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
	if not context.pending_chain_arcs.is_empty():
		for arc_any in context.pending_chain_arcs:
			if not (arc_any is Dictionary):
				continue
			var arc: Dictionary = arc_any
			_spawn_chain_lightning_arc(
				arc.get("from", context.hit_point),
				arc.get("to", context.hit_point),
				int(arc.get("jump", 1))
			)
	if context.pending_coin_gain > 0:
		GameState.add_gold(context.pending_coin_gain)
		DebugLog.add_entry("Coin gain: +%d" % context.pending_coin_gain)
	if not context.pending_spawns.is_empty():
		var spawn_count: int = 0
		var form_count: Dictionary = {}
		for request in context.pending_spawns:
			if not (request is Dictionary):
				continue
			var request_dict: Dictionary = request
			var form: String = str(request_dict.get("form", "auto"))
			var target_status_ref: StatusController = request_dict.get("target_status", null) as StatusController
			var power: float = float(request_dict.get("power", 1.0))
			var spawn_pos: Vector3 = context.target_world_position + Vector3(randf_range(-0.8, 0.8), 0.9, randf_range(-0.8, 0.8))
			_spawn_seedling(spawn_pos, power, form, target_status_ref)
			spawn_count += 1
			form_count[form] = int(form_count.get(form, 0)) + 1
		if spawn_count > 0:
			DebugLog.add_entry("Spawn trigger: count=%d forms=%s" % [spawn_count, str(form_count)])
		return
	if context.pending_spawn_count > 0:
		var spawn_power: float = context.pending_spawn_power / float(max(1, context.pending_spawn_count))
		for _index in range(context.pending_spawn_count):
			_spawn_seedling(
				context.target_world_position + Vector3(randf_range(-0.8, 0.8), 0.9, randf_range(-0.8, 0.8)),
				spawn_power,
				"auto",
				context.target_status
			)
		DebugLog.add_entry("Spawn trigger (legacy): count=%d" % context.pending_spawn_count)


func _spawn_chain_lightning_arc(from_world: Vector3, to_world: Vector3, jump_index: int) -> void:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return
	var distance: float = from_world.distance_to(to_world)
	if distance <= 0.02:
		return
	var root := Node3D.new()
	root.name = "ChainLightningArc"
	root.add_to_group(FX_GROUP)
	scene.add_child(root)
	var segment_count: int = clampi(4 + int(distance * 1.2), 4, 9)
	var prev: Vector3 = from_world
	var direction: Vector3 = (to_world - from_world).normalized()
	for i in range(1, segment_count + 1):
		var t: float = float(i) / float(segment_count)
		var point: Vector3 = from_world.lerp(to_world, t)
		if i < segment_count:
			var jitter_scale: float = 0.16 + 0.04 * float(jump_index - 1)
			var random_vec := Vector3(randf_range(-1.0, 1.0), randf_range(-0.8, 0.8), randf_range(-1.0, 1.0))
			var tangent: Vector3 = random_vec - random_vec.dot(direction) * direction
			if tangent.length() < 0.001:
				tangent = Vector3.UP.cross(direction)
			if tangent.length() < 0.001:
				tangent = Vector3.RIGHT
			var jitter: Vector3 = tangent.normalized() * jitter_scale
			point += jitter
		_spawn_chain_segment(root, prev, point, jump_index)
		prev = point
	var tween := root.create_tween()
	tween.tween_interval(0.12)
	tween.finished.connect(root.queue_free)


func _spawn_chain_segment(parent: Node3D, from_world: Vector3, to_world: Vector3, jump_index: int) -> void:
	var segment := MeshInstance3D.new()
	var dist: float = from_world.distance_to(to_world)
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.018
	mesh.bottom_radius = 0.018
	mesh.height = maxf(0.05, dist)
	mesh.radial_segments = 6
	mesh.rings = 1
	segment.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var alpha_decay: float = clampf(1.0 - float(jump_index - 1) * 0.18, 0.3, 1.0)
	var color: Color = Color(1.0, 0.9, 0.26, 0.94 * alpha_decay)
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 7.6 * alpha_decay
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = false
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	segment.set_surface_override_material(0, mat)
	parent.add_child(segment)
	var center: Vector3 = from_world.lerp(to_world, 0.5)
	var forward: Vector3 = (to_world - from_world).normalized()
	segment.global_position = center
	segment.look_at(center + forward, Vector3.UP, true)
	segment.rotate_object_local(Vector3.RIGHT, deg_to_rad(90.0))
	var tween := segment.create_tween()
	tween.parallel().tween_property(mat, "albedo_color:a", 0.0, 0.1)
	tween.parallel().tween_property(segment, "scale", Vector3(1.0, 1.0, 0.88), 0.1)
	tween.finished.connect(segment.queue_free)


func _spawn_seedling(position: Vector3, power: float, form: String = "auto", target_status_ref: StatusController = null) -> void:
	var scene: Node = get_tree().current_scene
	if scene == null:
		return
	var normalized_form: String = form.strip_edges().to_lower()
	if normalized_form == "runner":
		var runner: RunnerSummon = RunnerSummon.new()
		scene.add_child(runner)
		runner.global_position = _resolve_runner_spawn_position(position, target_status_ref)
		runner.configure(power)
		runner.set_spawn_target(target_status_ref)
		return

	var summon: SeedlingSummon = SeedlingSummon.new()
	scene.add_child(summon)
	summon.global_position = position
	summon.configure(power)
	summon.apply_form(normalized_form, target_status_ref)


func _resolve_runner_spawn_position(default_pos: Vector3, target_status_ref: StatusController) -> Vector3:
	if target_status_ref == null:
		return default_pos
	var target_pos: Vector3 = _get_status_world_position(target_status_ref)
	var random_dir: Vector2 = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0))
	if random_dir.length() < 0.01:
		random_dir = Vector2.RIGHT
	random_dir = random_dir.normalized()
	var radius: float = randf_range(2.3, 3.1)
	return target_pos + Vector3(random_dir.x * radius, 0.3, random_dir.y * radius)


func _log_verbose(message: String) -> void:
	if verbose_fire_logs:
		DebugLog.add_entry(message)


func ammo_status_text() -> String:
	var cap: int = max(1, magazine_capacity)
	var left: int = _ammo_for_hand(HAND_LEFT)
	var right: int = _ammo_for_hand(HAND_RIGHT)
	var trigger_hand: String = trigger_hand_text()
	var reload_parts: Array[String] = []
	if _is_hand_reloading(HAND_LEFT):
		reload_parts.append("L %.0f%%" % (_reload_progress_for_hand(HAND_LEFT) * 100.0))
	if _is_hand_reloading(HAND_RIGHT):
		reload_parts.append("R %.0f%%" % (_reload_progress_for_hand(HAND_RIGHT) * 100.0))
	if not reload_parts.is_empty():
		return "Ammo L:%d/%d R:%d/%d | Reload %s | Fire Map %s" % [left, cap, right, cap, ", ".join(reload_parts), trigger_hand]
	return "Ammo L:%d/%d R:%d/%d | Fire Map %s" % [left, cap, right, cap, trigger_hand]


func _reload_progress_for_hand(hand: String) -> float:
	var key: String = _normalize_hand(hand)
	var duration: float = maxf(0.01, reload_duration)
	var elapsed: float = float(_reload_elapsed_by_hand.get(key, 0.0))
	return clampf(elapsed / duration, 0.0, 1.0)


func _ensure_builtin_viewmodel() -> void:
	if shoot_camera == null:
		return
	var existing := shoot_camera.get_node_or_null("ViewModelRoot")
	if existing is Node3D:
		_viewmodel_root = existing
	else:
		_viewmodel_root = Node3D.new()
		_viewmodel_root.name = "ViewModelRoot"
		shoot_camera.add_child(_viewmodel_root)

	_viewmodel_root.position = Vector3(0.0, viewmodel_offset.y, viewmodel_offset.z)
	_viewmodel_root.rotation_degrees = viewmodel_rotation_deg
	_viewmodel_left = _ensure_hand_viewmodel("LeftGun", -1.0)
	_viewmodel_right = _ensure_hand_viewmodel("RightGun", 1.0)


func _ensure_hand_viewmodel(node_name: String, side_sign: float) -> Node3D:
	var hand_root := _viewmodel_root.get_node_or_null(node_name)
	if hand_root == null:
		hand_root = Node3D.new()
		hand_root.name = node_name
		_viewmodel_root.add_child(hand_root)
		_build_hand_mesh(hand_root, side_sign)
	if hand_root is Node3D:
		var hand_x: float = absf(viewmodel_offset.x) * side_sign
		(hand_root as Node3D).position = Vector3(hand_x, 0.0, 0.0)
		return hand_root as Node3D
	return null


func _build_hand_mesh(hand_root: Node3D, side_sign: float) -> void:
	var gun_body: MeshInstance3D = _create_viewmodel_piece(
		Vector3(0.18, 0.14, 0.58),
		Vector3(0.02 * side_sign, 0.0, -0.12),
		Color(0.18, 0.19, 0.22, 1.0)
	)
	gun_body.name = "GunBody"
	var gun_barrel: MeshInstance3D = _create_viewmodel_piece(
		Vector3(0.07, 0.07, 0.30),
		Vector3(0.02 * side_sign, -0.02, -0.52),
		Color(0.22, 0.23, 0.26, 1.0)
	)
	gun_barrel.name = "GunBarrel"
	var gun_grip: MeshInstance3D = _create_viewmodel_piece(
		Vector3(0.10, 0.18, 0.16),
		Vector3(0.02 * side_sign, -0.14, 0.04),
		Color(0.15, 0.16, 0.18, 1.0)
	)
	gun_grip.name = "GunGrip"
	hand_root.add_child(gun_body)
	hand_root.add_child(gun_barrel)
	hand_root.add_child(gun_grip)


func _create_viewmodel_piece(size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var piece := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	piece.mesh = mesh
	piece.position = pos
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.75
	mat.metallic = 0.05
	piece.set_surface_override_material(0, mat)
	return piece


func _apply_recoil_impulse(hand: String) -> void:
	var hand_key: String = _normalize_hand(hand)
	var hand_yaw_sign: float = -1.0 if hand_key == HAND_LEFT else 1.0
	_gun_kick_back = minf(_gun_kick_back + recoil_kick_distance, recoil_kick_distance * 2.0)
	_gun_kick_rotation.x += deg_to_rad(recoil_pitch_deg)
	_gun_kick_rotation.y += deg_to_rad(randf_range(0.35, 1.0) * recoil_yaw_deg * hand_yaw_sign)
	_gun_kick_rotation.z += deg_to_rad(randf_range(-recoil_roll_deg, recoil_roll_deg))
	_camera_trauma = clampf(_camera_trauma + camera_shake_impulse, 0.0, 1.0)
	_fire_jitter_strength = clampf(_fire_jitter_strength + 0.9, 0.0, 1.0)
	_hand_kick[hand_key] = minf(float(_hand_kick.get(hand_key, 0.0)) + recoil_kick_distance * 0.9, recoil_kick_distance * 2.0)


func _update_recoil(delta: float) -> void:
	_gun_kick_back = move_toward(_gun_kick_back, 0.0, recoil_position_recover_speed * delta)
	_gun_kick_rotation = _gun_kick_rotation.move_toward(Vector3.ZERO, recoil_rotation_recover_speed * delta)
	_fire_jitter_strength = move_toward(_fire_jitter_strength, 0.0, fire_jitter_decay * delta)
	_hand_kick[HAND_LEFT] = move_toward(float(_hand_kick.get(HAND_LEFT, 0.0)), 0.0, recoil_position_recover_speed * delta)
	_hand_kick[HAND_RIGHT] = move_toward(float(_hand_kick.get(HAND_RIGHT, 0.0)), 0.0, recoil_position_recover_speed * delta)
	_fire_jitter_phase += delta * fire_jitter_frequency
	var jitter_wave: float = sin(_fire_jitter_phase) * _fire_jitter_strength
	var jitter_wave_2: float = sin(_fire_jitter_phase * 1.37 + 0.8) * _fire_jitter_strength
	var jitter_position: Vector3 = Vector3(
		jitter_wave * fire_jitter_position * 0.35,
		absf(jitter_wave_2) * fire_jitter_position * 0.45,
		-absf(jitter_wave) * fire_jitter_position
	)
	var jitter_rotation: Vector3 = Vector3(
		deg_to_rad(jitter_wave_2 * fire_jitter_rotation_deg),
		deg_to_rad(jitter_wave * fire_jitter_rotation_deg * 0.6),
		deg_to_rad(jitter_wave * fire_jitter_rotation_deg * 0.45)
	)
	if _viewmodel_root != null and is_instance_valid(_viewmodel_root):
		_viewmodel_root.position = Vector3(0.0, viewmodel_offset.y, viewmodel_offset.z) + Vector3(0.0, 0.0, _gun_kick_back) + jitter_position
		var base_rot: Vector3 = Vector3(
			deg_to_rad(viewmodel_rotation_deg.x),
			deg_to_rad(viewmodel_rotation_deg.y),
			deg_to_rad(viewmodel_rotation_deg.z)
		)
		_viewmodel_root.basis = Basis.from_euler(base_rot + _gun_kick_rotation + jitter_rotation)
		_update_hand_viewmodel_offsets()

	if shoot_camera == null:
		return
	_camera_trauma = maxf(0.0, _camera_trauma - camera_shake_decay * delta)
	var trauma: float = _camera_trauma * _camera_trauma
	var shake_pos: Vector3 = Vector3(
		randf_range(-1.0, 1.0) * camera_shake_position * trauma,
		randf_range(-1.0, 1.0) * camera_shake_position * trauma,
		0.0
	)
	var shake_rot: Vector3 = Vector3(
		deg_to_rad(randf_range(-camera_shake_rotation_deg, camera_shake_rotation_deg) * trauma),
		deg_to_rad(randf_range(-camera_shake_rotation_deg, camera_shake_rotation_deg) * trauma),
		deg_to_rad(randf_range(-camera_shake_rotation_deg, camera_shake_rotation_deg) * trauma)
	)
	var t: Transform3D = _camera_base_transform
	t.origin += shake_pos
	t.basis = _camera_base_transform.basis * Basis.from_euler(shake_rot)
	shoot_camera.transform = t


func _update_hand_viewmodel_offsets() -> void:
	var hand_offset_x: float = absf(viewmodel_offset.x)
	if _viewmodel_left != null and is_instance_valid(_viewmodel_left):
		_viewmodel_left.position = Vector3(-hand_offset_x, 0.0, float(_hand_kick.get(HAND_LEFT, 0.0)))
		_viewmodel_left.basis = Basis.from_euler(Vector3(-_reload_spin_for_hand(HAND_LEFT), 0.0, 0.0))
	if _viewmodel_right != null and is_instance_valid(_viewmodel_right):
		_viewmodel_right.position = Vector3(hand_offset_x, 0.0, float(_hand_kick.get(HAND_RIGHT, 0.0)))
		_viewmodel_right.basis = Basis.from_euler(Vector3(-_reload_spin_for_hand(HAND_RIGHT), 0.0, 0.0))


func _reload_spin_for_hand(hand: String) -> float:
	return float(_reload_spin_by_hand.get(_normalize_hand(hand), 0.0))


func _start_reload_all_hands() -> void:
	_start_reload_for_hand(HAND_LEFT)
	_start_reload_for_hand(HAND_RIGHT)


func _start_reload_for_hand(hand: String) -> void:
	var key: String = _normalize_hand(hand)
	if _is_hand_reloading(key):
		return
	var cap: int = max(1, magazine_capacity)
	if _ammo_for_hand(key) >= cap:
		return
	_reloading_by_hand[key] = true
	_reload_elapsed_by_hand[key] = 0.0
	_reload_spin_by_hand[key] = 0.0
	var now: float = Time.get_ticks_msec() / 1000.0
	_set_next_fire_time_for_hand(key, maxf(_next_fire_time_for_hand(key), now + reload_duration))
	DebugLog.add_entry("Reload start: %s" % hand_to_text(key))


func _update_reload(delta: float) -> void:
	_update_reload_for_hand(HAND_LEFT, delta)
	_update_reload_for_hand(HAND_RIGHT, delta)


func _update_reload_for_hand(hand: String, delta: float) -> void:
	var key: String = _normalize_hand(hand)
	if not _is_hand_reloading(key):
		return
	var elapsed: float = float(_reload_elapsed_by_hand.get(key, 0.0)) + maxf(0.0, delta)
	_reload_elapsed_by_hand[key] = elapsed
	var progress: float = _reload_progress_for_hand(key)
	_reload_spin_by_hand[key] = TAU * progress
	if progress >= 1.0:
		_finish_reload_for_hand(key)


func _finish_reload_for_hand(hand: String) -> void:
	var key: String = _normalize_hand(hand)
	var cap: int = max(1, magazine_capacity)
	_ammo_by_hand[key] = cap
	_reloading_by_hand[key] = false
	_reload_elapsed_by_hand[key] = 0.0
	_reload_spin_by_hand[key] = 0.0
	DebugLog.add_entry("Reload finish: %s" % hand_to_text(key))


func _is_hand_reloading(hand: String) -> bool:
	return bool(_reloading_by_hand.get(_normalize_hand(hand), false))
