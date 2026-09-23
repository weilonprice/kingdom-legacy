class_name Nature
extends RefCounted
## Decoration that isn't terrain: individual trees standing on forest tiles,
## boulders on rocky tiles, small props (flowers, stumps...) scattered over
## open ground, and props beside buildings that suit them (crates by
## storehouses, hay by farms, firewood by woodcutters...).
## Sprites live under the world's y-sorted building root so villagers walk
## behind and in front of them. Everything is chosen by a hash of the tile,
## so the same map always decorates the same way. Without the art files
## nothing is drawn (the forest tileset overlay shows instead).

const TREES := {
	"": ["tree_summer_0", "tree_summer_0", "tree_pine_0"],
	"summer": ["tree_summer_0", "tree_summer_0", "tree_pine_0"],
	"autumn": ["tree_autumn_0", "tree_autumn_1", "tree_autumn_0", "tree_pine_0"],
	"winter": ["tree_pine_snow_0", "tree_bare_snow_0", "tree_pine_snow_0"],
}
const TREE_ART := "res://assets/sprites/nature/%s.png"
const PROP_ART := "res://assets/sprites/props/%s.png"
const ROCKS := ["rock_0", "rock_1", "rock_2", "rock_3"]
## Share of rocky tiles that show a boulder.
const ROCK_CHANCE := 0.35
## Props that suit each building; others get GENERIC_PROPS.
const BUILDING_PROPS := {
	"keep": ["crates", "barrel", "sacks", "lantern"],
	"stockpile": ["crates", "barrel", "sacks"],
	"warehouse": ["crates", "barrel", "sacks", "cart"],
	"granary": ["sacks", "haybale", "barrel"],
	"farm": ["haybale", "cart", "wheelbarrow", "pumpkins"],
	"mill": ["sacks", "haybale"],
	"bakery": ["sacks", "barrel", "firewood"],
	"woodcutter": ["firewood", "stump", "wheelbarrow"],
	"quarry": ["rock", "wheelbarrow"],
	"iron_mine": ["rock", "wheelbarrow", "crates"],
	"smithy": ["anvil", "firewood", "barrel"],
	"armory": ["anvil", "crates"],
	"market": ["market_stall", "crates", "barrel"],
	"tavern": ["barrel", "bench", "lantern"],
	"chapel": ["bench", "flowers", "lantern"],
	"well": ["trough"],
	"barracks": ["crates", "barrel", "fence"],
	"carter": ["cart", "wheelbarrow", "crates"],
	"fisher": ["barrel", "crates"],
	"house": ["barrel", "flowers", "bench", "firewood"],
	"stone_house": ["barrel", "flowers", "lantern", "bench"],
}
const GENERIC_PROPS := ["barrel", "crates"]
const WILD_PROPS := {
	"": ["flowers", "rock", "stump", "mushrooms"],
	"summer": ["flowers", "flowers", "rock", "stump", "mushrooms"],
	"autumn": ["flowers", "rock", "stump", "mushrooms", "pumpkins"],
	"winter": ["rock", "stump"],
}
## Share of open grass tiles that get a wild prop.
const PROP_CHANCE := 0.035
## Share of forest tiles left without a tree (clearings between trunks).
const TREE_GAP := 0.2

var world: WorldMap
var _trees := {}   # Vector2i -> Sprite2D
var _props := {}   # Vector2i -> Sprite2D (wild props)
var _rocks := {}   # Vector2i -> Sprite2D
var _near := {}    # Vector2i -> Sprite2D (props beside buildings)


func _init(p_world: WorldMap) -> void:
	world = p_world


## True when there's tree art for the current season (so the forest tileset
## overlay should step aside).
func has_trees() -> bool:
	return Art.texture(TREE_ART % _tree_names()[0]) != null


func has_rocks() -> bool:
	return Art.texture(PROP_ART % ROCKS[0]) != null


func rebuild() -> void:
	for layer in [_trees, _props, _rocks, _near]:
		for s in layer.values():
			s.queue_free()
		layer.clear()
	for y in world.height:
		for x in world.width:
			refresh_tile(Vector2i(x, y))
	for b in world.buildings:
		decorate_building(b)


