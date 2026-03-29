extends Node3D
## Root scene script. Wires SimulationRoot, CommandServer, and ScenarioRunner together.

@onready var sim: Node = $SimulationRoot
@onready var cmd_server: Node = $CommandServer
@onready var build_manager: Node = $BuildManager

var _selected_hero_id: int = -1
var _selected_building_id: int = -1
var _quest_filter_boxes: Dictionary = {}
var _pause_menu: CanvasLayer = null

const BUILDING_ICONS := {
	"tavern": "res://assets/ui/tavern_icon.svg",
	"weapons_shop": "res://assets/ui/weapons_shop_icon.svg",
	"temple": "res://assets/ui/temple_icon.svg",
}

func _ready() -> void:
	cmd_server.set_sim(sim)
	cmd_server.start(RuntimeConfig.port)

	if RuntimeConfig.is_test() and RuntimeConfig.scenario_path != "":
		var runner: Node = load("res://scripts/control/ScenarioRunner.gd").new()
		add_child(runner)
		runner.run_scenario.call_deferred(sim, RuntimeConfig.scenario_path)
		return

	if not RuntimeConfig.is_headless():
		var btn := get_node_or_null("UILayer/UI/BuildButton")
		if btn:
			btn.pressed.connect(_on_build_tavern_pressed)
		var btn2 := get_node_or_null("UILayer/UI/BuildWeaponsShopButton")
		if btn2:
			btn2.pressed.connect(_on_build_weapons_shop_pressed)
		var btn3 := get_node_or_null("UILayer/UI/BuildTempleButton")
		if btn3:
			btn3.pressed.connect(_on_build_temple_pressed)
		var up1 := get_node_or_null("UILayer/UI/UpgradeTavernButton")
		if up1:
			up1.pressed.connect(func() -> void: _upgrade_building_type("tavern"))
		var up2 := get_node_or_null("UILayer/UI/UpgradeWeaponsShopButton")
		if up2:
			up2.pressed.connect(func() -> void: _upgrade_building_type("weapons_shop"))
		var up3 := get_node_or_null("UILayer/UI/UpgradeTempleButton")
		if up3:
			up3.pressed.connect(func() -> void: _upgrade_building_type("temple"))
		var save_btn := get_node_or_null("UILayer/UI/SaveButton")
		if save_btn:
			save_btn.pressed.connect(_save_world)
		var load_btn := get_node_or_null("UILayer/UI/LoadButton")
		if load_btn:
			load_btn.pressed.connect(_load_world)
		var enable_all_btn := get_node_or_null("UILayer/QuestPanel/QuestVBox/QuestFilterControls/EnableAllQuestsButton")
		if enable_all_btn:
			enable_all_btn.pressed.connect(func() -> void: _set_all_quest_filters(true))
		var disable_all_btn := get_node_or_null("UILayer/QuestPanel/QuestVBox/QuestFilterControls/DisableAllQuestsButton")
		if disable_all_btn:
			disable_all_btn.pressed.connect(func() -> void: _set_all_quest_filters(false))
		GameState.gold_changed.connect(_on_gold_changed)
		GameState.building_placed.connect(_on_building_state_changed)
		GameState.building_removed.connect(_on_building_removed)
		GameState.building_upgraded.connect(_on_building_upgraded)
		GameState.hero_state_changed.connect(_on_hero_state_changed)
		GameState.hero_removed.connect(_on_hero_removed)
		GameState.quests_changed.connect(_refresh_quest_ui)
		GameState.quest_filters_changed.connect(_refresh_quest_ui)
		GameState.quest_history_changed.connect(_refresh_quest_ui)
		GameState.state_reloaded.connect(_on_state_reloaded)
		_setup_quest_menu()
		_on_gold_changed(GameState.gold)
		_refresh_quest_ui()
		if RuntimeConfig.request_load_world:
			RuntimeConfig.request_load_world = false
			_load_world()
		_set_status("LMB place/select  RMB rotate build  Q/E cycle  Del remove  F1/F5 save  F2/F9 load")

