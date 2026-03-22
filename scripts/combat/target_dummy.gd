extends StaticBody3D
class_name TargetDummy

const STATUS_SHADER := preload("res://scripts/combat/target_status_effect.gdshader")
const StatusController = preload("res://scripts/combat/status_controller.gd")

@export var auto_reset_delay: float = 3.0
@export var dps_window: float = 1.0
@export var execute_ready_marks: int = 4
@export var max_effect_bursts: int = 12

@onready var status: StatusController = $StatusController
@onready var mesh_instance: MeshInstance3D = $Visual

var _damage_events: Array[Dictionary] = []
var _mark_particles: GPUParticles3D
var _mark_particle_material: ParticleProcessMaterial
var _visual_material: ShaderMaterial
var _flash_color: Color = Color(1.0, 1.0, 1.0, 1.0)
var _flash_strength: float = 0.0
var _last_effect_time: Dictionary = {}
var _active_effect_bursts: int = 0

func _ready() -> void:
	add_to_group("target_dummy")
	_setup_visual_material()
	status.damaged.connect(_on_damaged)
	status.status_reset.connect(_on_status_reset)
	_setup_mark_particles()


func _process(delta: float) -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	_prune_damage_events(now)
	if status.current_hp < status.max_hp and status.last_damage_time >= 0.0:
		if now - status.last_damage_time >= auto_reset_delay:
			reset_dummy()
	_flash_strength = maxf(0.0, _flash_strength - delta * 2.2)
	_update_visual_material()
	_update_mark_particles()


func reset_dummy() -> void:
	status.reset_status()


func _on_damaged(amount: float) -> void:
	_damage_events.append({
		"time": Time.get_ticks_msec() / 1000.0,
		"amount": amount,
	})


func _on_status_reset() -> void:
	_damage_events.clear()
	_flash_strength = 0.0
	_last_effect_time.clear()
	_clear_runtime_bursts()
	_update_mark_particles()


func _prune_damage_events(now: float) -> void:
	while not _damage_events.is_empty() and now - float(_damage_events[0]["time"]) > dps_window:
		_damage_events.remove_at(0)


func _calculate_dps() -> float:
	var total: float = 0.0
	for event in _damage_events:
		total += float(event["amount"])
	return total / maxf(0.1, dps_window)


func get_overlay_text() -> String:
	var execute_hint := " | 处决就绪" if is_execute_ready() else ""
	return "生命 %d/%d\n印记 %d 种子 %d 灼烧 %d 冻结 %d 贪婪 %d | DPS %.1f%s" % [
		int(round(status.current_hp)),
		int(round(status.max_hp)),
		status.mark_stacks,
		status.seed_stacks,
		status.burn_stacks,
		status.freeze_stacks,
		status.greed_stacks,
		_calculate_dps(),
		execute_hint
	]


func is_execute_ready() -> bool:
	return not status.is_dead() and status.mark_stacks >= execute_ready_marks


func get_overlay_color() -> Color:
	if is_execute_ready():
		return Color(1.0, 0.36, 0.28, 1.0)
	if status.burn_stacks > 0 and status.freeze_stacks > 0:
		return Color(0.95, 0.5, 1.0, 1.0)
	if status.burn_stacks > 0:
		return Color(1.0, 0.57, 0.24, 1.0)
	if status.freeze_stacks > 0:
		return Color(0.45, 0.9, 1.0, 1.0)
	if status.seed_stacks > 0:
		return Color(0.52, 1.0, 0.64, 1.0)
	if status.greed_stacks > 0:
		return Color(1.0, 0.82, 0.32, 1.0)
	var tier: int = _get_mark_tier()
	if tier <= 0:
		return Color(0.93, 0.97, 0.86, 1.0)
	if tier == 1:
		return Color(0.72, 0.95, 1.0, 1.0)
	if tier == 2:
		return Color(0.48, 0.9, 1.0, 1.0)
	return Color(1.0, 0.66, 0.3, 1.0)


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
		_flash_strength = minf(1.0, _flash_strength + 0.42)
		_spawn_effect_burst(tag)


