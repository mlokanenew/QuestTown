extends Node3D
## Keeps 3D hero nodes in sync with GameState.heroes.
## Creates/moves/removes Node3D instances — owns no game state.

# Dict[hero_id -> Node3D]
var _nodes: Dictionary = {}

func _ready() -> void:
	if RuntimeConfig.is_headless():
		return
	GameState.hero_spawned.connect(_on_hero_spawned)
	GameState.hero_removed.connect(_on_hero_removed)

func _process(_delta: float) -> void:
	if RuntimeConfig.is_headless():
		return
	for id in _nodes.keys():
		if not GameState.heroes.has(id):
			continue
		var h: Dictionary = GameState.heroes[id]
		var node: Node3D = _nodes[id]
		var sim_pos := Vector3(h["position"]["x"], h["position"]["y"], h["position"]["z"])
		# Smooth visual movement toward sim position
		node.global_position = node.global_position.lerp(sim_pos, 0.2)

func _on_hero_spawned(hero: Dictionary) -> void:
	var node := _make_hero_node(hero)
	add_child(node)
	_nodes[hero["id"]] = node

func _on_hero_removed(hero_id: int) -> void:
	if _nodes.has(hero_id):
		_nodes[hero_id].queue_free()
		_nodes.erase(hero_id)

func _make_hero_node(hero: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Hero_%d" % hero["id"]

	# Placeholder capsule — swap for glTF in M3
	var mesh := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.3
	capsule.height = 1.6
	mesh.mesh = capsule
	mesh.position = Vector3(0, 0.8, 0)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.5, 0.2)
	mesh.material_override = mat
	root.add_child(mesh)

	# Name label (billboard)
	var label := Label3D.new()
	label.text = hero["name"]
	label.position = Vector3(0, 2.0, 0)
	label.pixel_size = 0.005
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	root.add_child(label)

	# Start position
	var p: Dictionary = hero["position"]
	root.global_position = Vector3(p["x"], p["y"], p["z"])
	return root
