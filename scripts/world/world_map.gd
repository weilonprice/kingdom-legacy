class_name WorldMap
extends Node2D
## The tile grid: terrain, roads, building occupancy and pathfinding.

signal building_placed(building: Building)
signal building_removed(building: Building)
signal roads_changed
signal keep_destroyed

enum FieldStage { TILLED, GROWING, RIPE }

const INVALID_TILE := Vector2i(-1, -1)
const NEIGHBORS: Array[Vector2i] = [
	Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0),
	Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1),
]
const T := Terrain.TILE_SIZE

var width := 128
var height := 128
var map_seed := 0
var terrain := PackedByteArray()
var resource_left := PackedInt32Array()
var roads := {}        # Vector2i -> true
## Road tiles paved as plazas (a subset of roads; see place_plazas).
var plazas := {}       # Vector2i -> true
## Upgraded road tiles: 1 cobblestone, 2 paved street (absent = dirt).
var road_tiers := {}   # Vector2i -> int
## Walkers on each tile right now (villagers and townsfolk), and how busy
## each road tile has been lately (for the Traffic overlay).
var traffic := {}      # Vector2i -> int
var road_use := {}     # Vector2i -> float
var _traffic_timer := 0.0
var occupancy := {}    # Vector2i -> Building
var entrances := {}    # Vector2i -> Building
var reserved := {}     # Vector2i -> Object reserving that resource tile
var fields := {}       # Vector2i -> {"farm": Building, "stage": FieldStage, "timer": float}
## Young trees: tile -> game seconds until it's forest (see Forests below).
var saplings := {}
## Forest tiles cut down to grass: tile -> seconds since. They grow back on
## their own after REGROW_DELAY if they still touch the forest.
var cleared := {}
var buildings: Array[Building] = []
var enemies: Array[Enemy] = []
## Lairs and their guards: hostile, but not part of a raid.
var wild: Array[Enemy] = []
## True while raiders are on the map; villagers hide.
var raid_active := false
## Call to Arms: during a raid villagers fight nearby raiders instead of hiding.
var call_to_arms := false
## Set by DayNight; villagers sleep at night.
var is_night := false
## Per-building inventories (storages, the Keep's treasury).
var stock: Stock
var keep: Building
## Reserved for the castle to grow into (CastleDefs.GROUNDS square around
## the map centre): no other buildings, walls, fields or trees.
var castle_grounds := Rect2i()

var renderer: TerrainRenderer
var building_root: Node2D
var unit_root: Node2D
## Villagers and troops: walls are solid, gates are open.
var astar := AStarGrid2D.new()
## Raiders: walls and gates are passable but costly (they smash through).
var enemy_astar := AStarGrid2D.new()


func _ready() -> void:
	GameState.modifiers_changed.connect(recompute_capacity)
	renderer = TerrainRenderer.new()
	renderer.setup(self)
	add_child(renderer)
	building_root = Node2D.new()
	building_root.z_index = 2
	# Nearer (lower) buildings draw over tall sprites behind them.
	building_root.y_sort_enabled = true
	add_child(building_root)
	unit_root = Node2D.new()
	unit_root.z_index = 3
	unit_root.y_sort_enabled = true
	add_child(unit_root)


## Winter: crops and trees stop growing (see Seasons).
var growth_paused := false
var _forest_timer := 0.0


func _process(delta: float) -> void:
	if _desirability_dirty:
		_recompute_desirability()
	_traffic_timer -= delta
	if _traffic_timer <= 0.0:
		_count_traffic(0.5 - _traffic_timer)
		_traffic_timer = 0.5
	if growth_paused:
		return
	for t: Vector2i in fields:
		var field: Dictionary = fields[t]
		if field.stage == FieldStage.GROWING:
			field.timer -= delta
			if field.timer <= 0.0:
				_set_field_stage(t, FieldStage.RIPE)
	_forest_timer += delta
	if _forest_timer >= FOREST_TICK:
		_grow_forests(_forest_timer)
		_forest_timer = 0.0


# --- Generation -------------------------------------------------------------

func generate(seed_value: int) -> void:
	map_seed = seed_value
	terrain.resize(width * height)
	resource_left.resize(width * height)

	var elevation := _noise(seed_value, 0.018, 4)
	var moisture := _noise(seed_value + 1, 0.045, 3)
	for y in height:
		for x in width:
			var e := elevation.get_noise_2d(x, y)
			var m := moisture.get_noise_2d(x, y)
			_set_terrain_raw(Vector2i(x, y), _pick_terrain(e, m))

	_carve_rivers(seed_value)

	# Guarantee a buildable start with wood and stone within reach.
	var center := Vector2i(width >> 1, height >> 1)
	_stamp(center, 10, Terrain.GRASS)
	_stamp(center + Vector2i(12, -5), 4, Terrain.FOREST)
	_stamp(center + Vector2i(-12, 6), 3, Terrain.STONE)

	renderer.rebuild()

	for grid in [astar, enemy_astar]:
		grid.region = Rect2i(0, 0, width, height)
		grid.cell_size = Vector2(T, T)
		grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
		grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
		grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
		grid.update()
	for y in height:
		for x in width:
			_update_nav(Vector2i(x, y))

	stock = Stock.new(self)
	_place_start(center)
	GameState.attach_stock(stock)


