class_name Enemy
extends Node2D
## A raider. Re-plans every THINK_INTERVAL: attack a nearby visible villager,
## otherwise go for its primary target by `behavior`:
##   thief   - nearest storage with goods; steals and flees off the map
##   wrecker - nearest building
##   raider  - farms and gatherers first (outlying economy)
##   siege   - walls, gates and towers first
##   support - follows the war band and heals it; never targets buildings
## Raiders path on the enemy grid, where walls and gates are passable but
## costly; when the next step is a wall or gate they stop and smash it.

enum State { ADVANCE, ATTACK, FLEE }

const THINK_INTERVAL := 0.5
const HEAL_INTERVAL := 1.0

var world: WorldMap
var enemy_id := ""
var def: Dictionary
var health: Health
var state := State.ADVANCE
var target: Node2D
var exit_tile := Vector2i.ZERO
var loot_item := ""
var loot_amount := 0
var path: Array[Vector2i] = []

var _goal_tile := WorldMap.INVALID_TILE
var _think_timer := 0.0
var _attack_timer := 0.0
var _heal_timer := 0.0
var _jitter := Vector2.ZERO
var _facing := "south"
var _anim_time := 0.0


func setup(p_world: WorldMap, id: String, spawn_tile: Vector2i, p_exit_tile: Vector2i) -> void:
	world = p_world
	enemy_id = id
	def = EnemyDefs.get_def(id)
	health = Health.new(def.hp)
	health.changed.connect(queue_redraw)
	health.died.connect(_on_died)
	exit_tile = p_exit_tile
	_jitter = Vector2(randf_range(-6, 6), randf_range(-6, 6))
	position = world.tile_center(spawn_tile) + _jitter
	_think_timer = randf() * THINK_INTERVAL


func _enter_tree() -> void:
	world.enemies.append(self)


func _exit_tree() -> void:
	world.enemies.erase(self)


func current_tile() -> Vector2i:
	return world.world_to_tile(position)


func _process(delta: float) -> void:
	_anim_time += delta
	queue_redraw()
	_attack_timer -= delta
	_think_timer -= delta
	if _think_timer <= 0.0:
		_think_timer = THINK_INTERVAL
		_think()
	if def.behavior == "support":
		_heal_timer -= delta
		if _heal_timer <= 0.0:
			_heal_timer = HEAL_INTERVAL
			_heal_allies()
	if state == State.ATTACK:
		_try_attack()
	elif not path.is_empty():
		var wall := world.fortification_at(path[0])
		if wall != null and state != State.FLEE:
			# The route runs through a wall or gate: break it down first.
			target = wall
			state = State.ATTACK
		else:
			_step(delta)
	elif state == State.FLEE:
		queue_free()  # Reached the map edge (or it's unreachable): escaped.


func _step(delta: float) -> void:
	var goal: Vector2 = world.tile_center(path[0]) + _jitter
	var to_goal := goal - position
	_facing = Art.facing(to_goal, _facing)
	var move: float = def.speed * world.speed_multiplier(current_tile()) * delta
	if to_goal.length() <= move:
		position = goal
		path.remove_at(0)
	else:
		position += to_goal.normalized() * move


func _path_to(t: Vector2i) -> void:
	if t == _goal_tile and not path.is_empty():
		return
	_goal_tile = t
	var p: Array[Vector2i] = world.find_enemy_path(current_tile(), t)
	if not p.is_empty():
		p.remove_at(0)
	path = p


# --- Decisions --------------------------------------------------------------

func _think() -> void:
	if state == State.FLEE:
		_path_to(exit_tile)
		return
	if not _target_valid():
		target = null
	# Keep smashing a wall or gate we're standing at.
	if target is Building and BuildingDefs.is_fortification(target.def) and _in_reach(target):
		state = State.ATTACK
		return
	var victim := _nearest_victim()
	if victim != null:
		target = victim
	elif target == null or not target is Building:
		target = _pick_primary_target()
	if target == null:
		_flee()
		return
	if _in_reach(target):
		state = State.ATTACK
		path.clear()
	else:
		state = State.ADVANCE
		_path_to(_target_tile(target))


func _pick_primary_target() -> Node2D:
	if def.behavior == "support":
		return _nearest_ally()
	var best: Building = null
	var best_dist := INF
	for b in world.buildings:
		if b.health.is_dead() or not _wants(b):
			continue
		var d := position.distance_squared_to(b.center())
		if d < best_dist:
			best_dist = d
			best = b
	if best == null and def.behavior in ["raider", "siege"]:
		# Nothing of their favourite kind left: fall back to anything.
		for b in world.buildings:
			var d := position.distance_squared_to(b.center())
			if not b.health.is_dead() and d < best_dist:
				best_dist = d
				best = b
	return best


