class_name CameraController
extends Camera2D
## WASD / arrow keys to pan, middle-mouse drag to pan, wheel to zoom at cursor.

const PAN_SPEED := 900.0
const ZOOM_MIN := 0.35
const ZOOM_MAX := 3.0
const ZOOM_STEP := 1.15

var bounds := Rect2()

var _dragging := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(delta: float) -> void:
	# Pan at a constant real-time speed regardless of game speed.
	var real_delta := delta / maxf(Engine.time_scale, 0.001)
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
		dir.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
		dir.x += 1
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
		dir.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
		dir.y += 1
	if dir != Vector2.ZERO:
		position += dir.normalized() * PAN_SPEED * real_delta / zoom.x
		_clamp()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					_zoom_at(zoom.x * ZOOM_STEP, event.position)
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					_zoom_at(zoom.x / ZOOM_STEP, event.position)
			MOUSE_BUTTON_MIDDLE:
				_dragging = event.pressed
	elif event is InputEventMouseMotion and _dragging:
		position -= event.relative / zoom.x
		_clamp()


func _zoom_at(target_zoom: float, screen_pos: Vector2) -> void:
	target_zoom = clampf(target_zoom, ZOOM_MIN, ZOOM_MAX)
	var offset_from_center := screen_pos - get_viewport_rect().size * 0.5
	var world_under_cursor := position + offset_from_center / zoom.x
	zoom = Vector2(target_zoom, target_zoom)
	position = world_under_cursor - offset_from_center / target_zoom
	_clamp()


func _clamp() -> void:
	if bounds.has_area():
		position = position.clamp(bounds.position, bounds.end)
