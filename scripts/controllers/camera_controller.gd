class_name CameraController
extends Camera2D
## WASD / arrow keys to pan, middle-mouse drag to pan, wheel to zoom at cursor.
## Edge scrolling (mouse against the window edge) when turned on in Settings.

const PAN_SPEED := 900.0
## Pixels from the window edge that count as "against the edge".
const EDGE := 6.0
const ZOOM_MIN := 0.35
const ZOOM_MAX := 3.0
const ZOOM_STEP := 1.15

var bounds := Rect2()

var _dragging := false
## Last mouse position seen in a motion event (over the map or the HUD);
## off-screen once the mouse leaves the window.
var _mouse := Vector2(-1, -1)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_window().mouse_exited.connect(func() -> void: _mouse = Vector2(-1, -1))


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse = event.position


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
	if Settings.get_value("game/edge_scroll"):
		dir += _edge_direction()
	if dir != Vector2.ZERO:
		var speed: float = PAN_SPEED * Settings.get_value("game/pan_speed")
		position += dir.normalized() * speed * real_delta / zoom.x
		_clamp()


func _edge_direction() -> Vector2:
	var size := get_viewport_rect().size
	var m := _mouse
	# A mouse left at the edge of an unfocused window shouldn't drift the map.
	if not Rect2(Vector2.ZERO, size).has_point(m) or (
			DisplayServer.get_name() != "headless" and not get_window().has_focus()):
		return Vector2.ZERO
	var dir := Vector2.ZERO
	if m.x <= EDGE:
		dir.x -= 1
	elif m.x >= size.x - EDGE:
		dir.x += 1
	if m.y <= EDGE:
		dir.y -= 1
	elif m.y >= size.y - EDGE:
		dir.y += 1
	return dir


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
