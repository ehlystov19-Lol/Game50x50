extends Node

# Global Signals
signal gold_changed(new_gold: float)
signal score_changed(new_score: int)
signal building_selected_for_placement(building_type: String)
signal selected_building_changed(building_node: Node)
signal game_over

# Resources & Stats
var gold: float = 15.0:
	set(val):
		gold = max(0.0, val)
		gold_changed.emit(gold)

var score: int = 0:
	set(val):
		score = val
		score_changed.emit(score)

var selected_placement_type: String = "" # "", "kingdom", "mill", "wall", "tower", "barracks"
var selected_building_instance: Node = null

# Costs
const COST_KINGDOM: float = 10.0
const COST_MILL: float = 2.0
const COST_WALL: float = 0.1
const COST_TOWER: float = 5.0
const COST_BARRACKS: float = 5.0

# Upgrade Progressions (as specified)
# Kingdom: 5 levels HP [100, 125, 150, 200, 500]
const KINGDOM_HP_LEVELS: Array[float] = [100.0, 125.0, 150.0, 200.0, 500.0]

# Barracks: 10 levels spawn interval [0.6, 0.5, 0.42, 0.37, 0.3, 0.27, 0.24, 0.2, 0.15, 0.12, 0.1]
const BARRACKS_INTERVAL_LEVELS: Array[float] = [0.6, 0.5, 0.42, 0.37, 0.3, 0.27, 0.24, 0.2, 0.15, 0.12, 0.1]

# Mill: 25 levels score rate [1, 2, 4, 6, 8, 10, 15, 25, 35, 45, 50, 55, 60, 65, 70, 75, 80, 85, 90, 92, 94, 96, 98, 99, 100]
const MILL_SCORE_LEVELS: Array[int] = [
	1, 2, 4, 6, 8, 10, 15, 25, 35, 45,
	50, 55, 60, 65, 70, 75, 80, 85, 90,
	92, 94, 96, 98, 99, 100
]

# Tower/Warrior: 50 levels (Damage & HP progression from 1 to 75)
var TOWER_DMG_HP_LEVELS: Array[float] = []

# Wall: 100 levels HP (progression from 2 to 1000)
var WALL_HP_LEVELS: Array[float] = []

func _ready() -> void:
	_init_tower_levels()
	_init_wall_levels()

func _init_tower_levels() -> void:
	# Preset 50 levels progression from 1 to 75
	var base_preset: Array[float] = [1, 2, 3, 5, 7, 8, 9, 11, 12, 13, 15, 17, 18, 19, 20]
	TOWER_DMG_HP_LEVELS.clear()
	for v in base_preset:
		TOWER_DMG_HP_LEVELS.append(v)
	# Fill up to 50 levels linearly scaling to 75
	while TOWER_DMG_HP_LEVELS.size() < 50:
		var i: float = float(TOWER_DMG_HP_LEVELS.size())
		var val: float = round(lerp(20.0, 75.0, (i - 14.0) / (50.0 - 15.0)))
		TOWER_DMG_HP_LEVELS.append(val)

func _init_wall_levels() -> void:
	# Preset 100 levels progression from 2 to 1000
	var base_preset: Array[float] = [2, 3, 5, 9, 12, 15, 17, 19, 25, 35, 40, 42]
	WALL_HP_LEVELS.clear()
	for v in base_preset:
		WALL_HP_LEVELS.append(v)
	# Fill up to 100 levels exponentially scaling to 1000
	while WALL_HP_LEVELS.size() < 100:
		var idx: float = float(WALL_HP_LEVELS.size())
		var t: float = (idx - 11.0) / (100.0 - 12.0)
		var val: float = round(lerp(42.0, 1000.0, pow(t, 1.5)))
		WALL_HP_LEVELS.append(val)

func select_placement(type_name: String) -> void:
	selected_placement_type = type_name
	building_selected_for_placement.emit(type_name)

func select_building_instance(node: Node) -> void:
	selected_building_instance = node
	selected_building_changed.emit(node)

func get_building_cost(type_name: String) -> float:
	match type_name.to_lower():
		"kingdom": return COST_KINGDOM
		"mill": return COST_MILL
		"wall": return COST_WALL
		"tower": return COST_TOWER
		"barracks": return COST_BARRACKS
		_: return 0.0

func can_afford(amount: float) -> bool:
	return gold >= amount

func spend_gold(amount: float) -> bool:
	if gold >= amount:
		gold -= amount
		return true
	return false
