extends RefCounted
class_name BuildingSystem
## Manages building placement and queries.
## Owned by SimulationRoot. Works entirely with GameState data.

const CELL_SIZE := 1.0  # world units per grid cell
const OUTPUT_TICKS := {
	"tavern": 660,
	"weapons_shop": 600,
	"temple": 600,
}
const UPGRADE_TICKS := {
	"tavern": 420,
	"weapons_shop": 420,
	"temple": 420,
}

# Occupied grid cells: Dict[Vector2i -> building_id]
var _occupied: Dictionary = {}

func reset() -> void:
	_occupied.clear()

func place_building(type: String, position: Vector3) -> Dictionary:
	var building_data: Dictionary = DataLoader.buildings_by_id.get(type, {})
	if building_data.is_empty():
		push_error("BuildingSystem: unknown building type '%s'" % type)
		return {}
	if not can_place_building(type, position):
		return {}

	var cost: int = int(building_data.get("base_cost", building_data.get("cost", 0)))
	if not GameState.spend_gold(cost):
		return {}

	var b := GameState.add_building(type, position)
	var footprint: Array = building_data.get("footprint", [1, 1])
	var cells := _cells_for(position, footprint[0], footprint[1])
	for cell in cells:
		_occupied[cell] = b["id"]
	return b

func upgrade_building(id: int) -> Dictionary:
	var building: Dictionary = GameState.buildings.get(id, {})
	if building.is_empty():
		return {}

	var building_data: Dictionary = DataLoader.buildings_by_id.get(building["type"], {})
	if building_data.is_empty():
		return {}

	var levels: Array = building_data.get("levels", [])
	var current_level: int = int(building.get("level", 1))
	if current_level >= levels.size():
		return {}

	var next_level_data: Dictionary = levels[current_level - 1]
	var upgrade_cost: int = int(next_level_data.get("upgrade_cost", 0))
	if not GameState.spend_gold(upgrade_cost):
		return {}

	return GameState.upgrade_building(id)

func start_upgrade_work(id: int) -> Dictionary:
	var building: Dictionary = GameState.buildings.get(id, {})
	if building.is_empty():
		return {}
	if building.get("current_action", "idle") != "idle":
		return {}

	var building_data: Dictionary = DataLoader.buildings_by_id.get(building["type"], {})
	if building_data.is_empty():
		return {}
	var levels: Array = building_data.get("levels", [])
	var current_level: int = int(building.get("level", 1))
	if current_level >= levels.size():
		return {}

	var next_level_data: Dictionary = levels[current_level - 1]
	var upgrade_cost: int = int(next_level_data.get("upgrade_cost", 0))
	if not GameState.spend_gold(upgrade_cost):
		return {}

	var required_ticks: int = _upgrade_ticks(building.get("type", ""))
	var updated := GameState.set_building_action(id, "upgrading", required_ticks)
	GameState.log_event("building_upgrade_started", {
		"building_id": id,
		"building_type": building.get("type", ""),
		"building_name": building_data.get("name", building.get("type", "")),
		"target_level": current_level + 1
	})
	return updated

func set_output_mode(id: int) -> Dictionary:
	var building: Dictionary = GameState.buildings.get(id, {})
	if building.is_empty():
		return {}
	if building.get("current_action", "idle") != "idle":
		return {}
	if int(building.get("output_stock", 0)) >= _output_cap(building):
		return {}
	return GameState.set_building_action(id, "output", _output_ticks(building.get("type", "")))

func step() -> void:
	for building_id in GameState.buildings.keys():
		_step_building(int(building_id))

func remove_building(id: int) -> void:
	var cells_to_free: Array = []
	for cell in _occupied.keys():
		if _occupied[cell] == id:
			cells_to_free.append(cell)
	for cell in cells_to_free:
		_occupied.erase(cell)
	GameState.remove_building(id)

func is_position_free(position: Vector3, footprint_w: int = 1, footprint_d: int = 1) -> bool:
	for cell in _cells_for(position, footprint_w, footprint_d):
		if _occupied.has(cell):
			return false
	return true

func can_place_building(type: String, position: Vector3) -> bool:
	var building_data: Dictionary = DataLoader.buildings_by_id.get(type, {})
	if building_data.is_empty():
		return false
	if not _can_place_instance(type, building_data):
		return false
	var footprint: Array = building_data.get("footprint", [1, 1])
	if not is_position_free(position, int(footprint[0]), int(footprint[1])):
		return false
	var cost: int = int(building_data.get("base_cost", building_data.get("cost", 0)))
	return GameState.gold >= cost

func get_buildings_of_type(type: String) -> Array:
	var result := []
	for b in GameState.buildings.values():
		if b["type"] == type:
			result.append(b)
	return result

