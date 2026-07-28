extends Area2D

signal stats_changed

var level: int = 0 # 0 to 24 (25 levels)
var max_hp: float = 20.0
var current_hp: float = 20.0
var timer: float = 0.0

@onready var label: Label = $Label

func _ready() -> void:
	add_to_group("buildings")
	add_to_group("mills")
	update_stats()

func _process(delta: float) -> void:
	timer += delta
	if timer >= 1.0:
		timer -= 1.0
		_generate_score()

func _generate_score() -> void:
	var gm = get_node_or_null("/root/GameManager")
	if gm:
		var score_gain = get_current_score_rate()
		gm.score += score_gain

func get_current_score_rate() -> int:
	var gm = get_node_or_null("/root/GameManager")
	if gm and level < gm.MILL_SCORE_LEVELS.size():
		return gm.MILL_SCORE_LEVELS[level]
	return level + 1

func can_upgrade() -> bool:
	var gm = get_node_or_null("/root/GameManager")
	var max_lv = (gm.MILL_SCORE_LEVELS.size() - 1) if gm else 24
	return level < max_lv

func get_upgrade_cost() -> float:
	return 2.0 * pow(1.5, level + 1)

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

func update_stats() -> void:
	_update_ui()
	stats_changed.emit()

func take_damage(amount: float) -> void:
	current_hp -= amount
	_update_ui()
	if current_hp <= 0:
		queue_free()

func _update_ui() -> void:
	if label:
		label.text = "Мельница Lv%d\n+%d очков/с" % [level + 1, get_current_score_rate()]
