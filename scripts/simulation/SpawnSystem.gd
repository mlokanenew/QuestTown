extends RefCounted
class_name SpawnSystem
## Decides when to spawn heroes based on world attractiveness.

var _ticks_since_spawn: int = 0

func reset() -> void:
	_ticks_since_spawn = 0

func step(hero_system: Object, economy_system: Object, building_system: Object) -> void:
	if GameState.get_building_count("tavern") == 0:
		return
	if GameState.heroes.size() >= economy_system.max_supported_heroes(building_system):
		return

	_ticks_since_spawn += 1
	if _ticks_since_spawn >= _spawn_interval():
		_ticks_since_spawn = 0
		hero_system.spawn_hero()

func export_state() -> Dictionary:
	return {"ticks_since_spawn": _ticks_since_spawn}

func import_state(data: Dictionary) -> void:
	_ticks_since_spawn = int(data.get("ticks_since_spawn", 0))

func _spawn_interval() -> int:
	var config: Dictionary = DataLoader.get_spawn_config()
	var opening_count: int = DataLoader.MVP_CAREER_IDS.size()
	if GameState.heroes.size() < opening_count:
		return int(config.get("opening_interval_ticks", 45))
	return int(config.get("regular_interval_ticks", 120))
