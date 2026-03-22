extends CharacterBody3D
class_name EnemyWalker

signal defeated(gold_reward: int)

const STATUS_SHADER := preload("res://scripts/combat/target_status_effect.gdshader")
const StatusController = preload("res://scripts/combat/status_controller.gd")

@export var move_speed: float = 3.2
@export var acceleration: float = 18.0
@export var attack_range: float = 1.45
@export var attack_damage: float = 9.0
@export var attack_cooldown: float = 0.9
@export var gold_reward: int = 3
@export var execute_ready_marks: int = 3
@export var max_effect_bursts: int = 8
@export var overlay_height: float = 2.45

var status: StatusController = null
var mesh_instance: MeshInstance3D = null

var _attack_cooldown_left: float = 0.0
var _flash_color: Color = Color(1.0, 1.0, 1.0, 1.0)
var _flash_strength: float = 0.0
var _visual_material: ShaderMaterial
var _last_effect_time: Dictionary = {}
var _active_effect_bursts: int = 0
var _death_announced: bool = false
var _despawn_delay: float = 0.24
var _player: FpsController = null


func _ready() -> void:
	add_to_group("combat_target")
	add_to_group("enemy_walker")
	status = get_node("StatusController") as StatusController
	mesh_instance = get_node("Visual") as MeshInstance3D
	_setup_visual_material()
	status.damaged.connect(_on_damaged)
	status.status_reset.connect(_on_status_reset)


func _physics_process(delta: float) -> void:
	_attack_cooldown_left = maxf(0.0, _attack_cooldown_left - delta)
	_flash_strength = maxf(0.0, _flash_strength - delta * 2.6)
	_update_visual_material()

	if status.is_dead():
		velocity = velocity.move_toward(Vector3.ZERO, acceleration * delta)
		move_and_slide()
		_handle_death(delta)
		return

	if _player == null or not is_instance_valid(_player):
		_player = _find_player()
	if _player == null or _player.is_dead():
		velocity = velocity.move_toward(Vector3.ZERO, acceleration * delta)
		move_and_slide()
		return

	var to_player: Vector3 = _player.global_position - global_position
	var planar: Vector3 = Vector3(to_player.x, 0.0, to_player.z)
	if planar.length() <= attack_range:
		velocity.x = move_toward(velocity.x, 0.0, acceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, acceleration * delta)
		if _attack_cooldown_left <= 0.0:
			_attack_player()
	else:
		var speed_scale: float = clampf(1.0 - float(status.freeze_stacks) * 0.12, 0.38, 1.0)
		var desired: Vector3 = planar.normalized() * move_speed * speed_scale
		velocity.x = move_toward(velocity.x, desired.x, acceleration * delta)
		velocity.z = move_toward(velocity.z, desired.z, acceleration * delta)
		look_at(global_position + planar, Vector3.UP, true)

	if not is_on_floor():
		velocity.y -= 24.0 * delta
	else:
		velocity.y = -0.1
	move_and_slide()


func configure_for_wave(wave_number: int) -> void:
	if status == null:
		status = get_node_or_null("StatusController") as StatusController
	if status == null:
		return
	var wave_scale: float = maxf(1.0, float(wave_number))
	move_speed = 3.0 + wave_scale * 0.18
	attack_damage = 8.0 + wave_scale * 1.4
	attack_cooldown = clampf(0.95 - wave_scale * 0.03, 0.52, 0.95)
	gold_reward = 2 + int(floor(wave_scale * 0.5))
	status.max_hp = 22.0 + wave_scale * 9.0
	status.burn_damage_per_stack = 0.9 + wave_scale * 0.04
	status.reset_status()
	execute_ready_marks = 3 + int(minf(2.0, floor(wave_scale / 3.0)))


func reset_dummy() -> void:
	status.reset_status()


func get_status_controller() -> StatusController:
	return status


func get_overlay_world_position() -> Vector3:
	return global_position + Vector3(0.0, overlay_height, 0.0)


func get_overlay_text() -> String:
	var execute_hint := " | Execute Ready" if is_execute_ready() else ""
	return "Enemy HP %d/%d\nMark %d Seed %d Burn %d Freeze %d Greed %d%s" % [
		int(round(status.current_hp)),
		int(round(status.max_hp)),
		status.mark_stacks,
		status.seed_stacks,
		status.burn_stacks,
		status.freeze_stacks,
		status.greed_stacks,
		execute_hint,
	]


func is_execute_ready() -> bool:
	return not status.is_dead() and status.mark_stacks >= execute_ready_marks


func get_overlay_color() -> Color:
	if is_execute_ready():
		return Color(1.0, 0.36, 0.28, 1.0)
	if status.freeze_stacks > 0 and status.burn_stacks > 0:
		return Color(0.95, 0.5, 1.0, 1.0)
	if status.freeze_stacks > 0:
		return Color(0.45, 0.9, 1.0, 1.0)
	if status.burn_stacks > 0:
		return Color(1.0, 0.57, 0.24, 1.0)
	if status.seed_stacks > 0:
		return Color(0.52, 1.0, 0.64, 1.0)
	return Color(0.96, 0.93, 0.85, 1.0)