## Rivers run edge to edge, winding, passing 14-26 tiles from the start so
## they're close enough to matter but never through the town site. Each gets
## sandy fords where anyone can wade across, so a river is never a wall.
const RIVER_WIDTH := 2
## Tools can turn rivers off to compare maps.
static var rivers_enabled := true
const FORDS_PER_RIVER := 2


func _carve_rivers(seed_value: int) -> void:
	if not rivers_enabled:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + 3
	var count := 1 if width <= 128 else 2
	var center := Vector2(width, height) * 0.5
	for r in count:
		var vertical := rng.randf() < 0.5
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var base: float = (center.x if vertical else center.y) + side * rng.randi_range(14, 26)
		var meander := _noise(seed_value + 11 + r, 0.025, 2)
		var length := height if vertical else width
		var course: Array[Vector2i] = []
		var prev := -1
		for i in length:
			var c := roundi(base + meander.get_noise_1d(i) * 16.0)
			# Fill sideways steps so the river never breaks up diagonally.
			var from := c if prev < 0 else prev
			for k in range(mini(from, c), maxi(from, c) + 1):
				for w in RIVER_WIDTH:
					var t := Vector2i(k + w, i) if vertical else Vector2i(i, k + w)
					if is_in_bounds(t) and Vector2(t).distance_to(center) > 12.0:
						_set_terrain_raw(t, Terrain.WATER)
						course.append(t)
			prev = c
		_place_fords(course, vertical, rng)


func _place_fords(course: Array[Vector2i], vertical: bool, rng: RandomNumberGenerator) -> void:
	if course.is_empty():
		return
	var along := func(t: Vector2i) -> int: return t.y if vertical else t.x
	var length := height if vertical else width
	for f in FORDS_PER_RIVER:
		# Spread fords along the river, one in each stretch of it, at a spot
		# with dry land on both banks (not where the river runs into a lake).
		var lo := int(float(f) / FORDS_PER_RIVER * length) + 4
		var hi := maxi(lo, int(float(f + 1) / FORDS_PER_RIVER * length) - 5)
		var at := -1
		for attempt in 30:
			var candidate := rng.randi_range(lo, hi)
			if _banks_dry(course, along, candidate, vertical):
				at = candidate
				break
		if at < 0:
			continue
		for t in course:
			if absi(along.call(t) - at) <= 1:
				_set_terrain_raw(t, Terrain.SAND)


## True when the river's cross-section at `at` has land just beyond it on
## both sides.
func _banks_dry(course: Array[Vector2i], along: Callable, at: int, vertical: bool) -> bool:
	var across: Array[int] = []
	for t in course:
		if along.call(t) == at:
			across.append(t.x if vertical else t.y)
	if across.is_empty():
		return false
	var lo: int = across.min() - 1
	var hi: int = across.max() + 1
	for side in [lo, hi]:
		var t := Vector2i(side, at) if vertical else Vector2i(at, side)
		if not is_in_bounds(t) or get_terrain(t) == Terrain.WATER:
			return false
	return true


## Sand with water on two opposite sides: a river crossing.
func _is_ford(t: Vector2i) -> bool:
	var w := func(o: Vector2i) -> bool: return is_in_bounds(t + o) and get_terrain(t + o) == Terrain.WATER
	return (w.call(Vector2i.LEFT) and w.call(Vector2i.RIGHT)) or (w.call(Vector2i.UP) and w.call(Vector2i.DOWN))


func _noise(seed_value: int, frequency: float, octaves: int) -> FastNoiseLite:
	var noise := FastNoiseLite.new()
	noise.seed = seed_value
	noise.frequency = frequency
	noise.fractal_octaves = octaves
	return noise


func _pick_terrain(e: float, m: float) -> int:
	if e < -0.26:
		return Terrain.WATER
	if e < -0.21:
		return Terrain.SAND
	if e > 0.28:
		return Terrain.STONE
	if m > 0.08:
		return Terrain.FOREST
	return Terrain.GRASS


func _stamp(center: Vector2i, radius: int, type: int) -> void:
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var t := center + Vector2i(dx, dy)
			if dx * dx + dy * dy <= radius * radius and is_in_bounds(t):
				_set_terrain_raw(t, type)


func _place_start(center: Vector2i) -> void:
	var half := CastleDefs.GROUNDS / 2
	castle_grounds = Rect2i(center - Vector2i(half, half), Vector2i(CastleDefs.GROUNDS, CastleDefs.GROUNDS))
	var s: int = CastleDefs.STAGES[0].size
	keep = place_building("keep", center - Vector2i(s / 2, s / 2))
	# The approach road runs from the gate out of the grounds to a cross
	# street, so every later (bigger) stage's gate is already on it.
	var e := keep.entrance()
	var street := castle_grounds.end.y + 2
	var road_tiles: Array[Vector2i] = []
	for y in range(e.y, street + 1):
		road_tiles.append(Vector2i(e.x, y))
	for dx in range(-5, 6):
		road_tiles.append(Vector2i(e.x + dx, street))
	place_roads(road_tiles)


# --- Tiles ------------------------------------------------------------------

func is_in_bounds(t: Vector2i) -> bool:
	return t.x >= 0 and t.y >= 0 and t.x < width and t.y < height


func get_terrain(t: Vector2i) -> int:
	return terrain[t.y * width + t.x]


func set_terrain(t: Vector2i, type: int) -> void:
	if type != Terrain.FIELD:
		fields.erase(t)
	_set_terrain_raw(t, type)
	if not terrain.is_empty():
		renderer.refresh_tile(t)
	_update_nav(t)


