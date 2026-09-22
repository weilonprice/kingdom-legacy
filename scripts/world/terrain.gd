class_name Terrain
extends RefCounted
## Terrain types, their rules, and a generated placeholder tileset.
## Swap build_tileset() for a PixelLab atlas later; keep the atlas order.

enum { WATER, SAND, GRASS, FOREST, STONE, FIELD }

const TILE_SIZE := 32
const NAMES := ["Water", "Sand", "Grass", "Forest", "Stone", "Field"]
const ROAD_ATLAS := Vector2i(6, 0)
## Field visuals by growth stage: tilled, growing, ripe.
const FIELD_ATLAS := [Vector2i(5, 0), Vector2i(7, 0), Vector2i(8, 0)]
const ATLAS_COUNT := 9

## How many times a tile can be harvested before it turns to grass.
const HARVESTS := {FOREST: 3, STONE: 8}


static func is_buildable(type: int) -> bool:
	return type == GRASS or type == SAND


## Pathfinding weight off-road. Roads always cost 1.0.
static func walk_cost(type: int) -> float:
	match type:
		FOREST:
			return 3.5
		STONE:
			return 3.0
		FIELD:
			return 2.5
		_:
			return 2.0


static func build_tileset() -> TileSet:
	var img := Image.create(TILE_SIZE * ATLAS_COUNT, TILE_SIZE, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7

	_paint_base(img, WATER, Color(0.20, 0.42, 0.70), Color(0.32, 0.56, 0.82), rng, 0)
	_paint_waves(img, WATER, rng)
	_paint_base(img, SAND, Color(0.86, 0.78, 0.52), Color(0.76, 0.67, 0.43), rng, 40)
	_paint_base(img, GRASS, Color(0.40, 0.62, 0.30), Color(0.34, 0.55, 0.25), rng, 60)
	_paint_base(img, FOREST, Color(0.36, 0.56, 0.27), Color(0.30, 0.49, 0.22), rng, 60)
	_paint_trees(img, FOREST)
	_paint_base(img, STONE, Color(0.50, 0.50, 0.48), Color(0.43, 0.43, 0.42), rng, 50)
	_paint_rocks(img, STONE)
	_paint_base(img, ROAD_ATLAS.x, Color(0.60, 0.47, 0.31), Color(0.51, 0.39, 0.25), rng, 50)
	var crop_colors := [Color(0, 0, 0, 0), Color(0.45, 0.72, 0.28), Color(0.93, 0.80, 0.35)]
	for stage in FIELD_ATLAS.size():
		var index: int = FIELD_ATLAS[stage].x
		_paint_base(img, index, Color(0.50, 0.35, 0.20), Color(0.44, 0.30, 0.17), rng, 30)
		_paint_furrows(img, index, crop_colors[stage], stage)

	var source := TileSetAtlasSource.new()
	source.texture = ImageTexture.create_from_image(img)
	source.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	for i in ATLAS_COUNT:
		source.create_tile(Vector2i(i, 0))

	var tileset := TileSet.new()
	tileset.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)
	tileset.add_source(source, 0)
	return tileset


static func _paint_base(img: Image, index: int, base: Color, speck: Color, rng: RandomNumberGenerator, specks: int) -> void:
	var ox := index * TILE_SIZE
	img.fill_rect(Rect2i(ox, 0, TILE_SIZE, TILE_SIZE), base)
	for i in specks:
		img.set_pixel(ox + rng.randi_range(0, TILE_SIZE - 1), rng.randi_range(0, TILE_SIZE - 1), speck)


static func _paint_furrows(img: Image, index: int, crop: Color, stage: int) -> void:
	var ox := index * TILE_SIZE
	for row in range(3, TILE_SIZE, 7):
		img.fill_rect(Rect2i(ox + 1, row, TILE_SIZE - 2, 2), Color(0.36, 0.24, 0.13))
		if stage == 0:
			continue
		var height := 2 if stage == 1 else 4
		for x in range(2, TILE_SIZE - 2, 3):
			img.fill_rect(Rect2i(ox + x, row - height + 1, 2, height), crop)


static func _paint_waves(img: Image, index: int, rng: RandomNumberGenerator) -> void:
	var ox := index * TILE_SIZE
	for i in 6:
		var x := rng.randi_range(0, TILE_SIZE - 5)
		var y := rng.randi_range(1, TILE_SIZE - 2)
		for dx in 4:
			img.set_pixel(ox + x + dx, y, Color(0.45, 0.66, 0.90))


static func _paint_trees(img: Image, index: int) -> void:
	for p in [Vector2i(9, 10), Vector2i(23, 11), Vector2i(15, 23)]:
		_circle(img, index, p + Vector2i(1, 2), 7, Color(0.12, 0.24, 0.10))
		_circle(img, index, p, 6, Color(0.17, 0.38, 0.15))
		_circle(img, index, p + Vector2i(-2, -2), 3, Color(0.25, 0.50, 0.20))


static func _paint_rocks(img: Image, index: int) -> void:
	for p in [Vector2i(9, 9), Vector2i(22, 13), Vector2i(12, 23), Vector2i(25, 25)]:
		_circle(img, index, p + Vector2i(1, 1), 5, Color(0.30, 0.30, 0.30))
		_circle(img, index, p, 4, Color(0.66, 0.66, 0.64))
		_circle(img, index, p + Vector2i(-1, -1), 2, Color(0.78, 0.78, 0.76))


static func _circle(img: Image, index: int, center: Vector2i, radius: int, color: Color) -> void:
	var ox := index * TILE_SIZE
	for dy in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if dx * dx + dy * dy > radius * radius:
				continue
			var x := center.x + dx
			var y := center.y + dy
			if x >= 0 and x < TILE_SIZE and y >= 0 and y < TILE_SIZE:
				img.set_pixel(ox + x, y, color)
