class_name Troop
extends Node2D
## A soldier in a squad. Every THINK_INTERVAL it picks the raider to fight
## (the squad's focus target, or the nearest one within the squad's engage
## radius and leash), otherwise returns to its formation slot at the anchor.

signal died(troop: Troop)

const THINK_INTERVAL := 0.3
const HEAL_PER_SECOND := 3.0
const HEAL_RANGE_TILES := 3

var world: WorldMap
var unit_id := ""
var def: Dictionary
var health: Health
var squad: Squad
var slot := 0
var path: Array[Vector2i] = []
var target: Enemy

var _goal_tile := WorldMap.INVALID_TILE
var _think_timer := 0.0
var _attack_timer := 0.0
var _facing := "south"
var _anim_time := 0.0


func setup(p_world: WorldMap, id: String, p_squad: Squad, spawn_tile: Vector2i) -> void:
	world = p_world
	unit_id = id
	def = UnitDefs.get_def(id)
	squad = p_squad
	health = Health.new(def.hp)
	health.changed.connect(queue_redraw)
	health.died.connect(func() -> void: died.emit(self))
	position = world.tile_center(spawn_tile)
	add_to_group("troops")
	_think_timer = randf() * THINK_INTERVAL


func is_targetable() -> bool:
	return not health.is_dead()


func current_tile() -> Vector2i:
	return world.world_to_tile(position)


func is_ranged() -> bool:
	return def.has("range")


func attack_distance() -> float:
	if is_ranged():
		return (def.range + GameState.mod("archer_range", 0.0)) * Terrain.TILE_SIZE
	return def.reach


func _process(delta: float) -> void:
	_anim_time += delta
	queue_redraw()
	_attack_timer -= delta
	_think_timer -= delta
	if _think_timer <= 0.0:
		_think_timer = THINK_INTERVAL
		_think()
	if target != null and is_instance_valid(target) and _in_range(target):
		path.clear()
		_attack()
	elif not path.is_empty():
		_step(delta)
	elif target == null:
		_settle_into_slot(delta)
		_heal_near_barracks(delta)


func _think() -> void:
	target = _choose_target()
	if target != null:
		if not _in_range(target):
			_path_to(target.current_tile())
	else:
		_path_to(squad.anchor_tile())


func _choose_target() -> Enemy:
	var anchor_pos := world.tile_center(squad.anchor_tile())
	var focus: Enemy = squad.focus
	if focus != null and (not is_instance_valid(focus) or focus.health.is_dead()):
		focus = null
	if focus != null and not focus.is_lair():
		return focus
	# Keep fighting the current target while it's still a threat or within the leash.
	if target != null and is_instance_valid(target) and not target.health.is_dead() and not target.is_lair() \
			and (squad.is_threat(target, world)
				or target.position.distance_to(anchor_pos) <= Squad.LEASH_TILES * Terrain.TILE_SIZE):
		return target
	var best: Enemy = null
	var best_dist := INF
	for e in world.hostiles():
		if e.is_lair() or not squad.is_threat(e, world):
			continue
		var d := position.distance_squared_to(e.position)
		if e.is_flying() and not is_ranged():
			d *= 9.0  # can't reach it in the air: prefer anything on the ground
		if d < best_dist:
			best_dist = d
			best = e
	# Assaulting a lair: fight off its guards first, then hit the den.
	return best if best != null else focus


func _in_range(e: Enemy) -> bool:
	if e.is_flying() and not is_ranged():
		return false
	var extra: float = e.def.radius if e.is_lair() else 0.0
	return position.distance_to(e.position) <= attack_distance() + extra


func _attack() -> void:
	if _attack_timer > 0.0:
		return
	_attack_timer = def.attack_cooldown
	var damage: float = def.damage * GameState.mod("troop_damage")
	if target.def.get("large", false):
		damage *= def.get("large_bonus", 1.0)
	if is_ranged():
		var arrow := Projectile.new()
		arrow.setup(position + Vector2(0, -6), target, damage)
		world.unit_root.add_child(arrow)
	else:
		target.health.take_damage(damage)
		Sound.play("hit", position)


func _path_to(t: Vector2i) -> void:
	if not world.is_walkable(t):
		t = world.nearest_walkable(t)
		if t == WorldMap.INVALID_TILE:
			return
	if t == _goal_tile and not path.is_empty():
		return
	_goal_tile = t
	var p: Array[Vector2i] = world.find_path(current_tile(), t)
	if not p.is_empty():
		p.remove_at(0)
	path = p


func _step(delta: float) -> void:
	var goal: Vector2 = world.tile_center(path[0])
	var to_goal := goal - position
	_facing = Art.facing(to_goal, _facing)
	var move: float = def.speed * world.speed_multiplier(current_tile()) * delta
	if to_goal.length() <= move:
		position = goal
		path.remove_at(0)
	else:
		position += to_goal.normalized() * move


## Nudge from the anchor tile center into this troop's formation slot.
func _settle_into_slot(delta: float) -> void:
	var goal: Vector2 = world.tile_center(squad.anchor_tile()) + squad.slot_offset(slot)
	var to_goal := goal - position
	if to_goal.length() > 1.0 and to_goal.length() < Terrain.TILE_SIZE * 1.5:
		position += to_goal.limit_length(def.speed * 0.5 * delta)


func _heal_near_barracks(delta: float) -> void:
	if not health.is_damaged() or squad.barracks == null or not is_instance_valid(squad.barracks):
		return
	if position.distance_to(squad.barracks.center()) <= HEAL_RANGE_TILES * Terrain.TILE_SIZE:
		health.heal(HEAL_PER_SECOND * delta)


func _draw() -> void:
	if squad.selected:
		draw_arc(Vector2(0, 1), 9.0, 0, TAU, 20, Color(0.4, 1.0, 0.4), 1.5)
	if target != null and is_instance_valid(target) and path.is_empty():
		_facing = Art.facing(target.position - position, _facing)
	var top := Art.draw_character(self, unit_id, _facing, not path.is_empty(), _anim_time)
	if not is_nan(top):
		health.draw_bar(self, Vector2(0, top - 4), 14)
		return
	var body: Color = def.color
	draw_circle(Vector2(0, 3), 5.5, body.darkened(0.6))
	draw_circle(Vector2(0, 3), 4.5, body)
	draw_circle(Vector2(0, -4), 3.2, Color(0.75, 0.75, 0.78))  # helmet
	match unit_id:
		"spearman":
			draw_line(Vector2(6, 8), Vector2(6, -10), Color(0.45, 0.32, 0.18), 1.5)
			draw_line(Vector2(6, -10), Vector2(6, -13), Color(0.85, 0.85, 0.9), 2.0)
		"archer":
			draw_arc(Vector2(5, 1), 6.0, -PI * 0.45, PI * 0.45, 8, Color(0.5, 0.35, 0.18), 1.5)
		_:
			draw_line(Vector2(5, 6), Vector2(8, -4), Color(0.55, 0.40, 0.22), 2.0)
	health.draw_bar(self, Vector2(0, -12), 14)
