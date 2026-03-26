extends Node3D
## Root scene script. Wires SimulationRoot, CommandServer, and ScenarioRunner together.

@onready var sim: Node = $SimulationRoot
@onready var cmd_server: Node = $CommandServer
@onready var build_manager: Node = $BuildManager

func _ready() -> void:
	# Wire CommandServer to SimulationRoot
	cmd_server.set_sim(sim)
	cmd_server.start(RuntimeConfig.port)

	# In test mode, run scenario and exit
	if RuntimeConfig.is_test() and RuntimeConfig.scenario_path != "":
		var runner: Node = load("res://scripts/control/ScenarioRunner.gd").new()
		add_child(runner)
		# Defer so the scene tree is fully ready
		runner.run_scenario.call_deferred(sim, RuntimeConfig.scenario_path)
		return

	# Visual mode: wire UI
	if not RuntimeConfig.is_headless():
		var btn := get_node_or_null("UILayer/UI/BuildButton")
		if btn:
			btn.pressed.connect(_on_build_tavern_pressed)
		GameState.gold_changed.connect(_on_gold_changed)

func _on_build_tavern_pressed() -> void:
	if GameState.get_building_count("tavern") > 0:
		return  # only one tavern for now
	if GameState.spend_gold(50):
		sim.place_building("tavern", Vector3(0, 0, 0))

func _on_gold_changed(amount: int) -> void:
	var lbl := get_node_or_null("UILayer/UI/GoldLabel")
	if lbl:
		lbl.text = "Gold: %d" % amount

func _physics_process(delta: float) -> void:
	sim.physics_step(delta)
