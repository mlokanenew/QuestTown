extends RefCounted
class_name BuildingSystem
## Manages building placement and queries.
## Owned by SimulationRoot. Works entirely with GameState data.

const CELL_SIZE := 1.0  # world units per grid cell

# Occupied grid cells: Dict[Vector2i -> building_id]
var _occupied: Dictionary = {}

func reset() -> void:
	_occupied.clear()

func place_building(type: String, position: Vector3) -> Dictionary:
	var building_data: Dictionary = DataLoader.buildings_by_id.get(type, {})
	if building_data.is_empty():
		push_error("BuildingSystem: unknown building type '%s'" % type)
		return {}

	var footprint: Array = building_data.get("footprint", [1, 1])
	var cells := _cells_for(position, footprint[0], footprint[1])

	for cell in cells:
		if _occupied.has(cell):
			return {}  # blocked

	var b := GameState.add_building(type, position)
	for cell in cells:
		_occupied[cell] = b["id"]
	return b

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

func get_buildings_of_type(type: String) -> Array:
	var result := []
	for b in GameState.buildings.values():
		if b["type"] == type:
			result.append(b)
	return result

func get_tavern_position() -> Vector3:
	for b in GameState.buildings.values():
		if b["type"] == "tavern":
			var p: Dictionary = b["position"]
			return Vector3(p["x"], p["y"], p["z"])
	return Vector3.ZERO

func _cells_for(position: Vector3, w: int, d: int) -> Array:
	var origin := Vector2i(int(position.x / CELL_SIZE), int(position.z / CELL_SIZE))
	var cells := []
	for dx in range(w):
		for dz in range(d):
			cells.append(origin + Vector2i(dx, dz))
	return cells
