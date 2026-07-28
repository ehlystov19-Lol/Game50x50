extends Area2D

signal kingdom_destroyed
signal stats_changed

var level: int = 0
var max_hp: float = 100.0
var current_hp: float = 100.0
const BUILD_RADIUS_TILES: int = 7 # 15x15 area centered on kingdom (7 tiles each direction + center = 15)

@onready var hp_label: Label = $HPLabel
@onready var sprite: Sprite2D = $Sprite2D

func _ready() -> void:
	add_to_group("kingdom")
	add_to_group("buildings")
	update_stats()

func update_stats() -> void:
	var gm = get_node_or_null("/root/GameManager")
	var hp_list = gm.KINGDOM_HP_LEVELS if gm else [100.0, 125.0, 150.0, 200.0, 500.0]
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
	var max_lv = (gm.KINGDOM_HP_LEVELS.size() - 1) if gm else 4
	return level < max_lv

func get_upgrade_cost() -> float:
	return 10.0 * pow(1.8, level + 1)

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
		current_hp = 0
		kingdom_destroyed.emit()
		queue_free()

func _update_ui() -> void:
	if hp_label:
		hp_label.text = "Королевство Lvl %d\nHP: %d/%d" % [level + 1, int(current_hp), int(max_hp)]