func _set_terrain_raw(t: Vector2i, type: int) -> void:
	var i := t.y * width + t.x
	terrain[i] = type
	resource_left[i] = Terrain.HARVESTS.get(type, 0)


func tile_center(t: Vector2i) -> Vector2:
	return Vector2(t) * T + Vector2(T, T) * 0.5


func world_to_tile(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / T), floori(p.y / T))


func pixel_size() -> Vector2:
	return Vector2(width * T, height * T)


func is_walkable(t: Vector2i) -> bool:
	return is_in_bounds(t) and not astar.is_point_solid(t)


## Villagers move faster on roads and slower through woods.
## Road speed by tier (dirt, cobblestone, paved).
const ROAD_SPEEDS := [1.6, 2.0, 2.4]
const ROAD_TIER_NAMES := ["Dirt road", "Cobblestone road", "Paved street"]
## More walkers than this on one road tile slow everyone on it.
const TRAFFIC_FREE := 2
const TRAFFIC_SLOWDOWN := 0.2
const TRAFFIC_MIN := 0.45


func speed_multiplier(t: Vector2i) -> float:
	if not is_in_bounds(t):
		return 1.0
	if roads.has(t):
		var crowd: int = traffic.get(t, 0)
		var jam := 1.0 if crowd <= TRAFFIC_FREE else maxf(1.0 / (1.0 + TRAFFIC_SLOWDOWN * (crowd - TRAFFIC_FREE)), TRAFFIC_MIN)
		return ROAD_SPEEDS[road_tiers.get(t, 0)] * jam
	if get_terrain(t) == Terrain.FOREST:
		return 0.7
	return 1.0


func describe_tile(t: Vector2i) -> String:
	if not is_in_bounds(t):
		return ""
	if occupancy.has(t):
		return occupancy[t].describe()
	if roads.has(t):
		if get_terrain(t) == Terrain.WATER:
			return "Bridge"
		if plazas.has(t):
			return "Plaza"
		var busy: int = traffic.get(t, 0)
		return ROAD_TIER_NAMES[road_tiers.get(t, 0)] + (" — crowded" if busy > TRAFFIC_FREE else "")
	if fields.has(t):
		return "Field — %s" % ["Tilled", "Growing", "Ripe"][fields[t].stage]
	var text: String = Terrain.NAMES[get_terrain(t)]
	if get_terrain(t) == Terrain.SAND and _is_ford(t):
		text = "Ford (shallow crossing)"
	var left := resource_left[t.y * width + t.x]
	if left > 0:
		text += " (%d harvests left)" % left
	if saplings.has(t):
		var secs := ceili(saplings[t])
		text = "Sapling — %s" % ("resting for winter" if growth_paused
			else "forest in %d:%02d" % [secs / 60, secs % 60])
	return text


# --- Pathfinding ------------------------------------------------------------

func _update_nav(t: Vector2i) -> void:
	# Water is solid unless a bridge crosses it.
	var water := get_terrain(t) == Terrain.WATER and not roads.has(t)
	var ground_cost := 1.0 if roads.has(t) else Terrain.walk_cost(get_terrain(t))
	var b: Building = occupancy.get(t)
	var fortification: bool = b != null and BuildingDefs.is_fortification(b.def)
	var gate: bool = b != null and b.def.get("gate", false)

	var solid: bool = water or (b != null and not gate)
	astar.set_point_solid(t, solid)
	if not solid:
		astar.set_point_weight_scale(t, ground_cost)

	var enemy_solid: bool = water or (b != null and not fortification)
	enemy_astar.set_point_solid(t, enemy_solid)
	if not enemy_solid:
		enemy_astar.set_point_weight_scale(t, b.def.siege_cost if fortification else ground_cost)


func find_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	if not is_walkable(to):
		return []
	if not is_walkable(from):
		from = nearest_walkable(from)
		if from == INVALID_TILE:
			return []
	return astar.get_id_path(from, to)


## Where to stand to work tile `t`: the tile itself, or a walkable neighbor
## (e.g. the shore next to water).
func approach_tile(t: Vector2i) -> Vector2i:
	if is_walkable(t):
		return t
	for offset in NEIGHBORS:
		if is_walkable(t + offset):
			return t + offset
	return INVALID_TILE


## Route for raiders: walls and gates count as (costly) passable tiles.
func find_enemy_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	if not is_in_bounds(to) or enemy_astar.is_point_solid(to):
		return []
	if not is_in_bounds(from) or enemy_astar.is_point_solid(from):
		from = nearest_walkable(from)
		if from == INVALID_TILE:
			return []
	return enemy_astar.get_id_path(from, to)


## The wall or gate standing on `t`, or null.
func fortification_at(t: Vector2i) -> Building:
	var b: Building = occupancy.get(t)
	if b != null and BuildingDefs.is_fortification(b.def) and not b.health.is_dead():
		return b
	return null


func nearest_walkable(t: Vector2i, max_radius := 6) -> Vector2i:
	for r in range(0, max_radius + 1):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var c := t + Vector2i(dx, dy)
				if is_walkable(c):
					return c
	return INVALID_TILE


# --- Resources --------------------------------------------------------------

## Unreserved tiles of `type` within `radius` of `center`, nearest first.
func find_resource_tiles(center: Vector2i, type: int, radius: int, limit: int) -> Array[Vector2i]:
	var found: Array[Vector2i] = []
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var t := center + Vector2i(dx, dy)
			if is_in_bounds(t) and get_terrain(t) == type and not reserved.has(t) and not roads.has(t):
				found.append(t)
	found.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.distance_squared_to(center) < b.distance_squared_to(center))
	return found.slice(0, limit)


