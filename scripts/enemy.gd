extends Area2D

@export var move_speed: float = 60.0
@export var damage: float = 2.0
@export var max_hp: float = 10.0

var current_hp: float = 10.0
var attack_timer: float = 0.0
var attack_rate: float = 1.0

@onready var label: Label = $Label

func _ready() -> void:
	add_to_group("enemies")
	current_hp = max_hp
	_update_ui()

func _process(delta: float) -> void:
	var target_building = _find_target()
	if target_building and is_instance_valid(target_building):
		var dir = (target_building.global_position - global_position).normalized()
		var dist = global_position.distance_to(target_building.global_position)
		
		if dist > 20.0:
			global_position += dir * move_speed * delta
		else:
			# Attack building
			attack_timer += delta
			if attack_timer >= attack_rate:
				attack_timer -= attack_rate
				if target_building.has_method("take_damage"):
					target_building.take_damage(damage)

func take_damage(amount: float) -> void:
	current_hp -= amount
	_update_ui()
	if current_hp <= 0:
		var gm = get_node_or_null("/root/GameManager")
		if gm:
			gm.gold += 0.5
		queue_free()

func _find_target() -> Node2D:
	# Prioritize walls/towers if close, otherwise march directly to Kingdom
	var kingdom = get_tree().get_nodes_in_group("kingdom")
	if kingdom.size() > 0 and is_instance_valid(kingdom[0]):
		return kingdom[0]
		
	var buildings = get_tree().get_nodes_in_group("buildings")
	var nearest: Node2D = null
	var min_dist: float = 99999.0
	for b in buildings:
		if is_instance_valid(b):
			var d = global_position.distance_to(b.global_position)
			if d < min_dist:
				min_dist = d
				nearest = b
	return nearest

func _update_ui() -> void:
	if label:
		label.text = "HP:%d" % int(current_hp)
