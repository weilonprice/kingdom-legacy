class_name Villager
extends Node2D
## A citizen agent. Lives in `home`, works at `job`, and physically walks
## goods between resource tiles, workplaces and storage buildings.
##
## Work loops by the job's `work` type:
##   gather:  go to resource tile -> work -> drop at the workplace's pile
##   farm:    go to ripe field -> harvest -> drop wheat at the farm's pile
##            (or go to tilled field -> plant)
##   forester: go to open ground -> plant a sapling
##   build:   (castle builders) fetch a missing material from storage ->
##            carry it to the castle; once all is there, work on the site
##   produce: use delivered input (or fetch it from the nearest storage or
##            workplace pile) -> work -> drop output at the pile
##   haul:    empty the fullest workplace pile into storage, or deliver
##            inputs to producers
##   guard / study / service: walk to the building and stay inside
## When a workplace pile is full its own worker carries a load to storage.
## At night villagers (except those working inside) finish their delivery and
## sleep at home; during a raid they hide when raiders come close, or, under
## a Call to Arms, grab a pitchfork and fight them.

signal died(villager: Villager)

enum State {
	IDLE, WANDER, TO_TARGET, WORKING, TO_DEPOSIT, TO_FETCH, TO_WORKPLACE, TO_DROP,
	TO_PICKUP, TO_SUPPLY, TO_SHELTER, HIDING, TO_POST, STATIONED, TO_BED, SLEEPING,
	FIGHTING,
}
enum Task { NONE, GATHER, PLANT, HARVEST, PRODUCE, PLANT_TREE, BUILD }

const SPEED := 42.0
const COLOR_UNEMPLOYED := Color(0.87, 0.75, 0.55)
const COLOR_SKIN := Color(0.96, 0.80, 0.65)
const MAX_HP := 20.0
## Villagers run for shelter when raiders come this close, and come back out
## once none are within SAFE_TILES.
const DANGER_TILES := 10
const SAFE_TILES := 14
const DANGER_CHECK_INTERVAL := 0.4
## Call to Arms: pitchfork damage per strike, strike interval, reach (px).
const MILITIA_DAMAGE := 6.0
const MILITIA_COOLDOWN := 1.0
const MILITIA_REACH := 20.0
## Armed villagers toughen up to this many HP (back to MAX_HP afterwards).
const MILITIA_HP := 40.0
## Wounded villagers stop fighting and hide below this share of their HP.
const MILITIA_RETREAT := 0.4
## Most goods one villager carries in a single trip.
const HAUL_LOAD := 8
## Haulers only bother with piles at least this big.
const HAUL_MIN := 4
const NAMES := [
	"Aldric", "Bertram", "Cedric", "Edda", "Elspeth", "Godwin", "Hilda", "Isolde",
	"Jocelyn", "Leofric", "Maud", "Osric", "Rowena", "Sigrid", "Tamsin", "Ulric",
	"Wilfred", "Agnes", "Beatrix", "Cuthbert", "Emmeline", "Gareth", "Ingrid", "Oswin",
]

var world: WorldMap
var home: Building
var job: Building
var villager_name := ""
var state := State.IDLE
var task := Task.NONE
var timer := 0.0
var path: Array[Vector2i] = []
var carrying := ""
var carry_amount := 0
var missed_meals := 0
var health := Health.new(MAX_HP)
## What this villager is doing, shown in the building inspector.
var note := "Settling in"

var _jitter := Vector2.ZERO
var _target_tile := WorldMap.INVALID_TILE
## Building the current trip is headed to (storage, source, or supply target).
var _dest: Building
## Haulers: the producer being supplied.
var _supply_target: Building
## Castle builders: the material this builder promised to bring {item, amount}.
var _castle_claim := {}
var _danger_timer := 0.0
var _foe: Enemy
var _sound_timer := 0.0
var _strike_timer := 0.0
var _facing := "south"
var _moving := false
var _anim_time := 0.0
## A one-off animation (picking up, putting down) and how long the villager
## stands still for it.
var _once := ""
var _once_time := 0.0
var _hold := 0.0


func setup(p_world: WorldMap, p_home: Building) -> void:
	world = p_world
	home = p_home
	villager_name = NAMES.pick_random()
	add_to_group("villagers")
	health.changed.connect(queue_redraw)
	health.died.connect(func() -> void: died.emit(self))
	_jitter = Vector2(randf_range(-7, 7), randf_range(-7, 7))
	position = world.tile_center(home.entrance()) + _jitter
	timer = randf()


