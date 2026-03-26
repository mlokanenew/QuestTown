extends Camera3D
## Isometric camera: WASD to pan, right-click drag to pan.
## Keeps the fixed 45-degree tilt; only translates XZ position.

const MOVE_SPEED := 15.0

var _dragging := false
var _drag_last_mouse := Vector2.ZERO

func _input(event: InputEvent) -> void:
	if RuntimeConfig.is_headless():
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		_dragging = event.pressed
		if event.pressed:
			_drag_last_mouse = event.position

	if event is InputEventMouseMotion and _dragging:
		var px := event.position - _drag_last_mouse
		_drag_last_mouse = event.position
		var vp_h := float(get_viewport().get_visible_rect().size.y)
		var world_per_px := size / vp_h
		# Right-click drag pans the camera in the ground plane.
		# screen-right  = world +X, screen-down = world +Z (scaled by sqrt(2) for 45deg tilt)
		position.x -= px.x * world_per_px
		position.z += px.y * world_per_px * sqrt(2.0)

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
	if move.length() > 0.0:
		position += move.normalized() * MOVE_SPEED * delta
