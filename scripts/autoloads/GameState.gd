extends Node
## Single source of truth for world state.
## Holds plain data dictionaries — no Node references.
## The presentation layer reads this to sync 3D nodes.

signal building_placed(building: Dictionary)
signal building_removed(building_id: int)
signal building_upgraded(building_id: int, new_level: int)
signal building_action_changed(building_id: int, action: String)
signal hero_spawned(hero: Dictionary)
signal hero_state_changed(hero_id: int, new_state: String)
signal hero_removed(hero_id: int)
signal quests_changed()
signal quest_filters_changed()
signal quest_history_changed()
signal event_logged(event: Dictionary)
signal gold_changed(new_amount: int)
signal state_reloaded()

const DEFAULT_STARTING_GOLD := 70

var tick: int = 0
var seed_value: int = 0
var gold: int = DEFAULT_STARTING_GOLD

# Dict[id -> building_dict]
var buildings: Dictionary = {}
# Dict[id -> hero_dict]
var heroes: Dictionary = {}
# Array[quest_offer_dict]
var quests: Array = []
# Array[quest_result_dict]
var completed_quests: Array = []
# Dict[quest_template_id -> bool]
var enabled_quest_ids: Dictionary = {}
# Array of event dicts {tick, type, ...}
var events: Array = []

var _next_building_id: int = 1
var _next_hero_id: int = 1

func reset(p_seed: int) -> void:
	seed_value = p_seed
	tick = 0
	gold = _starting_gold()
	buildings.clear()
	heroes.clear()
	quests.clear()
	completed_quests.clear()
	enabled_quest_ids = {}
	for quest in DataLoader.quests:
		enabled_quest_ids[quest.get("id", "")] = true
	events.clear()
	_next_building_id = 1
	_next_hero_id = 1

# --- Buildings ---