func current_tile() -> Vector2i:
	return world.world_to_tile(position)


## Raiders can only attack villagers who are out in the open.
func is_targetable() -> bool:
	return visible and not health.is_dead()


func is_guard() -> bool:
	return job != null and job.def.get("work", "") == "guard"


## Guards, scholars and service workers work from inside their building: they
## don't flee raids or go home at night.
func works_inside() -> bool:
	return job != null and job.def.get("work", "") in ["guard", "study", "service"]


func set_job(building: Building) -> void:
	job = building
	job.workers.append(self)
	_reset()


func lose_job() -> void:
	_drop_castle_claim()
	if job != null:
		job.workers.erase(self)
		job = null
	_reset()


func _exit_tree() -> void:
	_release_claims()
	_drop_castle_claim()


## Drops the current plan. Anything carried is kept and taken to storage.
func _reset() -> void:
	path.clear()
	_release_claims()
	state = State.IDLE
	task = Task.NONE
	timer = 0.5
	visible = true
	if carrying == "":
		carry_amount = 0
	queue_redraw()


func _release_claims() -> void:
	if _target_tile != WorldMap.INVALID_TILE:
		world.release(_target_tile, self)
		_target_tile = WorldMap.INVALID_TILE
	if is_instance_valid(_dest) and _dest.pickup_claim == self:
		_dest.pickup_claim = null
	if is_instance_valid(_supply_target) and _supply_target.supply_claim == self:
		_supply_target.supply_claim = null
	_supply_target = null


func _claim(t: Vector2i) -> void:
	world.reserve(t, self)
	_target_tile = t


func _wait(reason: String, seconds := 2.0) -> void:
	note = reason
	state = State.IDLE
	timer = seconds


func _process(delta: float) -> void:
	_anim_time += delta
	_once_time += delta
	_moving = not path.is_empty()
	if visible:
		queue_redraw()
	_danger_timer -= delta
	if _danger_timer <= 0.0:
		_danger_timer = DANGER_CHECK_INTERVAL
		_update_raid_response()
	if _hold > 0.0:
		_hold -= delta
		if _hold <= 0.0:
			_once = ""
		return
	if not path.is_empty():
		_step(delta)
		return
	match state:
		State.HIDING, State.STATIONED:
			pass
		State.FIGHTING:
			_fight(delta)
		State.SLEEPING:
			if not world.is_night:
				visible = true
				_wait("Waking up", randf_range(0.2, 2.0))
		State.IDLE:
			timer -= delta
			if timer <= 0.0:
				_think()
		State.WORKING:
			_work_sound(delta)
			timer -= delta
			if timer <= 0.0:
				_finish_work()
		_:
			_arrive()


## Plays a one-off animation and stands still for it.
func _play_once(anim: String, hold := 0.45) -> void:
	_once = anim
	_once_time = 0.0
	_hold = hold


## What the villager's body is doing right now.
func current_anim() -> String:
	if _once != "":
		return _once
	if _moving:
		return "carry" if carrying != "" else "walk"
	if state == State.WORKING:
		match task:
			Task.GATHER:
				match job.def.get("resource", "") if job != null else "":
					"wood":
						return "chop"
					"stone", "iron":
						return "mine"
				return "idle"
			Task.PLANT, Task.HARVEST, Task.PLANT_TREE:
				return "farm"
			Task.BUILD:
				return "hammer"
			Task.PRODUCE:
				return "hammer" if job != null and job.def_id in ["smithy", "armory"] else "idle"
	return "idle"


func _step(delta: float) -> void:
	var target: Vector2 = world.tile_center(path[0]) + _jitter
	var to_target := target - position
	_facing = Art.facing(to_target, _facing)
	var move := SPEED * GameState.mod("villager_speed") * world.speed_multiplier(current_tile()) * delta
	if to_target.length() <= move:
		position = target
		path.remove_at(0)
	else:
		position += to_target.normalized() * move


func _walk_to(t: Vector2i) -> bool:
	var p: Array[Vector2i] = world.find_path(current_tile(), t)
	if p.is_empty():
		return false
	p.remove_at(0)
	path = p
	return true


