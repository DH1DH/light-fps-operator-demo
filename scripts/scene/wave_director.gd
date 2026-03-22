extends Node
class_name WaveDirector

const EnemyWalker = preload("res://scripts/combat/enemy_walker.gd")
const EnemyWalkerScene = preload("res://scenes/enemy_walker.tscn")

signal state_changed

enum RunState {
	PREPARING,
	ACTIVE,
	INTERMISSION,
	DEFEAT,
}

@export var base_enemies_per_wave: int = 4
@export var extra_enemies_per_wave: int = 2
@export var intermission_duration: float = 1.5
@export var defeat_restart_delay: float = 2.4
@export var wave_reward_base: int = 5
@export var wave_reward_per_wave: int = 4
@export var arena_center: Vector3 = Vector3(0.0, 0.0, 16.0)

var current_wave: int = 0
var enemies_alive: int = 0
var total_kills: int = 0
var state: int = RunState.PREPARING
var _state_timer: float = 0.0
var _player: FpsController = null
var _last_wave_reward: int = 0


func _ready() -> void:
	add_to_group("wave_director")
	_bind_player()
	call_deferred("start_run")


func _process(delta: float) -> void:
	if state == RunState.INTERMISSION or state == RunState.DEFEAT:
		_state_timer = maxf(0.0, _state_timer - delta)
		if _state_timer <= 0.0:
			if state == RunState.INTERMISSION:
				_start_wave(current_wave + 1)
			else:
				start_run()


func start_run() -> void:
	_clear_enemies()
	total_kills = 0
	current_wave = 0
	enemies_alive = 0
	_last_wave_reward = 0
	state = RunState.PREPARING
	_bind_player()
	if _player != null:
		_player.reset_player()
	_start_wave(1)


func reset_run() -> void:
	start_run()


func get_state_text() -> String:
	match state:
		RunState.ACTIVE:
			return "Combat"
		RunState.INTERMISSION:
			return "Wave Clear"
		RunState.DEFEAT:
			return "Defeat"
		_:
			return "Preparing"


func get_status_line() -> String:
	return "Wave %d | Enemies %d | State %s" % [current_wave, enemies_alive, get_state_text()]


func get_reward_line() -> String:
	if state == RunState.INTERMISSION:
		return "Wave reward +%d | Next wave in %.1fs | Total kills %d" % [_last_wave_reward, _state_timer, total_kills]
	if state == RunState.DEFEAT:
		return "Restarting in %.1fs | Total kills %d" % [_state_timer, total_kills]
	return "Kill reward active | Total kills %d | Gold %d" % [total_kills, GameState.gold]


func _bind_player() -> void:
	if _player != null and is_instance_valid(_player):
		if _player.player_died.is_connected(_on_player_died):
			_player.player_died.disconnect(_on_player_died)
	var player_node: Node = get_parent().get_node_or_null("Player")
	if player_node is FpsController:
		_player = player_node as FpsController
		if not _player.player_died.is_connected(_on_player_died):
			_player.player_died.connect(_on_player_died)
	else:
		_player = null


func _start_wave(wave_number: int) -> void:
	_clear_enemies()
	current_wave = max(1, wave_number)
	enemies_alive = 0
	state = RunState.ACTIVE
	_last_wave_reward = 0
	var spawn_count: int = base_enemies_per_wave + (current_wave - 1) * extra_enemies_per_wave
	for index in range(spawn_count):
		_spawn_enemy(index)
	state_changed.emit()


func _spawn_enemy(index: int) -> void:
	var enemy: EnemyWalker = EnemyWalkerScene.instantiate() as EnemyWalker
	if enemy == null:
		return
	get_parent().add_child(enemy)
	enemy.global_position = _spawn_position_for_index(index)
	enemy.call_deferred("configure_for_wave", current_wave)
	enemy.call_deferred("look_at", Vector3(enemy.global_position.x, enemy.global_position.y, arena_center.z), Vector3.UP, true)
	enemy.defeated.connect(_on_enemy_defeated)
	enemies_alive += 1


func _spawn_position_for_index(index: int) -> Vector3:
	var ring_radius: float = 10.0 + float(current_wave) * 0.8
	var angle: float = (TAU / 8.0) * float(index % 8) + randf_range(-0.18, 0.18)
	var offset: Vector3 = Vector3(cos(angle) * ring_radius, 0.95, sin(angle) * ring_radius)
	var position: Vector3 = arena_center + offset
	position.x = clampf(position.x, -20.0, 20.0)
	position.z = clampf(position.z, 8.0, 30.0)
	return position


func _on_enemy_defeated(gold_reward: int) -> void:
	if state != RunState.ACTIVE:
		return
	enemies_alive = max(0, enemies_alive - 1)
	total_kills += 1
	if gold_reward > 0:
		GameState.add_gold(gold_reward)
	if enemies_alive <= 0:
		_last_wave_reward = wave_reward_base + (current_wave - 1) * wave_reward_per_wave
		GameState.add_gold(_last_wave_reward)
		state = RunState.INTERMISSION
		_state_timer = intermission_duration
	state_changed.emit()


func _on_player_died() -> void:
	if state == RunState.DEFEAT:
		return
	_clear_enemies()
	enemies_alive = 0
	state = RunState.DEFEAT
	_state_timer = defeat_restart_delay
	state_changed.emit()


func _clear_enemies() -> void:
	for node in get_tree().get_nodes_in_group("enemy_walker"):
		if node != null and is_instance_valid(node):
			node.queue_free()
