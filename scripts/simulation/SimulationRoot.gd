extends Node
class_name SimulationRoot
## Owns all simulation systems and drives the fixed-step game loop.
## In visual mode: called by world.gd _physics_process().
## In headless mode: called directly by ScenarioRunner or CommandServer.

# Loaded at runtime so class_name registration order doesn't matter.
var building_system: RefCounted
var hero_system: RefCounted
var spawn_system: RefCounted
var quest_system: RefCounted
var economy_system: RefCounted
var snapshot: RefCounted

var _awaited_event: String = ""
var _event_received: bool = false
var _save_system_script := preload("res://scripts/control/SaveSystem.gd")

func _ready() -> void:
	building_system = load("res://scripts/simulation/BuildingSystem.gd").new()
	hero_system     = load("res://scripts/simulation/HeroSystem.gd").new()
	spawn_system    = load("res://scripts/simulation/SpawnSystem.gd").new()
	quest_system    = load("res://scripts/simulation/QuestSystem.gd").new()
	economy_system  = load("res://scripts/simulation/EconomySystem.gd").new()
	snapshot        = load("res://scripts/simulation/WorldSnapshot.gd").new()
	GameState.event_logged.connect(_on_event_logged)
	reset_world(RuntimeConfig.seed_value)

func _on_event_logged(event: Dictionary) -> void:
	if _awaited_event != "" and event.get("type", "") == _awaited_event:
		_event_received = true

# --- Public API ---

func reset_world(seed_value: int) -> void:
	GameState.reset(seed_value)
	building_system.reset()
	hero_system.reset(seed_value)
	spawn_system.reset()
	quest_system.reset(seed_value)
	economy_system.reset()

func place_building(type: String, position: Vector3) -> Dictionary:
	return building_system.place_building(type, position)

func upgrade_building(id: int) -> Dictionary:
	return building_system.upgrade_building(id)

func remove_building(id: int) -> void:
	building_system.remove_building(id)

func get_world_state() -> Dictionary:
	return snapshot.snapshot()

func get_heroes() -> Array:
	return snapshot._heroes()

func get_buildings() -> Array:
	return snapshot._buildings()

func get_building_of_type(type: String) -> Dictionary:
	return building_system.get_building_of_type(type)

func can_place_building(type: String, position: Vector3) -> bool:
	return building_system.can_place_building(type, position)

func export_save_data() -> Dictionary:
	return {
		"version": 1,
		"game_state": GameState.export_state(),
		"systems": {
			"spawn": spawn_system.export_state(),
			"quest": quest_system.export_state(),
		}
	}

func import_save_data(data: Dictionary) -> bool:
	if not data.has("game_state"):
		return false
	reset_world(int(data.get("game_state", {}).get("seed_value", RuntimeConfig.seed_value)))
	GameState.import_state(data.get("game_state", {}))
	building_system.rebuild_from_game_state()
	var systems: Dictionary = data.get("systems", {})
	spawn_system.import_state(systems.get("spawn", {}))
	quest_system.import_state(systems.get("quest", {}))
	return true

func save_world(path: String = "") -> bool:
	if path == "":
		return _save_system_script.save_simulation(self)
	return _save_system_script.save_simulation(self, path)

func load_world(path: String = "") -> bool:
	if path == "":
		return _save_system_script.load_simulation(self)
	return _save_system_script.load_simulation(self, path)

func step_ticks(n: int) -> void:
	var delta := 1.0 / 60.0
	for _i in range(n):
		_tick(delta)

func run_until(event_name: String, max_ticks: int) -> bool:
	_awaited_event = event_name
	_event_received = false
	var delta := 1.0 / 60.0
	for _i in range(max_ticks):
		_tick(delta)
		if _event_received:
			_awaited_event = ""
			return true
	_awaited_event = ""
	return false

func _tick(delta: float) -> void:
	GameState.tick += 1
	spawn_system.step(hero_system, economy_system, building_system)
	economy_system.step(building_system)
	quest_system.step(building_system)
	hero_system.step(delta, building_system)

func physics_step(delta: float) -> void:
	_tick(delta)