func _get_mark_tier() -> int:
	if status.mark_stacks <= 0:
		return 0
	if status.mark_stacks <= 2:
		return 1
	if status.mark_stacks <= 4:
		return 2
	return 3


func _setup_visual_material() -> void:
	_visual_material = ShaderMaterial.new()
	_visual_material.shader = STATUS_SHADER
	mesh_instance.set_surface_override_material(0, _visual_material)
	_update_visual_material()


func _update_visual_material() -> void:
	if _visual_material == null:
		return
	var base := Color.GRAY if status.is_dead() else Color.FIREBRICK
	_visual_material.set_shader_parameter("base_color", base)
	_visual_material.set_shader_parameter("mark_intensity", clampf(float(status.mark_stacks) / 6.0, 0.0, 1.0))
	_visual_material.set_shader_parameter("seed_intensity", clampf(float(status.seed_stacks) / 5.0, 0.0, 1.0))
	_visual_material.set_shader_parameter("burn_intensity", clampf(float(status.burn_stacks) / 5.0, 0.0, 1.0))
	_visual_material.set_shader_parameter("freeze_intensity", clampf(float(status.freeze_stacks) / 5.0, 0.0, 1.0))
	_visual_material.set_shader_parameter("greed_intensity", clampf(float(status.greed_stacks) / 5.0, 0.0, 1.0))
	_visual_material.set_shader_parameter("flash_color", _flash_color)
	_visual_material.set_shader_parameter("flash_strength", _flash_strength)


func _setup_mark_particles() -> void:
	_mark_particles = GPUParticles3D.new()
	_mark_particles.name = "MarkParticles"
	_mark_particles.position = Vector3(0.0, 0.9, 0.0)
	_mark_particles.amount = 10
	_mark_particles.lifetime = 0.7
	_mark_particles.emitting = false
	_mark_particles.local_coords = true
	_mark_particles.draw_order = GPUParticles3D.DRAW_ORDER_LIFETIME
	_mark_particles.process_material = _create_mark_particle_material()
	_mark_particles.draw_pass_1 = _create_mark_particle_mesh()
	add_child(_mark_particles)
	_mark_particle_material = _mark_particles.process_material as ParticleProcessMaterial


func _create_mark_particle_material() -> ParticleProcessMaterial:
	var material := ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	material.emission_sphere_radius = 0.55
	material.direction = Vector3(0.0, 1.0, 0.0)
	material.spread = 45.0
	material.initial_velocity_min = 0.18
	material.initial_velocity_max = 0.55
	material.gravity = Vector3(0.0, 2.8, 0.0)
	material.scale_min = 0.22
	material.scale_max = 0.38
	material.color = Color(0.45, 0.94, 0.57, 0.9)
	material.angle_min = 0.0
	material.angle_max = 360.0
	return material


func _create_mark_particle_mesh() -> Mesh:
	var mesh := QuadMesh.new()
	mesh.size = Vector2(0.34, 0.34)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_color = Color(0.44, 0.9, 0.58, 0.95)
	mat.emission_enabled = true
	mat.emission = Color(0.44, 0.9, 0.58, 1.0)
	mat.emission_energy_multiplier = 3.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mesh.material = mat
	return mesh