# --- Decisions --------------------------------------------------------------

func _think() -> void:
	if carrying != "":
		_go_deposit()
		return
	if world.is_night and not works_inside():
		_go_to_bed()
		return
	if job == null:
		note = "Unemployed"
		_wander()
		return
	if not job.has_road:
		note = "Workplace has no road"
		_wander()
		return
	match job.work_type():
		"build":
			_plan_build()
		"gather":
			_plan_gather()
		"farm":
			_plan_farm()
		"forester":
			_plan_forester()
		"produce":
			_plan_produce()
		"haul":
			_plan_haul()
		"guard", "study", "service":
			_plan_station()
		_:
			_wander()


func _plan_station() -> void:
	if _walk_to(job.entrance()):
		state = State.TO_POST
		note = "Heading to the %s" % job.title
	else:
		_wait("Can't reach the %s" % job.title, 3.0)


## Makes room in the workplace pile for `needed` more goods: carries a load
## to storage if the pile is too full. Returns false if the worker is busy
## doing that (or waiting because storage is full).
func _ensure_pile_space(needed: int) -> bool:
	if job.output_space() >= needed:
		return true
	if GameState.space_for(job.fullest_output()) <= 0:
		_wait("Storage full", 3.0)
		return false
	if _walk_to(job.entrance()):
		_dest = job
		state = State.TO_PICKUP
		note = "Pile is full: hauling a load to storage"
	else:
		_wait("Can't reach workplace", 3.0)
	return false


func _plan_gather() -> void:
	var def: Dictionary = job.def
	if not _ensure_pile_space(def.yield):
		return
	for t in world.find_resource_tiles(job.entrance(), def.gather_terrain, def.radius, 6):
		var stand: Vector2i = world.approach_tile(t)
		if stand != WorldMap.INVALID_TILE and _walk_to(stand):
			_claim(t)
			task = Task.GATHER
			state = State.TO_TARGET
			note = "Going to gather %s" % def.resource
			return
	_wait("No %s left nearby" % Terrain.NAMES[def.gather_terrain].to_lower(), 4.0)


func _plan_farm() -> void:
	var t: Vector2i = world.find_field(job, WorldMap.FieldStage.RIPE)
	if t != WorldMap.INVALID_TILE:
		if not _ensure_pile_space(job.def.yield):
			return
		if _walk_to(t):
			_claim(t)
			task = Task.HARVEST
			state = State.TO_TARGET
			note = "Going to harvest"
			return
	t = world.find_field(job, WorldMap.FieldStage.TILLED)
	if t != WorldMap.INVALID_TILE and _walk_to(t):
		_claim(t)
		task = Task.PLANT
		state = State.TO_TARGET
		note = "Going to plant"
		return
	_wait("Waiting for crops to grow", 3.0)


## Castle builders: bring what the project still lacks, then build.
func _plan_build() -> void:
	var castle: Castle = world.get_parent().castle
	if not castle.is_building():
		_wait("Waiting for orders", 3.0)
		return
	if castle.materials_done():
		var spot := castle.work_spot()
		if spot != WorldMap.INVALID_TILE and _walk_to(spot):
			task = Task.BUILD
			state = State.TO_TARGET
			_target_tile = WorldMap.INVALID_TILE
			note = "Going to build the %s" % CastleDefs.STAGES[castle.project.stage].title
			return
		_wait("Can't reach the building site", 3.0)
		return
	var missing := castle.missing()
	for item: String in missing:
		# The castle's own storehouse counts too: goods move from store to site.
		var source := world.stock.nearest_source(item, 1, current_tile())
		if source != null and _walk_to(source.entrance()):
			var amount := mini(HAUL_LOAD, missing[item])
			castle.claim(item, amount)
			_castle_claim = {"item": item, "amount": amount}
			_dest = source
			state = State.TO_FETCH
			note = "Fetching %s for the castle" % item
			return
	_wait("Waiting for %s" % ", ".join(missing.keys()) if not missing.is_empty() else "Materials on the way", 3.0)


## Gives back a castle material claim that won't be delivered.
func _drop_castle_claim() -> void:
	if _castle_claim.is_empty():
		return
	var castle: Castle = world.get_parent().castle
	castle.deliver(_castle_claim.item, _castle_claim.amount, false)
	_castle_claim = {}


