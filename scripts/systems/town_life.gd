class_name TownLife
extends Node
## Keeps the town lively (none of it affects the economy): as it grows it
## gains children playing near homes, townsfolk visiting the market, well,
## tavern and chapel, dogs, chickens at farms, sheep and cows grazing beside
## them, and birds flying over by day. Counts are re-balanced every few
## seconds from the number of homes, people and farms.

const CHECK := 3.0
## One child per this many homes, one townsperson per this many people, one
## dog per this many people (each capped).
const HOMES_PER_CHILD := 3
const PEOPLE_PER_SHOPPER := 10
const PEOPLE_PER_DOG := 15
const MAX := {"child": 24, "shopper": 20, "dog": 10}
const CHICKENS_PER_FARM := 3
## Where townsfolk like to gather.
const GATHERING := ["market", "well", "tavern", "chapel", "trading_post", "fountain", "garden", "monument", "statue"]

var world: WorldMap
var folk: Array[Townsfolk] = []
var animals: Array[Animal] = []
var birds: Birds

var _timer := 0.5


func setup(p_world: WorldMap) -> void:
	world = p_world


func _ready() -> void:
	birds = Birds.new()
	birds.world = world
	world.add_child(birds)


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = CHECK
	folk.assign(folk.filter(func(f: Townsfolk) -> bool: return is_instance_valid(f)))
	animals.assign(animals.filter(func(a: Animal) -> bool: return is_instance_valid(a)))
	var homes := world.buildings.filter(func(b: Building) -> bool:
		return b.is_home() and b != world.keep and not b.residents.is_empty())
	if homes.is_empty():
		return
	var pop := GameState.population
	_balance("child", mini(homes.size() / HOMES_PER_CHILD, MAX.child), homes)
	_balance("shopper", mini(pop / PEOPLE_PER_SHOPPER, MAX.shopper), homes)
	_balance("dog", mini(pop / PEOPLE_PER_DOG, MAX.dog), homes)
	_balance_animals()


func count(kind: String) -> int:
	if kind in ["chicken", "sheep", "cow"]:
		return animals.filter(func(a: Animal) -> bool: return a.kind == kind).size()
	return folk.filter(func(f: Townsfolk) -> bool: return f.kind == kind).size()


func _balance(kind: String, want: int, homes: Array) -> void:
	var have := folk.filter(func(f: Townsfolk) -> bool: return f.kind == kind)
	while have.size() < want:
		var f := Townsfolk.new()
		f.setup(world, self, kind, homes.pick_random())
		world.unit_root.add_child(f)
		folk.append(f)
		have.append(f)
	while have.size() > want:
		var gone: Townsfolk = have.pop_back()
		folk.erase(gone)
		gone.queue_free()


## Chickens by every farm; each farm also keeps either a cow or two sheep.
func _balance_animals() -> void:
	for farm in world.buildings:
		if farm.def_id != "farm":
			continue
		var mine := animals.filter(func(a: Animal) -> bool: return a.farm == farm)
		if not mine.is_empty():
			continue
		var start := world.tile_center(farm.entrance())
		for i in CHICKENS_PER_FARM:
			_add_animal("chicken", farm, start + Vector2(randf_range(-20, 20), randf_range(-6, 12)))
		if absi(hash(farm.origin)) % 2 == 0:
			_add_animal("cow", farm, start + Vector2(28, -8))
		else:
			_add_animal("sheep", farm, start + Vector2(-30, -6))
			_add_animal("sheep", farm, start + Vector2(-40, 4))


func _add_animal(kind: String, farm: Building, at: Vector2) -> void:
	var a := Animal.new()
	a.setup(world, kind, farm, at)
	world.unit_root.add_child(a)
	animals.append(a)


# --- Helpers for Townsfolk -----------------------------------------------------

## The nearest other visible townsperson of `kind` within `radius` px.
func nearby(me: Townsfolk, kind: String, radius: float) -> Townsfolk:
	var best: Townsfolk = null
	var best_d := radius
	for f in folk:
		if f == me or f.kind != kind or not is_instance_valid(f) or not f.visible:
			continue
		var d := f.position.distance_to(me.position)
		if d < best_d:
			best_d = d
			best = f
	return best


## Anyone standing about near `me` (townsfolk loitering or a villager).
func someone_near(me: Townsfolk, radius: float) -> bool:
	for f in folk:
		if f != me and is_instance_valid(f) and f.is_loitering() and f.position.distance_to(me.position) <= radius:
			return true
	return false


## A gathering place (market, well, tavern...) for a townsperson to visit,
## favouring ones close to home.
func gathering_spot(me: Townsfolk) -> Vector2i:
	# Plazas are the town's squares: a favourite place to meet.
	if not world.plazas.is_empty() and randf() < 0.4:
		return world.plazas.keys().pick_random()
	var spots := world.buildings.filter(func(b: Building) -> bool: return b.def_id in GATHERING and b.has_road)
	if spots.is_empty():
		return WorldMap.INVALID_TILE
	spots.sort_custom(func(a: Building, b: Building) -> bool:
		return a.center().distance_squared_to(me.position) < b.center().distance_squared_to(me.position))
	var pick: Building = spots[mini(randi() % 3, spots.size() - 1)]
	return pick.entrance()


func villager_near(pos: Vector2, radius: float) -> Node2D:
	var best: Node2D = null
	var best_d := radius
	for v in get_tree().get_nodes_in_group("villagers"):
		if not v.visible:
			continue
		var d: float = v.position.distance_to(pos)
		if d < best_d:
			best_d = d
			best = v
	return best
