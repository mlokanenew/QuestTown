extends Node
class_name SimulationRoot
## Owns all simulation systems and drives the fixed-step game loop.
## In visual mode: called by world.gd _physics_process().
## In headless mode: called directly by ScenarioRunner or CommandServer.

# Loaded at runtime so class_name registration order doesn't matter.
var building_system: RefCounted
var hero_system: RefCounted
var spawn_system: RefCounted
var snapshot: RefCounted

var _awaited_event: String = ""
var _event_received: bool = false

func _ready() -> void:
	building_system = load("res://scripts/simulation/BuildingSystem.gd").new()
	hero_system     = load("res://scripts/simulation/HeroSystem.gd").new()
	spawn_system    = load("res://scripts/simulation/SpawnSystem.gd").new()
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

func place_building(type: String, position: Vector3) -> Dictionary:
	return building_system.place_building(type, position)

func get_world_state() -> Dictionary:
	return snapshot.snapshot()

func get_heroes() -> Array:
	return snapshot._heroes()

func get_buildings() -> Array:
	return snapshot._buildings()

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
	spawn_system.step(hero_system)
	hero_system.step(delta, building_system)

func physics_step(delta: float) -> void:
	_tick(delta)
