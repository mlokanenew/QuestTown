extends Node3D
## Root scene script. Wires SimulationRoot, CommandServer, and ScenarioRunner together.

@onready var sim: Node = $SimulationRoot
@onready var cmd_server: Node = $CommandServer
@onready var build_manager: Node = $BuildManager

var _selected_hero_id: int = -1

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
		GameState.gold_changed.connect(_on_gold_changed)
		GameState.hero_state_changed.connect(_on_hero_state_changed)
		GameState.hero_removed.connect(_on_hero_removed)

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
	if not (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT):
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
	if name_lbl:
		name_lbl.text = h["name"]
	if career_lbl:
		career_lbl.text = "%s  (Lv %d)" % [h["career"], h["level"]]
	if state_lbl:
		state_lbl.text = h["state"].capitalize()

func _hide_hero_panel() -> void:
	_selected_hero_id = -1
	var panel := get_node_or_null("UILayer/HeroPanel")
	if panel:
		panel.visible = false

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
	build_manager.start_placement("weapons_shop")

func _on_gold_changed(amount: int) -> void:
	var lbl := get_node_or_null("UILayer/UI/GoldLabel")
	if lbl:
		lbl.text = "Gold: %d" % amount
