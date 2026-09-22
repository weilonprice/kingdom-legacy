class_name UnitDefs
extends RefCounted
## Troops trained at the Barracks. Each costs a villager plus `cost`, and
## `upkeep` gold per minute. Melee units attack within `reach` pixels; units
## with `range` (tiles) shoot arrows instead. `large_bonus` multiplies damage
## against large enemies (e.g. goblin brutes).

const DEFS := {
	"militia": {
		"name": "Militia",
		"desc": "Cheap, lightly armed villagers. Better than nothing.",
		"hp": 40.0,
		"damage": 4.0,
		"attack_cooldown": 1.0,
		"reach": 20.0,
		"speed": 46.0,
		"cost": {"gold": 10},
		"upkeep": 1,
		"train_time": 8.0,
		"color": Color(0.62, 0.48, 0.32),
	},
	"spearman": {
		"name": "Spearman",
		"desc": "Sturdy melee fighter. Deals 2.5x damage to brutes.",
		"hp": 70.0,
		"damage": 7.0,
		"attack_cooldown": 1.2,
		"reach": 22.0,
		"speed": 42.0,
		"large_bonus": 2.5,
		"cost": {"gold": 25, "wood": 10},
		"upkeep": 2,
		"train_time": 15.0,
		"color": Color(0.30, 0.42, 0.70),
	},
	"archer": {
		"name": "Archer",
		"desc": "Shoots raiders from 5 tiles away. Fragile up close.",
		"hp": 35.0,
		"damage": 6.0,
		"attack_cooldown": 1.3,
		"range": 5,
		"speed": 44.0,
		"cost": {"gold": 25, "wood": 15},
		"upkeep": 2,
		"train_time": 15.0,
		"color": Color(0.32, 0.55, 0.30),
	},
}

const TRAIN_ORDER := ["militia", "spearman", "archer"]


static func get_def(id: String) -> Dictionary:
	return DEFS[id]
