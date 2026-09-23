class_name Enemy
extends Node2D
## A raider. Re-plans every THINK_INTERVAL: attack a nearby visible villager,
## otherwise go for its primary target by `behavior`:
##   thief   - nearest storage with goods; steals and flees off the map
##   wrecker - nearest building
##   raider  - farms and gatherers first (outlying economy)
##   siege   - walls, gates and towers first
##   support - follows the war band and heals it; never targets buildings
##   lair    - a den in the wilds: never moves, sends guards at nearby troops
##   dragon  - the final boss: flies over everything, breathes fire, lands
##             now and then (see EnemyDefs)
## Lairs and their guards are "wild": they live in world.wild instead of
## world.enemies, so they don't count as raiders. Guards keep to `guard_post`
## unless a troop or villager comes within aggro range.
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
var wild := false
var guard_post := WorldMap.INVALID_TILE
## Lairs: the guards they have sent out.
var guards: Array[Enemy] = []
## Dragon state.
var _airborne := true
var _phase_timer := 0.0
var _summoned := false
var _enraged := false
var _altitude := 36.0
var _heading := Vector2.DOWN
var _breath_time := 0.0
var _breath_at := Vector2.ZERO

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
	(world.wild if wild else world.enemies).append(self)


func _exit_tree() -> void:
	(world.wild if wild else world.enemies).erase(self)


func is_lair() -> bool:
	return def.behavior == "lair"


## Where arrows should fly: the dragon's body rides above its shadow.
func aim_point() -> Vector2:
	return position + Vector2(0, -_altitude) if def.behavior == "dragon" else position


## Airborne raiders can only be hit by arrows (towers, archers).
func is_flying() -> bool:
	return def.get("flying", false) and _airborne


func current_tile() -> Vector2i:
	return world.world_to_tile(position)


func _process(delta: float) -> void:
	_anim_time += delta
	queue_redraw()
	_attack_timer -= delta
	_think_timer -= delta
	if def.behavior == "dragon":
		_dragon_process(delta)
		return
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
	if is_lair():
		_lair_think()
		return
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
	elif guard_post != WorldMap.INVALID_TILE:
		# Lair guards return to the den when nobody is close.
		target = null
		state = State.ADVANCE
		_path_to(guard_post)
		return
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


## Sends out a guard at a time while troops are near, up to `guards` alive.
func _lair_think() -> void:
	guards.assign(guards.filter(func(g: Variant) -> bool: return is_instance_valid(g) and not g.health.is_dead()))
	_heal_timer -= THINK_INTERVAL
	if _heal_timer > 0.0 or guards.size() >= int(def.guards):
		return
	var radius: float = def.guard_radius * Terrain.TILE_SIZE
	var threatened := get_tree().get_nodes_in_group("troops").any(
		func(t: Troop) -> bool: return t.is_targetable() and t.position.distance_to(position) <= radius)
	if not threatened:
		return
	_heal_timer = def.guard_interval
	var tile := world.nearest_walkable(current_tile() + Vector2i(randi_range(-1, 1), 2))
	if tile == WorldMap.INVALID_TILE:
		return
	var g := Enemy.new()
	g.wild = true
	g.guard_post = tile
	g.setup(world, def.guard, tile, tile)
	g.def = g.def.duplicate()
	g.def.aggro = def.guard_radius
	world.unit_root.add_child(g)
	guards.append(g)


# --- Dragon -----------------------------------------------------------------

func _dragon_process(delta: float) -> void:
	if _phase_timer == 0.0:
		_phase_timer = def.land_every
		z_index = 20
	_phase_timer -= delta
	_breath_time = maxf(_breath_time - delta, 0.0)
	_altitude = move_toward(_altitude, 36.0 if _airborne else 4.0, 40.0 * delta)
	if _phase_timer <= 0.0:
		_airborne = not _airborne
		_phase_timer = def.land_every if _airborne else def.land_for
		GameState.notify("The Dragon takes to the air again." if _airborne
			else "The Dragon lands to rest. Strike it now!")
	var ratio := health.hp / health.max_hp
	if not _summoned and ratio <= def.summon_at:
		_summoned = true
		_summon()
	if not _enraged and ratio <= def.enrage_at:
		_enraged = true
		GameState.notify("The Dragon is enraged!")
	if not _airborne:
		return
	if _think_timer <= 0.0:
		_think_timer = 1.0
		target = _dragon_target()
	if not _target_valid():
		target = _dragon_target()
		if target == null:
			return
	var goal: Vector2 = target.center()
	var to_goal := goal - position
	if to_goal.length() > 6.0:
		_heading = to_goal.normalized()
		var speed: float = def.speed * (1.3 if _enraged else 1.0)
		position += to_goal.limit_length(speed * delta)
	if to_goal.length() <= Terrain.TILE_SIZE * 2.0 and _attack_timer <= 0.0:
		_attack_timer = def.attack_cooldown * (0.6 if _enraged else 1.0)
		_breathe(goal)


