class_name MerchantAgent
extends Node2D
## The travelling merchant walking to the Trading Post and away again.
## Purely visual (raiders ignore it; merchants leave before raids).

signal reached

const SPEED := 60.0

var world: WorldMap
var path: Array[Vector2i] = []
var _leaving := false
var _facing := "south"
var _anim := 0.0


func setup(p_world: WorldMap, from: Vector2i, to: Vector2i) -> void:
	world = p_world
	position = world.tile_center(from)
	path = world.find_path(from, to)


func go_away(to: Vector2i) -> void:
	_leaving = true
	if to == WorldMap.INVALID_TILE:
		queue_free()
		return
	path = world.find_path(world.world_to_tile(position), to)
	if path.is_empty():
		queue_free()


func _process(delta: float) -> void:
	_anim += delta
	queue_redraw()
	if path.is_empty():
		if _leaving:
			queue_free()
		return
	var goal := world.tile_center(path[0])
	var to_goal := goal - position
	_facing = Art.facing(to_goal, _facing)
	var move := SPEED * world.speed_multiplier(world.world_to_tile(position)) * delta
	if to_goal.length() <= move:
		position = goal
		path.remove_at(0)
		if path.is_empty() and not _leaving:
			reached.emit()
	else:
		position += to_goal.normalized() * move


func _draw() -> void:
	var top := Art.draw_character(self, "merchant", _facing, not path.is_empty(), _anim)
	if is_nan(top):
		draw_circle(Vector2(0, 2), 6.0, Color(0.25, 0.45, 0.25))
		draw_circle(Vector2(0, -5), 3.5, Color(0.96, 0.8, 0.65))
		draw_rect(Rect2(Vector2(-7, -2), Vector2(6, 8)), Color(0.55, 0.35, 0.2))