func reserve(t: Vector2i, by: Object) -> void:
	reserved[t] = by


func release(t: Vector2i, by: Object) -> void:
	if reserved.get(t) == by:
		reserved.erase(t)


## Takes one harvest from a tile. Returns the amount gathered (0 if gone).
func harvest(t: Vector2i, type: int, amount: int) -> int:
	if not is_in_bounds(t) or get_terrain(t) != type:
		return 0
	if Terrain.HARVESTS.has(type):
		var i := t.y * width + t.x
		resource_left[i] -= 1
		if resource_left[i] <= 0:
			set_terrain(t, Terrain.GRASS)
			if type == Terrain.FOREST:
				cleared[t] = 0.0
	return amount


# --- Forests ------------------------------------------------------------------
# A Forester plants saplings on open ground; they grow into forest tiles
# (full harvests) after SAPLING_GROW. Cleared forest also comes back by
# itself, slowly and only from the forest's edge. Neither happens next to
# roads, buildings, doors or fields, so trees never swallow the town.

const SAPLING_GROW := 180.0
const REGROW_DELAY := 420.0
const FOREST_TICK := 2.0


## Open grass with nothing on or beside it that a tree would get in the way of.
func is_plantable(t: Vector2i) -> bool:
	if not is_in_bounds(t) or get_terrain(t) != Terrain.GRASS or saplings.has(t) or reserved.has(t) \
			or in_castle_grounds(t):
		return false
	for off in NEIGHBORS + [Vector2i.ZERO]:
		var n: Vector2i = t + off
		if occupancy.has(n) or roads.has(n) or entrances.has(n) or fields.has(n):
			return false
	return true


func plant_sapling(t: Vector2i) -> bool:
	if get_terrain(t) != Terrain.GRASS or saplings.has(t) or occupancy.has(t) or roads.has(t):
		return false
	saplings[t] = SAPLING_GROW * randf_range(0.9, 1.1)
	cleared.erase(t)
	renderer.nature.refresh_tile(t)
	return true


## 0 = seedling, 1 = young tree.
func sapling_stage(t: Vector2i) -> int:
	return 0 if saplings.get(t, 0.0) > SAPLING_GROW * 0.5 else 1


## Where a forester at `center` should plant next: the nearest plantable
## tile, preferring ones that grow an existing wood or plantation.
func find_plant_site(center: Vector2i, radius: int) -> Vector2i:
	var best := INVALID_TILE
	var best_score := INF
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var t := center + Vector2i(dx, dy)
			if maxi(absi(dx), absi(dy)) < 2 or not is_plantable(t):
				continue
			var score := float(dx * dx + dy * dy)
			if _touches_trees(t):
				score -= 12.0
			if score < best_score:
				best_score = score
				best = t
	return best


func count_saplings(center: Vector2i, radius: int) -> int:
	var n := 0
	for t: Vector2i in saplings:
		if absi(t.x - center.x) <= radius and absi(t.y - center.y) <= radius:
			n += 1
	return n


func _touches_trees(t: Vector2i) -> bool:
	for off in NEIGHBORS:
		var n: Vector2i = t + off
		if is_in_bounds(n) and (get_terrain(n) == Terrain.FOREST or saplings.has(n)):
			return true
	return false


func _grow_forests(dt: float) -> void:
	for t: Vector2i in saplings.keys():
		if get_terrain(t) != Terrain.GRASS or occupancy.has(t) or roads.has(t) or fields.has(t):
			saplings.erase(t)  # built over: the sapling is gone
			renderer.nature.refresh_tile(t)
			continue
		var stage := sapling_stage(t)
		saplings[t] -= dt
		if saplings[t] <= 0.0:
			saplings.erase(t)
			set_terrain(t, Terrain.FOREST)
		elif sapling_stage(t) != stage:
			renderer.nature.refresh_tile(t)
	for t: Vector2i in cleared.keys():
		if get_terrain(t) != Terrain.GRASS or occupancy.has(t) or roads.has(t) or fields.has(t):
			cleared.erase(t)
			continue
		cleared[t] += dt
		if cleared[t] >= REGROW_DELAY and is_plantable(t) and _touches_trees(t):
			plant_sapling(t)



# --- Buildings --------------------------------------------------------------

## Returns "" when placement is valid, otherwise a player-facing reason.
func can_place_building(id: String, origin: Vector2i) -> String:
	var def := BuildingDefs.get_def(id)
	if BuildingDefs.is_fortification(def):
		return _can_place_fortification(def, origin)
	var size: Vector2i = def.size
	for dy in size.y:
		for dx in size.x:
			var t := origin + Vector2i(dx, dy)
			if not is_in_bounds(t):
				return "Out of bounds"
			if occupancy.has(t) or roads.has(t):
				return "Space is blocked"
			if entrances.has(t):
				return "Would block an entrance"
			if in_castle_grounds(t):
				return "Castle grounds are reserved"
			if not Terrain.is_buildable(get_terrain(t)):
				return "Must build on clear ground"
	var e := BuildingDefs.entrance_of(origin, size)
	if not def.get("decor", false) and (not is_in_bounds(e) or occupancy.has(e) or get_terrain(e) == Terrain.WATER):
		return "Entrance is blocked"
	if def.get("decor", false):
		return ""  # decorations have no door
	if def.has("gather_terrain") and find_resource_tiles(e, def.gather_terrain, def.radius, 1).is_empty():
		return "No %s nearby" % Terrain.NAMES[def.gather_terrain].to_lower()
	if def.has("fields") and field_candidates(origin, size, def.field_radius).size() < def.min_fields:
		return "Not enough open land for fields"
	return ""


