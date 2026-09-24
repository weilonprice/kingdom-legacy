class_name CameraController
extends Camera2D
## Panning: WASD / arrow keys, middle-mouse drag, two-finger trackpad scroll,
## and edge scrolling when turned on in Settings.
## Zooming: mouse wheel or trackpad pinch (toward the cursor), +/- keys and
## the HUD's zoom buttons (toward the screen centre). Zoom eases to its
## target; the widest zoom shows the whole map.

const PAN_SPEED := 900.0
## Pixels from the window edge that count as "against the edge".
const EDGE := 6.0
const ZOOM_MAX := 3.0
## Never zoom in less than this, even on a map small enough to fit sooner.
const ZOOM_MIN_CAP := 0.35
const ZOOM_STEP := 1.15
## Key and button presses take bigger steps than a wheel notch.
const ZOOM_KEY_STEP := 1.4
## How quickly zoom eases toward its target (higher is snappier).
const ZOOM_EASE := 14.0
## Screen pixels per unit of trackpad pan (macOS reports scroll points x 0.03).
const PAN_GESTURE_SCALE := 32.0

var bounds := Rect2()
## Where zoom is heading, and the screen point that stays put meanwhile.
var target_zoom := 1.0

var _zoom_anchor := Vector2.ZERO
var _dragging := false
## Last mouse position seen in a motion event (over the map or the HUD);
## off-screen once the mouse leaves the window.
var _mouse := Vector2(-1, -1)
## Godot delivers each trackpad gesture to _unhandled_input twice in the
## same frame (separate copies); the repeat is dropped so a pinch zooms once.
var _last_gesture := ""
var _last_gesture_frame := -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	target_zoom = zoom.x
	get_window().mouse_exited.connect(func() -> void: _mouse = Vector2(-1, -1))


## The widest zoom: the whole map fits on screen (with a little margin).
func min_zoom() -> float:
	if not bounds.has_area():
		return ZOOM_MIN_CAP
	var view := get_viewport_rect().size
	var fit := minf(view.x / bounds.size.x, view.y / bounds.size.y) * 0.95
	return minf(ZOOM_MIN_CAP, fit)


## Smoothly zoom by `factor` toward `screen_pos` (default: the screen centre).
func zoom_by(factor: float, screen_pos := Vector2(-1, -1)) -> void:
	if screen_pos.x < 0.0:
		screen_pos = get_viewport_rect().size * 0.5
	target_zoom = clampf(target_zoom * factor, min_zoom(), ZOOM_MAX)
	_zoom_anchor = screen_pos


func zoom_in() -> void:
	zoom_by(ZOOM_KEY_STEP)


func zoom_out() -> void:
	zoom_by(1.0 / ZOOM_KEY_STEP)


## Zoom all the way out, centred on the map.
func show_whole_map() -> void:
	target_zoom = min_zoom()
	_zoom_anchor = get_viewport_rect().size * 0.5
	position = bounds.get_center()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_mouse = event.position


func _process(delta: float) -> void:
	# Pan and ease zoom at real-time speed regardless of game speed.
	var real_delta := delta / maxf(Engine.time_scale, 0.001)
	if not is_equal_approx(zoom.x, target_zoom):
		var z := lerpf(zoom.x, target_zoom, 1.0 - exp(-ZOOM_EASE * real_delta))
		if absf(z - target_zoom) < 0.002:
			z = target_zoom
		_set_zoom_at(z, _zoom_anchor)
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
					zoom_by(ZOOM_STEP, event.position)
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					zoom_by(1.0 / ZOOM_STEP, event.position)
			MOUSE_BUTTON_MIDDLE:
				_dragging = event.pressed
	elif event is InputEventMouseMotion and _dragging:
		position -= event.relative / zoom.x
		_clamp()
	elif event is InputEventGesture and _is_repeat(event):
		return
	elif event is InputEventMagnifyGesture:
		# Pinch: follow the fingers directly (the gesture is already smooth).
		var z := clampf(zoom.x * event.factor, min_zoom(), ZOOM_MAX)
		target_zoom = z
		_set_zoom_at(z, event.position)
	elif event is InputEventPanGesture:
		var speed: float = PAN_GESTURE_SCALE * Settings.get_value("game/pan_speed")
		position += event.delta * speed / zoom.x
		_clamp()
	elif event is InputEventKey and event.pressed:
		if event.keycode in [KEY_EQUAL, KEY_PLUS, KEY_KP_ADD]:
			zoom_in()
		elif event.keycode in [KEY_MINUS, KEY_KP_SUBTRACT]:
			zoom_out()
		elif event.keycode == KEY_HOME:
			show_whole_map()
		else:
			return
		get_viewport().set_input_as_handled()


func _is_repeat(event: InputEventGesture) -> bool:
	var amount: Variant = event.factor if event is InputEventMagnifyGesture else event.delta
	var signature := "%s %s %s" % [event.get_class(), event.position, amount]
	var frame := Engine.get_process_frames()
	if signature == _last_gesture and frame == _last_gesture_frame:
		return true
	_last_gesture = signature
	_last_gesture_frame = frame
	return false


func _set_zoom_at(z: float, screen_pos: Vector2) -> void:
	var offset_from_center := screen_pos - get_viewport_rect().size * 0.5
	var world_under_cursor := position + offset_from_center / zoom.x
	zoom = Vector2(z, z)
	position = world_under_cursor - offset_from_center / z
	_clamp()


## Keeps the view centre on the map; once the whole map fits across (or
## down), centres it that way instead.
func _clamp() -> void:
	if not bounds.has_area():
		return
	var half := get_viewport_rect().size * 0.5 / zoom.x
	for axis in 2:
		if half[axis] * 2.0 >= bounds.size[axis]:
			position[axis] = bounds.get_center()[axis]
		else:
			position[axis] = clampf(position[axis], bounds.position[axis], bounds.end[axis])
