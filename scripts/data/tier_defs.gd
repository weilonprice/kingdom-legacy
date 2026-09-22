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
			"buildings": ["house", "well", "woodcutter", "quarry", "farm", "fisher", "mill",
				"bakery", "stockpile", "granary", "guard_tower"],
		},
		"keep": {"title": "Keep", "hp": 800.0, "capacity": 200},
	},
	{
		"name": "Village",
		"requires": {"population": 15, "buildings": ["well", "granary"]},
		"unlocks": {
			"buildings": ["barracks", "scholars_hall", "stone_house", "chapel", "market"],
			"units": ["militia", "spearman"],
			"research": ["crop_rotation", "sharp_tools", "wheelbarrows", "fletching", "ledgers"],
		},
		"keep": {"title": "Keep", "hp": 1100.0, "capacity": 300},
	},
	{
		"name": "Town",
		"requires": {"population": 35, "raids_survived": 2, "buildings": ["barracks", "scholars_hall"],
			"house_level": {"level": 2, "count": 4}},
		"unlocks": {
			"buildings": ["stone_tower", "warehouse", "tavern"],
			"units": ["archer"],
			"research": ["tempered_steel", "masonry"],
		},
		"keep": {"title": "Castle", "hp": 1500.0, "capacity": 400},
	},
	{
		"name": "City",
		"requires": {"population": 70, "raids_survived": 5, "research": 4, "buildings": ["warehouse", "stone_tower"],
			"house_level": {"level": 3, "count": 6}, "happiness": 60},
		"unlocks": {},
		"keep": {"title": "Castle", "hp": 2000.0, "capacity": 500},
	},
	{
		"name": "Kingdom",
		"requires": {"population": 120, "raids_survived": 8, "research": 6, "happiness": 65},
		"unlocks": {},
		"keep": {"title": "Citadel", "hp": 2500.0, "capacity": 600},
	},
]