func _can_place_fortification(def: Dictionary, t: Vector2i) -> String:
	if not is_in_bounds(t):
		return "Out of bounds"
	if occupancy.has(t):
		return "Space is blocked"
	if entrances.has(t):
		return "Would block an entrance"
	if in_castle_grounds(t):
		return "Castle grounds are reserved"
	if roads.has(t) and not def.get("gate", false):
		return "Walls can't go on roads (use a Gate)"
	if not roads.has(t) and not Terrain.is_buildable(get_terrain(t)):
		return "Must build on clear ground"
	return ""


func place_building(id: String, origin: Vector2i) -> Building:
	var b := Building.new()
	b.setup(self, id, origin)
	building_root.add_child(b)
	buildings.append(b)
	for t in b.footprint():
		occupancy[t] = b
		_update_nav(t)
		renderer.nature.refresh_tile(t)
	if not BuildingDefs.is_fortification(b.def) and not b.def.get("decor", false):
		entrances[b.entrance()] = b
	if b.def.has("fields"):
		_allocate_fields(b)
	b.refresh_road_access()
	_redraw_fortifications_around(b)
	recompute_capacity()
	if not b.def.get("decor", false):
		renderer.nature.decorate_building(b)
	_desirability_dirty = true
	Sound.play("build", b.center())
	building_placed.emit(b)
	return b


func remove_building(b: Building) -> void:
	for t in b.footprint():
		occupancy.erase(t)
		_update_nav(t)
		renderer.nature.refresh_tile(t)
	if entrances.get(b.entrance()) == b:
		entrances.erase(b.entrance())
	for t in b.fields:
		if fields.has(t) and fields[t].farm == b:
			set_terrain(t, Terrain.GRASS)
	buildings.erase(b)
	_desirability_dirty = true
	_redraw_fortifications_around(b)
	recompute_capacity()
	building_removed.emit(b)
	b.queue_free()


## Wall segments draw links to their neighbours, so repaint those next to `b`.
func _redraw_fortifications_around(b: Building) -> void:
	if not BuildingDefs.is_fortification(b.def):
		return
	for off in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
		var n: Building = occupancy.get(b.origin + off)
		if n != null and n != b:
			n.queue_redraw()


## Every wall piece joined to `b` (walls, gates, towers), walking along
## neighbouring fortification tiles.
func connected_wall(b: Building) -> Array[Building]:
	var found: Array[Building] = []
	var seen := {b.origin: true}
	var queue: Array[Vector2i] = [b.origin]
	while not queue.is_empty():
		var t: Vector2i = queue.pop_back()
		var here: Building = occupancy.get(t)
		if here == null or not BuildingDefs.is_fortification(here.def):
			continue
		found.append(here)
		for off in [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)]:
			var n: Vector2i = t + off
			if not seen.has(n):
				seen[n] = true
				queue.append(n)
	return found


## Replaces every palisade joined to `b` with stone wall (gates and towers
## stay). Returns "" or why not.
func upgrade_wall_to_stone(b: Building) -> String:
	var palisades := connected_wall(b).filter(func(w: Building) -> bool: return w.def_id == "palisade")
	var cost := {}
	for item: String in BuildingDefs.get_def("stone_wall").cost:
		cost[item] = BuildingDefs.get_def("stone_wall").cost[item] * palisades.size()
	if palisades.is_empty():
		return "No palisade to upgrade."
	if not GameState.spend(cost):
		return "Upgrading %d segments needs %s." % [palisades.size(), BuildingDefs.cost_text(cost)]
	for p: Building in palisades:
		var t := p.origin
		remove_building(p)
		place_building("stone_wall", t)
	GameState.notify("%d palisade segments rebuilt in stone." % palisades.size())
	return ""


# --- Beauty -------------------------------------------------------------------

var desirability := PackedFloat32Array()
var _desirability_dirty := true


## How pleasant a tile is to live by (BeautyDefs): decorations and some
## civic buildings add, industry and storage subtract.
func desirability_at(t: Vector2i) -> float:
	if not is_in_bounds(t) or desirability.is_empty():
		return 0.0
	return desirability[t.y * width + t.x]


## Average desirability over a building's footprint.
func building_desirability(b: Building) -> float:
	var total := 0.0
	var tiles := b.footprint()
	for t in tiles:
		total += desirability_at(t)
	return total / maxf(tiles.size(), 1.0)


func _recompute_desirability() -> void:
	_desirability_dirty = false
	desirability.resize(width * height)
	desirability.fill(0.0)
	for b in buildings:
		var src: Array = BeautyDefs.SOURCES.get(b.def_id, [])
		if not src.is_empty():
			_spread(b.origin + b.size / 2, src[0], src[1], b.size.x / 2)
	for t: Vector2i in plazas:
		_spread(t, BeautyDefs.PLAZA[0], BeautyDefs.PLAZA[1], 0)
	for t: Vector2i in road_tiers:
		var paving: Array = BeautyDefs.PAVING[road_tiers[t]]
		_spread(t, paving[0], paving[1], 0)
	for i in desirability.size():
		desirability[i] = clampf(desirability[i], BeautyDefs.MIN, BeautyDefs.MAX)


