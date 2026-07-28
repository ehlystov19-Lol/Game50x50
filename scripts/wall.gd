extends Area2D

signal stats_changed

var level: int = 0 # 0 to 99 (100 levels)
var max_hp: float = 2.0
var current_hp: float = 2.0

@onready var label: Label = $Label

func _ready() -> void:
	add_to_group("buildings")
	add_to_group("walls")
	update_stats()

func update_stats() -> void:
	var gm = get_node_or_null("/root/GameManager")
	var hp_list = gm.WALL_HP_LEVELS if gm else [2.0, 3.0, 5.0, 9.0, 12.0, 15.0]
	level = clamp(level, 0, hp_list.size() - 1)
	
	var prev_max = max_hp
	max_hp = hp_list[level]
	if prev_max > 0:
		current_hp = min(max_hp, current_hp + (max_hp - prev_max))
	else:
		current_hp = max_hp
	
	_update_ui()
	stats_changed.emit()

func can_upgrade() -> bool:
	var gm = get_node_or_null("/root/GameManager")
	var max_lv = (gm.WALL_HP_LEVELS.size() - 1) if gm else 99
	return level < max_lv

func get_upgrade_cost() -> float:
	return 0.1 * pow(1.15, level + 1)

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

func _update_ui() -> void:
	if label:
		label.text = "Стена Lv%d\nHP:%d/%d" % [level + 1, int(current_hp), int(max_hp)]