func _wants(b: Building) -> bool:
	match def.behavior:
		"thief":
			return b.def.has("accepts") and not b.inventory.is_empty()
		"raider":
			return b.def.get("work", "") in ["farm", "gather"]
		"siege":
			return BuildingDefs.is_fortification(b.def) or b.def.has("damage")
	# Wreckers ignore walls unless they block the way (handled while moving).
	return not BuildingDefs.is_fortification(b.def)


## Support raiders tag along with the nearest fighting ally.
func _nearest_ally() -> Enemy:
	var best: Enemy = null
	var best_dist := INF
	for e in world.enemies:
		if e == self or e.def.behavior == "support" or e.health.is_dead():
			continue
		var d := position.distance_squared_to(e.position)
		if d < best_dist:
			best_dist = d
			best = e
	return best


func _heal_allies() -> void:
	var radius: float = def.heal_radius * Terrain.TILE_SIZE
	for e in world.enemies:
		if e != self and not e.health.is_dead() and e.position.distance_to(position) <= radius:
			e.health.heal(def.heal)


## Nearest villager or troop out in the open within aggro range.
func _nearest_victim() -> Node2D:
	var best: Node2D = null
	var best_dist: float = pow(def.aggro * Terrain.TILE_SIZE, 2)
	for group in ["troops", "villagers"]:
		for v in get_tree().get_nodes_in_group(group):
			if not v.is_targetable():
				continue
			var d := position.distance_squared_to(v.position)
			if d < best_dist:
				best_dist = d
				best = v
	return best


func _target_valid() -> bool:
	if not is_instance_valid(target) or target.health.is_dead():
		return false
	return target is Building or target is Enemy or target.is_targetable()


func _target_tile(t: Node2D) -> Vector2i:
	if t is Building:
		return t.origin if BuildingDefs.is_fortification(t.def) else t.entrance()
	return world.world_to_tile(t.position)


## Buildings are in reach from any tile touching the footprint (tile-based so
## path jitter can't leave us stranded just out of range).
func _in_reach(t: Node2D) -> bool:
	if t is Enemy:
		return position.distance_to(t.position) <= Terrain.TILE_SIZE * 1.5
	if t is Building:
		var tile := current_tile()
		var footprint := Rect2i(t.origin, t.size).grow(1)
		return footprint.has_point(tile)
	return position.distance_to(t.position) <= def.reach


func _try_attack() -> void:
	if not _target_valid() or not _in_reach(target):
		state = State.ADVANCE
		_think_timer = 0.0
		return
	if _attack_timer > 0.0:
		return
	_attack_timer = def.attack_cooldown
	if target is Enemy:
		return  # support raiders just keep close to their ally
	if def.behavior == "thief" and target is Building and not BuildingDefs.is_fortification(target.def):
		_steal()
		return
	var damage: float = def.damage
	if target is Building and BuildingDefs.is_fortification(target.def):
		damage *= def.get("wall_damage", 1.0)
	target.health.take_damage(damage)
	if target is Building and randf() < def.get("ignite_chance", 0.0):
		target.ignite()


## Grabs up to `loot` of whatever this storehouse holds most of, then runs.
func _steal() -> void:
	var store: Building = target
	var best := ""
	for item: String in store.inventory:
		if best == "" or store.inventory[item] > store.inventory[best]:
			best = item
	if best != "":
		loot_amount = world.stock.take_from(store, best, def.loot)
		loot_item = best
		GameState.notify("A goblin stole %d %s from the %s! Kill it before it escapes." % [
			loot_amount, best, store.title])
		queue_redraw()
	_flee()


func _flee() -> void:
	state = State.FLEE
	target = null
	_path_to(exit_tile)


func _on_died() -> void:
	if loot_amount > 0:
		GameState.add_resource(loot_item, loot_amount)
		GameState.notify("Recovered %d %s from a slain goblin" % [loot_amount, loot_item])
	queue_free()


func _draw() -> void:
	var r: float = def.radius
	if state == State.ATTACK and is_instance_valid(target):
		_facing = Art.facing(target.position - position, _facing)
	var top := Art.draw_character(self, enemy_id, _facing, not path.is_empty(), _anim_time)
	if is_nan(top):
		top = -r
		var body: Color = def.color
		draw_circle(Vector2(0, 1), r + 1.0, body.darkened(0.6))
		draw_circle(Vector2(0, 1), r, body)
		draw_circle(Vector2(-r * 0.35, -r * 0.2), 1.3, Color(0.95, 0.15, 0.1))
		draw_circle(Vector2(r * 0.35, -r * 0.2), 1.3, Color(0.95, 0.15, 0.1))
	if loot_item != "":
		var c := ItemDefs.color_of(loot_item)
		var box := Rect2(Vector2(r - 2, top + 10), Vector2(7, 7))
		draw_rect(box, c)
		draw_rect(box, c.darkened(0.5), false, 1.0)
	health.draw_bar(self, Vector2(0, top - 4), r * 2.5)
