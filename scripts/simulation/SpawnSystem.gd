extends RefCounted
class_name SpawnSystem
## Decides when to spawn heroes based on world attractiveness.

const MAX_HEROES      := 10
const SPAWN_INTERVAL  := 180   # ticks between spawns (~3s at 60Hz)

var _ticks_since_spawn: int = 0

func reset() -> void:
	_ticks_since_spawn = 0

func step(hero_system: Object) -> void:
	if GameState.get_building_count("tavern") == 0:
		return
	if GameState.heroes.size() >= MAX_HEROES:
		return

	_ticks_since_spawn += 1
	if _ticks_since_spawn >= SPAWN_INTERVAL:
		_ticks_since_spawn = 0
		hero_system.spawn_hero()