func _plan_forester() -> void:
	var t: Vector2i = world.find_plant_site(job.entrance(), job.def.radius)
	if t != WorldMap.INVALID_TILE and _walk_to(t):
		_claim(t)
		task = Task.PLANT_TREE
		state = State.TO_TARGET
		note = "Going to plant a sapling"
		return
	_wait("No open ground left to plant", 5.0)


func _plan_produce() -> void:
	var input := job.input_item()
	var batch := job.input_batch()
	var output: String = job.def.output.keys()[0]
	if not _ensure_pile_space(job.def.output[output]):
		return
	if job.input_stock.get(input, 0) >= batch:
		# A hauler delivered it: just walk over and work.
		if _walk_to(job.entrance()):
			state = State.TO_WORKPLACE
			note = "Going to work"
		return
	var source := world.stock.nearest_source(input, batch, current_tile(), job)
	if source != null and _walk_to(source.entrance()):
		_dest = source
		state = State.TO_FETCH
		note = "Fetching %s from %s" % [input, source.title]
	else:
		_wait("Waiting for %s" % input, 3.0)


func _plan_haul() -> void:
	# 1. Empty the fullest workplace pile into storage.
	var best: Building = null
	for b in world.buildings:
		if b.output_total() < HAUL_MIN or not b.has_road or is_instance_valid(b.pickup_claim):
			continue
		if GameState.space_for(b.fullest_output()) <= 0:
			continue
		if best == null or b.output_total() > best.output_total():
			best = b
	if best != null and _walk_to(best.entrance()):
		best.pickup_claim = self
		_dest = best
		state = State.TO_PICKUP
		note = "Collecting from %s" % best.title
		return
	# 2. Keep producers supplied with inputs.
	for p in world.buildings:
		if not p.def.has("input") or not p.has_road or p.workers.is_empty() or is_instance_valid(p.supply_claim):
			continue
		var input := p.input_item()
		var wanted: int = p.input_batch() * 2 - p.input_stock.get(input, 0)
		if wanted <= 0:
			continue
		var source := world.stock.nearest_source(input, 1, p.entrance(), p)
		if source != null and _walk_to(source.entrance()):
			p.supply_claim = self
			_supply_target = p
			_dest = source
			carry_amount = mini(wanted, HAUL_LOAD)  # how much to pick up
			state = State.TO_FETCH
			note = "Fetching %s for %s" % [input, p.title]
			return
	_wait("Nothing to haul", 3.0)


func _go_deposit() -> void:
	var storage := world.stock.nearest_with_space(carrying, current_tile())
	if storage != null and _walk_to(storage.entrance()):
		_dest = storage
		state = State.TO_DEPOSIT
		note = "Hauling %s to %s" % [carrying, storage.title]
		return
	_wait("Storage full (holding %s)" % carrying, 3.0)


## Takes finished goods to the workplace pile, or straight to storage if the
## pile is full.
func _deliver_output(item: String, amount: int) -> void:
	carrying = item
	carry_amount = amount
	queue_redraw()
	if job.output_space() > 0 and _walk_to(job.entrance()):
		state = State.TO_DROP
		note = "Bringing %s to %s" % [item, job.title]
	else:
		_go_deposit()


func _go_to_bed() -> void:
	var bed: Building = home if is_instance_valid(home) else world.keep
	if bed != null and _walk_to(bed.entrance()):
		state = State.TO_BED
		note = "Going home for the night"
	else:
		_sleep()


func _sleep() -> void:
	state = State.SLEEPING
	visible = false
	note = "Sleeping"


func _wander() -> void:
	var anchor: Vector2i = home.entrance() if is_instance_valid(home) else current_tile()
	for i in 6:
		var t := anchor + Vector2i(randi_range(-4, 4), randi_range(-4, 4))
		if world.is_walkable(t) and _walk_to(t):
			state = State.WANDER
			return
	state = State.IDLE
	timer = randf_range(2.0, 4.0)


# --- Raids ------------------------------------------------------------------