func get_building_of_type(type: String) -> Dictionary:
	for b in GameState.buildings.values():
		if b["type"] == type:
			return b
	return {}

func get_tavern_position() -> Vector3:
	for b in GameState.buildings.values():
		if b["type"] == "tavern":
			var p: Dictionary = b["position"]
			return Vector3(p["x"], p["y"], p["z"])
	return Vector3.ZERO

func rebuild_from_game_state() -> void:
	_occupied.clear()
	for building: Dictionary in GameState.buildings.values():
		var building_data: Dictionary = DataLoader.buildings_by_id.get(building.get("type", ""), {})
		if building_data.is_empty():
			continue
		var footprint: Array = building_data.get("footprint", [1, 1])
		var p: Dictionary = building.get("position", {})
		var cells := _cells_for(
			Vector3(float(p.get("x", 0.0)), float(p.get("y", 0.0)), float(p.get("z", 0.0))),
			int(footprint[0]),
			int(footprint[1])
		)
		for cell in cells:
			_occupied[cell] = building["id"]
		if int(building.get("action_required_ticks", 0)) <= 0:
			var current_action: String = building.get("current_action", "idle")
			var required_ticks: int = 0
			if current_action == "upgrading":
				required_ticks = _upgrade_ticks(building.get("type", ""))
			elif current_action == "output":
				required_ticks = _output_ticks(building.get("type", ""))
			GameState.buildings[int(building["id"])]["action_required_ticks"] = required_ticks

func _cells_for(position: Vector3, w: int, d: int) -> Array:
	var origin := Vector2i(int(position.x / CELL_SIZE), int(position.z / CELL_SIZE))
	var cells := []
	for dx in range(w):
		for dz in range(d):
			cells.append(origin + Vector2i(dx, dz))
	return cells

func _can_place_instance(type: String, building_data: Dictionary) -> bool:
	var max_instances: int = int(building_data.get("max_instances", 0))
	if max_instances <= 0:
		return true
	return get_buildings_of_type(type).size() < max_instances

func _step_building(building_id: int) -> void:
	var building: Dictionary = GameState.buildings.get(building_id, {})
	if building.is_empty():
		return
	var action: String = building.get("current_action", "idle")
	if action == "idle":
		return
	var building_type: String = building.get("type", "")
	var required_ticks: int = int(building.get("action_required_ticks", 0))
	if required_ticks <= 0:
		required_ticks = _upgrade_ticks(building_type) if action == "upgrading" else _output_ticks(building_type)
	var progress_ticks: int = int(building.get("action_progress_ticks", 0)) + 1
	if progress_ticks < required_ticks:
		GameState.set_building_action_progress(building_id, progress_ticks, required_ticks)
		return
	if action == "upgrading":
		GameState.set_building_action_progress(building_id, required_ticks, required_ticks)
		var upgraded := GameState.upgrade_building(building_id)
		var building_data: Dictionary = DataLoader.buildings_by_id.get(building_type, {})
		GameState.log_event("building_upgrade_completed", {
			"building_id": building_id,
			"building_type": building_type,
			"building_name": building_data.get("name", building_type),
			"new_level": int(upgraded.get("level", building.get("level", 1)))
		})
		return
	_produce_output(building_id, building)

func _produce_output(building_id: int, building: Dictionary) -> void:
	var building_type: String = building.get("type", "")
	var building_data: Dictionary = DataLoader.buildings_by_id.get(building_type, {})
	var output_cap: int = _output_cap(building)
	var stock: int = int(building.get("output_stock", 0))
	if stock >= output_cap:
		GameState.set_building_action(building_id, "idle", 0)
		return
	var output_name := ""
	match building_type:
		"tavern":
			output_name = "Listen for Rumours"
		"weapons_shop":
			output_name = "Stock Basic Supplies"
		"temple":
			output_name = "Offer Minor Healing"
		_:
			output_name = "Produce Output"
	var next_stock := GameState.add_building_output_stock(building_id, 1, output_cap)
	GameState.log_event("building_output_completed", {
		"building_id": building_id,
		"building_type": building_type,
		"building_name": building_data.get("name", building_type),
		"output_name": output_name,
		"output_stock": next_stock
	})
	GameState.set_building_action(building_id, "idle", 0)

func _output_ticks(building_type: String) -> int:
	return int(OUTPUT_TICKS.get(building_type, 300))

func _upgrade_ticks(building_type: String) -> int:
	return int(UPGRADE_TICKS.get(building_type, 420))

func _output_cap(building: Dictionary) -> int:
	return 1 + int(building.get("level", 1))
