class_name ResearchDefs
extends RefCounted
## Research topics studied at the Scholar's Hall. `time` is seconds with one
## scholar working (more scholars study faster). Each effect changes a
## GameState modifier: "mul" multiplies it (default 1.0), "add" adds to it
## (default 0).

const DEFS := {
	"crop_rotation": {
		"name": "Crop Rotation",
		"desc": "Farms harvest 50% more wheat per field.",
		"cost": {"gold": 40},
		"time": 60.0,
		"effects": [{"key": "farm_yield", "mul": 1.5}],
	},
	"sharp_tools": {
		"name": "Sharp Tools",
		"desc": "Woodcutters, quarries and fishers work 30% faster.",
		"cost": {"gold": 40},
		"time": 60.0,
		"effects": [{"key": "gather_time", "mul": 0.7}],
	},
	"wheelbarrows": {
		"name": "Wheelbarrows",
		"desc": "Villagers walk 20% faster.",
		"cost": {"gold": 50},
		"time": 60.0,
		"effects": [{"key": "villager_speed", "mul": 1.2}],
	},
	"fletching": {
		"name": "Fletching",
		"desc": "Towers +2 range, archers +1 range.",
		"cost": {"gold": 50},
		"time": 75.0,
		"effects": [{"key": "tower_range", "add": 2}, {"key": "archer_range", "add": 1}],
	},
	"ledgers": {
		"name": "Ledgers",
		"desc": "All storage holds 25% more.",
		"cost": {"gold": 40},
		"time": 60.0,
		"effects": [{"key": "storage_capacity", "mul": 1.25}],
	},
	"tempered_steel": {
		"name": "Tempered Steel",
		"desc": "Troops deal 25% more damage.",
		"cost": {"gold": 80, "stone": 20},
		"time": 90.0,
		"effects": [{"key": "troop_damage", "mul": 1.25}],
	},
	"masonry": {
		"name": "Masonry",
		"desc": "All buildings have 50% more HP.",
		"cost": {"gold": 80, "stone": 30},
		"time": 90.0,
		"effects": [{"key": "building_hp", "mul": 1.5}],
	},
}

## Display order in the research panel.
const ORDER := ["crop_rotation", "sharp_tools", "wheelbarrows", "fletching", "ledgers",
	"tempered_steel", "masonry"]


static func get_def(id: String) -> Dictionary:
	return DEFS[id]
