extends Node
class_name BuildManager
## Handles player input for building placement in visual mode.
## Ghost follows mouse; left-click confirms placement; right-click rotates.

var _sim: Node = null
var _ghost: Node3D = null
var _placing: bool = false
var _current_type: String = ""
var _ground_plane := Plane(Vector3.UP, 0.0)
var _footprint: Vector2i = Vector2i.ONE
var _is_valid_location: bool = false
var _last_snapped: Vector3 = Vector3.ZERO
var _rotation_y_degrees: float = 0.0
var _build_types: Array = []

func _ready() -> void:
	if RuntimeConfig.is_headless():
		set_process_input(false)
		return
	_sim = get_parent().get_node("SimulationRoot")
	_build_types = DataLoader.buildings.map(func(building: Dictionary) -> String: return String(building.get("id", "")))

func start_placement(building_type: String) -> void:
	_current_type = building_type
	_placing = true
	_rotation_y_degrees = 0.0
	var data: Dictionary = DataLoader.buildings_by_id.get(building_type, {})
	var footprint: Array = data.get("footprint", [1, 1])
	_footprint = Vector2i(int(footprint[0]), int(footprint[1]))
	if _ghost:
		_ghost.queue_free()
	_ghost = _make_ghost()
	get_parent().add_child(_ghost)

func cancel_placement() -> void:
	_placing = false
	if _ghost:
		_ghost.queue_free()
		_ghost = null
	_is_valid_location = false
	_rotation_y_degrees = 0.0

func is_placing() -> bool:
	return _placing

func get_current_building_type() -> String:
	return _current_type

func _input(event: InputEvent) -> void:
	if not _placing:
		return

	if event is InputEventMouseMotion:
		var world_pos := _mouse_to_ground(event.position)
		if _ghost and world_pos != Vector3.INF:
			_last_snapped = _snap(world_pos)
			_ghost.global_position = _last_snapped
			_update_ghost_validity()

	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_confirm_placement(event.position)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_rotate_preview(90.0)
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			cancel_placement()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_Q:
			cycle_building_type(-1)
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_E:
			cycle_building_type(1)
			get_viewport().set_input_as_handled()

func _confirm_placement(mouse_pos: Vector2) -> void:
	var world_pos := _mouse_to_ground(mouse_pos)
	if world_pos == Vector3.INF:
		return
	var snapped := _snap(world_pos)
	if not _sim.can_place_building(_current_type, snapped):
		return
	var result: Variant = _sim.place_building(_current_type, snapped)
	if not result.is_empty():
		GameState.buildings[int(result.get("id", -1))]["rotation_degrees_y"] = _rotation_y_degrees
		cancel_placement()

func _mouse_to_ground(mouse_pos: Vector2) -> Vector3:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return Vector3.INF
	var ray_origin := camera.project_ray_origin(mouse_pos)
	var ray_dir := camera.project_ray_normal(mouse_pos)
	var hit: Variant = _ground_plane.intersects_ray(ray_origin, ray_dir)
	if hit == null:
		return Vector3.INF
	return hit

func _snap(pos: Vector3) -> Vector3:
	return Vector3(round(pos.x), 0.0, round(pos.z))

func _make_ghost() -> Node3D:
	var root := Node3D.new()
	var data: Dictionary = DataLoader.buildings_by_id.get(_current_type, {})
	var scene_path: String = data.get("scene", "")

	if scene_path != "":
		var packed: PackedScene = load(scene_path)
		if packed:
			var preview: Node3D = packed.instantiate()
			_apply_ghost_materials(preview)
			root.add_child(preview)

	# Solid footprint on the ground so you can see placement exactly.
	var foot_inst := MeshInstance3D.new()
	var foot_mesh := BoxMesh.new()
	foot_mesh.size = Vector3(float(_footprint.x), 0.05, float(_footprint.y))
	foot_inst.mesh = foot_mesh
	foot_inst.position = Vector3((float(_footprint.x) - 1.0) * 0.5, 0.03, (float(_footprint.y) - 1.0) * 0.5)
	var foot_mat := StandardMaterial3D.new()
	foot_mat.albedo_color = Color(0.3, 0.75, 1.0, 0.8)
	foot_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	foot_inst.set_surface_override_material(0, foot_mat)
	foot_inst.name = "Footprint"
	root.add_child(foot_inst)

	return root

func _update_ghost_validity() -> void:
	_is_valid_location = _sim.can_place_building(_current_type, _last_snapped)
	if _ghost == null:
		return
	var foot := _ghost.get_node_or_null("Footprint") as MeshInstance3D
	if foot:
		var mat: StandardMaterial3D = foot.get_active_material(0)
		if mat == null:
			mat = StandardMaterial3D.new()
			foot.set_surface_override_material(0, mat)
		mat.albedo_color = Color(0.25, 0.8, 0.45, 0.8) if _is_valid_location else Color(0.9, 0.25, 0.25, 0.8)
	_ghost.rotation_degrees.y = _rotation_y_degrees

func _apply_ghost_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		for surface_idx in range(mesh_instance.get_surface_override_material_count()):
			pass
		var surface_count: int = mesh_instance.mesh.get_surface_count() if mesh_instance.mesh != null else 0
		for surface_idx in range(surface_count):
			var ghost_mat := StandardMaterial3D.new()
			ghost_mat.albedo_color = Color(0.75, 0.9, 1.0, 0.35)
			ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			mesh_instance.set_surface_override_material(surface_idx, ghost_mat)
	for child in node.get_children():
		_apply_ghost_materials(child)

func cycle_building_type(direction: int) -> void:
	if _build_types.is_empty():
		return
	var current_index: int = _build_types.find(_current_type)
	if current_index < 0:
		current_index = 0
	var next_index := posmod(current_index + direction, _build_types.size())
	start_placement(_build_types[next_index])

func _rotate_preview(amount: float) -> void:
	_rotation_y_degrees = fmod(_rotation_y_degrees + amount, 360.0)
	if _ghost:
		_ghost.rotation_degrees.y = _rotation_y_degrees
