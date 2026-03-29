class_name WfrpDatabase
extends RefCounted

const DATA_ROOT := "res://godot_data/wfrp_db"

static func load_all() -> Dictionary:
	return {
		"manifest": _load_json("wfrp_database_manifest.json"),
		"characteristics": _load_json("characteristics.json"),
		"skills": _load_json("skills.json"),
		"careers": _load_json("careers.json"),
		"equipment": _load_json("equipment.json"),
	}


static func _load_json(filename: String) -> Variant:
	var path := "%s/%s" % [DATA_ROOT, filename]
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("WFRP database file not found: %s" % path)
		return null
	var parsed := JSON.parse_string(file.get_as_text())
	if parsed == null:
		push_error("WFRP database file is not valid JSON: %s" % path)
	return parsed