## Adds `value` around `center`, full strength out to `inner` tiles, fading
## to zero just past `inner + radius`.
func _spread(center: Vector2i, value: float, radius: int, inner: int) -> void:
	var reach := radius + inner
	for dy in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var t := center + Vector2i(dx, dy)
			if not is_in_bounds(t):
				continue
			var d := maxf(Vector2(dx, dy).length() - inner, 0.0)
			if d > radius + 0.5:
				continue
			desirability[t.y * width + t.x] += value * (1.0 - d / (radius + 1.0))


## Paves road tiles (laying road first where there's none) as plaza,
## 3 stone a tile. Returns the number paved; road_problem says why not.
func place_plazas(tiles: Array[Vector2i]) -> int:
	road_problem = ""
	var cost: Dictionary = BuildingDefs.get_def("plaza").cost
	var paved := 0
	for t in tiles:
		if plazas.has(t) or get_terrain(t) == Terrain.WATER:
			continue
		if not roads.has(t) and not can_place_road(t):
			continue
		if not GameState.spend(cost):
			road_problem = "Ran out of stone after %d plaza tiles" % paved
			break
		if not roads.has(t):
			var one: Array[Vector2i] = [t]
			place_roads(one)
		plazas[t] = true
		renderer.refresh_tile(t)
		paved += 1
	if paved > 0:
		_desirability_dirty = true
		roads_changed.emit()
	return paved


## Lays or upgrades road to `tier` (1 cobblestone, 2 paved) along `tiles`.
## New road where there's none; dirt or cobbles are raised; bridges and
## plazas are left alone. Returns tiles done; road_problem says why not.
func place_road_tier(tiles: Array[Vector2i], tier: int) -> int:
	road_problem = ""
	var cost: Dictionary = BuildingDefs.get_def(["", "cobble_road", "paved_road"][tier]).cost
	var done := 0
	for t in tiles:
		if get_terrain(t) == Terrain.WATER or plazas.has(t) or road_tiers.get(t, 0) >= tier:
			continue
		if not roads.has(t) and not can_place_road(t):
			continue
		if not GameState.spend(cost):
			road_problem = "Ran out after %d tiles (%s each)" % [done, BuildingDefs.cost_text(cost)]
			break
		if not roads.has(t):
			var one: Array[Vector2i] = [t]
			place_roads(one)
		road_tiers[t] = tier
		renderer.refresh_tile(t)
		done += 1
	if done > 0:
		_desirability_dirty = true
		roads_changed.emit()
	return done


func road_tier_at(t: Vector2i) -> int:
	return road_tiers.get(t, 0) if roads.has(t) else -1


func restore_road_tiers(saved: Array) -> void:
	road_tiers.clear()
	for e: Array in saved:
		var t := Vector2i(int(e[0]), int(e[1]))
		if roads.has(t):
			road_tiers[t] = int(e[2])
	_desirability_dirty = true


## Counts walkers per tile, and adds to each road tile's recent use (which
## fades over a couple of minutes).
func _count_traffic(elapsed: float) -> void:
	traffic.clear()
	for group in ["villagers", "townsfolk"]:
		for w in get_tree().get_nodes_in_group(group):
			if w.visible:
				var t := world_to_tile(w.position)
				traffic[t] = traffic.get(t, 0) + 1
	var fade := pow(0.5, elapsed / 60.0)
	for t: Vector2i in road_use.keys():
		road_use[t] *= fade
		if road_use[t] < 0.05:
			road_use.erase(t)
	for t: Vector2i in traffic:
		if roads.has(t):
			road_use[t] = road_use.get(t, 0.0) + traffic[t] * elapsed


func restore_plazas(tiles: Array) -> void:
	plazas.clear()
	for t: Vector2i in tiles:
		if roads.has(t):
			plazas[t] = true
	_desirability_dirty = true


func in_castle_grounds(t: Vector2i) -> bool:
	return castle_grounds.has_area() and castle_grounds.has_point(t)


## Grows (or sets) the castle to `s` x `s`, centred in its grounds. Roads
## under the new footprint go; the gate's road is extended to the old
## approach road if needed.
func resize_keep(s: int) -> void:
	if keep == null or keep.size == Vector2i(s, s):
		return
	for t in keep.footprint():
		occupancy.erase(t)
	if entrances.get(keep.entrance()) == keep:
		entrances.erase(keep.entrance())
	var old := keep.footprint()
	var center := castle_grounds.get_center()
	keep.origin = Vector2i(center) - Vector2i(s / 2, s / 2)
	keep.size = Vector2i(s, s)
	keep.position = Vector2(keep.origin * T)
	for t in keep.footprint():
		occupancy[t] = keep
		roads.erase(t)
		fields.erase(t)
		saplings.erase(t)
	entrances[keep.entrance()] = keep
	var e := keep.entrance()
	var y := e.y
	while is_in_bounds(Vector2i(e.x, y)) and not roads.has(Vector2i(e.x, y)) and y <= castle_grounds.end.y + 2:
		roads[Vector2i(e.x, y)] = true
		y += 1
	roads[e] = true
	for t in old + keep.footprint() + [e]:
		_update_nav(t)
		renderer.refresh_tile(t)
	_refresh_road_access()
	roads_changed.emit()
	keep.queue_redraw()
	recompute_capacity()


