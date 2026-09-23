class_name EnemyDefs
extends RefCounted
## Raider stats. `behavior`:
##   "thief"   - runs for the nearest storage, steals `loot`, flees off the map
##   "wrecker" - smashes the nearest building, then the next, until killed
##   "raider"  - goes for farms and gatherers first
##   "siege"   - goes for walls, gates and towers first
##   "support" - follows its war band, healing `heal` HP/s within `heal_radius`
##   "lair"    - a monster den out in the wilds. Never moves; sends out up to
##               `guards` of `guard` when troops come within `guard_radius`
##               tiles. While it stands, raids bring `raid_bonus` extra
##               goblins; destroying it pays `bounty` gold.
## All attack visible villagers and troops within `aggro` tiles. Optional:
## `ignite_chance` per hit on a building, `wall_damage` multiplier vs walls.

const DEFS := {
	"goblin_lair": {
		"name": "Goblin Lair",
		"hp": 2500.0,
		"speed": 0.0,
		"damage": 0.0,
		"attack_cooldown": 1.0,
		"reach": 0.0,
		"aggro": 0,
		"behavior": "lair",
		"large": true,
		"radius": 24.0,
		"guard": "goblin_brute",
		"guards": 3,
		"guard_radius": 9,
		"guard_interval": 8.0,
		"raid_bonus": 3,
		"bounty": 150,
		"color": Color(0.30, 0.25, 0.20),
	},
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
	"orc": {
		"name": "Orc Warrior",
		"hp": 150.0,
		"speed": 38.0,
		"damage": 10.0,
		"attack_cooldown": 1.3,
		"reach": 20.0,
		"aggro": 3,
		"behavior": "wrecker",
		"ignite_chance": 0.25,
		"radius": 7.0,
		"color": Color(0.35, 0.45, 0.30),
	},
	"orc_shaman": {
		"name": "Orc Shaman",
		"hp": 70.0,
		"speed": 40.0,
		"damage": 4.0,
		"attack_cooldown": 1.5,
		"reach": 18.0,
		"aggro": 3,
		"behavior": "support",
		"heal": 6.0,
		"heal_radius": 3,
		"radius": 6.0,
		"color": Color(0.40, 0.50, 0.25),
	},
	"wolf_rider": {
		"name": "Wolf Rider",
		"hp": 80.0,
		"speed": 80.0,
		"damage": 7.0,
		"attack_cooldown": 1.0,
		"reach": 20.0,
		"aggro": 3,
		"behavior": "raider",
		"radius": 7.0,
		"color": Color(0.55, 0.55, 0.58),
	},
	"troll": {
		"name": "Troll",
		"hp": 650.0,
		"speed": 24.0,
		"damage": 30.0,
		"attack_cooldown": 2.2,
		"reach": 24.0,
		"aggro": 1,
		"behavior": "siege",
		"wall_damage": 2.5,
		"large": true,
		"radius": 10.0,
		"color": Color(0.40, 0.48, 0.38),
	},
}


static func get_def(id: String) -> Dictionary:
	return DEFS[id]
