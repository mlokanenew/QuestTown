extends Node
## Loads and caches JSON data files.
## Access via DataLoader.careers, DataLoader.buildings, etc.

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
