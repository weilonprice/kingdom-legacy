class_name Birds
extends Node2D
## A small flock that crosses the sky every so often by day, drawn above
## everything: dark wing strokes that flap as they go.

const SPEED := 70.0

var world: WorldMap
var flock: Array = []  # of {"pos": Vector2, "off": Vector2, "phase": float}
var _dir := Vector2.RIGHT
var _timer := 8.0


func _ready() -> void:
	z_index = 20


func _process(delta: float) -> void:
	if flock.is_empty():
		_timer -= delta
		if _timer <= 0.0 and not world.is_night:
			_launch()
		return
	for b: Dictionary in flock:
		b.pos += _dir * SPEED * delta
		b.phase += delta * 9.0
	var bounds := Rect2(Vector2.ZERO, world.pixel_size()).grow(200)
	if not bounds.has_point(flock[0].pos):
		flock.clear()
		_timer = randf_range(20.0, 45.0)
	queue_redraw()


## A flock of 4-8 in a loose V, starting off one side of the camera's view.
func _launch() -> void:
	var cam := get_viewport().get_camera_2d()
	var center := cam.position if cam != null else world.pixel_size() * 0.5
	_dir = Vector2.from_angle(randf_range(-0.4, 0.4) + (PI if randf() < 0.5 else 0.0))
	var start := center - _dir * 900.0 + Vector2(0, randf_range(-300, 300))
	var n := randi_range(4, 8)
	for i in n:
		var side := 1.0 if i % 2 == 0 else -1.0
		var rank := ceilf(i / 2.0)
		var off := -_dir * rank * 14.0 + _dir.orthogonal() * side * rank * 10.0
		flock.append({"pos": start + off + Vector2(randf_range(-3, 3), randf_range(-3, 3)), "phase": randf() * TAU})


func count() -> int:
	return flock.size()


func _draw() -> void:
	for b: Dictionary in flock:
		var p: Vector2 = b.pos
		var lift := sin(b.phase) * 3.0
		var col := Color(0.12, 0.1, 0.1, 0.85)
		draw_line(p, p + Vector2(-5, -2 - lift), col, 1.5)
		draw_line(p, p + Vector2(5, -2 - lift), col, 1.5)
