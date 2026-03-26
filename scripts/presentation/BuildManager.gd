extends Node
class_name BuildManager
## Handles player input for building placement in visual mode.
## Calls SimulationRoot.place_building() — never touches GameState directly.

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
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			cancel_placement()

func _confirm_placement(mouse_pos: Vector2) -> void:
	var world_pos := _mouse_to_ground(mouse_pos)
	if world_pos == Vector3.INF:
		return
	var snapped := _snap(world_pos)
	var result: Variant = _sim.place_building(_current_type, snapped)
	if not result.is_empty():
		cancel_placement()
	else:
		# Flash ghost red briefly to indicate blocked (just leave it for now)
		pass

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
	var box := CSGBox3D.new()
	box.size = Vector3(2, 2, 2)
	box.position = Vector3(0, 1, 0)
	# Slightly transparent to indicate preview
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.7, 1.0, 0.5)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	box.material_override = mat
	return box
