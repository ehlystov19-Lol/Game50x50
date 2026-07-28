extends Control

@onready var gold_label: Label = $VBoxContainer/Header/GoldLabel
@onready var score_label: Label = $VBoxContainer/Header/ScoreLabel

# Building Placement Buttons
@onready var btn_kingdom: Button = $VBoxContainer/BuildSection/Grid/BtnKingdom
@onready var btn_mill: Button = $VBoxContainer/BuildSection/Grid/BtnMill
@onready var btn_wall: Button = $VBoxContainer/BuildSection/Grid/BtnWall
@onready var btn_tower: Button = $VBoxContainer/BuildSection/Grid/BtnTower
@onready var btn_barracks: Button = $VBoxContainer/BuildSection/Grid/BtnBarracks

# Upgrade Panel
@onready var upgrade_panel: PanelContainer = $VBoxContainer/UpgradeSection/UpgradePanel
@onready var selected_info_label: Label = $VBoxContainer/UpgradeSection/UpgradePanel/VBox/InfoLabel
@onready var upgrade_button: Button = $VBoxContainer/UpgradeSection/UpgradePanel/VBox/UpgradeButton

var current_selected_building: Node = null

func _ready() -> void:
	var gm = get_node_or_null("/root/GameManager")
	if gm:
		gm.gold_changed.connect(_on_gold_changed)
		gm.score_changed.connect(_on_score_changed)
		gm.selected_building_changed.connect(_on_selected_building_changed)
		_on_gold_changed(gm.gold)
		_on_score_changed(gm.score)

	btn_kingdom.pressed.connect(func(): _on_build_btn_pressed("kingdom"))
	btn_mill.pressed.connect(func(): _on_build_btn_pressed("mill"))
	btn_wall.pressed.connect(func(): _on_build_btn_pressed("wall"))
	btn_tower.pressed.connect(func(): _on_build_btn_pressed("tower"))
	btn_barracks.pressed.connect(func(): _on_build_btn_pressed("barracks"))
	upgrade_button.pressed.connect(_on_upgrade_pressed)

	_update_upgrade_panel()

func _on_gold_changed(new_gold: float) -> void:
	if gold_label:
		gold_label.text = "Золото: %.1f" % new_gold
	_update_build_buttons()

func _on_score_changed(new_score: int) -> void:
	if score_label:
		score_label.text = "Очки: %d" % new_score

func _on_build_btn_pressed(type_name: String) -> void:
	var gm = get_node_or_null("/root/GameManager")
	if gm:
		gm.select_placement(type_name)

func _update_build_buttons() -> void:
	var gm = get_node_or_null("/root/GameManager")
	if not gm:
		return
	btn_kingdom.disabled = not gm.can_afford(gm.COST_KINGDOM)
	btn_mill.disabled = not gm.can_afford(gm.COST_MILL)
	btn_wall.disabled = not gm.can_afford(gm.COST_WALL)
	btn_tower.disabled = not gm.can_afford(gm.COST_TOWER)
	btn_barracks.disabled = not gm.can_afford(gm.COST_BARRACKS)

func _on_selected_building_changed(building_node: Node) -> void:
	current_selected_building = building_node
	_update_upgrade_panel()

func _update_upgrade_panel() -> void:
	if not is_instance_valid(current_selected_building):
		upgrade_panel.visible = false
		return
		
	upgrade_panel.visible = true
	var info_text = "Выбран объект: "
	var can_up = false
	var cost = 0.0
	
	if current_selected_building.has_method("can_upgrade"):
		can_up = current_selected_building.can_upgrade()
	if current_selected_building.has_method("get_upgrade_cost"):
		cost = current_selected_building.get_upgrade_cost()

	var b_name = current_selected_building.name
	var lv = current_selected_building.get("level") if "level" in current_selected_building else 0
	
	info_text += "%s (Уровень %d)\n" % [b_name, lv + 1]
	info_text += "Цена прокачки: %.1f золото" % cost
	
	selected_info_label.text = info_text
	
	var gm = get_node_or_null("/root/GameManager")
	upgrade_button.disabled = not can_up or (gm and not gm.can_afford(cost))
	if not can_up:
		upgrade_button.text = "МАКС. УРОВЕНЬ"
	else:
		upgrade_button.text = "Прокачать (%.1f Золота)" % cost

func _on_upgrade_pressed() -> void:
	if is_instance_valid(current_selected_building) and current_selected_building.has_method("upgrade"):
		if current_selected_building.upgrade():
			_update_upgrade_panel()
