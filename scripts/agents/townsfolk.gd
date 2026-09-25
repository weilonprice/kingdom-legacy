class_name Townsfolk
extends Node2D
## Life around town that isn't part of the economy (see TownLife): children
## playing and chasing each other near their homes, townsfolk with baskets
## going between homes and the market, well, tavern and chapel and chatting
## when they meet, and dogs trotting after villagers. Everyone goes indoors
## at night and when raiders are about.

const SPEEDS := {"child": 52.0, "shopper": 30.0, "dog": 58.0}
## Seconds a chat bubble shows.
const CHAT_TIME := 2.5

var world: WorldMap
var life: TownLife
## "child", "shopper" or "dog"; also the art folder (child, townswoman, dog).
var kind := "child"
var home: Building
var look := "child"

var path: Array[Vector2i] = []
var _pause := 1.0
var _facing := "south"
var _anim_time := 0.0
var _follow: Node2D
var _follow_time := 0.0
var _chat := 0.0
var _loitering := false


func setup(p_world: WorldMap, p_life: TownLife, p_kind: String, p_home: Building) -> void:
	world = p_world
	life = p_life
	add_to_group("townsfolk")
	kind = p_kind
	home = p_home
	look = {"child": "child", "shopper": "townswoman", "dog": "dog"}[kind]
	position = world.tile_center(_home_tile()) + Vector2(randf_range(-8, 8), randf_range(-6, 6))
	_pause = randf_range(0.0, 3.0)


func is_chatting() -> bool:
	return _chat > 0.0


func is_loitering() -> bool:
	return _loitering and path.is_empty()


func _home_tile() -> Vector2i:
	return home.entrance() if is_instance_valid(home) else world.keep.entrance()


func _process(delta: float) -> void:
	_anim_time += delta
	_chat = maxf(_chat - delta, 0.0)
	var indoors := world.is_night or world.raid_active
	if indoors:
		if visible:
			visible = false
			path.clear()
			position = world.tile_center(_home_tile())
		return
	visible = true
	queue_redraw()
	if kind == "dog" and _follow_dog(delta):
		return
	if not path.is_empty():
		_step(delta)
		return
	_pause -= delta
	if _loitering and _chat <= 0.0 and randf() < delta * 0.5 and life.someone_near(self, 64.0):
		_chat = CHAT_TIME
	if _pause <= 0.0:
		_next()


func _step(delta: float) -> void:
	var goal := world.tile_center(path[0])
	var to_goal := goal - position
	_facing = Art.facing(to_goal, _facing)
	var move: float = SPEEDS[kind] * world.speed_multiplier(world.world_to_tile(position)) * delta
	if to_goal.length() <= move:
		position = goal
		path.remove_at(0)
	else:
		position += to_goal.normalized() * move


func _next() -> void:
	_loitering = false
	match kind:
		"child":
			# Chase a playmate now and then, otherwise run somewhere near home.
			var mate := life.nearby(self, "child", 8.0 * Terrain.TILE_SIZE)
			if mate != null and randf() < 0.5:
				_go(world.world_to_tile(mate.position))
			else:
				_go(_home_tile() + Vector2i(randi_range(-5, 5), randi_range(-4, 4)))
			_pause = randf_range(0.5, 2.5)
		"shopper":
			var spot := life.gathering_spot(self)
			if spot != WorldMap.INVALID_TILE and randf() < 0.75:
				_go(spot + Vector2i(randi_range(-2, 2), randi_range(0, 2)))
				_loitering = true
				_pause = randf_range(6.0, 14.0)
			else:
				_go(_home_tile())
				_pause = randf_range(3.0, 8.0)
		"dog":
			_go(_home_tile() + Vector2i(randi_range(-4, 4), randi_range(-4, 4)))
			_pause = randf_range(1.0, 4.0)


func _go(t: Vector2i) -> void:
	if not world.is_walkable(t):
		t = world.nearest_walkable(t, 2)
		if t == WorldMap.INVALID_TILE:
			return
	var p: Array[Vector2i] = world.find_path(world.world_to_tile(position), t)
	if p.size() > 1:
		p.remove_at(0)
		path = p


## Dogs tag along behind a villager for a while. True while following.
func _follow_dog(delta: float) -> bool:
	_follow_time -= delta
	if _follow_time <= 0.0 or not is_instance_valid(_follow) or not _follow.visible:
		_follow = life.villager_near(position, 10.0 * Terrain.TILE_SIZE) if randf() < 0.7 else null
		_follow_time = randf_range(15.0, 35.0)
	if _follow == null:
		return false
	var goal := _follow.position + Vector2(-12, 6)
	var to_goal := goal - position
	if to_goal.length() > 6.0:
		_facing = Art.facing(to_goal, _facing)
		position += to_goal.normalized() * minf(SPEEDS.dog * delta, to_goal.length())
		path.clear()
	return true


func _draw() -> void:
	var moving := not path.is_empty() or (kind == "dog" and is_instance_valid(_follow)
		and _follow.position.distance_to(position) > 14.0)
	var s: float = {"child": 0.55, "shopper": 0.72, "dog": 0.75}[kind]
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(s, s))
	var top := Art.draw_character_anim(self, look, _facing, "walk" if moving else "idle", _anim_time)
	draw_set_transform(Vector2.ZERO)
	if is_nan(top):
		var c: Color = {"child": Color(0.8, 0.6, 0.4), "shopper": Color(0.3, 0.55, 0.35), "dog": Color(0.55, 0.4, 0.25)}[kind]
		draw_circle(Vector2(0, 2), 3.5 if kind != "shopper" else 4.5, c)
		top = -6.0
	if _chat > 0.0:
		_draw_bubble(Vector2(4, top * s - 4))


## A small speech bubble with three dots.
func _draw_bubble(at: Vector2) -> void:
	var r := Rect2(at + Vector2(-2, -9), Vector2(13, 8))
	draw_rect(r, Color(1, 0.98, 0.9, 0.95))
	draw_rect(r, Color(0.25, 0.18, 0.1), false, 1.0)
	draw_colored_polygon(PackedVector2Array([r.position + Vector2(2, 8), r.position + Vector2(6, 8),
		r.position + Vector2(1, 11)]), Color(1, 0.98, 0.9, 0.95))
	for i in 3:
		var dot_on := int(_anim_time * 3.0) % 4 > i
		if dot_on:
			draw_rect(Rect2(r.position + Vector2(2 + i * 4, 3), Vector2(2, 2)), Color(0.25, 0.18, 0.1))