## Called when a building's health reaches zero.
func destroy_building(b: Building) -> void:
	if b == keep:
		keep_destroyed.emit()
		return
	GameState.notify("%s was destroyed!" % b.def.name)
	Sound.play("crash", b.center())
	remove_building(b)


## Any raider (not lairs, but their guards) within `radius`. Villagers call
## this constantly during raids, so it stops at the first hit and allocates
## nothing.
func enemy_within(pos: Vector2, radius: float) -> bool:
	var r2 := radius * radius
	for list: Array[Enemy] in [enemies, wild]:
		for e in list:
			if pos.distance_squared_to(e.position) <= r2 and not e.is_lair() and not e.health.is_dead():
				return true
	return false


## Raiders plus lairs and their guards.
func hostiles() -> Array[Enemy]:
	var all: Array[Enemy] = enemies.duplicate()
	all.append_array(wild)
	return all


func lairs() -> Array[Enemy]:
	var found: Array[Enemy] = []
	found.assign(wild.filter(func(e: Enemy) -> bool: return e.is_lair() and not e.health.is_dead()))
	return found


func nearest_enemy(pos: Vector2, radius: float, include_flying := true) -> Enemy:
	var best: Enemy = null
	var best_dist := radius * radius
	for list: Array[Enemy] in [enemies, wild]:
		for e in list:
			var d := pos.distance_squared_to(e.position)
			if d > best_dist or e.health.is_dead() or e.is_lair() or (e.is_flying() and not include_flying):
				continue
			best_dist = d
			best = e
	return best


## Demolishes whatever is on tile `t`. Returns a message to show, or "".
func demolish_at(t: Vector2i) -> String:
	if occupancy.has(t) or roads.has(t):
		Sound.play("demolish", tile_center(t))
	if occupancy.has(t):
		var b: Building = occupancy[t]
		if b == keep:
			return "The Keep cannot be demolished"
		GameState.refund(b.def.cost, 0.5)
		var goods: Dictionary = b.inventory.duplicate()
		for item: String in b.output_stock:
			goods[item] = goods.get(item, 0) + b.output_stock[item]
		remove_building(b)
		# Demolishing (unlike destruction) moves what was inside elsewhere.
		for item: String in goods:
			GameState.add_resource(item, goods[item])
		return ""
	if roads.has(t):
		if get_terrain(t) == Terrain.WATER:
			GameState.refund(BRIDGE_COST, 0.5)
		if plazas.has(t) or road_tiers.has(t):
			plazas.erase(t)
			road_tiers.erase(t)
			_desirability_dirty = true
		roads.erase(t)
		renderer.refresh_tile(t)
		_update_nav(t)
		_refresh_road_access()
	return ""


func recompute_capacity() -> void:
	GameState.refresh_capacity()


# --- Fields -----------------------------------------------------------------

## Open tiles within `radius` of a footprint that a farm could till, nearest first.
func field_candidates(origin: Vector2i, size: Vector2i, radius: int) -> Array[Vector2i]:
	var footprint := Rect2i(origin, size)
	var e := BuildingDefs.entrance_of(origin, size)
	var center := Vector2(origin) + Vector2(size) * 0.5
	var found: Array[Vector2i] = []
	for y in range(origin.y - radius, origin.y + size.y + radius):
		for x in range(origin.x - radius, origin.x + size.x + radius):
			var t := Vector2i(x, y)
			if footprint.has_point(t) or t == e or not is_in_bounds(t):
				continue
			if Terrain.is_buildable(get_terrain(t)) and not occupancy.has(t) and not roads.has(t) \
					and not entrances.has(t) and not fields.has(t) and not in_castle_grounds(t):
				found.append(t)
	found.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return center.distance_squared_to(Vector2(a)) < center.distance_squared_to(Vector2(b)))
	return found


func _allocate_fields(farm: Building) -> void:
	var def := farm.def
	for t in field_candidates(farm.origin, farm.size, def.field_radius).slice(0, def.fields):
		set_terrain(t, Terrain.FIELD)
		fields[t] = {"farm": farm, "stage": FieldStage.TILLED, "timer": 0.0}
		farm.fields.append(t)


func _set_field_stage(t: Vector2i, stage: int) -> void:
	fields[t].stage = stage
	renderer.refresh_tile(t)


## Nearest unreserved field of `farm` in `stage`, or INVALID_TILE.
func find_field(farm: Building, stage: int) -> Vector2i:
	var best := INVALID_TILE
	var best_dist := INF
	var e := Vector2(farm.entrance())
	for t in farm.fields:
		if not fields.has(t) or fields[t].farm != farm or fields[t].stage != stage or reserved.has(t):
			continue
		var d := e.distance_squared_to(Vector2(t))
		if d < best_dist:
			best_dist = d
			best = t
	return best


func count_fields(farm: Building, stage: int) -> int:
	var n := 0
	for t in farm.fields:
		if fields.has(t) and fields[t].farm == farm and fields[t].stage == stage:
			n += 1
	return n


func plant_field(t: Vector2i) -> void:
	if fields.has(t) and fields[t].stage == FieldStage.TILLED:
		var farm: Building = fields[t].farm
		fields[t].timer = farm.def.grow_time * randf_range(0.9, 1.1)
		_set_field_stage(t, FieldStage.GROWING)


