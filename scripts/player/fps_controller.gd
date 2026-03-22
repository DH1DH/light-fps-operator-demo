extends CharacterBody3D
class_name FpsController

@export var move_speed: float = 6.0
@export var gravity_strength: float = 20.0
@export var mouse_sensitivity: float = 0.0025
@export var sprint_multiplier: float = 1.2
@export var jump_velocity: float = 6.0

@onready var camera_pivot: Node3D = $CameraPivot

var _pitch: float = 0.0
var _look_input: Vector2 = Vector2.ZERO

func _ready() -> void:
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
		velocity.x = move_toward(velocity.x, 0.0, move_speed * delta * 10.0)
		velocity.z = move_toward(velocity.z, 0.0, move_speed * delta * 10.0)
		if not is_on_floor():
			velocity.y -= gravity_strength * delta
		else:
			velocity.y = -0.1
		move_and_slide()
		return
	_apply_look()
	var input_vector: Vector2 = Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction: Vector3 = (transform.basis * Vector3(input_vector.x, 0.0, input_vector.y)).normalized()
	var current_speed: float = move_speed
	if Input.is_action_pressed("sprint"):
		current_speed *= sprint_multiplier
	if direction != Vector3.ZERO:
		velocity.x = direction.x * current_speed
		velocity.z = direction.z * current_speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, move_speed * delta * 10.0)
		velocity.z = move_toward(velocity.z, 0.0, move_speed * delta * 10.0)
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