func _physics_process(delta: float) -> void:
	if RuntimeConfig.is_headless():
		return  # sim is driven on-demand by CommandServer in headless mode
	sim.physics_step(delta)
	# Refresh selected hero panel each physics tick so state/position stay current
	if _selected_hero_id >= 0 and GameState.heroes.has(_selected_hero_id):
		_refresh_hero_panel(_selected_hero_id)

func _unhandled_input(event: InputEvent) -> void:
	if RuntimeConfig.is_headless():
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F1:
			_save_world()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_F2:
			_load_world()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_F5:
			_save_world()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_F9:
			_load_world()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_DELETE:
			_remove_selected_building()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_ESCAPE and not build_manager.is_placing():
			_toggle_pause_menu()
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_Q:
			build_manager.cycle_building_type(-1)
			get_viewport().set_input_as_handled()
			return
		if event.keycode == KEY_E:
			build_manager.cycle_building_type(1)
			get_viewport().set_input_as_handled()
			return
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
		return
	if _try_select_building(event.position):
		return
	_try_select_hero(event.position)

func _try_select_hero(mouse_pos: Vector2) -> void:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var space_state := get_world_3d().direct_space_state
	var params := PhysicsRayQueryParameters3D.new()
	params.from = camera.project_ray_origin(mouse_pos)
	params.to = params.from + camera.project_ray_normal(mouse_pos) * 200.0
	params.collide_with_areas = true
	params.collide_with_bodies = false
	params.collision_mask = 2
	var result: Dictionary = space_state.intersect_ray(params)
	if not result.is_empty() and result["collider"].has_meta("hero_id"):
		_show_hero_panel(result["collider"].get_meta("hero_id"))
	else:
		_hide_hero_panel()

func _try_select_building(mouse_pos: Vector2) -> bool:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return false
	var space_state := get_world_3d().direct_space_state
	var params := PhysicsRayQueryParameters3D.new()
	params.from = camera.project_ray_origin(mouse_pos)
	params.to = params.from + camera.project_ray_normal(mouse_pos) * 200.0
	params.collide_with_areas = true
	params.collide_with_bodies = false
	params.collision_mask = 4
	var result: Dictionary = space_state.intersect_ray(params)
	if result.is_empty() or not result["collider"].has_meta("building_id"):
		_selected_building_id = -1
		return false
	_selected_building_id = int(result["collider"].get_meta("building_id"))
	var building: Dictionary = GameState.buildings.get(_selected_building_id, {})
	_set_status("Selected %s  (Del remove)" % building.get("type", "building"))
	return true

func _show_hero_panel(hero_id: int) -> void:
	if not GameState.heroes.has(hero_id):
		return
	_selected_hero_id = hero_id
	_refresh_hero_panel(hero_id)
	var panel := get_node_or_null("UILayer/HeroPanel")
	if panel:
		panel.visible = true

