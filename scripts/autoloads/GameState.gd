extends Node
## Single source of truth for world state.
## Holds plain data dictionaries — no Node references.
## The presentation layer reads this to sync 3D nodes.

signal building_placed(building: Dictionary)
signal building_removed(building_id: int)
signal hero_spawned(hero: Dictionary)
signal hero_state_changed(hero_id: int, new_state: String)
signal hero_removed(hero_id: int)
signal event_logged(event: Dictionary)
signal gold_changed(new_amount: int)

var tick: int = 0
var seed_value: int = 0
var gold: int = 100

# Dict[id -> building_dict]
var buildings: Dictionary = {}
# Dict[id -> hero_dict]
var heroes: Dictionary = {}
# Array of event dicts {tick, type, ...}
var events: Array = []

var _next_building_id: int = 1
var _next_hero_id: int = 1

func reset(p_seed: int) -> void:
	seed_value = p_seed
	tick = 0
	gold = 100
	buildings.clear()
	heroes.clear()
	events.clear()
	_next_building_id = 1
	_next_hero_id = 1

# --- Buildings ---

func add_building(type: String, position: Vector3) -> Dictionary:
	var b := {
		"id": _next_building_id,
		"type": type,
		"position": {"x": position.x, "y": position.y, "z": position.z}
	}
	_next_building_id += 1
	buildings[b["id"]] = b
	building_placed.emit(b)
	return b

func remove_building(id: int) -> void:
	if buildings.has(id):
		buildings.erase(id)
		building_removed.emit(id)

func get_building_count(type: String) -> int:
	var count := 0
	for b in buildings.values():
		if b["type"] == type:
			count += 1
	return count

# --- Heroes ---

func add_hero(name: String, career: String) -> Dictionary:
	var h := {
		"id": _next_hero_id,
		"name": name,
		"career": career,
		"level": 1,
		"state": "arriving",
		"position": {"x": 0.0, "y": 0.0, "z": 0.0},
		"target": {"x": 0.0, "y": 0.0, "z": 0.0},
		"idle_ticks_remaining": 0
	}
	_next_hero_id += 1
	heroes[h["id"]] = h
	hero_spawned.emit(h)
	log_event("hero_arrived", {"hero_id": h["id"], "hero_name": h["name"], "career": h["career"]})
	return h

func set_hero_state(id: int, state: String) -> void:
	if heroes.has(id):
		heroes[id]["state"] = state
		hero_state_changed.emit(id, state)
		if state == "idling":
			log_event("hero_arrived_at_tavern", {"hero_id": id})

func remove_hero(id: int) -> void:
	if heroes.has(id):
		heroes.erase(id)
		hero_removed.emit(id)

# --- Economy ---

func add_gold(amount: int) -> void:
	gold += amount
	gold_changed.emit(gold)

func spend_gold(amount: int) -> bool:
	if gold >= amount:
		gold -= amount
		gold_changed.emit(gold)
		return true
	return false

# --- Events ---

func log_event(type: String, data: Dictionary = {}) -> void:
	var e := {"tick": tick, "type": type}
	e.merge(data)
	events.append(e)
	event_logged.emit(e)

func get_recent_events(count: int = 10) -> Array:
	return events.slice(max(0, events.size() - count))
