extends Node3D
## Keeps 3D hero nodes in sync with GameState.heroes.
## Uses KayKit GLB character models, mapped by career.

# Career → character model path
const CAREER_MODELS: Dictionary = {
	"Rat Catcher":   "res://assets/characters/Rogue_Hooded.glb",
	"Soldier":       "res://assets/characters/Knight.glb",
	"Camp Follower": "res://assets/characters/Barbarian.glb",
	"Mercenary":     "res://assets/characters/Barbarian.glb",
	"Riverfolk":     "res://assets/characters/Rogue.glb",
	"Peasant":       "res://assets/characters/Mage.glb",
}
const DEFAULT_MODEL := "res://assets/characters/Knight.glb"

# KayKit GLB animation names (check what's available in AnimationPlayer)
const ANIM_IDLE  := "Idle"
const ANIM_WALK  := "Walk"
const ANIM_RUN   := "Run"

# Approximate scale — KayKit characters are ~2 units tall, we want ~1.8m heroes
const MODEL_SCALE := Vector3(0.8, 0.8, 0.8)

# Dict[hero_id -> Node3D]
var _nodes: Dictionary = {}

func _ready() -> void:
	if RuntimeConfig.is_headless():
		return
	GameState.hero_spawned.connect(_on_hero_spawned)
	GameState.hero_removed.connect(_on_hero_removed)
	GameState.hero_state_changed.connect(_on_hero_state_changed)

func _process(_delta: float) -> void:
	if RuntimeConfig.is_headless():
		return
	for id in _nodes.keys():
		if not GameState.heroes.has(id):
			continue
		var h: Dictionary = GameState.heroes[id]
		var node: Node3D = _nodes[id]
		var sim_pos := Vector3(h["position"]["x"], h["position"]["y"], h["position"]["z"])
		var prev_pos := node.global_position
		node.global_position = node.global_position.lerp(sim_pos, 0.15)

		# Face direction of movement
		var move := sim_pos - prev_pos
		if move.length() > 0.01:
			node.look_at(node.global_position + Vector3(move.x, 0, move.z), Vector3.UP)

func _on_hero_spawned(hero: Dictionary) -> void:
	var node := _make_hero_node(hero)
	add_child(node)
	_nodes[hero["id"]] = node
	_set_animation(hero["id"], ANIM_WALK)

func _on_hero_removed(hero_id: int) -> void:
	if _nodes.has(hero_id):
		_nodes[hero_id].queue_free()
		_nodes.erase(hero_id)

func _on_hero_state_changed(hero_id: int, new_state: String) -> void:
	match new_state:
		"idling":   _set_animation(hero_id, ANIM_IDLE)
		"leaving":  _set_animation(hero_id, ANIM_WALK)
		_:          _set_animation(hero_id, ANIM_WALK)

func _set_animation(hero_id: int, anim_name: String) -> void:
	if not _nodes.has(hero_id):
		return
	var node: Node3D = _nodes[hero_id]
	var player := _find_animation_player(node)
	if player == null:
		return
	# Try requested name, then common fallbacks
	var candidates := [anim_name, ANIM_IDLE, ANIM_WALK, ANIM_RUN]
	for name in candidates:
		if player.has_animation(name):
			player.play(name)
			return

func _find_animation_player(node: Node3D) -> AnimationPlayer:
	for child in node.get_children():
		if child is AnimationPlayer:
			return child
		var deep: AnimationPlayer = _find_animation_player_recursive(child)
		if deep:
			return deep
	return null

func _find_animation_player_recursive(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var r: AnimationPlayer = _find_animation_player_recursive(child)
		if r:
			return r
	return null

func _make_hero_node(hero: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Hero_%d" % hero["id"]

	# Load GLB model for this career
	var model_path: String = CAREER_MODELS.get(hero["career"], DEFAULT_MODEL)
	var packed: PackedScene = load(model_path)
	if packed:
		var model := packed.instantiate()
		model.scale = MODEL_SCALE
		root.add_child(model)
	else:
		# Fallback capsule if GLB not loaded
		var mesh := MeshInstance3D.new()
		var cap := CapsuleMesh.new()
		cap.radius = 0.3
		cap.height = 1.6
		mesh.mesh = cap
		mesh.position = Vector3(0, 0.8, 0)
		root.add_child(mesh)

	# Name label above the hero
	var label := Label3D.new()
	label.text = "%s\n%s" % [hero["name"], hero["career"]]
	label.position = Vector3(0, 2.4, 0)
	label.pixel_size = 0.005
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color(1, 0.95, 0.7)
	root.add_child(label)

	# Clickable Area3D so the player can select this hero
	var area := Area3D.new()
	area.collision_layer = 2
	area.collision_mask = 0
	area.set_meta("hero_id", hero["id"])
	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.5
	cap.height = 1.8
	col.shape = cap
	col.position = Vector3(0, 0.9, 0)
	area.add_child(col)
	root.add_child(area)

	# Start position
	var p: Dictionary = hero["position"]
	root.global_position = Vector3(p["x"], p["y"], p["z"])
	return root
