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
		"events":    GameState.get_recent_events(20),
		"warnings":  warnings
	}

func _buildings() -> Array:
	var result := []
	for b in GameState.buildings.values():
		result.append({
			"id":       b["id"],
			"type":     b["type"],
			"position": b["position"]
		})
	return result

func _heroes() -> Array:
	var result := []
	for h in GameState.heroes.values():
		result.append({
			"id":       h["id"],
			"name":     h["name"],
			"career":   h["career"],
			"level":    h["level"],
			"state":    h["state"],
			"position": h["position"]
		})
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
