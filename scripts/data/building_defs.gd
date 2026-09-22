class_name BuildingDefs
extends RefCounted
## Static building data.
##
## `work` decides what its workers do:
##   "gather"  - walk to nearby `gather_terrain` tiles, haul `yield` of `resource`
##   "farm"    - plant and harvest the building's own fields
##   "produce" - fetch `input` from storage, work `work_time`, deliver `output`
## Storage buildings list the item categories they `accept` and their `capacity`
## per category.

const DEFS := {
	"keep": {
		"name": "Keep",
		"desc": "The heart of your kingdom. Houses 4 and stores everything.",
		"size": Vector2i(3, 3),
		"cost": {},
		"color": Color(0.48, 0.42, 0.55),
		"housing": 4,
		"accepts": ["materials", "food"],
		"capacity": 200,
		"hp": 800.0,
	},
	"house": {
		"name": "House",
		"desc": "Home for 4 villagers.",
		"size": Vector2i(2, 2),
		"cost": {"wood": 20},
		"color": Color(0.71, 0.51, 0.35),
		"housing": 4,
		"hp": 150.0,
	},
	"well": {
		"name": "Well",
		"desc": "Provides water to nearby homes (needed from the Village tier).",
		"size": Vector2i(1, 1),
		"cost": {"stone": 10},
		"color": Color(0.35, 0.50, 0.70),
		"coverage": 6,
	},
	"woodcutter": {
		"name": "Woodcutter",
		"desc": "Chops nearby trees for wood.",
		"size": Vector2i(2, 2),
		"cost": {"wood": 25},
		"color": Color(0.37, 0.48, 0.23),
		"jobs": 2,
		"work": "gather",
		"gather_terrain": Terrain.FOREST,
		"resource": "wood",
		"radius": 10,
		"yield": 4,
		"work_time": 4.0,
	},
	"quarry": {
		"name": "Quarry",
		"desc": "Cuts nearby rocks for stone.",
		"size": Vector2i(2, 2),
		"cost": {"wood": 30},
		"color": Color(0.54, 0.54, 0.56),
		"jobs": 2,
		"work": "gather",
		"gather_terrain": Terrain.STONE,
		"resource": "stone",
		"radius": 10,
		"yield": 3,
		"work_time": 6.0,
	},
	"farm": {
		"name": "Farm",
		"desc": "Tills up to 8 fields around it and grows wheat.",
		"size": Vector2i(2, 2),
		"cost": {"wood": 30},
		"color": Color(0.78, 0.66, 0.30),
		"jobs": 2,
		"work": "farm",
		"resource": "wheat",
		"fields": 8,
		"min_fields": 3,
		"field_radius": 3,
		"yield": 3,
		"work_time": 3.0,
		"grow_time": 45.0,
	},
	"fisher": {
		"name": "Fisher's Hut",
		"desc": "Catches fish from nearby water. Must be built close to water.",
		"size": Vector2i(2, 2),
		"cost": {"wood": 20},
		"color": Color(0.40, 0.58, 0.68),
		"jobs": 2,
		"work": "gather",
		"gather_terrain": Terrain.WATER,
		"resource": "fish",
		"radius": 5,
		"yield": 2,
		"work_time": 5.0,
	},
	"mill": {
		"name": "Mill",
		"desc": "Grinds wheat into flour.",
		"size": Vector2i(2, 2),
		"cost": {"wood": 40, "stone": 10},
		"color": Color(0.85, 0.82, 0.70),
		"jobs": 1,
		"work": "produce",
		"input": {"wheat": 4},
		"output": {"flour": 4},
		"work_time": 10.0,
	},
	"bakery": {
		"name": "Bakery",
		"desc": "Bakes flour into bread. Each batch feeds twice as many.",
		"size": Vector2i(2, 2),
		"cost": {"wood": 30, "stone": 10},
		"color": Color(0.75, 0.40, 0.28),
		"jobs": 2,
		"work": "produce",
		"input": {"flour": 2},
		"output": {"bread": 4},
		"work_time": 8.0,
	},
	"guard_tower": {
		"name": "Guard Tower",
		"desc": "A villager keeps watch and shoots arrows at raiders in range.",
		"size": Vector2i(1, 1),
		"cost": {"wood": 40, "stone": 20},
		"color": Color(0.55, 0.52, 0.48),
		"jobs": 1,
		"work": "guard",
		"hp": 300.0,
		"range": 7,
		"damage": 10.0,
		"attack_cooldown": 1.2,
	},
	"stockpile": {
		"name": "Stockpile",
		"desc": "Stores 150 materials (wood, stone).",
		"size": Vector2i(2, 2),
		"cost": {"wood": 15},
		"color": Color(0.64, 0.56, 0.36),
		"accepts": ["materials"],
		"capacity": 150,
	},
	"granary": {
		"name": "Granary",
		"desc": "Stores 150 food (wheat, flour, bread, fish).",
		"size": Vector2i(2, 2),
		"cost": {"wood": 30, "stone": 10},
		"color": Color(0.82, 0.70, 0.45),
		"accepts": ["food"],
		"capacity": 150,
	},
}

## Build menu tabs. Road and Demolish are always-visible tools.
const CATEGORIES := [
	{"name": "Housing", "items": ["house", "well"]},
	{"name": "Resources", "items": ["woodcutter", "quarry"]},
	{"name": "Food", "items": ["farm", "fisher", "mill", "bakery"]},
	{"name": "Storage", "items": ["stockpile", "granary"]},
	{"name": "Defense", "items": ["guard_tower"]},
]


static func get_def(id: String) -> Dictionary:
	return DEFS[id]


## The tile just below the bottom-middle of the footprint. Villagers enter here,
## and it must sit on a road for the building to function.
static func entrance_of(origin: Vector2i, size: Vector2i) -> Vector2i:
	return origin + Vector2i(int(size.x * 0.5), size.y)


static func cost_text(cost: Dictionary) -> String:
	if cost.is_empty():
		return "free"
	var parts := PackedStringArray()
	for id in cost:
		parts.append("%d %s" % [cost[id], id])
	return ", ".join(parts)


## "4 wheat" from {"wheat": 4}. Recipes use a single item.
static func stack_text(stack: Dictionary) -> String:
	var item: String = stack.keys()[0]
	return "%d %s" % [stack[item], item]
