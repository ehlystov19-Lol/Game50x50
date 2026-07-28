extends Node2D

@onready var split_container: HSplitContainer = $CanvasLayer/HSplitContainer

func _ready() -> void:
	# Set 50/50 split ratio dynamically on window resize
	get_viewport().size_changed.connect(_on_viewport_size_changed)
	call_deferred("_on_viewport_size_changed")

func _on_viewport_size_changed() -> void:
	if split_container:
		var window_width = get_viewport().get_visible_rect().size.x
		split_container.split_offset = int(window_width * 0.5)
