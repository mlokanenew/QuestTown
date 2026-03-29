extends RefCounted
class_name WorldSnapshot
## Serialises full world state to a Dictionary suitable for JSON encoding.
## Used by CommandServer and ScenarioRunner.

func snapshot() -> Dictionary:
	var warnings: Array = _collect_warnings()
	return {
		"tick":      GameState.tick,
		"seed":      GameState.seed_value,
		"gold":      GameState.gold,
		"buildings": _buildings(),
		"heroes":    _heroes(),
		"quests":    _quests(),
		"completed_quests": GameState.completed_quests.duplicate(true),
		"events":    GameState.get_recent_events(100),
		"warnings":  warnings
	}

func _buildings() -> Array:
	var result := []
	for b in GameState.buildings.values():
		result.append({
			"id":       b["id"],
			"type":     b["type"],
			"level":    b.get("level", 1),
			"current_action": b.get("current_action", "output"),
			"action_progress_ticks": b.get("action_progress_ticks", 0),
			"action_required_ticks": b.get("action_required_ticks", 0),
			"output_stock": b.get("output_stock", 0),
			"rotation_degrees_y": b.get("rotation_degrees_y", 0.0),
			"position": b["position"]
		})
	return result

func _heroes() -> Array:
	var result := []
	for h in GameState.heroes.values():
		result.append({
			"id":       h["id"],
			"name":     h["name"],
			"career_id": h.get("career_id", ""),
			"career":   h["career"],
			"career_tier": h.get("career_tier", "basic"),
			"career_archetype": h.get("career_archetype", ""),
			"level":    h["level"],
			"xp":       h.get("xp", 0),
			"gold":     h.get("gold", 0),
			"health":   h.get("health", 0),
			"max_health": h.get("max_health", 0),
			"stats":    h.get("stats", {}),
			"skill_ids": h.get("skill_ids", []),
			"skill_names": h.get("skill_names", []),
			"career_tags": h.get("career_tags", []),
			"quest_bias": h.get("quest_bias", ""),
			"service_bias": h.get("service_bias", ""),
			"current_quest": h.get("current_quest", {}),
			"needs_lodging": h.get("needs_lodging", false),
			"gear_bonus": h.get("gear_bonus", 0),
			"blessing_bonus": h.get("blessing_bonus", 0),
			"state":    h["state"],
			"position": h["position"]
		})
	return result

func _quests() -> Array:
	var result := []
	for quest in GameState.quests:
		result.append(quest)
	return result

func _collect_warnings() -> Array:
	var w := []
	if GameState.gold < 0:
		w.append("gold_negative")
	for h in GameState.heroes.values():
		if h["state"] == "arriving" and GameState.get_building_count("tavern") == 0:
			w.append("hero_arriving_no_tavern")
			break
	return w

func to_json() -> String:
	return JSON.stringify(snapshot())
