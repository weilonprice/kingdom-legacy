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
var occupancy := {}    # Vector2i -> Building
var entrances := {}    # Vector2i -> Building
var reserved := {}     # Vector2i -> Object reserving that resource tile
var fields := {}       # Vector2i -> {"farm": Building, "stage": FieldStage, "timer": float}
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


func _process(delta: float) -> void:
	for t: Vector2i in fields:
		var field: Dictionary = fields[t]
		if field.stage == FieldStage.GROWING:
			field.timer -= delta
			if field.timer <= 0.0:
				_set_field_stage(t, FieldStage.RIPE)


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

	# Guarantee a buildable start with wood and stone within reach.
	var center := Vector2i(width >> 1, height >> 1)
	_stamp(center, 8, Terrain.GRASS)
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
	keep = place_building("keep", center - Vector2i(1, 1))
	var e := keep.entrance()
	var road_tiles: Array[Vector2i] = []
	for dy in 4:
		road_tiles.append(e + Vector2i(0, dy))
	for dx in range(-5, 6):
		road_tiles.append(e + Vector2i(dx, 3))
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
func speed_multiplier(t: Vector2i) -> float:
	if not is_in_bounds(t):
		return 1.0
	if roads.has(t):
		return 1.6
	if get_terrain(t) == Terrain.FOREST:
		return 0.7
	return 1.0


func describe_tile(t: Vector2i) -> String:
	if not is_in_bounds(t):
		return ""
	if occupancy.has(t):
		return occupancy[t].describe()
	if roads.has(t):
		return "Road"
	if fields.has(t):
		return "Field — %s" % ["Tilled", "Growing", "Ripe"][fields[t].stage]
	var text: String = Terrain.NAMES[get_terrain(t)]
	var left := resource_left[t.y * width + t.x]
	if left > 0:
		text += " (%d harvests left)" % left
	return text


# --- Pathfinding ------------------------------------------------------------

func _update_nav(t: Vector2i) -> void:
	var water := get_terrain(t) == Terrain.WATER
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
	return amount



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
			if not Terrain.is_buildable(get_terrain(t)):
				return "Must build on clear ground"
	var e := BuildingDefs.entrance_of(origin, size)
	if not is_in_bounds(e) or occupancy.has(e) or get_terrain(e) == Terrain.WATER:
		return "Entrance is blocked"
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
	if not BuildingDefs.is_fortification(b.def):
		entrances[b.entrance()] = b
	if b.def.has("fields"):
		_allocate_fields(b)
	b.refresh_road_access()
	_redraw_fortifications_around(b)
	recompute_capacity()
	building_placed.emit(b)
	return b


func remove_building(b: Building) -> void:
	for t in b.footprint():
		occupancy.erase(t)
		_update_nav(t)
	if entrances.get(b.entrance()) == b:
		entrances.erase(b.entrance())
	for t in b.fields:
		if fields.has(t) and fields[t].farm == b:
			set_terrain(t, Terrain.GRASS)
	buildings.erase(b)
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


## Called when a building's health reaches zero.
func destroy_building(b: Building) -> void:
	if b == keep:
		keep_destroyed.emit()
		return
	GameState.notify("%s was destroyed!" % b.def.name)
	remove_building(b)


func enemy_within(pos: Vector2, radius: float) -> bool:
	return nearest_enemy(pos, radius) != null


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
	for e in hostiles():
		if e.health.is_dead() or e.is_lair() or (e.is_flying() and not include_flying):
			continue
		var d := pos.distance_squared_to(e.position)
		if d <= best_dist:
			best_dist = d
			best = e
	return best


## Demolishes whatever is on tile `t`. Returns a message to show, or "".
func demolish_at(t: Vector2i) -> String:
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
					and not entrances.has(t) and not fields.has(t):
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

func can_place_road(t: Vector2i) -> bool:
	return is_in_bounds(t) and not occupancy.has(t) and not roads.has(t) and get_terrain(t) != Terrain.WATER


## Places roads on every valid tile, clearing trees and rocks. Returns count placed.
func place_roads(tiles: Array[Vector2i]) -> int:
	var placed := 0
	for t in tiles:
		if not can_place_road(t):
			continue
		if not Terrain.is_buildable(get_terrain(t)):
			set_terrain(t, Terrain.GRASS)
		roads[t] = true
		renderer.refresh_tile(t)
		_update_nav(t)
		placed += 1
	if placed > 0:
		_refresh_road_access()
	return placed


func is_road(t: Vector2i) -> bool:
	return roads.has(t)


func _refresh_road_access() -> void:
	for b in buildings:
		b.refresh_road_access()
	roads_changed.emit()