func _refresh_hero_panel(hero_id: int) -> void:
	if not GameState.heroes.has(hero_id):
		return
	var h: Dictionary = GameState.heroes[hero_id]
	var name_lbl := get_node_or_null("UILayer/HeroPanel/VBox/NameLabel")
	var career_lbl := get_node_or_null("UILayer/HeroPanel/VBox/CareerLabel")
	var state_lbl := get_node_or_null("UILayer/HeroPanel/VBox/StateLabel")
	var level_lbl := get_node_or_null("UILayer/HeroPanel/VBox/LevelLabel")
	var health_lbl := get_node_or_null("UILayer/HeroPanel/VBox/HealthLabel")
	var gold_lbl := get_node_or_null("UILayer/HeroPanel/VBox/HeroGoldLabel")
	var bias_lbl := get_node_or_null("UILayer/HeroPanel/VBox/BiasLabel")
	var stats_lbl := get_node_or_null("UILayer/HeroPanel/VBox/StatsLabel")
	var skills_lbl := get_node_or_null("UILayer/HeroPanel/VBox/SkillsLabel")
	var tags_lbl := get_node_or_null("UILayer/HeroPanel/VBox/TagsLabel")
	var desc_lbl := get_node_or_null("UILayer/HeroPanel/VBox/DescriptionLabel")
	var quest_lbl := get_node_or_null("UILayer/HeroPanel/VBox/CurrentQuestLabel")
	if name_lbl:
		name_lbl.text = h["name"]
	if career_lbl:
		career_lbl.text = "%s  [%s]" % [h["career"], h.get("career_archetype", "")]
	if state_lbl:
		state_lbl.text = h["state"].capitalize()
	if level_lbl:
		level_lbl.text = "Level %d  XP %d" % [h.get("level", 1), h.get("xp", 0)]
	if health_lbl:
		health_lbl.text = "Health %d/%d" % [h.get("health", 0), h.get("max_health", 0)]
	if gold_lbl:
		gold_lbl.text = "Gold %d" % h.get("gold", 0)
	if bias_lbl:
		bias_lbl.text = "Quest Bias: %s   Service Bias: %s" % [h.get("quest_bias", "-"), h.get("service_bias", "-")]
	if stats_lbl:
		var stats: Dictionary = h.get("stats", {})
		stats_lbl.text = "Stats  MGT %d  AGI %d  WIT %d  SPR %d  END %d" % [
			stats.get("might", 0),
			stats.get("agility", 0),
			stats.get("wits", 0),
			stats.get("spirit", 0),
			stats.get("endurance", 0)
		]
	if skills_lbl:
		skills_lbl.text = "Skills: %s" % ", ".join(h.get("skill_names", []))
	if tags_lbl:
		tags_lbl.text = "Tags: %s" % ", ".join(h.get("career_tags", []))
	if desc_lbl:
		desc_lbl.text = h.get("career_description", "")
	if quest_lbl:
		var current_quest: Dictionary = h.get("current_quest", {})
		if current_quest.is_empty():
			quest_lbl.text = "Current Quest: None"
		else:
			quest_lbl.text = "Current Quest: %s" % current_quest.get("name", "?")

func _hide_hero_panel() -> void:
	_selected_hero_id = -1
	var panel := get_node_or_null("UILayer/HeroPanel")
	if panel:
		panel.visible = false

func _remove_selected_building() -> void:
	if _selected_building_id < 0:
		return
	sim.remove_building(_selected_building_id)
	_set_status("Removed building")
	_selected_building_id = -1

func _toggle_pause_menu() -> void:
	if _pause_menu != null:
		_pause_menu.queue_free()
		_pause_menu = null
		get_tree().paused = false
		return
	var packed: PackedScene = load("res://scenes/ui/PauseMenu.tscn")
	if packed == null:
		return
	_pause_menu = packed.instantiate()
	_pause_menu.tree_exited.connect(func() -> void:
		_pause_menu = null
	)
	add_child(_pause_menu)

func _on_hero_state_changed(hero_id: int, _new_state: String) -> void:
	if hero_id == _selected_hero_id:
		_refresh_hero_panel(hero_id)

func _on_hero_removed(hero_id: int) -> void:
	if hero_id == _selected_hero_id:
		_hide_hero_panel()

func _on_build_tavern_pressed() -> void:
	if GameState.get_building_count("tavern") > 0:
		return
	build_manager.start_placement("tavern")

func _on_build_weapons_shop_pressed() -> void:
	if GameState.get_building_count("weapons_shop") > 0:
		return
	build_manager.start_placement("weapons_shop")

func _on_build_temple_pressed() -> void:
	if GameState.get_building_count("temple") > 0:
		return
	build_manager.start_placement("temple")

func _on_gold_changed(amount: int) -> void:
	var lbl := get_node_or_null("UILayer/UI/GoldLabel")
	if lbl:
		lbl.text = "Gold: %d" % amount
	_refresh_build_ui()

func _on_building_state_changed(_building: Dictionary) -> void:
	_refresh_build_ui()

