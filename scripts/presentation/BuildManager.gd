extends Node
class_name BuildManager
## Handles player input for building placement in visual mode.
## Ghost follows mouse; left-click confirms placement; right-click cancels.

var _sim: Node = null
var _ghost: Node3D = null
var _placing: bool = false
var _current_type: String = ""
var _ground_plane := Plane(Vector3.UP, 0.0)

func _ready() -> void:
	if RuntimeConfig.is_headless():
		set_process_input(false)
		return
	_sim = get_parent().get_node("SimulationRoot")

func start_placement(building_type: String) -> void:
	_current_type = building_type
	_placing = true
	if _ghost:
		_ghost.queue_free()
	_ghost = _make_ghost()
	get_parent().add_child(_ghost)

func cancel_placement() -> void:
	_placing = false
	if _ghost:
		_ghost.queue_free()
		_ghost = null

func _input(event: InputEvent) -> void:
	if not _placing:
		return

	if event is InputEventMouseMotion:
		var world_pos := _mouse_to_ground(event.position)
		if _ghost and world_pos != Vector3.INF:
			_ghost.global_position = _snap(world_pos)

	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_confirm_placement(event.position)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			cancel_placement()
			get_viewport().set_input_as_handled()

func _confirm_placement(mouse_pos: Vector2) -> void:
	var world_pos := _mouse_to_ground(mouse_pos)
	if world_pos == Vector3.INF:
		return
	var snapped := _snap(world_pos)
	var building_data: Dictionary = DataLoader.buildings_by_id.get(_current_type, {})
	var cost: int = building_data.get("cost", 0)
	if not GameState.spend_gold(cost):
		cancel_placement()
		return
	var result: Variant = _sim.place_building(_current_type, snapped)
	if result.is_empty():
		GameState.add_gold(cost)  # refund — cell was blocked
	else:
		cancel_placement()

func _mouse_to_ground(mouse_pos: Vector2) -> Vector3:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return Vector3.INF
	var ray_origin := camera.project_ray_origin(mouse_pos)
	var ray_dir    := camera.project_ray_normal(mouse_pos)
	var hit: Variant = _ground_plane.intersects_ray(ray_origin, ray_dir)
	if hit == null:
		return Vector3.INF
	return hit

func _snap(pos: Vector3) -> Vector3:
	return Vector3(round(pos.x), 0.0, round(pos.z))

func _make_ghost() -> Node3D:
	var root := Node3D.new()

	# Transparent building volume
	var body_inst := MeshInstance3D.new()
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(4.0, 3.0, 4.0)
	body_inst.mesh = body_mesh
	body_inst.position = Vector3(0, 1.5, 0)
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.5, 0.85, 1.0, 0.35)
	body_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	body_inst.set_surface_override_material(0, body_mat)
	root.add_child(body_inst)

	# Solid footprint on the ground so you can see placement exactly
	var foot_inst := MeshInstance3D.new()
	var foot_mesh := BoxMesh.new()
	foot_mesh.size = Vector3(4.0, 0.05, 4.0)
	foot_inst.mesh = foot_mesh
	foot_inst.position = Vector3(0, 0.03, 0)
	var foot_mat := StandardMaterial3D.new()
	foot_mat.albedo_color = Color(0.3, 0.75, 1.0, 0.8)
	foot_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	foot_inst.set_surface_override_material(0, foot_mat)
	root.add_child(foot_inst)

	return root
