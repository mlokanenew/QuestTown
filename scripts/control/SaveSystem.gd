extends RefCounted
class_name SaveSystem

const SAVE_PATH := "user://questtown_save.json"

static func save_simulation(sim: Node, path: String = SAVE_PATH) -> bool:
	var data: Dictionary = sim.export_save_data()
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("SaveSystem: failed to open save path for writing: %s" % path)
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	return true

static func load_simulation(sim: Node, path: String = SAVE_PATH) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("SaveSystem: failed to open save path for reading: %s" % path)
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if parsed == null or not (parsed is Dictionary):
		push_error("SaveSystem: invalid save file: %s" % path)
		return false
	return sim.import_save_data(parsed)
