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
## Ripe crops besides wheat (field_2); each farm grows one, picked by its spot.
const CROPS := ["cabbage", "pumpkin", "tomato"]
const CROP_ART := "res://assets/tiles/crop_%s.png"
const CROP_SOURCE := 10

var world: WorldMap
var bridges: BridgeLayer
var plaza_layer: PlazaLayer
## Trees and props (see Nature). When there's tree art, forests are drawn as
## grass with trees standing on it instead of the forest tileset.
var nature: Nature
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
	nature = Nature.new(world)
	_build_layers()


## The season's art changed: rebuild the tile layers from the new tilesets
## and repaint everything (trees and props included).
func rebuild_art() -> void:
	for child in get_children():
		child.queue_free()
	overlays.clear()
	_art_terrains.clear()
	_roads_have_art = false
	_build_layers()
	rebuild()


func _build_layers() -> void:
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
		for c in CROPS.size():
			var ctex := Art.texture(CROP_ART % CROPS[c])
			if ctex == null:
				continue
			var csrc := TileSetAtlasSource.new()
			csrc.texture = ctex
			csrc.texture_region_size = Vector2i(Terrain.TILE_SIZE, Terrain.TILE_SIZE)
			csrc.create_tile(Vector2i.ZERO)
			tileset.add_source(csrc, CROP_SOURCE + c)
	base = TileMapLayer.new()
	base.tile_set = tileset
	add_child(base)

	road_fallback = TileMapLayer.new()
	road_fallback.tile_set = tileset
	add_child(road_fallback)

	if nature.has_trees():
		_art_terrains[Terrain.FOREST] = true
	if nature.has_rocks():
		_art_terrains[Terrain.STONE] = true
	for spec: Dictionary in OVERLAYS:
		if spec.name == "grass_forest" and nature.has_trees():
			continue
		if spec.name == "grass_stone" and nature.has_rocks():
			continue
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
	_add_bridge_layer()


func _add_bridge_layer() -> void:
	plaza_layer = PlazaLayer.new()
	plaza_layer.world = world
	add_child(plaza_layer)
	bridges = BridgeLayer.new()
	bridges.world = world
	add_child(bridges)


func rebuild() -> void:
	for y in world.height:
		for x in world.width:
			_paint_base(Vector2i(x, y))
			_paint_road_fallback(Vector2i(x, y))
	for o in overlays:
		for y in world.height + 1:
			for x in world.width + 1:
				_paint_overlay_cell(o, Vector2i(x, y))
	nature.rebuild()
	bridges.queue_redraw()
	plaza_layer.queue_redraw()


## Call after a tile's terrain or road status changes.
func refresh_tile(t: Vector2i) -> void:
	_paint_base(t)
	_paint_road_fallback(t)
	for o in overlays:
		for dy in 2:
			for dx in 2:
				_paint_overlay_cell(o, t + Vector2i(dx, dy))
	nature.refresh_tile(t)
	if bridges != null:
		bridges.queue_redraw()
	if plaza_layer != null:
		plaza_layer.queue_redraw()


func _paint_base(t: Vector2i) -> void:
	var type := world.get_terrain(t)
	if type == Terrain.FIELD:
		var stage: int = world.fields[t].stage if world.fields.has(t) else 0
		if _fields_have_art:
			base.set_cell(t, _field_source(t, stage), Vector2i.ZERO)
		else:
			base.set_cell(t, CODE_SOURCE, Terrain.FIELD_ATLAS[stage])
	elif base.tile_set.has_source(GRASS_SOURCE) and (type == Terrain.GRASS or _art_terrains.has(type)):
		base.set_cell(t, GRASS_SOURCE, Art.wang("grass_dirt").tiles["0000"])
	else:
		base.set_cell(t, CODE_SOURCE, Vector2i(type, 0))


## Ripe fields show their farm's crop: wheat, or one of CROPS.
func _field_source(t: Vector2i, stage: int) -> int:
	if stage != 2 or not world.fields.has(t):
		return FIELD_SOURCE + stage
	var farm: Building = world.fields[t].farm
	var pick := absi(hash(farm.origin)) % (CROPS.size() + 1)
	if pick == 0 or not base.tile_set.has_source(CROP_SOURCE + pick - 1):
		return FIELD_SOURCE + stage
	return CROP_SOURCE + pick - 1


func _paint_road_fallback(t: Vector2i) -> void:
	if not _roads_have_art and world.roads.has(t) and world.get_terrain(t) != Terrain.WATER:
		road_fallback.set_cell(t, CODE_SOURCE, Terrain.ROAD_ATLAS)
	else:
		road_fallback.erase_cell(t)


func _matches(o: Dictionary, t: Vector2i) -> bool:
	if not world.is_in_bounds(t):
		return false
	if o.roads:
		return world.roads.has(t) and world.get_terrain(t) != Terrain.WATER
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
