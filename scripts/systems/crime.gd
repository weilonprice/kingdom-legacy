class_name Crime
extends Node
## Crime (M29). Once the town has MIN_POPULATION people, unhappy homes
## (below UNHAPPY) breed thieves, more so in crowded quarters. Now and then
## a thief robs a storage building near their home - gold from the castle's
## treasury, or goods - unless a staffed Town Watch covers that storehouse.
## A Watch covering the home also makes theft much less likely.

const TICK := 15.0
const MIN_POPULATION := 40
const UNHAPPY := 45.0
const BASE_CHANCE := 0.04
const CROWD_BONUS := 0.08
const REACH := 14
const STEAL_SHARE := 0.08
const WATCH_FACTOR := 0.2

var world: WorldMap
var thefts := 0
var _timer := TICK


func _process(delta: float) -> void:
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = TICK
	if GameState.population < MIN_POPULATION:
		return
	var homes := world.buildings.filter(func(b: Building) -> bool:
		return b.is_home() and b != world.keep and not b.residents.is_empty())
	for h: Building in homes:
		if h.happiness >= UNHAPPY:
			continue
		var crowd := homes.filter(func(o: Building) -> bool:
			return o != h and o.center().distance_to(h.center()) <= 4 * Terrain.TILE_SIZE + 32.0).size()
		var chance := BASE_CHANCE * (1.0 + CROWD_BONUS * crowd) * (UNHAPPY - h.happiness) / 20.0
		if h.needs_met.get("order", false):
			chance *= WATCH_FACTOR
		if randf() < chance:
			_rob_near(h)


func guarded(b: Building) -> bool:
	return world.buildings.any(func(w: Building) -> bool:
		return w.def.get("provides", "") == "order" and w.service_active() and w.covers(b))


func _rob_near(h: Building) -> void:
	var stores := world.buildings.filter(func(b: Building) -> bool:
		return b.def.has("accepts") and not b.inventory.is_empty() \
			and b.center().distance_to(h.center()) <= REACH * Terrain.TILE_SIZE and not guarded(b))
	if stores.is_empty():
		return
	var store: Building = stores.pick_random()
	var item: String = store.inventory.keys().pick_random()
	var n := maxi(1, int(store.inventory[item] * STEAL_SHARE))
	var got: int = world.stock.take_from(store, item, n)
	if got <= 0:
		return
	thefts += 1
	GameState.notify("Thieves stole %d %s from the %s! A Town Watch would stop them." % [
		got, ItemDefs.display_name(item).to_lower(), store.title])