## Puts one or two fitting props on free grass beside `b` (not in front of
## its door). Called when a building is placed.
func decorate_building(b: Building) -> void:
	if BuildingDefs.is_fortification(b.def):
		return
	var names: Array = BUILDING_PROPS.get(b.def_id, GENERIC_PROPS)
	var spots: Array[Vector2i] = []
	for y in range(b.origin.y - 1, b.origin.y + b.size.y + 1):
		for x in [b.origin.x - 1, b.origin.x + b.size.x]:
			spots.append(Vector2i(x, y))
	for x in range(b.origin.x, b.origin.x + b.size.x):
		spots.append(Vector2i(x, b.origin.y - 1))
	var placed := 0
	var want := 1 + int(_hash(b.origin, 8) * 2.0) + (1 if b.size.x >= 3 else 0)
	for i in spots.size():
		var t: Vector2i = spots[(i + int(_hash(b.origin, 9) * spots.size())) % spots.size()]
		if placed >= want or _near.has(t) or not _open(t) or t == b.entrance() or world.entrances.has(t):
			continue
		var tex := Art.texture(PROP_ART % names[(placed + int(_hash(t, 10) * names.size())) % names.size()])
		if tex == null:
			continue
		_set_sprite(_near, t, tex, false)
		_set_sprite(_props, t, null, false)
		placed += 1


## Re-decorate one tile after its terrain, road or building changed.
func refresh_tile(t: Vector2i) -> void:
	var want_tree := world.get_terrain(t) == Terrain.FOREST and _hash(t, 1) > TREE_GAP
	_set_sprite(_trees, t, _tree_texture(t) if want_tree else null, true)
	var want_rock := world.get_terrain(t) == Terrain.STONE and _hash(t, 11) < ROCK_CHANCE
	_set_sprite(_rocks, t, Art.texture(PROP_ART % ROCKS[int(_hash(t, 12) * ROCKS.size()) % ROCKS.size()])
		if want_rock else null, false)
	var open := _open(t)
	if _near.has(t) and not open:
		_set_sprite(_near, t, null, false)
	var want_prop := open and not _near.has(t) and _hash(t, 2) < PROP_CHANCE
	_set_sprite(_props, t, _prop_texture(t) if want_prop else null, false)


func _open(t: Vector2i) -> bool:
	return world.is_in_bounds(t) and world.get_terrain(t) == Terrain.GRASS and not world.roads.has(t) \
		and not world.occupancy.has(t) and not world.fields.has(t)


func _set_sprite(layer: Dictionary, t: Vector2i, tex: Texture2D, tree: bool) -> void:
	var s: Sprite2D = layer.get(t)
	if tex == null:
		if s != null:
			s.queue_free()
			layer.erase(t)
		return
	if s == null:
		s = Sprite2D.new()
		s.centered = false
		world.building_root.add_child(s)
		layer[t] = s
	s.texture = tex
	# Stand on the tile: the sprite's foot sits near the tile's lower edge,
	# nudged a little so rows don't look like a grid.
	var jitter := Vector2(_hash(t, 3) - 0.5, _hash(t, 4) - 0.5) * (12.0 if tree else 16.0)
	var foot := world.tile_center(t) + Vector2(0, 10) + jitter
	s.position = foot  # y-sort on the foot
	s.offset = Vector2(-tex.get_width() * 0.5, -tex.get_height() + (6.0 if tree else 2.0))
	s.flip_h = _hash(t, 5) < 0.5


func _tree_names() -> Array:
	return TREES.get(Art.season, TREES[""])


func _tree_texture(t: Vector2i) -> Texture2D:
	var names := _tree_names()
	return Art.texture(TREE_ART % names[int(_hash(t, 6) * names.size()) % names.size()])


func _prop_texture(t: Vector2i) -> Texture2D:
	var names: Array = WILD_PROPS.get(Art.season, WILD_PROPS[""])
	return Art.texture(PROP_ART % names[int(_hash(t, 7) * names.size()) % names.size()])


## Stable pseudo-random 0..1 per tile and purpose.
func _hash(t: Vector2i, salt: int) -> float:
	var h := hash(Vector3i(t.x, t.y, salt * 7919 + world.map_seed))
	return float(h & 0xFFFF) / 65535.0
