class_name Animal
extends Node2D
## Farm animals (see TownLife): chickens scratching about a farm, sheep and
## cows grazing on the grass beside it. They amble within a few tiles of
## their farm, pause to peck or graze (a little bob of the head) and face
## the way they walk. Art: assets/sprites/animals/<kind>.png, facing right.

const SPEEDS := {"chicken": 22.0, "sheep": 10.0, "cow": 8.0}
const ART := "res://assets/sprites/animals/%s.png"

var world: WorldMap
var kind := "chicken"
var farm: Building

var _goal := Vector2.ZERO
var _pause := 0.0
var _flip := false
var _peck := 0.0
var _time := 0.0


func setup(p_world: WorldMap, p_kind: String, p_farm: Building, start: Vector2) -> void:
	world = p_world
	kind = p_kind
	farm = p_farm
	position = start
	_goal = start
	_pause = randf_range(0.0, 4.0)


func _process(delta: float) -> void:
	if not is_instance_valid(farm):
		queue_free()
		return
	_time += delta
	_peck = maxf(_peck - delta, 0.0)
	var to_goal := _goal - position
	if to_goal.length() > 1.0:
		var step := minf(SPEEDS[kind] * delta, to_goal.length())
		position += to_goal.normalized() * step
		if absf(to_goal.x) > 0.5:
			_flip = to_goal.x < 0.0
		queue_redraw()
		return
	_pause -= delta
	if _pause <= 0.0:
		_pick_goal()
	elif _peck <= 0.0 and randf() < delta * (1.2 if kind == "chicken" else 0.3):
		_peck = 0.5 if kind == "chicken" else 1.5
		queue_redraw()
	elif _peck > 0.0:
		queue_redraw()


func _pick_goal() -> void:
	_pause = randf_range(1.5, 5.0) if kind == "chicken" else randf_range(4.0, 12.0)
	var radius := 3 if kind == "chicken" else 5
	var base := farm.entrance()
	for i in 6:
		var t := base + Vector2i(randi_range(-radius, radius), randi_range(-radius - 1, radius))
		if world.is_walkable(t) and not world.roads.has(t) and (kind == "chicken" or world.get_terrain(t) == Terrain.GRASS):
			_goal = world.tile_center(t) + Vector2(randf_range(-10, 10), randf_range(-8, 8))
			return


func _draw() -> void:
	var tex := Art.texture(ART % kind)
	var bob := 1.0 if _peck > 0.0 and int(_time * 6.0) % 2 == 0 else 0.0
	if tex != null:
		var size := Vector2(tex.get_size())
		draw_set_transform(Vector2(0, bob), 0.0, Vector2(-1.0 if _flip else 1.0, 1.0))
		draw_texture(tex, Vector2(-size.x * 0.5, -size.y * 0.8))
		draw_set_transform(Vector2.ZERO)
		return
	var c: Color = {"chicken": Color(0.95, 0.95, 0.9), "sheep": Color(0.92, 0.92, 0.88), "cow": Color(0.55, 0.38, 0.25)}[kind]
	draw_circle(Vector2(0, bob), {"chicken": 3.0, "sheep": 5.0, "cow": 7.0}[kind], c)
