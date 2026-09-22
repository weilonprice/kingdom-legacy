class_name Stock
extends RefCounted
## Goods held in storage buildings. Each storage has its own inventory and a
## per-category capacity; gold is the Keep's treasury (uncapped). Workplaces
## also keep small output piles (Building.output_stock) that count as sources
## for producers and haulers but not towards kingdom totals.

signal changed

var world: WorldMap


func _init(p_world: WorldMap) -> void:
	world = p_world


func storages() -> Array[Building]:
	var found: Array[Building] = []
	for b in world.buildings:
		if b.def.has("accepts"):
			found.append(b)
	return found


func accepts(b: Building, item: String) -> bool:
	var category := ItemDefs.category_of(item)
	if category == "treasury":
		return b == world.keep
	return category in b.def.get("accepts", [])


func used_at(b: Building, category: String) -> int:
	var total := 0
	for item: String in b.inventory:
		if ItemDefs.category_of(item) == category:
			total += b.inventory[item]
	return total


func space_at(b: Building, item: String) -> int:
	if not accepts(b, item):
		return 0
	var category := ItemDefs.category_of(item)
	if category == "treasury":
		return 1 << 30
	return maxi(b.storage_capacity() - used_at(b, category), 0)


## Adds up to the free space (or everything, with `force`). Returns the amount added.
func store_at(b: Building, item: String, amount: int, force := false) -> int:
	var added := amount if force else mini(amount, space_at(b, item))
	if added > 0:
		b.inventory[item] = b.inventory.get(item, 0) + added
		changed.emit()
	return added


func take_from(b: Building, item: String, amount: int) -> int:
	var taken := mini(amount, b.inventory.get(item, 0))
	if taken > 0:
		b.inventory[item] -= taken
		if b.inventory[item] == 0:
			b.inventory.erase(item)
		changed.emit()
	return taken


# --- Kingdom-wide -----------------------------------------------------------

func total(item: String) -> int:
	var n := 0
	for b in storages():
		n += b.inventory.get(item, 0)
	return n


func totals() -> Dictionary:
	var result := {}
	for b in storages():
		for item: String in b.inventory:
			result[item] = result.get(item, 0) + b.inventory[item]
	return result


func used(category: String) -> int:
	var n := 0
	for b in storages():
		n += used_at(b, category)
	return n


func capacity(category: String) -> int:
	var n := 0
	for b in storages():
		if category in b.def.accepts:
			n += b.storage_capacity()
	return n


func total_space(item: String) -> int:
	var n := 0
	for b in storages():
		n += space_at(b, item)
	return n


## Takes from the fullest storages first. Returns the amount taken.
func take_anywhere(item: String, amount: int) -> int:
	var holders := storages().filter(func(b: Building) -> bool: return b.inventory.get(item, 0) > 0)
	holders.sort_custom(func(a: Building, b: Building) -> bool: return a.inventory[item] > b.inventory[item])
	var taken := 0
	for b: Building in holders:
		if taken >= amount:
			break
		taken += take_from(b, item, amount - taken)
	return taken


## Stores wherever there's room, nearest the Keep first; anything left over
## is forced into the Keep (refunds, recovered loot, starting stock).
func store_anywhere(item: String, amount: int) -> void:
	var near := world.keep.entrance() if world.keep != null else Vector2i.ZERO
	var left := amount
	while left > 0:
		var b := nearest_with_space(item, near)
		if b == null:
			break
		left -= store_at(b, item, left)
	if left > 0 and world.keep != null:
		store_at(world.keep, item, left, true)


func spend(cost: Dictionary) -> bool:
	for item: String in cost:
		if total(item) < cost[item]:
			return false
	for item: String in cost:
		take_anywhere(item, cost[item])
	return true


# --- Finding buildings ------------------------------------------------------

func nearest_with_space(item: String, from: Vector2i) -> Building:
	return _nearest(storages().filter(func(b: Building) -> bool: return space_at(b, item) > 0), from)


## Nearest building holding at least `amount` of `item`: a storage, or (if
## `include_workplaces`) a workplace's output pile. `exclude` is skipped.
func nearest_source(item: String, amount: int, from: Vector2i, exclude: Building = null,
		include_workplaces := true) -> Building:
	var found: Array = []
	for b in world.buildings:
		if b == exclude or b.health.is_dead():
			continue
		if b.inventory.get(item, 0) >= amount or (include_workplaces and b.output_stock.get(item, 0) >= amount):
			found.append(b)
	return _nearest(found, from)


## Takes from whichever of `b`'s stores holds `item` (storage or output pile).
func take_from_source(b: Building, item: String, amount: int) -> int:
	if b.inventory.get(item, 0) > 0:
		return take_from(b, item, amount)
	return b.take_output(item, amount)


func _nearest(candidates: Array, from: Vector2i) -> Building:
	var best: Building = null
	var best_dist := INF
	for b: Building in candidates:
		var d := Vector2(b.entrance()).distance_squared_to(Vector2(from))
		if d < best_dist:
			best_dist = d
			best = b
	return best