## The nearest standing building that isn't a wall; the Keep if none.
func _dragon_target() -> Building:
	var best: Building = null
	var best_dist := INF
	for b in world.buildings:
		if b.health.is_dead() or BuildingDefs.is_fortification(b.def):
			continue
		var d := position.distance_squared_to(b.center())
		if d < best_dist:
			best_dist = d
			best = b
	return best if best != null else world.keep


func _breathe(at: Vector2) -> void:
	_breath_at = at
	_breath_time = 0.5
	var radius: float = def.breath_radius * Terrain.TILE_SIZE
	for b in world.buildings.duplicate():
		if b.health.is_dead():
			continue
		var r := Rect2(b.position, Vector2(b.size * Terrain.TILE_SIZE)).grow(radius)
		if r.has_point(at):
			b.health.take_damage(def.damage)
			if randf() < def.ignite_chance:
				b.ignite()
	for group in ["troops", "villagers"]:
		for v in get_tree().get_nodes_in_group(group):
			if v.is_targetable() and v.position.distance_to(at) <= radius:
				v.health.take_damage(def.damage * 0.5)


func _summon() -> void:
	GameState.notify("The Dragon roars, and its horde answers!")
	for id: String in def.summon:
		for i in int(def.summon[id]):
			var tile := world.nearest_walkable(current_tile() + Vector2i(randi_range(-2, 2), randi_range(-2, 2)))
			if tile == WorldMap.INVALID_TILE:
				continue
			var e := Enemy.new()
			e.setup(world, id, tile, exit_tile)
			world.unit_root.add_child(e)


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
		for v: Node2D in get_tree().get_nodes_in_group(group):
			# Distance first: it's cheap, and most are far away.
			var d := position.distance_squared_to(v.position)
			if d < best_dist and v.is_targetable():
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
	if def.behavior == "dragon":
		GameState.notify("The Dragon is slain!")
	if is_lair():
		GameState.add_resource("gold", def.bounty)
		GameState.notify("The %s is destroyed! +%d gold. Raids will be smaller." % [def.name, def.bounty])
	if loot_amount > 0:
		GameState.add_resource(loot_item, loot_amount)
		GameState.notify("Recovered %d %s from a slain goblin" % [loot_amount, loot_item])
	queue_free()


const DRAGON_ART := "res://assets/sprites/dragon/dragon.png"


func _draw_dragon() -> void:
	# Shadow on the ground; the body rides above it, turned to its heading.
	var shadow := 1.0 - _altitude / 90.0
	draw_set_transform(Vector2(0, 4), 0.0, Vector2(1.0, 0.45))
	draw_circle(Vector2.ZERO, 34.0 * shadow, Color(0, 0, 0, 0.28))
	var flap := 1.0 + (0.05 * sin(_anim_time * 6.0) if _airborne else 0.0)
	draw_set_transform(Vector2(0, -_altitude), _heading.angle() + PI * 0.5, Vector2(flap, 1.0))
	var tex := Art.texture(DRAGON_ART)
	if tex != null:
		draw_texture(tex, -Vector2(tex.get_size()) * 0.5)
	else:
		var c: Color = def.color
		draw_colored_polygon(PackedVector2Array([Vector2(0, -30), Vector2(40, 10), Vector2(0, 0), Vector2(-40, 10)]), c)
		draw_circle(Vector2(0, -26), 8, c.darkened(0.3))
		draw_line(Vector2(0, 0), Vector2(0, 36), c, 6.0)
	draw_set_transform(Vector2.ZERO)
	if _breath_time > 0.0:
		var to := _breath_at - position
		var from := Vector2(0, -_altitude) + _heading * 40.0
		var a := _breath_time / 0.5
		draw_line(from, to, Color(1.0, 0.55, 0.1, a), 10.0)
		draw_line(from, to, Color(1.0, 0.9, 0.4, a), 4.0)
		draw_circle(to, def.breath_radius * Terrain.TILE_SIZE * 0.6, Color(1.0, 0.45, 0.1, a * 0.5))
	health.draw_bar(self, Vector2(0, -_altitude - 72), 96)


func _draw() -> void:
	if def.behavior == "dragon":
		_draw_dragon()
		return
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
