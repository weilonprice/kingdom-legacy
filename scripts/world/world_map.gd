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
## True while raiders are on the map; villagers hide.
var raid_active := false
var keep: Building

var terrain_layer: TileMapLayer
var road_layer: TileMapLayer
var building_root: Node2D
var unit_root: Node2D
var astar := AStarGrid2D.new()


func _ready() -> void:
	GameState.modifiers_changed.connect(recompute_capacity)
	var tileset := Terrain.build_tileset()
	terrain_layer = TileMapLayer.new()
	terrain_layer.tile_set = tileset
	add_child(terrain_layer)
	road_layer = TileMapLayer.new()
	road_layer.tile_set = tileset
	road_layer.z_index = 1
	add_child(road_layer)
	building_root = Node2D.new()
	building_root.z_index = 2
	add_child(building_root)
	unit_root = Node2D.new()
	unit_root.z_index = 3
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

	for y in height:
		for x in width:
			var t := Vector2i(x, y)
			terrain_layer.set_cell(t, 0, Vector2i(get_terrain(t), 0))

	astar.region = Rect2i(0, 0, width, height)
	astar.cell_size = Vector2(T, T)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	astar.update()
	for y in height:
		for x in width:
			_update_nav(Vector2i(x, y))

	_place_start(center)


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
	terrain_layer.set_cell(t, 0, Vector2i(type, 0))
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
	var solid := get_terrain(t) == Terrain.WATER or occupancy.has(t)
	astar.set_point_solid(t, solid)
	if not solid:
		astar.set_point_weight_scale(t, 1.0 if roads.has(t) else Terrain.walk_cost(get_terrain(t)))


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


## Nearest storage building that accepts `item`'s category.
func nearest_storage_for(item: String, from: Vector2i) -> Building:
	var category := ItemDefs.category_of(item)
	var best: Building = null
	var best_dist := INF
	for b in buildings:
		if not category in b.def.get("accepts", []):
			continue
		var d := Vector2(b.entrance()).distance_squared_to(Vector2(from))
		if d < best_dist:
			best_dist = d
			best = b
	return best


# --- Buildings --------------------------------------------------------------

## Returns "" when placement is valid, otherwise a player-facing reason.
func can_place_building(id: String, origin: Vector2i) -> String:
	var def := BuildingDefs.get_def(id)
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


func place_building(id: String, origin: Vector2i) -> Building:
	var b := Building.new()
	b.setup(self, id, origin)
	building_root.add_child(b)
	buildings.append(b)
	for t in b.footprint():
		occupancy[t] = b
		_update_nav(t)
	entrances[b.entrance()] = b
	if b.def.has("fields"):
		_allocate_fields(b)
	b.refresh_road_access()
	recompute_capacity()
	building_placed.emit(b)
	return b


func remove_building(b: Building) -> void:
	for t in b.footprint():
		occupancy.erase(t)
		_update_nav(t)
	entrances.erase(b.entrance())
	for t in b.fields:
		if fields.has(t) and fields[t].farm == b:
			set_terrain(t, Terrain.GRASS)
	buildings.erase(b)
	recompute_capacity()
	building_removed.emit(b)
	b.queue_free()


## Called when a building's health reaches zero.
func destroy_building(b: Building) -> void:
	if b == keep:
		keep_destroyed.emit()
		return
	GameState.notify("%s was destroyed!" % b.def.name)
	remove_building(b)


func enemy_within(pos: Vector2, radius: float) -> bool:
	return nearest_enemy(pos, radius) != null


func nearest_enemy(pos: Vector2, radius: float) -> Enemy:
	var best: Enemy = null
	var best_dist := radius * radius
	for e in enemies:
		if e.health.is_dead():
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
		remove_building(b)
		return ""
	if roads.has(t):
		roads.erase(t)
		road_layer.erase_cell(t)
		_update_nav(t)
		_refresh_road_access()
	return ""


func recompute_capacity() -> void:
	var cap := {}
	for b in buildings:
		for category: String in b.def.get("accepts", []):
			cap[category] = cap.get(category, 0) + b.storage_capacity()
	GameState.set_capacity(cap)


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
	terrain_layer.set_cell(t, 0, Terrain.FIELD_ATLAS[stage])


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
		road_layer.set_cell(t, 0, Terrain.ROAD_ATLAS)
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
