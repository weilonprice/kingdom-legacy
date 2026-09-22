class_name EnemyDefs
extends RefCounted
## Raider stats. `behavior`:
##   "thief"   - runs for the nearest storage, steals `loot`, flees off the map
##   "wrecker" - smashes the nearest building, then the next, until killed
## Both attack visible villagers within `aggro` tiles.

const DEFS := {
	"goblin": {
		"name": "Goblin",
		"hp": 30.0,
		"speed": 55.0,
		"damage": 3.0,
		"attack_cooldown": 1.0,
		"reach": 18.0,
		"aggro": 3,
		"behavior": "thief",
		"loot": 10,
		"radius": 5.0,
		"color": Color(0.42, 0.65, 0.25),
	},
	"goblin_brute": {
		"name": "Goblin Brute",
		"hp": 90.0,
		"speed": 34.0,
		"damage": 12.0,
		"attack_cooldown": 1.5,
		"reach": 20.0,
		"aggro": 2,
		"behavior": "wrecker",
		"large": true,
		"radius": 7.5,
		"color": Color(0.28, 0.45, 0.18),
	},
}


static func get_def(id: String) -> Dictionary:
	return DEFS[id]
