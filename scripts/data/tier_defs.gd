class_name TierDefs
extends RefCounted
## Settlement tiers. Reaching a tier needs every listed requirement; it then
## unlocks content and upgrades the Keep. Requirement keys:
##   population, raids_survived, research (count completed), buildings (all built),
##   house_level ({level, count}: homes at that level or higher), happiness (average)

const TIERS := [
	{
		"name": "Hamlet",
		"requires": {},
		"unlocks": {
			"buildings": ["plaza", "flowerbed", "avenue_tree", "house", "well", "woodcutter", "forester", "quarry", "farm", "fisher", "mill",
				"bakery", "stockpile", "granary", "carter", "guard_tower", "palisade", "gate"],
		},
		"keep": {"hp": 800.0, "capacity": 300},
	},
	{
		"name": "Village",
		"requires": {"population": 20, "buildings": ["well", "granary"]},
		"unlocks": {
			"buildings": ["barracks", "scholars_hall", "stone_house", "chapel", "market", "iron_mine", "smithy", "trading_post",
				"garden", "fountain", "cobble_road", "bathhouse", "physician", "fire_station", "brewery", "toolmaker", "sheep_farm", "weaver"],
			"units": ["militia", "spearman"],
			"research": ["crop_rotation", "sharp_tools", "wheelbarrows", "fletching", "ledgers"],
		},
		"keep": {"hp": 1100.0, "capacity": 450},
	},
	{
		"name": "Town",
		"requires": {"population": 60, "raids_survived": 2, "buildings": ["barracks", "scholars_hall"],
			"house_level": {"level": 2, "count": 8}},
		"unlocks": {
			"buildings": ["stone_tower", "warehouse", "tavern", "stone_wall", "wall_tower", "armory", "statue", "monument", "paved_road", "watch_house", "school", "tailor", "vineyard", "winery"],
			"units": ["archer"],
			"research": ["tempered_steel", "masonry"],
		},
		"keep": {"hp": 1500.0, "capacity": 600},
	},
	{
		"name": "City",
		"requires": {"population": 130, "raids_survived": 5, "research": 4, "buildings": ["warehouse", "stone_tower"],
			"house_level": {"level": 3, "count": 15}, "happiness": 60},
		"unlocks": {"units": ["knight"]},
		"keep": {"hp": 2000.0, "capacity": 800},
	},
	{
		"name": "Kingdom",
		"requires": {"population": 250, "raids_survived": 8, "research": 6, "happiness": 65,
			"house_level": {"level": 3, "count": 30}},
		"unlocks": {},
		"keep": {"hp": 2500.0, "capacity": 1000},
	},
]