func add_building(type: String, position: Vector3) -> Dictionary:
	var b := {
		"id": _next_building_id,
		"type": type,
		"level": 1,
		"current_action": "idle",
		"action_progress_ticks": 0,
		"action_required_ticks": 0,
		"output_stock": 0,
		"rotation_degrees_y": 0.0,
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

func upgrade_building(id: int) -> Dictionary:
	if not buildings.has(id):
		return {}
	buildings[id]["level"] += 1
	buildings[id]["current_action"] = "idle"
	buildings[id]["action_progress_ticks"] = 0
	buildings[id]["action_required_ticks"] = 0
	var new_level: int = buildings[id]["level"]
	building_upgraded.emit(id, new_level)
	return buildings[id]

func set_building_action(id: int, action: String, required_ticks: int = 0) -> Dictionary:
	if not buildings.has(id):
		return {}
	buildings[id]["current_action"] = action
	buildings[id]["action_progress_ticks"] = 0
	buildings[id]["action_required_ticks"] = required_ticks
	building_action_changed.emit(id, action)
	return buildings[id]

func set_building_action_progress(id: int, progress_ticks: int, required_ticks: int) -> void:
	if not buildings.has(id):
		return
	buildings[id]["action_progress_ticks"] = progress_ticks
	buildings[id]["action_required_ticks"] = required_ticks

func add_building_output_stock(id: int, amount: int, cap: int) -> int:
	if not buildings.has(id):
		return 0
	var next_value: int = min(cap, int(buildings[id].get("output_stock", 0)) + amount)
	buildings[id]["output_stock"] = next_value
	return next_value

func consume_building_output_stock(id: int, amount: int = 1) -> bool:
	if not buildings.has(id):
		return false
	var current_stock: int = int(buildings[id].get("output_stock", 0))
	if current_stock < amount:
		return false
	buildings[id]["output_stock"] = current_stock - amount
	return true

func get_building_count(type: String) -> int:
	var count := 0
	for b in buildings.values():
		if b["type"] == type:
			count += 1
	return count

# --- Heroes ---

func add_hero(hero_name: String, career_data: Dictionary, profile: Dictionary = {}) -> Dictionary:
	var career_name: String = career_data.get("name", "Mercenary")
	var h := {
		"id": _next_hero_id,
		"name": hero_name,
		"career_id": career_data.get("id", "mercenary"),
		"career": career_name,
		"career_role": career_data.get("mvp_role_name", career_name),
		"career_tier": career_data.get("tier", "basic"),
		"career_archetype": career_data.get("archetype", "martial"),
		"career_description": career_data.get("description", ""),
		"quest_bias": career_data.get("quest_bias", "local"),
		"service_bias": career_data.get("service_bias", "tavern"),
		"career_tags": career_data.get("trait_tags", []),
		"skill_ids": career_data.get("skill_ids", []),
		"skill_names": DataLoader.get_skill_names(career_data.get("skill_ids", [])),
		"level": 1,
		"xp": profile.get("xp", 0),
		"gold": profile.get("gold", 0),
		"health": profile.get("health", 10),
		"max_health": profile.get("max_health", 10),
		"wound_state": profile.get("wound_state", "healthy"),
		"stats": profile.get("stats", {}),
		"wfrp_stats": profile.get("wfrp_stats", {}),
		"starting_trappings": profile.get("starting_trappings", []),
		"starting_talents": profile.get("starting_talents", []),
		"state": "arriving",
		"position": {"x": 0.0, "y": 0.0, "z": 0.0},
		"target": {"x": 0.0, "y": 0.0, "z": 0.0},
		"idle_ticks_remaining": 0,
		"needs_lodging": true,
		"needs_meal": true,
		"service_cooldown_ticks": 120,
		"gear_bonus": 0,
		"blessing_bonus": 0,
		"pending_service": {},
		"quest_party_id": -1,
		"quest_party_size": 0,
		"quest_party_leader_id": -1
	}
	_next_hero_id += 1
	heroes[h["id"]] = h
	hero_spawned.emit(h)
	log_event("hero_arrived", {
		"hero_id": h["id"],
		"hero_name": h["name"],
		"career": h["career"],
		"career_id": h["career_id"]
	})
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

# --- Quests ---

func set_available_quests(next_quests: Array) -> void:
	quests = next_quests
	quests_changed.emit()

func record_completed_quest(entry: Dictionary) -> void:
	completed_quests.append(entry)
	while completed_quests.size() > 20:
		completed_quests.pop_front()
	quest_history_changed.emit()

func is_quest_enabled(quest_id: String) -> bool:
	return bool(enabled_quest_ids.get(quest_id, true))

func set_quest_enabled(quest_id: String, enabled: bool) -> void:
	enabled_quest_ids[quest_id] = enabled
	quest_filters_changed.emit()

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

func export_state() -> Dictionary:
	return {
		"tick": tick,
		"seed_value": seed_value,
		"gold": gold,
		"buildings": buildings.values().duplicate(true),
		"heroes": heroes.values().duplicate(true),
		"quests": quests.duplicate(true),
		"completed_quests": completed_quests.duplicate(true),
		"enabled_quest_ids": enabled_quest_ids.duplicate(true),
		"events": events.duplicate(true),
		"next_building_id": _next_building_id,
		"next_hero_id": _next_hero_id,
	}

func import_state(data: Dictionary) -> void:
	tick = int(data.get("tick", 0))
	seed_value = int(data.get("seed_value", 0))
	gold = int(data.get("gold", _starting_gold()))
	buildings.clear()
	for building: Dictionary in data.get("buildings", []):
		buildings[int(building.get("id", 0))] = building.duplicate(true)
	heroes.clear()
	for hero: Dictionary in data.get("heroes", []):
		heroes[int(hero.get("id", 0))] = hero.duplicate(true)
	quests = data.get("quests", []).duplicate(true)
	completed_quests = data.get("completed_quests", []).duplicate(true)
	enabled_quest_ids = data.get("enabled_quest_ids", {}).duplicate(true)
	events = data.get("events", []).duplicate(true)
	_next_building_id = int(data.get("next_building_id", buildings.size() + 1))
	_next_hero_id = int(data.get("next_hero_id", heroes.size() + 1))
	gold_changed.emit(gold)
	quests_changed.emit()
	quest_filters_changed.emit()
	quest_history_changed.emit()
	state_reloaded.emit()

func _starting_gold() -> int:
	var loader: Node = get_node_or_null("/root/DataLoader")
	if loader != null:
		return DataLoader.get_starting_gold()
	return DEFAULT_STARTING_GOLD
