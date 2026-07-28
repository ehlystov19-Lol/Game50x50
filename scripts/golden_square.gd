extends Control

@export var cooldown_time: float = 0.6

@onready var button: Button = $Button
@onready var progress_bar: ProgressBar = $ProgressBar
@onready var status_label: Label = $StatusLabel

var timer: float = 0.0
var is_on_cooldown: bool = false

func _ready() -> void:
	button.pressed.connect(_on_button_pressed)
	if progress_bar:
		progress_bar.max_value = cooldown_time
		progress_bar.value = cooldown_time

func _process(delta: float) -> void:
	if is_on_cooldown:
		timer -= delta
		if progress_bar:
			progress_bar.value = cooldown_time - timer
		if status_label:
			status_label.text = "Кулдаун: %.2fс" % max(0.0, timer)
		
		if timer <= 0.0:
			is_on_cooldown = false
			button.disabled = false
			if status_label:
				status_label.text = "ГОТОВО! ЖМИ!"
			if progress_bar:
				progress_bar.value = cooldown_time

func _on_button_pressed() -> void:
	if is_on_cooldown:
		return
	
	# Add +1 gold via GameManager
	var gm = get_node_or_null("/root/GameManager")
	if gm:
		gm.gold += 1.0
	else:
		# Fallback if GameManager is child node
		var parent_gm = get_tree().root.find_child("GameManager", true, false)
		if parent_gm:
			parent_gm.gold += 1.0

	# Start 0.6s cooldown
	is_on_cooldown = true
	timer = cooldown_time
	button.disabled = true
