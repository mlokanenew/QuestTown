extends Node
## Loads and caches JSON data files.
## Access via DataLoader.careers, DataLoader.buildings, etc.

const MVP_CAREER_IDS := ["mercenary", "apprentice_wizard", "thief"]
const MVP_ROLE_LABELS := {
	"mercenary": "Warrior",
	"apprentice_wizard": "Wizard",
	"thief": "Rogue",
}

var careers: Array = []
var advanced_careers: Array = []
var buildings: Array = []
var quests: Array = []
var skills: Array = []
var characteristics: Array = []
var services: Array = []
var gear_catalog: Array = []
var loot_tables: Array = []
var hero_names: Dictionary = {"first": [], "last": []}
var wfrp_source_careers: Array = []
var wfrp_characteristics: Dictionary = {}

# Indexed lookups
var careers_by_id: Dictionary = {}
var advanced_careers_by_id: Dictionary = {}
var buildings_by_id: Dictionary = {}
var quests_by_id: Dictionary = {}
var skills_by_id: Dictionary = {}
var characteristics_by_id: Dictionary = {}
var services_by_id: Dictionary = {}
var gear_by_id: Dictionary = {}
var loot_tables_by_id: Dictionary = {}
var wfrp_source_careers_by_id: Dictionary = {}

func _ready() -> void:
	careers = _load_json("res://data/careers.json")
	advanced_careers = _load_json("res://data/advanced_careers.json")
	buildings = _load_json("res://data/buildings.json")
	quests = _load_json("res://data/quests.json")
	skills = _load_json("res://data/skills.json")
	characteristics = _load_json("res://data/characteristics.json")
	services = _load_json("res://data/services.json")
	gear_catalog = _load_json("res://data/gear_catalog.json")
	loot_tables = _load_json("res://data/loot_tables.json")
	hero_names = _load_json("res://data/hero_names.json")
	wfrp_source_careers = _load_json("res://godot_data/wfrp_db/careers.json")
	wfrp_characteristics = _load_json("res://godot_data/wfrp_db/characteristics.json")
	careers = _filter_mvp_careers(careers)

	for c in careers:
		careers_by_id[c["id"]] = c
	for c in advanced_careers:
		advanced_careers_by_id[c["id"]] = c
	for b in buildings:
		buildings_by_id[b["id"]] = b
	for q in quests:
		quests_by_id[q["id"]] = q
	for s in skills:
		skills_by_id[s["id"]] = s
	for characteristic in characteristics:
		characteristics_by_id[characteristic["id"]] = characteristic
	for service in services:
		services_by_id[service["id"]] = service
	for gear in gear_catalog:
		gear_by_id[gear["id"]] = gear
	for loot_table in loot_tables:
		loot_tables_by_id[loot_table["id"]] = loot_table
	for source_career in wfrp_source_careers:
		wfrp_source_careers_by_id[source_career["id"]] = source_career

func _load_json(path: String) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("DataLoader: cannot open %s" % path)
		return []
	var text := file.get_as_text()
	file.close()
	var result: Variant = JSON.parse_string(text)
	if result == null:
		push_error("DataLoader: failed to parse %s" % path)
		return []
	return result

func random_hero_name(rng: RandomNumberGenerator) -> String:
	var first: Array = hero_names.get("first", ["Hans"])
	var last: Array  = hero_names.get("last",  ["Müller"])
	return "%s %s" % [
		first[rng.randi() % first.size()],
		last[rng.randi() % last.size()]
	]

func random_career(rng: RandomNumberGenerator) -> Dictionary:
	if careers.is_empty():
		return {"id": "mercenary", "name": "Mercenary", "archetype": "martial"}
	return careers[rng.randi() % careers.size()]

func _filter_mvp_careers(source_careers: Array) -> Array:
	var allowed := {}
	for career_id in MVP_CAREER_IDS:
		allowed[career_id] = true
	var filtered: Array = []
	for career: Dictionary in source_careers:
		if allowed.has(career.get("id", "")):
			var career_copy := career.duplicate(true)
			career_copy["mvp_role_name"] = MVP_ROLE_LABELS.get(career_copy.get("id", ""), career_copy.get("name", "Adventurer"))
			filtered.append(career_copy)
	return filtered

func get_skill_names(skill_ids: Array) -> Array:
	var names := []
	for skill_id in skill_ids:
		var skill: Dictionary = skills_by_id.get(skill_id, {})
		if not skill.is_empty():
			names.append(skill.get("name", skill_id))
	return names

func get_service(service_id: String) -> Dictionary:
	return services_by_id.get(service_id, {})

func get_best_gear_offer(building_level: int) -> Dictionary:
	var best: Dictionary = {}
	for gear: Dictionary in gear_catalog:
		if int(gear.get("min_building_level", 1)) > building_level:
			continue
		if best.is_empty() or int(best.get("gear_bonus", 0)) < int(gear.get("gear_bonus", 0)):
			best = gear
	return best

