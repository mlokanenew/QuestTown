extends Camera3D
## Isometric camera: WASD to pan, middle mouse to orbit, scroll to zoom.

const MOVE_SPEED := 15.0
const ROTATE_SPEED := 0.25
const MIN_SIZE := 8.0
const MAX_SIZE := 28.0
const POSITION_SMOOTHNESS := 10.0

var _dragging := false
var _drag_last_mouse := Vector2.ZERO
var _yaw_degrees := 0.0
var _target_position := Vector3.ZERO

func _input(event: InputEvent) -> void:
	if RuntimeConfig.is_headless():
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		_dragging = event.pressed
		if event.pressed:
			_drag_last_mouse = event.position
	elif event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			size = max(MIN_SIZE, size - 1.5)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			size = min(MAX_SIZE, size + 1.5)

	if event is InputEventMouseMotion and _dragging:
		var px: Vector2 = event.position - _drag_last_mouse
		_drag_last_mouse = event.position
		_yaw_degrees = wrapf(_yaw_degrees - px.x * ROTATE_SPEED, -180.0, 180.0)
		_update_transform()

func _ready() -> void:
	_target_position = position

func _process(delta: float) -> void:
	if RuntimeConfig.is_headless():
		return
	var move := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		move.z -= 1.0
	if Input.is_key_pressed(KEY_S):
		move.z += 1.0
	if Input.is_key_pressed(KEY_A):
		move.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		move.x += 1.0
	if Input.is_key_pressed(KEY_F):
		_target_position.x = move_toward(_target_position.x, 0.0, MOVE_SPEED * delta)
		_target_position.z = move_toward(_target_position.z, 0.0, MOVE_SPEED * delta)
	if move.length() > 0.0:
		var basis := Basis(Vector3.UP, deg_to_rad(_yaw_degrees))
		_target_position += basis * move.normalized() * MOVE_SPEED * delta
	position = position.lerp(_target_position, clamp(delta * POSITION_SMOOTHNESS, 0.0, 1.0))
	_update_transform()

func _update_transform() -> void:
	rotation_degrees = Vector3(-45.0, _yaw_degrees, 0.0)
