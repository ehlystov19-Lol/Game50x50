extends Area2D

signal stats_changed

var level: int = 0 # 0 to 49 (50 levels)
var damage: float = 1.0
var max_hp: float = 1.0
var current_hp: float = 1.0
var attack_cooldown: float = 0.8
var timer: float = 0.0

@export var attack_range: float = 200.0
@onready var label: Label = $Label

var projectile_scene: PackedScene = null

func _ready() -> void:
	add_to_group("buildings")
	add_to_group("towers")
	if FileAccess.file_exists("res://scenes/projectile.tscn"):
		projectile_scene = load("res://scenes/projectile.tscn")
	update_stats()

func _process(delta: float) -> void:
	timer += delta
	if timer >= attack_cooldown:
		timer -= attack_cooldown
		_shoot_nearest_enemy()

func update_stats() -> void:
	var gm = get_node_or_null("/root/GameManager")
	var stats_list = gm.TOWER_DMG_HP_LEVELS if gm else [1.0, 2.0, 3.0, 5.0, 7.0]
	level = clamp(level, 0, stats_list.size() - 1)
	
	damage = stats_list[level]
	var prev_max = max_hp
	max_hp = stats_list[level]
	if prev_max > 0:
		current_hp = min(max_hp, current_hp + (max_hp - prev_max))
	else:
		current_hp = max_hp
	
	_update_ui()
	stats_changed.emit()

func can_upgrade() -> bool:
	var gm = get_node_or_null("/root/GameManager")
	var max_lv = (gm.TOWER_DMG_HP_LEVELS.size() - 1) if gm else 49
	return level < max_lv

func get_upgrade_cost() -> float:
	return 5.0 * pow(1.4, level + 1)

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

func _shoot_nearest_enemy() -> void:
	var enemies = get_tree().get_nodes_in_group("enemies")
	var nearest_enemy: Node2D = null
	var min_dist: float = attack_range
	
	for enemy in enemies:
		if is_instance_valid(enemy):
			var dist = global_position.distance_to(enemy.global_position)
			if dist <= min_dist:
				min_dist = dist
				nearest_enemy = enemy
				
	if nearest_enemy and projectile_scene:
		var proj = projectile_scene.instantiate()
		proj.global_position = global_position
		proj.target_enemy = nearest_enemy
		proj.damage = damage
		get_tree().current_scene.add_child(proj)

func _update_ui() -> void:
	if label:
		label.text = "Башня Lv%d\nУрон:%d | HP:%d" % [level + 1, int(damage), int(current_hp)]