func _on_building_removed(_building_id: int) -> void:
	_refresh_build_ui()

func _on_building_upgraded(_building_id: int, _new_level: int) -> void:
	_refresh_build_ui()

func _on_state_reloaded() -> void:
	_hide_hero_panel()
	_selected_building_id = -1
	build_manager.cancel_placement()
	_refresh_build_ui()
	_refresh_quest_ui()
	_on_gold_changed(GameState.gold)
	_set_status("Loaded save from user://questtown_save.json")

func _upgrade_building_type(building_type: String) -> void:
	var building := _get_building_of_type(building_type)
	if building.is_empty():
		return
	sim.upgrade_building(int(building["id"]))

func _get_building_of_type(building_type: String) -> Dictionary:
	for building in GameState.buildings.values():
		if building["type"] == building_type:
			return building
	return {}

func _refresh_build_ui() -> void:
	_refresh_build_button("tavern", "UILayer/UI/BuildButton")
	_refresh_build_button("weapons_shop", "UILayer/UI/BuildWeaponsShopButton")
	_refresh_build_button("temple", "UILayer/UI/BuildTempleButton")
	_refresh_upgrade_button("tavern", "UILayer/UI/UpgradeTavernButton")
	_refresh_upgrade_button("weapons_shop", "UILayer/UI/UpgradeWeaponsShopButton")
	_refresh_upgrade_button("temple", "UILayer/UI/UpgradeTempleButton")

func _refresh_build_button(building_type: String, path: String) -> void:
	var button := get_node_or_null(path)
	if button == null:
		return
	var data: Dictionary = DataLoader.buildings_by_id.get(building_type, {})
	var building_name: String = data.get("name", building_type.capitalize())
	var base_cost: int = int(data.get("base_cost", data.get("cost", 0)))
	button.text = "Build %s  (%dg)" % [building_name, base_cost]
	button.icon = load(BUILDING_ICONS.get(building_type, ""))
	button.disabled = GameState.get_building_count(building_type) > 0 or GameState.gold < base_cost

func _refresh_upgrade_button(building_type: String, path: String) -> void:
	var button := get_node_or_null(path)
	if button == null:
		return
	var data: Dictionary = DataLoader.buildings_by_id.get(building_type, {})
	var building_name: String = data.get("name", building_type.capitalize())
	var building := _get_building_of_type(building_type)
	if building.is_empty():
		button.text = "Upgrade %s  (place first)" % building_name
		button.disabled = true
		return

	var current_level: int = int(building.get("level", 1))
	var levels: Array = data.get("levels", [])
	if current_level >= levels.size():
		button.text = "%s Max Level" % building_name
		button.disabled = true
		return

	var next_level: Dictionary = levels[current_level]
	var next_cost: int = int(next_level.get("upgrade_cost", 0))
	button.text = "Upgrade %s  (L%d -> L%d, %dg)" % [building_name, current_level, current_level + 1, next_cost]
	button.disabled = GameState.gold < next_cost

func _setup_quest_menu() -> void:
	var list := get_node_or_null("UILayer/QuestPanel/QuestVBox/QuestFilterList")
	if list == null:
		return
	for child in list.get_children():
		child.queue_free()
	_quest_filter_boxes.clear()
	for quest in DataLoader.quests:
		var quest_id: String = quest.get("id", "")
		var box := CheckBox.new()
		box.text = quest.get("name", quest_id)
		box.button_pressed = GameState.is_quest_enabled(quest_id)
		box.toggled.connect(func(enabled: bool) -> void:
			GameState.set_quest_enabled(quest_id, enabled)
		)
		list.add_child(box)
		_quest_filter_boxes[quest_id] = box
	_refresh_quest_ui()

