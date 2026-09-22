class_name Projectile
extends Node2D
## An arrow that homes in on its target and deals damage on arrival.

const SPEED := 320.0

var target: Node2D
var damage := 0.0

var _last_target_pos := Vector2.ZERO


func setup(from: Vector2, p_target: Node2D, p_damage: float) -> void:
	position = from
	target = p_target
	damage = p_damage
	_last_target_pos = target.position


func _process(delta: float) -> void:
	if is_instance_valid(target):
		_last_target_pos = target.position
	var to_target := _last_target_pos - position
	var step := SPEED * delta
	if to_target.length() <= step:
		if is_instance_valid(target) and not target.health.is_dead():
			target.health.take_damage(damage)
		queue_free()
		return
	position += to_target.normalized() * step
	rotation = to_target.angle()


func _draw() -> void:
	draw_line(Vector2(-7, 0), Vector2(4, 0), Color(0.35, 0.25, 0.15), 2.0)
	draw_line(Vector2(4, 0), Vector2(0, -2), Color(0.8, 0.8, 0.8), 1.5)
	draw_line(Vector2(4, 0), Vector2(0, 2), Color(0.8, 0.8, 0.8), 1.5)
