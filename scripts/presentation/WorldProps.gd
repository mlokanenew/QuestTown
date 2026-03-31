extends Node3D
## Spawns environmental props from the medieval glTF pack when buildings are placed.
## Godot auto-imports the glTF files on first editor open.

const PROP_BASE := "res://assets/environment/medieval/"
const PLAZA_TILES := [
	Vector3(0, 0.01, 0),
	Vector3(2, 0.01, 0),
	Vector3(-2, 0.01, 0),
	Vector3(0, 0.01, 2),
	Vector3(0, 0.01, -2),
	Vector3(2, 0.01, 2),
	Vector3(-2, 0.01, 2),
	Vector3(2, 0.01, -2),
	Vector3(-2, 0.01, -2),
]
const ROAD_TILES := [
	Vector3(-6, 0.01, 0),
	Vector3(-4, 0.01, 0),
	Vector3(-8, 0.01, 0),
	Vector3(4, 0.01, 0),
	Vector3(6, 0.01, 0),
	Vector3(8, 0.01, 0),
	Vector3(0, 0.01, -4),
	Vector3(0, 0.01, -6),
	Vector3(0, 0.01, -8),
	Vector3(0, 0.01, 4),
	Vector3(0, 0.01, 6),
	Vector3(0, 0.01, 8),
	Vector3(-4, 0.01, 2),
	Vector3(-2, 0.01, 4),
	Vector3(4, 0.01, -2),
	Vector3(2, 0.01, -4),
]
const WORLD_ANCHORS := [
	["Prop_Wagon.gltf", Vector3(5.5, 0, 4.8), 36.0],
	["Prop_Crate.gltf", Vector3(6.2, 0, 3.8), 12.0],
	["Prop_Crate.gltf", Vector3(5.0, 0, 3.2), -18.0],
	["Prop_WoodenFence_Single.gltf", Vector3(-6.5, 0, -4.5), 90.0],
	["Prop_WoodenFence_Single.gltf", Vector3(-6.5, 0, -3.3), 90.0],
	["Prop_MetalFence_Ornament.gltf", Vector3(0.0, 0, 7.0), 0.0],
	["Prop_MetalFence_Ornament.gltf", Vector3(1.8, 0, 7.0), 0.0],
	["Prop_Brick2.gltf", Vector3(-1.8, 0.0, -5.2), 10.0],
	["Prop_Brick4.gltf", Vector3(-2.7, 0.0, -5.6), -24.0],
	["Prop_Vine2.gltf", Vector3(6.8, 0.2, 5.4), 0.0],
	["Prop_Vine5.gltf", Vector3(-6.8, 0.2, -4.6), 0.0],
	["Prop_WoodenFence_Extension2.gltf", Vector3(7.3, 0.0, -1.4), 90.0],
	["Prop_WoodenFence_Extension2.gltf", Vector3(7.3, 0.0, -0.1), 90.0],
]

# Props scattered near a tavern (path, position offset, y_rotation_degrees)
const TAVERN_PROPS := [
	["Prop_Crate.gltf",        Vector3( 3.2, 0, 1.8),   15.0],
	["Prop_Crate.gltf",        Vector3( 3.5, 0, 0.6),  -20.0],
	["Prop_Wagon.gltf",        Vector3(-4.0, 0, 2.5),   90.0],
	["Prop_WoodenFence_Single.gltf", Vector3(-2.8, 0, 3.2), 0.0],
	["Prop_WoodenFence_Single.gltf", Vector3(-1.8, 0, 3.2), 0.0],
	["Prop_Chimney.gltf",      Vector3( 0.6, 3.0, 0.6), 0.0],
]
const STORE_PROPS := [
	["Prop_Crate.gltf", Vector3(2.3, 0, -1.8), 10.0],
	["Prop_Crate.gltf", Vector3(2.9, 0, -0.7), -14.0],
	["Prop_WoodenFence_Extension1.gltf", Vector3(-2.1, 0, -2.6), 0.0],
	["Prop_Brick1.gltf", Vector3(2.6, 0, 0.4), 0.0],
]
const TEMPLE_PROPS := [
	["Prop_MetalFence_Ornament.gltf", Vector3(0, 0, 3.1), 0.0],
	["Prop_MetalFence_Ornament.gltf", Vector3(1.7, 0, 3.1), 0.0],
	["Prop_Vine4.gltf", Vector3(2.0, 0.2, 1.8), 0.0],
	["Prop_Vine6.gltf", Vector3(-1.8, 0.2, 2.4), 0.0],
]

func _ready() -> void:
	if RuntimeConfig.is_headless():
		return
	_spawn_foundation()
	GameState.building_placed.connect(_on_building_placed)

func _on_building_placed(building: Dictionary) -> void:
	var origin := Vector3(
		building["position"]["x"],
		building["position"]["y"],
		building["position"]["z"]
	)
	match str(building["type"]):
		"tavern":
			_spawn_props(origin, TAVERN_PROPS)
		"weapons_shop":
			_spawn_props(origin, STORE_PROPS)
		"temple":
			_spawn_props(origin, TEMPLE_PROPS)

func _spawn_foundation() -> void:
	for tile_pos in PLAZA_TILES:
		_spawn_static("Floor_UnevenBrick.gltf", tile_pos, 0.0)
	for tile_pos in ROAD_TILES:
		_spawn_static("Floor_Brick.gltf", tile_pos, 0.0)
	for tile_pos in [
		Vector3(4, 0.008, 4),
		Vector3(6, 0.008, 4),
		Vector3(-4, 0.008, -4),
		Vector3(-6, 0.008, -4),
		Vector3(4, 0.008, -6),
	]:
		_spawn_static("Floor_RedBrick.gltf", tile_pos, 0.0)
	for anchor in WORLD_ANCHORS:
		_spawn_static(anchor[0], anchor[1], anchor[2])

func _spawn_props(origin: Vector3, prop_set: Array) -> void:
	for entry in prop_set:
		var path: String = PROP_BASE + entry[0]
		var offset: Vector3 = entry[1]
		var rot_deg: float = entry[2]
		var packed: PackedScene = load(path)
		if packed == null:
			continue
		var node: Node3D = packed.instantiate()
		node.position = origin + offset
		node.rotation_degrees.y = rot_deg
		add_child(node)

func _spawn_static(asset_name: String, position: Vector3, rot_deg: float) -> void:
	var packed: PackedScene = load(PROP_BASE + asset_name)
	if packed == null:
		return
	var node: Node3D = packed.instantiate()
	node.position = position
	node.rotation_degrees.y = rot_deg
	add_child(node)