func _refresh_quest_ui() -> void:
	var enabled_count := 0
	for quest_id in _quest_filter_boxes.keys():
		var box: CheckBox = _quest_filter_boxes[quest_id]
		var enabled := GameState.is_quest_enabled(quest_id)
		if box.button_pressed != enabled:
			box.set_pressed_no_signal(enabled)
		if enabled:
			enabled_count += 1

	var summary_label := get_node_or_null("UILayer/QuestPanel/QuestVBox/QuestFilterSummaryLabel")
	if summary_label:
		summary_label.text = "Enabled Templates: %d/%d" % [enabled_count, DataLoader.quests.size()]

	var offers_label := get_node_or_null("UILayer/QuestPanel/QuestVBox/QuestOffersLabel")
	if offers_label:
		if GameState.quests.is_empty():
			offers_label.text = "No quests available with the current filters and building unlocks."
		else:
			var offer_lines: Array = []
			for quest: Dictionary in GameState.quests:
				offer_lines.append("%s  [%s, D%d, %dg, %dxp]" % [
					quest.get("name", "?"),
					String(quest.get("type", "")).capitalize(),
					quest.get("difficulty", 1),
					quest.get("gold_reward", 0),
					quest.get("xp_reward", 0)
				])
			offers_label.text = "\n".join(offer_lines)

	var active_summary := get_node_or_null("UILayer/QuestPanel/QuestVBox/ActiveQuestSummaryLabel")
	var active_list := get_node_or_null("UILayer/QuestPanel/QuestVBox/ActiveQuestListLabel")
	var completed_title := get_node_or_null("UILayer/QuestPanel/QuestVBox/CompletedQuestTitle")
	var completed_list := get_node_or_null("UILayer/QuestPanel/QuestVBox/CompletedQuestListLabel")
	if active_summary == null or active_list == null:
		return

	var departing_count := 0
	var on_quest_count := 0
	var returning_count := 0
	var active_lines: Array = []
	for hero: Dictionary in GameState.heroes.values():
		var hero_state: String = hero.get("state", "")
		var current_quest: Dictionary = hero.get("current_quest", {})
		if current_quest.is_empty():
			continue
		if hero_state == "departing_quest":
			departing_count += 1
		elif hero_state == "on_quest":
			on_quest_count += 1
		elif hero_state == "returning":
			returning_count += 1
		else:
			continue
		active_lines.append("%s: %s (%s)" % [
			hero.get("name", "?"),
			current_quest.get("name", "?"),
			_format_quest_state(hero_state)
		])

	if active_lines.is_empty():
		active_summary.text = "No heroes are out on quests."
		active_list.text = "No active expeditions."
	else:
		active_summary.text = "Departing: %d   On Quest: %d   Returning: %d" % [
			departing_count,
			on_quest_count,
			returning_count
		]
		active_list.text = "\n".join(active_lines)

	if completed_title == null or completed_list == null:
		return
	completed_title.text = "Recent Completed Quests"
	if GameState.completed_quests.is_empty():
		completed_list.text = "No quests have been completed yet."
		return
	var completed_lines: Array = []
	for entry in GameState.completed_quests.slice(max(0, GameState.completed_quests.size() - 5)):
		completed_lines.append("%s: %s (%s)" % [
			entry.get("hero_name", "?"),
			entry.get("quest_name", "?"),
			"success" if bool(entry.get("success", false)) else "failed"
		])
	completed_list.text = "\n".join(completed_lines)

func _set_all_quest_filters(enabled: bool) -> void:
	for quest: Dictionary in DataLoader.quests:
		GameState.set_quest_enabled(quest.get("id", ""), enabled)

func _format_quest_state(state: String) -> String:
	match state:
		"departing_quest":
			return "leaving town"
		"on_quest":
			return "off-screen"
		"returning":
			return "heading home"
		_:
			return state.replace("_", " ")

func _save_world() -> void:
	var saved: bool = sim.save_world()
	_set_status("Saved to user://questtown_save.json" if saved else "Save failed")

func _load_world() -> void:
	var loaded: bool = sim.load_world()
	if not loaded:
		_set_status("No save file found")

func _set_status(message: String) -> void:
	var status_label := get_node_or_null("UILayer/UI/StatusLabel")
	if status_label:
		status_label.text = message
