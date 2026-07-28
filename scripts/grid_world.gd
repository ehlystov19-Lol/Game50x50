extends Node2D

const TILE_SIZE: float = 40.0
const BUILD_RADIUS: int = 7 # 15x15 tiles (7 left/right/up/down + center)

var kingdom_scene: PackedScene = load("res://scenes/kingdom.tscn")
var mill_scene: PackedScene = load("res://scenes/mill.tscn")
var wall_scene: PackedScene = load("res://scenes/wall.tscn")
var tower_scene: PackedScene = load("res://scenes/tower.tscn")
var barracks_scene: PackedScene = load("res://scenes/barracks.tscn")

var kingdom_node: Node2D = null
var placed_buildings: Dictionary = {} # Vector2i (tile_pos) -> Node2D

@onready var preview_sprite: Sprite2D = $PreviewSprite
@onready var grid_lines: Node2D = $GridLines

func _ready() -> void:
	# Automatically place initial Kingdom in center
	call_deferred("_place_initial_kingdom")

func _place_initial_kingdom() -> void:
	var center_tile = Vector2i(0, 0)
	_place_building_at_tile("kingdom", center_tile, true)

func _process(_delta: float) -> void:
	queue_redraw()
	_update_preview()

func _draw() -> void:
	# Draw grid lines for 50x50 game area (-25 to 25 tiles)
	var grid_color = Color(1.0, 1.0, 1.0, 0.12)
	const MAP_RADIUS: int = 25 # 50x50 tiles total
	for x in range(-MAP_RADIUS, MAP_RADIUS + 1):
		draw_line(Vector2(x * TILE_SIZE, -MAP_RADIUS * TILE_SIZE), Vector2(x * TILE_SIZE, MAP_RADIUS * TILE_SIZE), grid_color)
	for y in range(-MAP_RADIUS, MAP_RADIUS + 1):
		draw_line(Vector2(-MAP_RADIUS * TILE_SIZE, y * TILE_SIZE), Vector2(MAP_RADIUS * TILE_SIZE, y * TILE_SIZE), grid_color)

	# Draw 15x15 build radius outline around kingdom
	if is_instance_valid(kingdom_node):
		var k_tile = world_to_tile(kingdom_node.global_position)
		var min_p = Vector2((k_tile.x - BUILD_RADIUS) * TILE_SIZE, (k_tile.y - BUILD_RADIUS) * TILE_SIZE)
		var max_p = Vector2((k_tile.x + BUILD_RADIUS + 1) * TILE_SIZE, (k_tile.y + BUILD_RADIUS + 1) * TILE_SIZE)
		var rect = Rect2(min_p, max_p - min_p)
		draw_rect(rect, Color(0.2, 0.8, 1.0, 0.15), true)
		draw_rect(rect, Color(0.2, 0.8, 1.0, 0.8), false, 2.0)

var is_dragging_camera: bool = false
var last_mouse_pos: Vector2 = Vector2.ZERO

func world_to_tile(pos: Vector2) -> Vector2i:
	return Vector2i(round(pos.x / TILE_SIZE), round(pos.y / TILE_SIZE))

func tile_to_world(tile: Vector2i) -> Vector2:
	return Vector2(tile.x * TILE_SIZE, tile.y * TILE_SIZE)

func is_within_kingdom_range(tile: Vector2i) -> bool:
	if not is_instance_valid(kingdom_node):
		return true # If no kingdom yet, placement allowed anywhere
	var k_tile = world_to_tile(kingdom_node.global_position)
	return abs(tile.x - k_tile.x) <= BUILD_RADIUS and abs(tile.y - k_tile.y) <= BUILD_RADIUS

func _update_preview() -> void:
	var gm = get_node_or_null("/root/GameManager")
	if not gm or gm.selected_placement_type == "":
		if preview_sprite:
			preview_sprite.visible = false
		return
		
	var mouse_world = get_global_mouse_position()
	var tile = world_to_tile(mouse_world)
	var snap_pos = tile_to_world(tile)
	
	if preview_sprite:
		preview_sprite.visible = true
		preview_sprite.global_position = snap_pos
		
		# Check validity
		var valid = is_within_kingdom_range(tile) and not placed_buildings.has(tile)
		preview_sprite.modulate = Color(0, 1, 0, 0.5) if valid else Color(1, 0, 0, 0.5)

func _unhandled_input(event: InputEvent) -> void:
	# Camera Pan Controls (Right click or Middle click drag)
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT or event.button_index == MOUSE_BUTTON_MIDDLE:
			if event.pressed:
				is_dragging_camera = true
				last_mouse_pos = event.position
			else:
				is_dragging_camera = false

	if event is InputEventMouseMotion and is_dragging_camera:
		var camera = $Camera2D
		if camera:
			camera.position -= (event.position - last_mouse_pos)
			last_mouse_pos = event.position

	# Left Click: Place building or select building
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var gm = get_node_or_null("/root/GameManager")
		if not gm:
			return
			
		var mouse_world = get_global_mouse_position()
		var tile = world_to_tile(mouse_world)
		
		# If user selected a building to place
		if gm.selected_placement_type != "":
			if is_within_kingdom_range(tile) and not placed_buildings.has(tile):
				var cost = gm.get_building_cost(gm.selected_placement_type)
				if gm.spend_gold(cost):
					_place_building_at_tile(gm.selected_placement_type, tile)
					gm.selected_placement_type = ""
			return

		# Otherwise, check if user clicked on an existing building to select it
		if placed_buildings.has(tile):
			gm.select_building_instance(placed_buildings[tile])
		else:
			gm.select_building_instance(null)

func _place_building_at_tile(type_name: String, tile: Vector2i, is_free: bool = false) -> void:
	var scene_to_instantiate: PackedScene = null
	match type_name.to_lower():
		"kingdom": scene_to_instantiate = kingdom_scene
		"mill": scene_to_instantiate = mill_scene
		"wall": scene_to_instantiate = wall_scene
		"tower": scene_to_instantiate = tower_scene
		"barracks": scene_to_instantiate = barracks_scene
		
	if not scene_to_instantiate:
		return
		
	var instance = scene_to_instantiate.instantiate()
	instance.global_position = tile_to_world(tile)
	add_child(instance)
	
	placed_buildings[tile] = instance
	if type_name == "kingdom":
		kingdom_node = instance

	# Connect tree exiting signal to remove from placed_buildings map
	instance.tree_exiting.connect(func(): placed_buildings.erase(tile))

