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
## Service buildings `provide` a need (water, religion, market, tavern) to homes
## within `coverage` tiles; those with `jobs` only work while staffed.
## Homes have `housing` and gain `level_bonus` residents per house level.
## Fortifications (`wall` / `gate`) are 1x1, need no entrance or road, and
## block villagers (gates let them through). Raiders can walk through them
## only by smashing them; `siege_cost` is how hard their pathfinding avoids
## that. `drag` walls are laid with the wall drag tool. Towers with
## `auto_guard` shoot without a guard inside. Buildings without
## `flammable: false` can catch fire.

const DEFS := {
	"keep": {
		"name": "Keep",
		"desc": "The heart of your kingdom. Houses 4 and stores everything. It grows into a Castle (Town) and a Citadel (Kingdom) in its reserved grounds.",
		"size": Vector2i(5, 5),
		"cost": {},
		"color": Color(0.48, 0.42, 0.55),
		"housing": 4,
		"accepts": ["materials", "food", "grain"],
		"capacity": 300,
		"hp": 800.0,
		"flammable": false,
	},
	"house": {
		"name": "House",
		"desc": "Home for 4 villagers.",
		"size": Vector2i(2, 2),
		"cost": {"wood": 20},
		"color": Color(0.71, 0.51, 0.35),
		"housing": 4,
		"level_bonus": 2,
		"level_art": ["house", "townhouse", "manor"],
		"hp": 150.0,
	},
	"well": {
		"name": "Well",
		"desc": "Provides water to homes within 6 tiles.",
		"size": Vector2i(1, 1),
		"cost": {"stone": 10},
		"color": Color(0.35, 0.50, 0.70),
		"provides": "water",
		"coverage": 6,
	},
	"stone_house": {
		"name": "Stone House",
		"desc": "A sturdy home for 8 villagers.",
		"size": Vector2i(2, 2),
		"cost": {"wood": 20, "stone": 30},
		"color": Color(0.62, 0.58, 0.54),
		"housing": 8,
		"level_bonus": 2,
		"level_art": ["stone_house", "stone_townhouse", "stone_manor"],
		"hp": 350.0,
	},
	"chapel": {
		"name": "Chapel",
		"desc": "A priest tends to the faithful: provides religion to homes within 10 tiles.",
		"size": Vector2i(2, 2),
		"cost": {"wood": 40, "stone": 20},
		"color": Color(0.85, 0.83, 0.75),
		"jobs": 1,
		"work": "service",
		"provides": "religion",
		"coverage": 10,
		"hp": 300.0,
	},
	"market": {
		"name": "Market",
		"desc": "A merchant sells wares: provides market access to homes within 10 tiles.",
		"size": Vector2i(2, 2),
		"cost": {"wood": 50},
		"color": Color(0.80, 0.45, 0.35),
		"jobs": 1,
		"work": "service",
		"provides": "market",
		"coverage": 10,
		"hp": 250.0,
	},
	"tavern": {
		"name": "Tavern",
		"desc": "An innkeeper pours ale: provides a tavern to homes within 10 tiles.",
		"size": Vector2i(2, 2),
		"cost": {"wood": 40, "stone": 30},
		"color": Color(0.55, 0.35, 0.20),
		"jobs": 1,
		"work": "service",
		"provides": "tavern",
		"coverage": 10,
		"hp": 300.0,
	},
	"scholars_hall": {
		"name": "Scholar's Hall",
		"desc": "Scholars study research here. More scholars research faster.",
		"size": Vector2i(2, 2),
		"cost": {"wood": 50, "stone": 30},
		"color": Color(0.35, 0.40, 0.62),
		"jobs": 2,
		"work": "study",
		"hp": 300.0,
	},
	"carter": {
		"name": "Carter's Yard",
		"desc": "Haulers empty workplace piles into storage and bring mills and bakeries their ingredients.",
		"size": Vector2i(2, 2),
		"cost": {"wood": 30},
		"color": Color(0.58, 0.46, 0.30),
		"jobs": 3,
		"work": "haul",
		"hp": 200.0,
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
	"forester": {
		"name": "Forester's Lodge",
		"desc": "Plants saplings on open ground nearby; in about 3 minutes they grow into forest for your woodcutters.",
		"size": Vector2i(2, 2),
		"cost": {"wood": 30, "stone": 10},
		"color": Color(0.28, 0.45, 0.25),
		"jobs": 1,
		"work": "forester",
		"radius": 8,
		"work_time": 5.0,
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
	"iron_mine": {
		"name": "Iron Mine",
		"desc": "Miners dig iron ore out of nearby rocks.",
		"size": Vector2i(2, 2),
		"cost": {"wood": 40, "stone": 20},
		"color": Color(0.50, 0.36, 0.30),
		"jobs": 2,
		"work": "gather",
		"gather_terrain": Terrain.STONE,
		"resource": "iron",
		"radius": 10,
		"yield": 2,
		"work_time": 8.0,
		"hp": 300.0,
	},
	"smithy": {
		"name": "Smithy",
		"desc": "Forges iron into weapons for spearmen, archers and knights.",
		"size": Vector2i(2, 2),
		"cost": {"wood": 40, "stone": 30},
		"color": Color(0.40, 0.35, 0.35),
		"jobs": 1,
		"work": "produce",
		"input": {"iron": 2},
		"output": {"weapons": 1},
		"work_time": 12.0,
		"hp": 300.0,
	},
	"toolmaker": {
		"name": "Toolmaker", "desc": "Makes tools from iron. Burghers and nobles want tools.",
		"size": Vector2i(2, 2), "cost": {"wood": 40, "stone": 30}, "color": Color(0.5, 0.5, 0.55),
		"jobs": 1, "work": "produce", "input": {"iron": 1}, "output": {"tools": 2}, "work_time": 12.0,
	},
	"weaver": {
		"name": "Weaver", "desc": "Weaves wool into cloth. Burghers and nobles want cloth.",
		"size": Vector2i(2, 2), "cost": {"wood": 40, "stone": 10}, "color": Color(0.4, 0.55, 0.8),
		"jobs": 1, "work": "produce", "input": {"wool": 2}, "output": {"cloth": 1}, "work_time": 12.0,
	},
	"tailor": {
		"name": "Tailor", "desc": "Sews cloth into fine clothes for the nobility.",
		"size": Vector2i(2, 2), "cost": {"wood": 40, "stone": 30, "gold": 40}, "color": Color(0.7, 0.2, 0.55),
		"jobs": 1, "work": "produce", "input": {"cloth": 2}, "output": {"fine_clothes": 1}, "work_time": 16.0,
	},
	"winery": {
		"name": "Winery", "desc": "Presses grapes into wine for the nobility.",
		"size": Vector2i(2, 2), "cost": {"wood": 40, "stone": 40}, "color": Color(0.55, 0.1, 0.25),
		"jobs": 1, "work": "produce", "input": {"grapes": 3}, "output": {"wine": 1}, "work_time": 14.0,
	},
	"armory": {
		"name": "Armory",
		"desc": "Hammers iron into plate armor for knights.",
		"size": Vector2i(2, 2),
		"cost": {"wood": 40, "stone": 50},
		"color": Color(0.45, 0.40, 0.48),
		"jobs": 1,
		"work": "produce",
		"input": {"iron": 3},
		"output": {"armor": 1},
		"work_time": 16.0,
		"hp": 400.0,
		"flammable": false,
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
		"desc": "Two millers grind wheat into flour.",
		"size": Vector2i(2, 2),
		"cost": {"wood": 40, "stone": 10},
		"color": Color(0.85, 0.82, 0.70),
		"jobs": 2,
		"work": "produce",
		"input": {"wheat": 4},
		"output": {"flour": 4},
		"work_time": 5.0,
	},
	"brewery": {
		"name": "Brewery", "desc": "Brews ale from wheat. Every home wants ale; Townhouses need it.",
		"size": Vector2i(2, 2), "cost": {"wood": 40, "stone": 20}, "color": Color(0.7, 0.5, 0.2),
		"jobs": 1, "work": "produce", "input": {"wheat": 3}, "output": {"ale": 2}, "work_time": 10.0,
	},
	"sheep_farm": {
		"name": "Sheep Farm", "desc": "A shepherd raises sheep for wool.",
		"size": Vector2i(3, 3), "cost": {"wood": 40}, "color": Color(0.85, 0.85, 0.75),
		"jobs": 1, "work": "produce", "output": {"wool": 2}, "work_time": 10.0,
	},
	"vineyard": {
		"name": "Vineyard", "desc": "Rows of vines: a vintner harvests grapes for the winery.",
		"size": Vector2i(3, 3), "cost": {"wood": 40, "stone": 10}, "color": Color(0.4, 0.55, 0.25),
		"jobs": 1, "work": "produce", "output": {"grapes": 2}, "work_time": 10.0,
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
	"stone_tower": {
		"name": "Stone Tower",
		"desc": "A fortified tower: longer range, harder arrows, much tougher walls.",
		"size": Vector2i(1, 1),
		"cost": {"wood": 30, "stone": 60},
		"color": Color(0.45, 0.45, 0.50),
		"jobs": 1,
		"work": "guard",
		"hp": 700.0,
		"flammable": false,
		"range": 9,
		"damage": 16.0,
		"attack_cooldown": 1.1,
	},
	"barracks": {
		"name": "Barracks",
		"desc": "Trains troops from your villagers. Holds one squad of up to 6; troops heal nearby.",
		"size": Vector2i(3, 2),
		"cost": {"wood": 60, "stone": 30},
		"color": Color(0.55, 0.30, 0.25),
		"hp": 450.0,
		"trains": ["militia", "spearman", "archer", "knight"],
		"troop_capacity": 6,
		"jobs": 1,
		"work": "guard",
	},
	"palisade": {
		"name": "Palisade",
		"desc": "A wooden stake wall. Drag to build. Raiders must smash through it; it can burn.",
		"size": Vector2i(1, 1),
		"cost": {"wood": 4},
		"color": Color(0.52, 0.36, 0.20),
		"hp": 250.0,
		"wall": true,
		"drag": true,
		"siege_cost": 20.0,
	},
	"stone_wall": {
		"name": "Stone Wall",
		"desc": "A thick fireproof stone wall. Drag to build. Very hard for raiders to break.",
		"size": Vector2i(1, 1),
		"cost": {"stone": 6},
		"color": Color(0.58, 0.58, 0.60),
		"hp": 800.0,
		"wall": true,
		"drag": true,
		"siege_cost": 45.0,
		"flammable": false,
	},
	"wall_tower": {
		"name": "Wall Tower",
		"desc": "A turret that joins your walls. Its own archers shoot raiders in range; no guard needed.",
		"size": Vector2i(1, 1),
		"cost": {"wood": 10, "stone": 30},
		"color": Color(0.52, 0.52, 0.56),
		"hp": 700.0,
		"wall": true,
		"siege_cost": 40.0,
		"flammable": false,
		"auto_guard": true,
		"range": 7,
		"damage": 8.0,
		"attack_cooldown": 1.4,
	},
	"gate": {
		"name": "Gate",
		"desc": "Lets your villagers and troops through a wall; raiders must break it. Can go on a road.",
		"size": Vector2i(1, 1),
		"cost": {"wood": 20, "stone": 10},
		"color": Color(0.45, 0.32, 0.18),
		"hp": 600.0,
		"gate": true,
		"siege_cost": 35.0,
	},
	"trading_post": {
		"name": "Trading Post",
		"desc": "Travelling merchants stop here to buy and sell goods. Click it while one is in town.",
		"size": Vector2i(2, 2),
		"cost": {"wood": 60, "stone": 20},
		"color": Color(0.72, 0.52, 0.30),
		"hp": 300.0,
	},
	"stockpile": {
		"name": "Stockpile",
		"desc": "Stores 250 materials (wood, stone, iron, weapons, armor).",
		"size": Vector2i(2, 2),
		"cost": {"wood": 15},
		"color": Color(0.64, 0.56, 0.36),
		"accepts": ["materials"],
		"capacity": 250,
	},
	"warehouse": {
		"name": "Warehouse",
		"desc": "Large storage for materials, food and grain (250 each).",
		"size": Vector2i(3, 2),
		"cost": {"wood": 60, "stone": 40},
		"color": Color(0.50, 0.42, 0.30),
		"accepts": ["materials", "food", "grain"],
		"capacity": 250,
		"hp": 400.0,
	},
	"granary": {
		"name": "Granary",
		"desc": "Stores 150 food (bread, fish) and 150 grain (wheat, flour).",
		"size": Vector2i(2, 2),
		"cost": {"wood": 30, "stone": 10},
		"color": Color(0.82, 0.70, 0.45),
		"accepts": ["food", "grain"],
		"capacity": 150,
	},
}

## Build menu tabs. Road and Demolish are always-visible tools.
const DECOR := {
	"flowerbed": {"name": "Flowerbed", "desc": "Flowers make a street nicer to live on (+beauty nearby).",
		"size": Vector2i(1, 1), "cost": {"wood": 5, "gold": 5}, "color": Color(0.85, 0.4, 0.5), "hp": 60.0, "decor": true},
	"avenue_tree": {"name": "Planted Tree", "desc": "A tree in a stone planter to line an avenue (+beauty nearby).",
		"size": Vector2i(1, 1), "cost": {"wood": 8, "gold": 5}, "color": Color(0.3, 0.6, 0.3), "hp": 80.0, "decor": true},
	"garden": {"name": "Garden", "desc": "Hedges, flowers and a bench: a pleasant spot for the neighbourhood.",
		"size": Vector2i(2, 2), "cost": {"wood": 20, "stone": 10, "gold": 20}, "color": Color(0.4, 0.7, 0.35), "hp": 150.0, "decor": true},
	"fountain": {"name": "Fountain", "desc": "A fountain for the town square. Townsfolk gather here.",
		"size": Vector2i(2, 2), "cost": {"stone": 50, "gold": 40}, "color": Color(0.5, 0.65, 0.85), "hp": 300.0, "decor": true},
	"statue": {"name": "Statue", "desc": "A stone knight on a plinth, a proud sight for any street.",
		"size": Vector2i(1, 1), "cost": {"stone": 60, "gold": 60}, "color": Color(0.7, 0.7, 0.7), "hp": 300.0, "decor": true},
	"monument": {"name": "Royal Monument", "desc": "A statue of your ruler. It changes when the throne passes. Great beauty nearby.",
		"size": Vector2i(2, 2), "cost": {"stone": 150, "gold": 200}, "color": Color(0.8, 0.7, 0.4), "hp": 500.0, "decor": true},
}

const CATEGORIES := [
	{"name": "Housing", "items": ["house", "stone_house", "well"]},
	{"name": "Resources", "items": ["woodcutter", "forester", "quarry", "iron_mine"]},
	{"name": "Industry", "items": ["smithy", "armory", "toolmaker", "brewery", "weaver", "tailor", "winery"]},
	{"name": "Food", "items": ["farm", "fisher", "mill", "bakery", "sheep_farm", "vineyard"]},
	{"name": "Storage", "items": ["stockpile", "granary", "warehouse", "carter", "trading_post"]},
	{"name": "Defense", "items": ["guard_tower", "stone_tower", "barracks", "palisade", "gate", "stone_wall", "wall_tower"]},
	{"name": "Civic", "items": ["chapel", "market", "tavern", "scholars_hall"]},
	{"name": "Decor", "items": ["plaza", "flowerbed", "avenue_tree", "garden", "fountain", "statue", "monument"]},
]


static func get_def(id: String) -> Dictionary:
	if DECOR.has(id):
		return DECOR[id]
	if id == "plaza":
		return PLAZA_DEF
	return DEFS[id]


## Plazas are paved road tiles dragged out like roads (see WorldMap.place_plazas).
const PLAZA_DEF := {"name": "Plaza", "desc": "Paved square: walkable like a road, a little beauty, townsfolk gather.",
	"size": Vector2i(1, 1), "cost": {"stone": 3}, "color": Color(0.7, 0.7, 0.65)}


## Walls and gates: 1x1, no entrance, block civilians (gates excepted).
static func is_fortification(def: Dictionary) -> bool:
	return def.get("wall", false) or def.get("gate", false)


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
