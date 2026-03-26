extends Node3D
class_name BuildingPresenter
## Listens to GameState signals and spawns 3D building scenes.

const BUILDING_SCENES: Dictionary = {
	"tavern": "res://scenes/buildings/Tavern.tscn",
}

# Dict[building_id -> Node3D]
var _nodes: Dictionary = {}

func _ready() -> void:
	if RuntimeConfig.is_headless():
		return
	GameState.building_placed.connect(_on_building_placed)
	GameState.building_removed.connect(_on_building_removed)

func _on_building_placed(building: Dictionary) -> void:
	var scene_path: String = BUILDING_SCENES.get(building["type"], "")
	if scene_path == "":
		return
	var packed: PackedScene = load(scene_path)
	if packed == null:
		return
	var node: Node3D = packed.instantiate()
	var p: Dictionary = building["position"]
	node.global_position = Vector3(p["x"], 0.0, p["z"])
	add_child(node)
	_nodes[building["id"]] = node

func _on_building_removed(building_id: int) -> void:
	if _nodes.has(building_id):
		_nodes[building_id].queue_free()
		_nodes.erase(building_id)