func _update_mark_particles() -> void:
	if _mark_particles == null or _mark_particle_material == null:
		return
	var stacks: int = status.mark_stacks
	if stacks <= 0 or status.is_dead():
		_mark_particles.emitting = false
		return
	_mark_particles.emitting = true
	var tier: int = _get_mark_tier()
	_mark_particles.amount = 4 + tier * 2 + min(stacks, 2)
	_mark_particles.lifetime = 0.66 + float(tier) * 0.06
	_mark_particle_material.scale_min = 0.24 + float(tier) * 0.04
	_mark_particle_material.scale_max = 0.4 + float(tier) * 0.06
	_mark_particle_material.initial_velocity_min = 0.16 + float(tier) * 0.06
	_mark_particle_material.initial_velocity_max = 0.48 + float(tier) * 0.12
	_mark_particle_material.gravity = Vector3(0.0, 2.6 + float(tier) * 0.6, 0.0)
	if is_execute_ready():
		_mark_particle_material.color = Color(0.9, 0.28, 0.78, 0.96)
	else:
		_mark_particle_material.color = Color(0.45, 0.94, 0.57, 0.9)


func _get_effect_color(tag: String) -> Color:
	match tag:
		"duplicate_x2":
			return Color(1.0, 0.86, 0.2, 1.0)
		"add_one":
			return Color(0.48, 0.9, 1.0, 1.0)
		"scatter":
			return Color(1.0, 0.6, 0.2, 1.0)
		"focus":
			return Color(0.5, 1.0, 1.0, 1.0)
		"mark":
			return Color(0.45, 1.0, 0.45, 1.0)
		"mark_amplifier":
			return Color(0.75, 1.0, 0.2, 1.0)
		"execute":
			return Color(1.0, 0.25, 0.45, 1.0)
		"converge":
			return Color(0.85, 0.75, 1.0, 1.0)
		"seed":
			return Color(0.35, 1.0, 0.65, 1.0)
		"seed_spread":
			return Color(0.25, 0.95, 0.75, 1.0)
		"spawn":
			return Color(0.66, 1.0, 0.35, 1.0)
		"burn":
			return Color(1.0, 0.4, 0.2, 1.0)
		"freeze":
			return Color(0.45, 0.86, 1.0, 1.0)
		"reactor":
			return Color(0.95, 0.4, 1.0, 1.0)
		"drop_coin":
			return Color(1.0, 0.84, 0.2, 1.0)
		"greed":
			return Color(1.0, 0.68, 0.2, 1.0)
		"cash_out":
			return Color(1.0, 0.95, 0.5, 1.0)
		_:
			return Color(1.0, 1.0, 1.0, 1.0)


func _spawn_effect_burst(tag: String) -> void:
	if _active_effect_bursts >= max_effect_bursts:
		return
	var preset: Dictionary = _get_effect_preset(tag)
	var burst := GPUParticles3D.new()
	burst.name = "EffectBurst"
	burst.one_shot = true
	burst.explosiveness = 1.0
	burst.amount = int(preset.get("amount", 10))
	burst.lifetime = float(preset.get("lifetime", 0.25))
	burst.local_coords = true
	burst.position = Vector3(0.0, 1.0, 0.0)
	burst.draw_pass_1 = _create_effect_mesh(preset)
	burst.process_material = _create_effect_material(preset)
	add_child(burst)
	burst.emitting = true
	_active_effect_bursts += 1
	var timer := get_tree().create_timer(burst.lifetime + 0.25)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(burst):
			burst.queue_free()
		_active_effect_bursts = maxi(0, _active_effect_bursts - 1)
	)


func _clear_runtime_bursts() -> void:
	for child in get_children():
		if child == _mark_particles:
			continue
		if child is GPUParticles3D:
			child.queue_free()
	_active_effect_bursts = 0


func _create_effect_material(preset: Dictionary) -> ParticleProcessMaterial:
	var material := ParticleProcessMaterial.new()
	var shape: String = str(preset.get("shape", "sphere"))
	match shape:
		"box":
			material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
			material.emission_box_extents = Vector3(0.45, 0.95, 0.45)
		"point":
			material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
		_:
			material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
			material.emission_sphere_radius = 0.55
	material.direction = Vector3(0.0, 1.0, 0.0)
	material.spread = float(preset.get("spread", 45.0))
	material.initial_velocity_min = float(preset.get("velocity_min", 0.2))
	material.initial_velocity_max = float(preset.get("velocity_max", 0.7))
	material.gravity = Vector3(0.0, float(preset.get("gravity_y", 2.4)), 0.0)
	material.scale_min = float(preset.get("scale_min", 0.14))
	material.scale_max = float(preset.get("scale_max", 0.28))
	material.color = preset.get("color", Color(1.0, 1.0, 1.0, 1.0))
	return material


