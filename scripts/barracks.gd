extends Area2D

signal stats_changed

var level: int = 0 # 0 to 9 (10 levels)
var spawn_interval: float = 0.6
var timer: float = 0.0
var max_hp: float = 50.0
var current_hp: float = 50.0

@onready var label: Label = $Label
var enemy_scene: PackedScene = null

func _ready() -> void:
	add_to_group("buildings")
	add_to_group("barracks")
	if FileAccess.file_exists("res://scenes/enemy.tscn"):
		enemy_scene = load("res://scenes/enemy.tscn")
	update_stats()

func _process(delta: float) -> void:
	timer += delta
	if timer >= spawn_interval:
		timer -= spawn_interval
		_spawn_enemy()

func update_stats() -> void:
	var gm = get_node_or_null("/root/GameManager")
	var intervals = gm.BARRACKS_INTERVAL_LEVELS if gm else [0.6, 0.5, 0.42, 0.37, 0.3, 0.27, 0.24, 0.2, 0.15, 0.12, 0.1]
	level = clamp(level, 0, intervals.size() - 1)
	spawn_interval = intervals[level]
	
	_update_ui()
	stats_changed.emit()

func can_upgrade() -> bool:
	var gm = get_node_or_null("/root/GameManager")
	var max_lv = (gm.BARRACKS_INTERVAL_LEVELS.size() - 1) if gm else 9
	return level < max_lv

func get_upgrade_cost() -> float:
	return 5.0 * pow(1.6, level + 1)

func upgrade() -> bool:
	if not can_upgrade():
		return false
	var gm = get_node_or_null("/root/GameManager")
	var cost = get_upgrade_cost()
	if gm and gm.spend_gold(cost):
		level += 1
		update_stats()
		return true
	return false

func take_damage(amount: float) -> void:
	current_hp -= amount
	_update_ui()
	if current_hp <= 0:
		queue_free()

func _spawn_enemy() -> void:
	if enemy_scene:
		var enemy = enemy_scene.instantiate()
		enemy.global_position = global_position + Vector2(randf_range(-15, 15), randf_range(-15, 15))
		get_tree().current_scene.add_child(enemy)

func _update_ui() -> void:
	if label:
		label.text = "Казарма Lv%d\nСпавн: %.2fс" % [level + 1, spawn_interval]
