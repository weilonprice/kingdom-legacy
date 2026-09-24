class_name RoyalAgent
extends Node2D
## A member of the royal family on the map: strolls between spots around
## the castle grounds, pausing now and then; goes inside at night and while
## raiders are about. Drawn with its own character art (king, queen, heir).

const SPEED := 28.0

var world: WorldMap
## Character art folder under assets/sprites.
var look := "king"
var role := ""
var tooltip := ""

var path: Array[Vector2i] = []
var _pause := 1.0
var _facing := "south"
var _anim_time := 0.0


func setup(p_world: WorldMap, p_look: String) -> void:
	world = p_world
	look = p_look
	position = world.tile_center(world.keep.entrance())
	z_index = 0


func _process(delta: float) -> void:
	_anim_time += delta
	var indoors := world.is_night or world.raid_active
	visible = not indoors
	if indoors:
		path.clear()
		position = world.tile_center(world.keep.entrance())
		return
	queue_redraw()
	if not path.is_empty():
		var goal := world.tile_center(path[0])
		var to_goal := goal - position
		_facing = Art.facing(to_goal, _facing)
		var move := SPEED * delta
		if to_goal.length() <= move:
			position = goal
			path.remove_at(0)
			if path.is_empty():
				_pause = randf_range(2.0, 6.0)
		else:
			position += to_goal.normalized() * move
		return
	_pause -= delta
	if _pause <= 0.0:
		_pause = 2.0
		var spot := _stroll_spot()
		if spot != WorldMap.INVALID_TILE:
			var p: Array[Vector2i] = world.find_path(world.world_to_tile(position), spot)
			if not p.is_empty():
				p.remove_at(0)
				path = p


## A walkable tile around the castle: inside its grounds or just outside.
func _stroll_spot() -> Vector2i:
	var area := world.castle_grounds.grow(3)
	for i in 12:
		var t := Vector2i(randi_range(area.position.x, area.end.x - 1), randi_range(area.position.y, area.end.y - 1))
		if world.is_walkable(t):
			return t
	return WorldMap.INVALID_TILE


func _draw() -> void:
	# The royal art is drawn on a bigger canvas than the villagers': scale it
	# so adults stand a little taller than villagers and the heir is a child.
	var s := 0.55 if look == "heir" else 0.72
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(s, s))
	var top := Art.draw_character_anim(self, look, _facing, "walk" if not path.is_empty() else "", _anim_time)
	draw_set_transform(Vector2.ZERO)
	if is_nan(top):
		# No art yet: a small figure with a gold crown.
		draw_circle(Vector2(0, 3), 5.0, Color(0.5, 0.15, 0.6))
		draw_circle(Vector2(0, -4), 3.0, Color(0.96, 0.8, 0.65))
		draw_rect(Rect2(-3, -9, 6, 2), Color(1.0, 0.8, 0.2))
