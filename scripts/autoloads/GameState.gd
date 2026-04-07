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
signal blockers_changed()
signal building_resources_changed(building_id: int)
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
# Dict[blocker_id -> blocker_state_dict]
var blockers: Dictionary = {}
# Dict[resource_id -> resource_unlock_dict]
var unlocked_resources: Dictionary = {}
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
	blockers = {}
	for blocker_template: Dictionary in DataLoader.world_blockers:
		var blocker_state: Dictionary = blocker_template.duplicate(true)
		blocker_state["state"] = "known_blocked"
		blocker_state["discovered"] = false
		blocker_state["active"] = false
		blocker_state["last_discovered_tick"] = -1
		blocker_state["last_cleared_tick"] = -1
		blocker_state["unlock_active"] = false
		blockers[str(blocker_template.get("blocker_id", ""))] = blocker_state
	unlocked_resources = {}
	events.clear()
	_next_building_id = 1
	_next_hero_id = 1
	blockers_changed.emit()

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
		"installed_resource_ids": [],
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

func set_blocker_state(blocker_id: String, next_state: String, discovered: bool = false, active: bool = false) -> void:
	if not blockers.has(blocker_id):
		return
	blockers[blocker_id]["state"] = next_state
	blockers[blocker_id]["discovered"] = discovered
	blockers[blocker_id]["active"] = active
	if discovered:
		blockers[blocker_id]["last_discovered_tick"] = tick
	if next_state == "unblocked":
		blockers[blocker_id]["last_cleared_tick"] = tick
		blockers[blocker_id]["unlock_active"] = true
	blockers_changed.emit()

func unlock_resource(resource_id: String, blocker_id: String) -> void:
	if resource_id == "":
		return
	var resource_data: Dictionary = DataLoader.get_world_resource(resource_id)
	if resource_data.is_empty():
		return
	unlocked_resources[resource_id] = {
		"resource_id": resource_id,
		"display_name": resource_data.get("display_name", resource_id),
		"building_type": resource_data.get("building_type", ""),
		"slot_type": resource_data.get("slot_type", "resource"),
		"description": resource_data.get("description", ""),
		"effects": resource_data.get("effects", {}).duplicate(true),
		"unlocked_tick": tick,
		"source_blocker_id": blocker_id,
		"active": true,
		"installed": false,
		"installed_building_id": -1
	}
	blockers_changed.emit()

func get_building_slot_capacity(building_id: int) -> int:
	var building: Dictionary = buildings.get(building_id, {})
	if building.is_empty():
		return 0
	var building_data: Dictionary = DataLoader.buildings_by_id.get(str(building.get("type", "")), {})
	var levels: Array = building_data.get("levels", [])
	var level: int = int(building.get("level", 1))
	if level <= 0 or level > levels.size():
		return 0
	return int(levels[level - 1].get("resource_slot_capacity", level))

func get_building_installed_resources(building_id: int) -> Array:
	var result: Array = []
	var building: Dictionary = buildings.get(building_id, {})
	if building.is_empty():
		return result
	for resource_id_variant in building.get("installed_resource_ids", []):
		var resource_id: String = str(resource_id_variant)
		if unlocked_resources.has(resource_id):
			result.append(unlocked_resources[resource_id].duplicate(true))
	return result

func get_building_resource_effect_bonus(building_id: int, effect_key: String) -> int:
	var total: int = 0
	var building: Dictionary = buildings.get(building_id, {})
	if building.is_empty():
		return 0
	for resource_id_variant in building.get("installed_resource_ids", []):
		var resource_id: String = str(resource_id_variant)
		var resource: Dictionary = unlocked_resources.get(resource_id, {})
		if resource.is_empty() or not bool(resource.get("active", false)):
			continue
		var effects: Dictionary = resource.get("effects", {})
		var value: Variant = effects.get(effect_key, 0)
		if value is bool:
			total += 1 if value else 0
		else:
			total += int(value)
	return total

func install_resource(building_id: int, resource_id: String) -> Dictionary:
	var building: Dictionary = buildings.get(building_id, {})
	if building.is_empty():
		return {}
	var unlocked: Dictionary = unlocked_resources.get(resource_id, {})
	if unlocked.is_empty() or not bool(unlocked.get("active", false)):
		return {}
	if str(unlocked.get("building_type", "")) != str(building.get("type", "")):
		return {}
	var installed_ids: Array = building.get("installed_resource_ids", []).duplicate()
	if installed_ids.has(resource_id):
		return unlocked.duplicate(true)
	if bool(unlocked.get("installed", false)):
		return {}
	if installed_ids.size() >= get_building_slot_capacity(building_id):
		return {}
	installed_ids.append(resource_id)
	buildings[building_id]["installed_resource_ids"] = installed_ids
	unlocked_resources[resource_id]["installed"] = true
	unlocked_resources[resource_id]["installed_building_id"] = building_id
	building_resources_changed.emit(building_id)
	blockers_changed.emit()
	log_event("resource_installed", {
		"resource_id": resource_id,
		"display_name": unlocked.get("display_name", resource_id),
		"building_id": building_id,
		"building_type": building.get("type", "")
	})
	return unlocked_resources[resource_id].duplicate(true)

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
		"blockers": blockers.duplicate(true),
		"unlocked_resources": unlocked_resources.duplicate(true),
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
		var building_copy: Dictionary = building.duplicate(true)
		if not building_copy.has("installed_resource_ids"):
			building_copy["installed_resource_ids"] = []
		buildings[int(building_copy.get("id", 0))] = building_copy
	heroes.clear()
	for hero: Dictionary in data.get("heroes", []):
		heroes[int(hero.get("id", 0))] = hero.duplicate(true)
	quests = data.get("quests", []).duplicate(true)
	completed_quests = data.get("completed_quests", []).duplicate(true)
	enabled_quest_ids = data.get("enabled_quest_ids", {}).duplicate(true)
	blockers = data.get("blockers", {}).duplicate(true)
	unlocked_resources = data.get("unlocked_resources", {}).duplicate(true)
	for resource_id in unlocked_resources.keys():
		if not unlocked_resources[resource_id].has("effects"):
			var resource_data: Dictionary = DataLoader.get_world_resource(str(resource_id))
			unlocked_resources[resource_id]["effects"] = resource_data.get("effects", {}).duplicate(true)
		if not unlocked_resources[resource_id].has("installed"):
			unlocked_resources[resource_id]["installed"] = false
		if not unlocked_resources[resource_id].has("installed_building_id"):
			unlocked_resources[resource_id]["installed_building_id"] = -1
	events = data.get("events", []).duplicate(true)
	_next_building_id = int(data.get("next_building_id", buildings.size() + 1))
	_next_hero_id = int(data.get("next_hero_id", heroes.size() + 1))
	gold_changed.emit(gold)
	quests_changed.emit()
	quest_filters_changed.emit()
	quest_history_changed.emit()
	blockers_changed.emit()
	for building_id in buildings.keys():
		building_resources_changed.emit(int(building_id))
	state_reloaded.emit()

func _starting_gold() -> int:
	var loader: Node = get_node_or_null("/root/DataLoader")
	if loader != null:
		return DataLoader.get_starting_gold()
	return DEFAULT_STARTING_GOLD