func _update_raid_response() -> void:
	if state == State.SLEEPING or state == State.TO_BED:
		return  # already heading indoors
	if state == State.FIGHTING:
		if not world.call_to_arms:
			_set_armed(false)
			_reset()
			note = "Back to work"
		return
	var sheltering := state == State.TO_SHELTER or state == State.HIDING
	var radius := (SAFE_TILES if sheltering else DANGER_TILES) * Terrain.TILE_SIZE
	var should_hide := world.raid_active and not works_inside() and world.enemy_within(position, radius)
	if should_hide and world.call_to_arms and not _wounded():
		_take_up_arms()
	elif should_hide and not sheltering:
		_seek_shelter()
	elif not should_hide and sheltering:
		visible = true
		_wait("Back to work", randf_range(0.2, 1.5))


func _seek_shelter() -> void:
	_reset()
	var shelter: Building = home if is_instance_valid(home) else world.keep
	if shelter != null and _walk_to(shelter.entrance()):
		state = State.TO_SHELTER
		note = "Fleeing to shelter"
	else:
		_hide()


func _take_up_arms() -> void:
	_reset()
	_set_armed(true)
	state = State.FIGHTING
	note = "Fighting raiders"
	_foe = null


## Chase the nearest raider and jab it; go back to work once none are near.
func _fight(delta: float) -> void:
	_strike_timer -= delta
	if _wounded():
		_set_armed(false)
		_seek_shelter()
		note = "Wounded, fleeing to shelter"
		return
	if _foe == null or not is_instance_valid(_foe) or _foe.health.is_dead() or _foe.is_flying():
		_foe = world.nearest_enemy(position, SAFE_TILES * Terrain.TILE_SIZE, false)
		if _foe == null:
			_set_armed(false)
			_wait("Back to work", randf_range(0.2, 1.5))
			return
	var dist := position.distance_to(_foe.position)
	_facing = Art.facing(_foe.position - position, _facing)
	if dist <= MILITIA_REACH:
		if _strike_timer <= 0.0:
			_strike_timer = MILITIA_COOLDOWN
			_foe.health.take_damage(MILITIA_DAMAGE * GameState.mod("troop_damage"))
			Sound.play("hit", position)
	elif dist < Terrain.TILE_SIZE * 1.5:
		# Close enough to step straight at it.
		position = position.move_toward(_foe.position, SPEED * delta)
		queue_redraw()
	elif not _walk_to(_foe.current_tile()):
		_foe = null


## The rhythm of work: chopping, picking, hammering.
func _work_sound(delta: float) -> void:
	_sound_timer -= delta
	if _sound_timer > 0.0 or job == null:
		return
	_sound_timer = randf_range(0.7, 1.0)
	var res: String = job.def.get("resource", "")
	if res == "wood":
		Sound.play("chop", position)
	elif res in ["stone", "iron"] or job.def_id in ["smithy", "armory"]:
		Sound.play("pick", position)


func _wounded() -> bool:
	return health.hp < health.max_hp * MILITIA_RETREAT


## Pitchfork and a leather jerkin: extra HP while fighting, kept in proportion.
func _set_armed(armed: bool) -> void:
	var new_max := MILITIA_HP if armed else MAX_HP
	if is_equal_approx(health.max_hp, new_max):
		return
	health.hp = health.hp / health.max_hp * new_max
	health.max_hp = new_max
	health.changed.emit()


func _hide() -> void:
	state = State.HIDING
	visible = false
	note = "Hiding from raiders"


# --- Arrivals & work --------------------------------------------------------