func apply_operator_effects(effect_tags: Array[String]) -> void:
	if effect_tags.is_empty():
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	var seen: Dictionary = {}
	for tag in effect_tags:
		if seen.has(tag):
			continue
		seen[tag] = true
		var last_time: float = float(_last_effect_time.get(tag, -10.0))
		if now - last_time < 0.06:
			continue
		_last_effect_time[tag] = now
		_flash_color = _get_effect_color(tag)
		_flash_strength = minf(1.0, _flash_strength + 0.46)
		_spawn_effect_burst(tag)


func _find_player() -> FpsController:
	var player_node: Node = get_tree().get_first_node_in_group("player_actor")
	if player_node is FpsController:
		return player_node as FpsController
	return null


func _attack_player() -> void:
	if _player == null or _player.is_dead():
		return
	_attack_cooldown_left = attack_cooldown
	_player.apply_damage(attack_damage, "enemy_walker")
	_flash_strength = minf(1.0, _flash_strength + 0.18)


func _handle_death(delta: float) -> void:
	if not _death_announced:
		_death_announced = true
		defeated.emit(gold_reward)
		_flash_color = Color(1.0, 0.85, 0.3, 1.0)
		_flash_strength = 1.0
	_despawn_delay -= delta
	if _despawn_delay <= 0.0:
		queue_free()


func _on_damaged(_amount: float) -> void:
	_flash_strength = minf(1.0, _flash_strength + 0.34)


func _on_status_reset() -> void:
	_flash_strength = 0.0
	_last_effect_time.clear()
	_clear_runtime_bursts()
	_death_announced = false
	_despawn_delay = 0.24


func _setup_visual_material() -> void:
	_visual_material = ShaderMaterial.new()
	_visual_material.shader = STATUS_SHADER
	mesh_instance.set_surface_override_material(0, _visual_material)
	_update_visual_material()


func _update_visual_material() -> void:
	if _visual_material == null:
		return
	var base := Color(0.35, 0.38, 0.44, 1.0) if status.is_dead() else Color(0.78, 0.28, 0.22, 1.0)
	_visual_material.set_shader_parameter("base_color", base)
	_visual_material.set_shader_parameter("mark_intensity", clampf(float(status.mark_stacks) / 6.0, 0.0, 1.0))
	_visual_material.set_shader_parameter("seed_intensity", clampf(float(status.seed_stacks) / 5.0, 0.0, 1.0))
	_visual_material.set_shader_parameter("burn_intensity", clampf(float(status.burn_stacks) / 5.0, 0.0, 1.0))
	_visual_material.set_shader_parameter("freeze_intensity", clampf(float(status.freeze_stacks) / 5.0, 0.0, 1.0))
	_visual_material.set_shader_parameter("greed_intensity", clampf(float(status.greed_stacks) / 5.0, 0.0, 1.0))
	_visual_material.set_shader_parameter("flash_color", _flash_color)
	_visual_material.set_shader_parameter("flash_strength", _flash_strength)


func _spawn_effect_burst(tag: String) -> void:
	if _active_effect_bursts >= max_effect_bursts:
		return
	var burst := GPUParticles3D.new()
	burst.name = "EnemyEffectBurst"
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.amount = 8
	burst.lifetime = 0.24
	burst.local_coords = true
	burst.position = Vector3(0.0, 1.0, 0.0)
	burst.process_material = _create_effect_material(tag)
	burst.draw_pass_1 = _create_effect_mesh(tag)
	add_child(burst)
	burst.emitting = true
	_active_effect_bursts += 1
	var timer := get_tree().create_timer(0.45)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(burst):
			burst.queue_free()
		_active_effect_bursts = maxi(0, _active_effect_bursts - 1)
	)


func _clear_runtime_bursts() -> void:
	for child in get_children():
		if child is GPUParticles3D:
			child.queue_free()
	_active_effect_bursts = 0


func _create_effect_material(tag: String) -> ParticleProcessMaterial:
	var color: Color = _get_effect_color(tag)
	var material := ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	material.emission_sphere_radius = 0.55
	material.direction = Vector3(0.0, 1.0, 0.0)
	material.spread = 80.0
	material.initial_velocity_min = 0.24
	material.initial_velocity_max = 0.72
	material.gravity = Vector3(0.0, 2.4, 0.0)
	material.scale_min = 0.14
	material.scale_max = 0.24
	material.color = color
	return material


func _create_effect_mesh(tag: String) -> Mesh:
	var color: Color = _get_effect_color(tag)
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.22, 0.22)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 4.8
	mesh.material = mat
	return mesh


func _get_effect_color(tag: String) -> Color:
	match tag:
		"mark", "mark_amplifier":
			return Color(0.45, 1.0, 0.45, 0.95)
		"seed", "spawn", "summon_runner":
			return Color(0.4, 1.0, 0.68, 0.95)
		"burn":
			return Color(1.0, 0.46, 0.24, 0.95)
		"freeze":
			return Color(0.45, 0.86, 1.0, 0.95)
		"execute":
			return Color(1.0, 0.25, 0.45, 1.0)
		"chain_lightning":
			return Color(1.0, 0.86, 0.24, 0.98)
		_:
			return Color(1.0, 1.0, 1.0, 0.95)
