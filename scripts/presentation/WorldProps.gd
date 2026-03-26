extends Node3D
## Spawns environmental props from the medieval glTF pack when buildings are placed.
## Godot auto-imports the glTF files on first editor open.

const PROP_BASE := "res://assets/environment/medieval/"

# Props scattered near a tavern (path, position offset, y_rotation_degrees)
const TAVERN_PROPS := [
	["Prop_Crate.gltf",        Vector3( 3.2, 0, 1.8),   15.0],
	["Prop_Crate.gltf",        Vector3( 3.5, 0, 0.6),  -20.0],
	["Prop_Wagon.gltf",        Vector3(-4.0, 0, 2.5),   90.0],
	["Prop_WoodenFence_Single.gltf", Vector3(-2.8, 0, 3.2), 0.0],
	["Prop_WoodenFence_Single.gltf", Vector3(-1.8, 0, 3.2), 0.0],
	["Prop_Chimney.gltf",      Vector3( 0.6, 3.0, 0.6), 0.0],
]

func _ready() -> void:
	if RuntimeConfig.is_headless():
		return
	GameState.building_placed.connect(_on_building_placed)

func _on_building_placed(building: Dictionary) -> void:
	if building["type"] != "tavern":
		return
	var origin := Vector3(
		building["position"]["x"],
		building["position"]["y"],
		building["position"]["z"]
	)
	_spawn_props(origin)

func _spawn_props(origin: Vector3) -> void:
	for entry in TAVERN_PROPS:
		var path: String = PROP_BASE + entry[0]
		var offset: Vector3 = entry[1]
		var rot_deg: float = entry[2]
		var packed: PackedScene = load(path)
		if packed == null:
			continue
		var node: Node3D = packed.instantiate()
		node.global_position = origin + offset
		node.rotation_degrees.y = rot_deg
		add_child(node)