func _arrive() -> void:
	match state:
		State.TO_SHELTER:
			_hide()
		State.TO_BED:
			_sleep()
		State.TO_POST:
			if job == null:
				_reset()
				return
			state = State.STATIONED
			visible = false
			note = {"guard": "On watch", "study": "Studying"}.get(job.def.work, "Serving customers")
		State.TO_TARGET:
			if job == null or (_target_tile == WorldMap.INVALID_TILE and task != Task.BUILD):
				_reset()
				return
			state = State.WORKING
			var look := world.tile_center(_target_tile) if _target_tile != WorldMap.INVALID_TILE else job.center()
			if look.distance_to(position) > 2.0:
				_facing = Art.facing(look - position, _facing)
			timer = job.def.get("work_time", 4.0) * _work_multiplier() \
					* (GameState.mod("gather_time") if task == Task.GATHER else 1.0)
			note = {Task.GATHER: "Gathering %s" % job.def.get("resource", ""),
					Task.PLANT: "Planting", Task.HARVEST: "Harvesting",
					Task.PLANT_TREE: "Planting a sapling",
					Task.BUILD: "Building the %s" % job.title}.get(task, "Working")
		State.TO_FETCH:
			_arrive_fetch()
		State.TO_WORKPLACE:
			_arrive_workplace()
		State.TO_DROP:
			_arrive_drop()
		State.TO_PICKUP:
			_arrive_pickup()
		State.TO_SUPPLY:
			if is_instance_valid(_supply_target):
				_supply_target.add_input(carrying, carry_amount)
				note = "Delivered %s to %s" % [carrying, _supply_target.title]
				_play_once("putdown")
				carrying = ""
				carry_amount = 0
				queue_redraw()
			_release_claims()
			_wait(note, 0.3)
		State.TO_DEPOSIT:
			if is_instance_valid(_dest):
				carry_amount -= world.stock.store_at(_dest, carrying, carry_amount)
				if carry_amount <= 0:
					carrying = ""
					carry_amount = 0
					_play_once("putdown")
				queue_redraw()
			_wait(note, 0.3)  # anything left over goes to another storage
		State.WANDER:
			state = State.IDLE
			timer = randf_range(2.0, 5.0)


func _arrive_fetch() -> void:
	if job == null or not is_instance_valid(_dest):
		_drop_castle_claim()
		_reset()
		return
	if not _castle_claim.is_empty():
		var item: String = _castle_claim.item
		var got := world.stock.take_from_source(_dest, item, _castle_claim.amount)
		if got <= 0:
			_drop_castle_claim()
			_wait("No %s left there" % item, 1.0)
			return
		if got < _castle_claim.amount:
			world.get_parent().castle.deliver(item, _castle_claim.amount - got, false)
			_castle_claim.amount = got
		carrying = item
		carry_amount = got
		_play_once("pickup")
		queue_redraw()
		if _walk_to(job.entrance()):
			state = State.TO_WORKPLACE
			note = "Carrying %s to the castle" % item
		else:
			_drop_castle_claim()
			_go_deposit()
		return
	if job.def.get("work", "") == "haul":
		var target := _supply_target
		var input := target.input_item() if is_instance_valid(target) else ""
		var got := world.stock.take_from_source(_dest, input, carry_amount) if input != "" else 0
		if got <= 0:
			carry_amount = 0
			_release_claims()
			_wait("Nothing left to fetch", 1.0)
			return
		carrying = input
		carry_amount = got
		_play_once("pickup")
		queue_redraw()
		if _walk_to(target.entrance()):
			state = State.TO_SUPPLY
			note = "Delivering %s to %s" % [input, target.title]
		else:
			_release_claims()
			_go_deposit()
		return
	var needed := job.input_batch()
	var item := job.input_item()
	if _dest.inventory.get(item, 0) + _dest.output_stock.get(item, 0) < needed:
		_wait("Waiting for %s" % item, 2.0)
		return
	# Bring a full load (whole batches) so the next batches need no trip.
	var load := maxi(needed, int(HAUL_LOAD / float(needed)) * needed)
	carrying = item
	carry_amount = world.stock.take_from_source(_dest, item, load)
	_play_once("pickup")
	queue_redraw()
	if _walk_to(job.entrance()):
		state = State.TO_WORKPLACE
		note = "Carrying %s to %s" % [item, job.title]
	else:
		_wait("Can't reach workplace")


func _arrive_workplace() -> void:
	if job == null:
		_reset()
		return
	if not _castle_claim.is_empty():
		world.get_parent().castle.deliver(carrying, carry_amount)
		_castle_claim = {}
		_play_once("putdown")
		carrying = ""
		carry_amount = 0
		queue_redraw()
		_wait("Delivered to the castle", 0.3)
		return
	if carrying == job.input_item():
		# One batch goes to work now; the rest waits at the workplace.
		var extra := carry_amount - job.input_batch()
		if extra > 0:
			job.add_input(carrying, extra)
		carrying = ""
		carry_amount = 0
		queue_redraw()
	elif not job.take_input(job.input_item(), job.input_batch()):
		_wait("Waiting for %s" % job.input_item(), 2.0)
		return
	task = Task.PRODUCE
	state = State.WORKING
	timer = job.def.work_time * _work_multiplier()
	note = "Working"