func _create_effect_mesh(preset: Dictionary) -> Mesh:
	var mesh := QuadMesh.new()
	var size: float = float(preset.get("mesh_size", 0.22))
	mesh.size = Vector2(size, size)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var color: Color = preset.get("color", Color(1.0, 1.0, 1.0, 1.0))
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = float(preset.get("energy", 4.0))
	mesh.material = mat
	return mesh


func _get_effect_preset(tag: String) -> Dictionary:
	match tag:
		"duplicate_x2":
			return {"color": Color(1.0, 0.86, 0.2, 0.95), "amount": 8, "lifetime": 0.26, "shape": "sphere", "spread": 100.0, "velocity_min": 0.25, "velocity_max": 0.8, "gravity_y": 1.6, "scale_min": 0.18, "scale_max": 0.28, "mesh_size": 0.28, "energy": 4.0}
		"add_one":
			return {"color": Color(0.48, 0.9, 1.0, 0.95), "amount": 6, "lifetime": 0.24, "shape": "point", "spread": 24.0, "velocity_min": 0.18, "velocity_max": 0.5, "gravity_y": 2.2, "scale_min": 0.16, "scale_max": 0.24, "mesh_size": 0.24, "energy": 3.4}
		"scatter":
			return {"color": Color(1.0, 0.58, 0.2, 0.92), "amount": 12, "lifetime": 0.3, "shape": "sphere", "spread": 180.0, "velocity_min": 0.28, "velocity_max": 1.0, "gravity_y": 1.2, "scale_min": 0.14, "scale_max": 0.24, "mesh_size": 0.22, "energy": 4.5}
		"focus":
			return {"color": Color(0.5, 1.0, 1.0, 0.95), "amount": 7, "lifetime": 0.28, "shape": "point", "spread": 10.0, "velocity_min": 0.3, "velocity_max": 0.9, "gravity_y": 3.0, "scale_min": 0.16, "scale_max": 0.3, "mesh_size": 0.26, "energy": 4.2}
		"mark":
			return {"color": Color(0.42, 1.0, 0.42, 0.95), "amount": 8, "lifetime": 0.28, "shape": "sphere", "spread": 70.0, "velocity_min": 0.2, "velocity_max": 0.65, "gravity_y": 2.8, "scale_min": 0.18, "scale_max": 0.3, "mesh_size": 0.25, "energy": 4.0}
		"mark_amplifier":
			return {"color": Color(0.75, 1.0, 0.2, 0.95), "amount": 10, "lifetime": 0.32, "shape": "box", "spread": 140.0, "velocity_min": 0.25, "velocity_max": 0.85, "gravity_y": 2.1, "scale_min": 0.2, "scale_max": 0.32, "mesh_size": 0.26, "energy": 4.4}
		"execute":
			return {"color": Color(1.0, 0.25, 0.45, 1.0), "amount": 14, "lifetime": 0.36, "shape": "sphere", "spread": 160.0, "velocity_min": 0.4, "velocity_max": 1.25, "gravity_y": 1.4, "scale_min": 0.2, "scale_max": 0.36, "mesh_size": 0.3, "energy": 5.2}
		"converge":
			return {"color": Color(0.85, 0.75, 1.0, 0.95), "amount": 9, "lifetime": 0.25, "shape": "point", "spread": 12.0, "velocity_min": 0.38, "velocity_max": 1.1, "gravity_y": 3.4, "scale_min": 0.16, "scale_max": 0.28, "mesh_size": 0.24, "energy": 4.6}
		"seed":
			return {"color": Color(0.35, 1.0, 0.65, 0.95), "amount": 7, "lifetime": 0.3, "shape": "sphere", "spread": 80.0, "velocity_min": 0.2, "velocity_max": 0.7, "gravity_y": 2.5, "scale_min": 0.16, "scale_max": 0.28, "mesh_size": 0.24, "energy": 4.0}
		"seed_spread":
			return {"color": Color(0.25, 0.95, 0.75, 0.95), "amount": 12, "lifetime": 0.28, "shape": "box", "spread": 170.0, "velocity_min": 0.2, "velocity_max": 0.9, "gravity_y": 2.0, "scale_min": 0.14, "scale_max": 0.24, "mesh_size": 0.22, "energy": 4.3}
		"spawn":
			return {"color": Color(0.66, 1.0, 0.35, 0.98), "amount": 10, "lifetime": 0.34, "shape": "box", "spread": 115.0, "velocity_min": 0.25, "velocity_max": 0.85, "gravity_y": 2.7, "scale_min": 0.2, "scale_max": 0.34, "mesh_size": 0.28, "energy": 4.8}
		"burn":
			return {"color": Color(1.0, 0.42, 0.2, 0.95), "amount": 10, "lifetime": 0.3, "shape": "sphere", "spread": 125.0, "velocity_min": 0.28, "velocity_max": 0.9, "gravity_y": 3.2, "scale_min": 0.18, "scale_max": 0.3, "mesh_size": 0.26, "energy": 4.8}
		"freeze":
			return {"color": Color(0.45, 0.86, 1.0, 0.95), "amount": 9, "lifetime": 0.34, "shape": "point", "spread": 35.0, "velocity_min": 0.2, "velocity_max": 0.6, "gravity_y": 1.2, "scale_min": 0.16, "scale_max": 0.3, "mesh_size": 0.26, "energy": 4.3}
		"reactor":
			return {"color": Color(0.95, 0.4, 1.0, 1.0), "amount": 16, "lifetime": 0.38, "shape": "sphere", "spread": 180.0, "velocity_min": 0.35, "velocity_max": 1.4, "gravity_y": 1.6, "scale_min": 0.2, "scale_max": 0.34, "mesh_size": 0.3, "energy": 5.4}
		"drop_coin":
			return {"color": Color(1.0, 0.84, 0.2, 0.95), "amount": 8, "lifetime": 0.26, "shape": "point", "spread": 65.0, "velocity_min": 0.2, "velocity_max": 0.75, "gravity_y": 2.9, "scale_min": 0.16, "scale_max": 0.28, "mesh_size": 0.25, "energy": 4.0}
		"greed":
			return {"color": Color(1.0, 0.68, 0.2, 0.95), "amount": 9, "lifetime": 0.3, "shape": "sphere", "spread": 90.0, "velocity_min": 0.2, "velocity_max": 0.7, "gravity_y": 2.4, "scale_min": 0.16, "scale_max": 0.3, "mesh_size": 0.26, "energy": 4.2}
		"cash_out":
			return {"color": Color(1.0, 0.95, 0.5, 1.0), "amount": 14, "lifetime": 0.34, "shape": "sphere", "spread": 150.0, "velocity_min": 0.3, "velocity_max": 1.1, "gravity_y": 2.0, "scale_min": 0.2, "scale_max": 0.34, "mesh_size": 0.3, "energy": 5.0}
		_:
			return {"color": Color(1.0, 1.0, 1.0, 0.95), "amount": 8, "lifetime": 0.24, "shape": "sphere", "spread": 80.0, "velocity_min": 0.2, "velocity_max": 0.7, "gravity_y": 2.4, "scale_min": 0.16, "scale_max": 0.28, "mesh_size": 0.24, "energy": 4.0}