func get_wfrp_source_career(career_id: String) -> Dictionary:
	return wfrp_source_careers_by_id.get(career_id, {})

func get_wfrp_trappings(career_id: String) -> Array:
	return get_wfrp_source_career(career_id).get("trappings", []).duplicate(true)

func get_wfrp_talents(career_id: String) -> Array:
	return get_wfrp_source_career(career_id).get("talents", []).duplicate(true)

func generate_wfrp_starting_profile(career_id: String, rng: RandomNumberGenerator) -> Dictionary:
	var source_career: Dictionary = get_wfrp_source_career(career_id)
	var racial_generation: Dictionary = wfrp_characteristics.get("racial_generation", {}).get("Human", {})
	var wounds_table: Dictionary = wfrp_characteristics.get("starting_wounds", {}).get("Human", {})
	var fate_table: Dictionary = wfrp_characteristics.get("starting_fate_points", {}).get("Human", {})
	var stats := {
		"WS": _roll_stat_expr(str(racial_generation.get("WS", "20+2d10")), rng),
		"BS": _roll_stat_expr(str(racial_generation.get("BS", "20+2d10")), rng),
		"S": _roll_stat_expr(str(racial_generation.get("S", "20+2d10")), rng),
		"T": _roll_stat_expr(str(racial_generation.get("T", "20+2d10")), rng),
		"Ag": _roll_stat_expr(str(racial_generation.get("Ag", "20+2d10")), rng),
		"Int": _roll_stat_expr(str(racial_generation.get("Int", "20+2d10")), rng),
		"WP": _roll_stat_expr(str(racial_generation.get("WP", "20+2d10")), rng),
		"Fel": _roll_stat_expr(str(racial_generation.get("Fel", "20+2d10")), rng),
		"A": int(racial_generation.get("A", "1")),
		"M": int(racial_generation.get("M", "4")),
		"Mag": int(racial_generation.get("Mag", "0")),
		"W": _roll_lookup_table(wounds_table, rng, 11),
		"FP": _roll_lookup_table(fate_table, rng, 2),
		"IP": 0
	}
	var main_advances: Dictionary = source_career.get("main_profile_advances", {})
	for key in ["WS", "BS", "S", "T", "Ag", "Int", "WP", "Fel"]:
		stats[key] += _parse_profile_advance(main_advances.get(key, ""))
	var secondary_advances: Dictionary = source_career.get("secondary_profile_advances", {})
	for key in ["A", "W", "M", "Mag", "IP", "FP"]:
		stats[key] += _parse_profile_advance(secondary_advances.get(key, ""))
	stats["SB"] = int(stats["S"]) / 10
	stats["TB"] = int(stats["T"]) / 10
	var simplified := {
		"might": int(round((float(stats["WS"]) + float(stats["S"])) / 20.0)),
		"agility": int(round((float(stats["BS"]) + float(stats["Ag"])) / 20.0)),
		"wits": int(round((float(stats["Int"]) + float(stats["Fel"])) / 20.0)),
		"spirit": int(round((float(stats["WP"]) + float(stats["Mag"]) * 10.0) / 15.0)),
		"endurance": int(round((float(stats["T"]) + float(stats["W"]) * 5.0) / 20.0))
	}
	for key in simplified.keys():
		simplified[key] = clampi(int(simplified[key]), 1, 6)
	return {
		"wfrp_stats": stats,
		"stats": simplified,
		"max_health": int(stats["W"]),
		"health": int(stats["W"]),
		"xp": 0,
		"gold": rng.randi_range(12, 22),
		"wound_state": "healthy",
		"starting_trappings": get_wfrp_trappings(career_id),
		"starting_talents": get_wfrp_talents(career_id)
	}

func _roll_stat_expr(expr: String, rng: RandomNumberGenerator) -> int:
	var cleaned := expr.strip_edges().replace(" ", "")
	if cleaned.contains("+2d10"):
		var parts := cleaned.split("+2d10")
		var base := int(parts[0]) if not parts[0].is_empty() else 0
		return base + rng.randi_range(1, 10) + rng.randi_range(1, 10)
	if cleaned.is_valid_int():
		return int(cleaned)
	return 0

func _parse_profile_advance(value: Variant) -> int:
	var text := str(value).strip_edges()
	if text == "" or text == "-":
		return 0
	text = text.replace("%", "")
	if text.is_valid_int():
		return int(text)
	return 0

func _roll_lookup_table(table: Dictionary, rng: RandomNumberGenerator, default_value: int) -> int:
	if table.is_empty():
		return default_value
	var roll := rng.randi_range(1, 10)
	for key in table.keys():
		var parts := str(key).split("-")
		if parts.size() == 2:
			var low := int(parts[0])
			var high := int(parts[1])
			if roll >= low and roll <= high:
				return int(table[key])
		elif str(key).is_valid_int() and roll == int(key):
			return int(table[key])
	return default_value
