class_name TerrainRenderer
extends Node2D
## Draws the map. A base layer paints grass everywhere (plus field stages);
## then each terrain with PixelLab art gets its own "dual grid" overlay: a
## TileMapLayer shifted half a tile up-left, where each cell sits on the
## corner shared by four map tiles and picks the Wang tile matching which of
## those four are that terrain. That gives smooth shores, forest edges and
## one-tile-wide roads from 16-tile corner sets.
##
## Terrain without art falls back to the code-drawn tile on the base layer.

## Overlay order = draw order. `lower` notes which terrain the tileset blends
## into (water's shore blends into sand, so sand also covers water tiles).
const OVERLAYS := [
	{"name": "grass_sand", "terrains": [Terrain.SAND, Terrain.WATER]},
	{"name": "sand_water", "terrains": [Terrain.WATER]},
	{"name": "grass_stone", "terrains": [Terrain.STONE]},
	{"name": "grass_forest", "terrains": [Terrain.FOREST]},
	{"name": "grass_dirt", "roads": true},
]
const CODE_SOURCE := 0
const GRASS_SOURCE := 1
## Sources 2..4: field stages (tilled, growing, ripe) when their art exists.
const FIELD_SOURCE := 2
const FIELD_ART := "res://assets/tiles/field_%d.png"

var world: WorldMap
var base: TileMapLayer
## Per overlay: {"layer": TileMapLayer, "tiles": {corner_key: atlas}, "terrains": [], "roads": bool}
var overlays: Array[Dictionary] = []
## Fallback per-tile road layer when there's no road tileset.
var road_fallback: TileMapLayer

var _art_terrains := {}   # terrain type -> true when an overlay draws it
var _fields_have_art := false
var _roads_have_art := false


func setup(p_world: WorldMap) -> void:
	world = p_world
	var tileset := Terrain.build_tileset()
	var grass: Variant = Art.wang("grass_dirt")
	if grass != null:
		var src := TileSetAtlasSource.new()
		src.texture = grass.texture
		src.texture_region_size = Vector2i(Terrain.TILE_SIZE, Terrain.TILE_SIZE)
		src.create_tile(grass.tiles["0000"])
		tileset.add_source(src, GRASS_SOURCE)
	_fields_have_art = range(3).all(func(i: int) -> bool: return Art.texture(FIELD_ART % i) != null)
	if _fields_have_art:
		for i in 3:
			var fsrc := TileSetAtlasSource.new()
			fsrc.texture = Art.texture(FIELD_ART % i)
			fsrc.texture_region_size = Vector2i(Terrain.TILE_SIZE, Terrain.TILE_SIZE)
			fsrc.create_tile(Vector2i.ZERO)
			tileset.add_source(fsrc, FIELD_SOURCE + i)
	base = TileMapLayer.new()
	base.tile_set = tileset
	add_child(base)

	road_fallback = TileMapLayer.new()
	road_fallback.tile_set = tileset
	add_child(road_fallback)

	for spec: Dictionary in OVERLAYS:
		var art: Variant = Art.wang(spec.name)
		if art == null or grass == null:
			continue
		var ts := TileSet.new()
		ts.tile_size = Vector2i(Terrain.TILE_SIZE, Terrain.TILE_SIZE)
		var src := TileSetAtlasSource.new()
		src.texture = art.texture
		src.texture_region_size = Vector2i(Terrain.TILE_SIZE, Terrain.TILE_SIZE)
		for key: String in art.tiles:
			if not src.has_tile(art.tiles[key]):
				src.create_tile(art.tiles[key])
		ts.add_source(src, 0)
		var layer := TileMapLayer.new()
		layer.tile_set = ts
		layer.position = -Vector2(Terrain.TILE_SIZE, Terrain.TILE_SIZE) * 0.5
		add_child(layer)
		overlays.append({"layer": layer, "tiles": art.tiles,
			"terrains": spec.get("terrains", []), "roads": spec.get("roads", false)})
		for t: int in spec.get("terrains", []):
			_art_terrains[t] = true
		if spec.get("roads", false):
			_roads_have_art = true


func rebuild() -> void:
	for y in world.height:
		for x in world.width:
			_paint_base(Vector2i(x, y))
			_paint_road_fallback(Vector2i(x, y))
	for o in overlays:
		for y in world.height + 1:
			for x in world.width + 1:
				_paint_overlay_cell(o, Vector2i(x, y))


## Call after a tile's terrain or road status changes.
func refresh_tile(t: Vector2i) -> void:
	_paint_base(t)
	_paint_road_fallback(t)
	for o in overlays:
		for dy in 2:
			for dx in 2:
				_paint_overlay_cell(o, t + Vector2i(dx, dy))


func _paint_base(t: Vector2i) -> void:
	var type := world.get_terrain(t)
	if type == Terrain.FIELD:
		var stage: int = world.fields[t].stage if world.fields.has(t) else 0
		if _fields_have_art:
			base.set_cell(t, FIELD_SOURCE + stage, Vector2i.ZERO)
		else:
			base.set_cell(t, CODE_SOURCE, Terrain.FIELD_ATLAS[stage])
	elif base.tile_set.has_source(GRASS_SOURCE) and (type == Terrain.GRASS or _art_terrains.has(type)):
		base.set_cell(t, GRASS_SOURCE, Art.wang("grass_dirt").tiles["0000"])
	else:
		base.set_cell(t, CODE_SOURCE, Vector2i(type, 0))


func _paint_road_fallback(t: Vector2i) -> void:
	if not _roads_have_art and world.roads.has(t):
		road_fallback.set_cell(t, CODE_SOURCE, Terrain.ROAD_ATLAS)
	else:
		road_fallback.erase_cell(t)


func _matches(o: Dictionary, t: Vector2i) -> bool:
	if not world.is_in_bounds(t):
		return false
	if o.roads:
		return world.roads.has(t)
	return world.get_terrain(t) in o.terrains


## Dual-grid cell `c` covers the corner shared by map tiles c-(1,1) .. c.
func _paint_overlay_cell(o: Dictionary, c: Vector2i) -> void:
	var key := ""
	for off in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0)]:
		key += "1" if _matches(o, c + off) else "0"
	var layer: TileMapLayer = o.layer
	if key == "0000":
		layer.erase_cell(c)
	else:
		layer.set_cell(c, 0, o.tiles[key])
