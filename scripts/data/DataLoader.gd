extends Node
## Loads and caches JSON data files.
## Access via DataLoader.careers, DataLoader.buildings, etc.

var careers: Array = []
var buildings: Array = []
var quests: Array = []
var skills: Array = []
var hero_names: Dictionary = {"first": [], "last": []}

# Indexed lookups
var careers_by_id: Dictionary = {}
var buildings_by_id: Dictionary = {}
var quests_by_id: Dictionary = {}
var skills_by_id: Dictionary = {}

func _ready() -> void:
	careers = _load_json("res://data/careers.json")
	buildings = _load_json("res://data/buildings.json")
	quests = _load_json("res://data/quests.json")
	skills = _load_json("res://data/skills.json")
	hero_names = _load_json("res://data/hero_names.json")

	for c in careers:
		careers_by_id[c["id"]] = c
	for b in buildings:
		buildings_by_id[b["id"]] = b
	for q in quests:
		quests_by_id[q["id"]] = q
	for s in skills:
		skills_by_id[s["id"]] = s

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
