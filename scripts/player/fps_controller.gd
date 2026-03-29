extends CharacterBody3D
class_name FpsController

@export var move_speed: float = 6.0
@export var gravity_strength: float = 20.0
@export var mouse_sensitivity: float = 0.0025
@export var gamepad_look_sensitivity: float = 1.07
@export var gamepad_look_deadzone: float = 0.18
@export var sprint_multiplier: float = 1.5
@export var jump_velocity: float = 6.0
@export var ground_deceleration: float = 28.0
@export var sprint_blend_speed: float = 7.5
@export var sprint_energy_max: float = 100.0
@export var sprint_energy_drain_per_second: float = 80.0
@export var sprint_energy_recharge_per_second: float = 88.0
@export var sprint_overload_recharge_multiplier: float = 0.6

@onready var camera_pivot: Node3D = $CameraPivot

var _pitch: float = 0.0
var _look_input: Vector2 = Vector2.ZERO
var _current_sprint_multiplier: float = 1.0
var _sprint_energy: float = 100.0
var _sprint_overloaded: bool = false

func _ready() -> void:
	_sprint_energy = sprint_energy_max
	_set_cursor_captured(true)


func _input(event: InputEvent) -> void:
	if GameState.operator_menu_open:
		return
	if event.is_action_pressed("toggle_cursor"):
		_set_cursor_captured(Input.mouse_mode != Input.MOUSE_MODE_CAPTURED)
		return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_XBUTTON1 or event.button_index == MOUSE_BUTTON_XBUTTON2:
			_set_cursor_captured(Input.mouse_mode != Input.MOUSE_MODE_CAPTURED)
			return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_look_input += event.relative


func _physics_process(delta: float) -> void:
	if GameState.operator_menu_open:
		_look_input = Vector2.ZERO
		velocity.x = move_toward(velocity.x, 0.0, ground_deceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, ground_deceleration * delta)
		if not is_on_floor():
			velocity.y -= gravity_strength * delta
		else:
			velocity.y = -0.1
		move_and_slide()
		return
	_accumulate_gamepad_look(delta)
	_apply_look()
	var input_vector: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction: Vector3 = (transform.basis * Vector3(input_vector.x, 0.0, input_vector.y)).normalized()
	var wants_sprint: bool = Input.is_action_pressed("sprint")
	var is_moving: bool = direction != Vector3.ZERO
	var can_sprint: bool = wants_sprint and is_moving and _can_use_sprint()
	_update_sprint_energy(delta, can_sprint)
	var sprint_target: float = sprint_multiplier if can_sprint else 1.0
	_current_sprint_multiplier = move_toward(_current_sprint_multiplier, sprint_target, sprint_blend_speed * delta)
	var current_speed: float = move_speed * _current_sprint_multiplier
	if is_moving:
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, ground_deceleration * delta)
		velocity.z = move_toward(velocity.z, 0.0, ground_deceleration * delta)
	if not is_on_floor():
		velocity.y -= gravity_strength * delta
	else:
		if Input.is_action_just_pressed("jump"):
			velocity.y = jump_velocity
		else:
			velocity.y = -0.1
	move_and_slide()


func _apply_look() -> void:
	if _look_input == Vector2.ZERO:
		return
	rotate_y(-_look_input.x * mouse_sensitivity)
	_pitch = clamp(_pitch - _look_input.y * mouse_sensitivity, deg_to_rad(-80.0), deg_to_rad(80.0))
	camera_pivot.rotation.x = _pitch
	_look_input = Vector2.ZERO


func _set_cursor_captured(captured: bool) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if captured else Input.MOUSE_MODE_VISIBLE


func _accumulate_gamepad_look(delta: float) -> void:
	var joypads: Array[int] = Input.get_connected_joypads()
	if joypads.is_empty():
		return
	var device_id: int = joypads[0]
	var look_x: float = Input.get_joy_axis(device_id, JOY_AXIS_RIGHT_X)
	var look_y: float = Input.get_joy_axis(device_id, JOY_AXIS_RIGHT_Y)
	var stick: Vector2 = Vector2(look_x, look_y)
	if stick.length() < gamepad_look_deadzone:
		return
	var normalized_strength: float = inverse_lerp(gamepad_look_deadzone, 1.0, minf(1.0, stick.length()))
	var filtered: Vector2 = stick.normalized() * normalized_strength
	_look_input += filtered * gamepad_look_sensitivity * delta * 1000.0


func get_sprint_energy_ratio() -> float:
	return 0.0 if sprint_energy_max <= 0.0 else clampf(_sprint_energy / sprint_energy_max, 0.0, 1.0)


func get_sprint_energy_current() -> float:
	return _sprint_energy


func get_sprint_energy_max() -> float:
	return sprint_energy_max


func is_sprint_overloaded() -> bool:
	return _sprint_overloaded


func _can_use_sprint() -> bool:
	return not _sprint_overloaded and _sprint_energy > 0.0


func _update_sprint_energy(delta: float, consuming: bool) -> void:
	if consuming:
		_sprint_energy = maxf(0.0, _sprint_energy - sprint_energy_drain_per_second * delta)
		if _sprint_energy <= 0.0:
			_sprint_overloaded = true
	else:
		var recharge_rate: float = sprint_energy_recharge_per_second
		if _sprint_overloaded:
			recharge_rate *= sprint_overload_recharge_multiplier
		_sprint_energy = minf(sprint_energy_max, _sprint_energy + recharge_rate * delta)
		if _sprint_overloaded and _sprint_energy >= sprint_energy_max:
			_sprint_overloaded = false
