extends Area2D

var target_enemy: Node2D = null
var damage: float = 1.0
var speed: float = 300.0

func _process(delta: float) -> void:
	if not is_instance_valid(target_enemy):
		queue_free()
		return
		
	var dir = (target_enemy.global_position - global_position).normalized()
	global_position += dir * speed * delta
	
	if global_position.distance_to(target_enemy.global_position) < 15.0:
		if target_enemy.has_method("take_damage"):
			target_enemy.take_damage(damage)
		queue_free()