func _arrive_drop() -> void:
	if job == null:
		_go_deposit()
		return
	carry_amount -= job.add_output(carrying, carry_amount)
	if carry_amount > 0:
		_go_deposit()  # pile filled up on the way
		return
	carrying = ""
	_play_once("putdown")
	queue_redraw()
	_wait(note, 0.2)


func _arrive_pickup() -> void:
	if not is_instance_valid(_dest):
		_reset()
		return
	var item := _dest.fullest_output()
	var got := _dest.take_output(item, HAUL_LOAD) if item != "" else 0
	_release_claims()
	if got <= 0:
		_wait("Pile was already emptied", 0.5)
		return
	carrying = item
	carry_amount = got
	_play_once("pickup")
	queue_redraw()
	_go_deposit()


## Happy households work faster, miserable ones slower.
func _work_multiplier() -> float:
	return NeedDefs.work_multiplier(home.happiness) if is_instance_valid(home) else 1.0


func _finish_work() -> void:
	if job == null:
		_reset()
		return
	var def: Dictionary = job.def
	var amount := 0
	var item := ""
	match task:
		Task.GATHER:
			amount = world.harvest(_target_tile, def.gather_terrain, def.yield)
			item = def.resource
		Task.PLANT:
			world.plant_field(_target_tile)
		Task.PLANT_TREE:
			world.plant_sapling(_target_tile)
		Task.BUILD:
			world.get_parent().castle.add_work(job.def.get("work_time", 4.0) * _work_multiplier())
		Task.HARVEST:
			amount = world.harvest_field(_target_tile)
			item = def.resource
		Task.PRODUCE:
			item = def.output.keys()[0]
			amount = def.output[item]
	_release_claims()
	task = Task.NONE
	if amount > 0:
		_play_once("pickup")
		_deliver_output(item, amount)
	else:
		_wait(note, 0.2)


func _draw() -> void:
	var anim := current_anim()
	var cart := carrying != "" and _moving and job != null and job.def_id == "carter"
	if cart and _facing != "south":
		_draw_cart()
	var top := Art.draw_character_anim(self, "villager", _facing, anim,
		_once_time if anim in Art.ONE_SHOT else _anim_time)
	if is_nan(top):
		top = -8.0
		var body := COLOR_UNEMPLOYED
		if job != null:
			body = (job.def.color as Color).lightened(0.25)
		draw_circle(Vector2(0, 3), 5.0, body.darkened(0.6))
		draw_circle(Vector2(0, 3), 4.0, body)
		draw_circle(Vector2(0, -4), 3.0, COLOR_SKIN)
	if state == State.FIGHTING:
		# Pitchfork.
		draw_line(Vector2(6, 8), Vector2(6, top + 4), Color(0.50, 0.35, 0.18), 1.5)
		for dx in [-2, 0, 2]:
			draw_line(Vector2(6 + dx, top + 4), Vector2(6 + dx, top), Color(0.75, 0.75, 0.8), 1.0)
	# While walking the carry animation shows the load; otherwise a small
	# box in the goods' colour does.
	if carrying != "" and not (anim == "carry" and not Art.anim_frames("villager", "carry", _facing).is_empty()):
		var c := ItemDefs.color_of(carrying)
		var box := Rect2(Vector2(4, top + 12), Vector2(7, 7))
		draw_rect(box, c)
		draw_rect(box, c.darkened(0.5), false, 1.0)
	if cart and _facing == "south":
		_draw_cart()
	if missed_meals > 0:
		draw_circle(Vector2(-6, top + 2), 2.5, Color(0.9, 0.15, 0.1))
	health.draw_bar(self, Vector2(0, top - 4), 12)


## The carter's handcart, pushed ahead of the hauler (the prop art, smaller).
func _draw_cart() -> void:
	var tex := Art.texture("res://assets/sprites/props/cart.png")
	if tex == null:
		return
	var ahead: Vector2 = {"east": Vector2(12, 2), "west": Vector2(-12, 2), "north": Vector2(0, -6),
		"south": Vector2(0, 8)}[_facing]
	var s := 0.6
	draw_set_transform(ahead, 0.0, Vector2(-s if _facing == "west" else s, s))
	draw_texture(tex, -Vector2(tex.get_size()) * Vector2(0.5, 0.8))
	draw_set_transform(Vector2.ZERO)


func set_missed_meals(value: int) -> void:
	missed_meals = value
	queue_redraw()
