class_name CitizenManager
extends Node
## Spawns villagers into free housing, assigns them to open jobs, and feeds them.

signal all_villagers_lost

const SPAWN_INTERVAL := 3.0
const JOB_INTERVAL := 1.0
## Every villager eats one meal (1 bread or 1 fish) per interval.
const MEAL_INTERVAL := 60.0
const MISSED_MEALS_TO_LEAVE := 3
## The first few settlers arrive regardless of food; after that growth needs food.
const FREE_SETTLERS := 4
const MIN_FOOD_TO_GROW := 5

var world: WorldMap
var villagers: Array[Villager] = []

var _settlers_arrived := 0
var _spawn_timer := 1.0
var _job_timer := 0.0
var _meal_timer := MEAL_INTERVAL
var _all_lost_emitted := false


func setup(p_world: WorldMap) -> void:
	world = p_world
	world.building_removed.connect(_on_building_removed)


func _process(delta: float) -> void:
	_spawn_timer -= delta
	if _spawn_timer <= 0.0:
		_spawn_timer = SPAWN_INTERVAL
		_try_spawn()
	_job_timer -= delta
	if _job_timer <= 0.0:
		_job_timer = JOB_INTERVAL
		_assign_jobs()
		_publish_stats()
	_meal_timer -= delta
	if _meal_timer <= 0.0:
		_meal_timer = MEAL_INTERVAL
		_feed()


## Seconds until the next meal, for the HUD.
func time_to_meal() -> float:
	return _meal_timer


func _try_spawn() -> void:
	if _settlers_arrived >= FREE_SETTLERS and GameState.edible_total() < MIN_FOOD_TO_GROW:
		return
	for b in world.buildings:
		if b.has_road and b.residents.size() < b.housing_capacity() \
				and b.happiness >= NeedDefs.MIN_TO_MOVE_IN:
			var v := Villager.new()
			v.setup(world, b)
			v.died.connect(_on_villager_died)
			world.unit_root.add_child(v)
			b.residents.append(v)
			villagers.append(v)
			_settlers_arrived += 1
			return


func _feed() -> void:
	if villagers.is_empty():
		return
	var order := villagers.duplicate()
	order.shuffle()
	var eaten := GameState.eat(order.size())
	for i in order.size():
		var v: Villager = order[i]
		v.set_missed_meals(0 if i < eaten else v.missed_meals + 1)
	var hungry := order.size() - eaten
	if hungry > 0:
		GameState.notify("%d villager%s went hungry!" % [hungry, "" if hungry == 1 else "s"])

	var leaving := villagers.filter(func(v: Villager) -> bool:
		return v.missed_meals >= MISSED_MEALS_TO_LEAVE)
	for v: Villager in leaving:
		remove_villager(v)
	if not leaving.is_empty():
		GameState.notify("%d starving villager%s left the kingdom" % [leaving.size(), "" if leaving.size() == 1 else "s"])
	_publish_stats()


func _assign_jobs() -> void:
	var idle: Array = villagers.filter(func(v: Villager) -> bool: return v.job == null)
	for b in world.buildings:
		if idle.is_empty():
			return
		if not b.has_road:
			continue
		var open_slots: int = b.def.get("jobs", 0) - b.workers.size()
		while open_slots > 0 and not idle.is_empty():
			var worker := _closest(idle, b.entrance())
			idle.erase(worker)
			worker.set_job(b)
			open_slots -= 1


func _closest(candidates: Array, tile: Vector2i) -> Villager:
	var target: Vector2 = world.tile_center(tile)
	var best: Villager = candidates[0]
	for v: Villager in candidates:
		if v.position.distance_squared_to(target) < best.position.distance_squared_to(target):
			best = v
	return best


func _publish_stats() -> void:
	var housing := 0
	var jobs := 0
	for b in world.buildings:
		housing += b.housing_capacity()
		jobs += b.def.get("jobs", 0)
	var employed := villagers.filter(func(v: Villager) -> bool: return v.job != null).size()
	GameState.set_population(villagers.size(), housing, employed, jobs)
	if _settlers_arrived > 0 and villagers.is_empty() and not _all_lost_emitted:
		_all_lost_emitted = true
		all_villagers_lost.emit()


## Takes a villager for military service: the nearest unemployed one, else the
## nearest non-guard worker. Their home slot frees up for a new settler.
func draft_villager(near: Vector2i) -> bool:
	var target := world.tile_center(near)
	var pool := villagers.filter(func(v: Villager) -> bool: return v.job == null)
	if pool.is_empty():
		pool = villagers.filter(func(v: Villager) -> bool: return not v.is_guard())
	if pool.is_empty():
		return false
	var recruit: Villager = pool[0]
	for v: Villager in pool:
		if v.position.distance_squared_to(target) < recruit.position.distance_squared_to(target):
			recruit = v
	remove_villager(recruit)
	_publish_stats()
	return true


func remove_villager(v: Villager) -> void:
	v.lose_job()
	if is_instance_valid(v.home):
		v.home.residents.erase(v)
	villagers.erase(v)
	v.queue_free()


func _on_villager_died(v: Villager) -> void:
	GameState.notify("%s was killed by raiders!" % v.villager_name)
	remove_villager(v)
	_publish_stats()


func _on_building_removed(b: Building) -> void:
	for v: Villager in b.workers.duplicate():
		v.lose_job()
	for v: Villager in b.residents.duplicate():
		remove_villager(v)
	_publish_stats()