## Returns the wheat harvested (0 if the field was not ripe).
func harvest_field(t: Vector2i) -> int:
	if not fields.has(t) or fields[t].stage != FieldStage.RIPE:
		return 0
	var farm: Building = fields[t].farm
	_set_field_stage(t, FieldStage.TILLED)
	return roundi(farm.def.yield * GameState.mod("farm_yield"))


# --- Roads ------------------------------------------------------------------

## Why the last place_roads left something out ("" if it didn't).
var road_problem := ""
const MAX_BRIDGE := 5
const BRIDGE_COST := {"wood": 6, "stone": 2}


func can_place_road(t: Vector2i) -> bool:
	return is_in_bounds(t) and not occupancy.has(t) and not roads.has(t) and get_terrain(t) != Terrain.WATER


# --- Loading a save (see SaveGame) ----------------------------------------------

## Replaces every road with `tiles`.
func restore_roads(tiles: Array) -> void:
	var old := roads.keys()
	roads.clear()
	for t: Vector2i in tiles:
		roads[t] = true
	for t: Vector2i in old + tiles:
		renderer.refresh_tile(t)
		_update_nav(t)
	_refresh_road_access()


## Overwrites the whole terrain grid, then redraws and rebuilds navigation.
func restore_terrain(p_terrain: PackedByteArray, p_resource_left: PackedInt32Array) -> void:
	if p_terrain.size() != width * height or p_resource_left.size() != width * height:
		push_error("save terrain has the wrong size")
		return
	terrain = p_terrain
	resource_left = p_resource_left
	renderer.rebuild()
	for y in height:
		for x in width:
			_update_nav(Vector2i(x, y))


## Saplings and cleared forest from a save: [[x, y, seconds], ...].
func restore_forests(p_saplings: Array, p_cleared: Array) -> void:
	var old := saplings.keys()
	saplings.clear()
	cleared.clear()
	for e: Array in p_saplings:
		saplings[Vector2i(int(e[0]), int(e[1]))] = float(e[2])
	for e: Array in p_cleared:
		cleared[Vector2i(int(e[0]), int(e[1]))] = float(e[2])
	for t: Vector2i in old + saplings.keys():
		renderer.nature.refresh_tile(t)


## Replaces farm fields with saved ones: [{t, farm, stage, timer}].
func restore_fields(saved: Array) -> void:
	for b in buildings:
		b.fields.clear()
	fields.clear()
	for f: Dictionary in saved:
		var farm: Building = f.farm
		if farm == null:
			continue
		fields[f.t] = {"farm": farm, "stage": f.stage, "timer": f.timer}
		farm.fields.append(f.t)
		renderer.refresh_tile(f.t)


## Places roads on every valid tile of a drag, clearing trees and rocks.
## Water crossings become bridges (see bridge_spans): each span is paid for
## as a whole or not built. Returns the count placed; road_problem says why
## a bridge wasn't built.
func place_roads(tiles: Array[Vector2i]) -> int:
	road_problem = ""
	var placed := 0
	var spans := bridge_spans(tiles)
	var bridged := {}
	for span: Array in spans.valid:
		var cost := bridge_cost(span.size())
		if not GameState.spend(cost):
			road_problem = "Not enough for a %d-tile bridge (%s)" % [span.size(), BuildingDefs.cost_text(cost)]
			continue
		for t: Vector2i in span:
			bridged[t] = true
	if spans.too_long > 0 and road_problem == "":
		road_problem = "Bridges can span at most %d tiles of water, with land at both ends" % MAX_BRIDGE
	for t in tiles:
		if bridged.has(t):
			roads[t] = true
		elif can_place_road(t):
			if not Terrain.is_buildable(get_terrain(t)):
				set_terrain(t, Terrain.GRASS)
			roads[t] = true
		else:
			continue
		renderer.refresh_tile(t)
		_update_nav(t)
		placed += 1
	if placed > 0:
		_refresh_road_access()
		Sound.play("road", tile_center(tiles[tiles.size() - 1]))
	return placed


func is_bridge(t: Vector2i) -> bool:
	return roads.has(t) and get_terrain(t) == Terrain.WATER


static func bridge_cost(length: int) -> Dictionary:
	var cost := {}
	for item: String in BRIDGE_COST:
		cost[item] = BRIDGE_COST[item] * length
	return cost


## Splits a road drag into its water crossings. A crossing can be bridged
## when it is at most MAX_BRIDGE tiles and the drag has land (or an existing
## bridge/road) right before and after it.
## -> {"valid": [[tiles...], ...], "too_long": count of rejected crossings}
func bridge_spans(tiles: Array[Vector2i]) -> Dictionary:
	var valid := []
	var too_long := 0
	var run: Array[Vector2i] = []
	var land_before := false
	for i in tiles.size() + 1:
		var t: Vector2i = tiles[i] if i < tiles.size() else INVALID_TILE
		var water := i < tiles.size() and is_in_bounds(t) and get_terrain(t) == Terrain.WATER and not roads.has(t)
		if water:
			run.append(t)
			continue
		if not run.is_empty():
			var land_after := i < tiles.size() and is_in_bounds(t) and not occupancy.has(t)
			if land_before and land_after and run.size() <= MAX_BRIDGE:
				valid.append(run.duplicate())
			else:
				too_long += 1
			run.clear()
		land_before = i < tiles.size() and is_in_bounds(t)
	return {"valid": valid, "too_long": too_long}


func is_road(t: Vector2i) -> bool:
	return roads.has(t)


func _refresh_road_access() -> void:
	for b in buildings:
		b.refresh_road_access()
	roads_changed.emit()
