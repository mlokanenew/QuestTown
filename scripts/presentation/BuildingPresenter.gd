extends Node3D
class_name BuildingPresenter
## Listens to GameState signals and spawns 3D building scenes.

const BUILDING_SCENES: Dictionary = {
	"tavern":        "res://scenes/buildings/Tavern.tscn",
	"weapons_shop":  "res://scenes/buildings/WeaponsShop.tscn",
	"temple":        "res://scenes/buildings/Temple.tscn",
}

# Dict[building_id -> Node3D]
var _nodes: Dictionary = {}

func _ready() -> void:
	if RuntimeConfig.is_headless():
		return
	GameState.building_placed.connect(_on_building_placed)
	GameState.building_removed.connect(_on_building_removed)
	GameState.building_upgraded.connect(_on_building_upgraded)
	GameState.state_reloaded.connect(_rebuild_all)

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
	node.rotation_degrees.y = float(building.get("rotation_degrees_y", 0.0))
	var selector := Area3D.new()
	selector.collision_layer = 4
	selector.collision_mask = 0
	selector.set_meta("building_id", building["id"])
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.4, 3.5, 2.4)
	shape.shape = box
	shape.position = Vector3(0.5, 1.75, 0.5)
	selector.add_child(shape)
	node.add_child(selector)
	add_child(node)
	_nodes[building["id"]] = node

func _on_building_removed(building_id: int) -> void:
	if _nodes.has(building_id):
		_nodes[building_id].queue_free()
		_nodes.erase(building_id)

func _on_building_upgraded(building_id: int, _new_level: int) -> void:
	if not _nodes.has(building_id):
		return
	var building: Dictionary = GameState.buildings.get(building_id, {})
	var level: int = int(building.get("level", 1))
	_nodes[building_id].scale = Vector3.ONE * (1.0 + 0.08 * max(0, level - 1))

func _rebuild_all() -> void:
	for node in _nodes.values():
		node.queue_free()
	_nodes.clear()
	for building: Dictionary in GameState.buildings.values():
		_on_building_placed(building)
