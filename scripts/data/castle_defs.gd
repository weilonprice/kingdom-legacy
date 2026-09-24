class_name CastleDefs
extends RefCounted
## The castle's stages. It stands in reserved 9x9 grounds and grows in place:
## each upgrade is a construction project the player starts from the
## castle's panel once the tier allows it. Materials are hauled in by the
## castle's builders; then they build for `work` builder-seconds. `gold` is
## paid when the project starts. HP and storage come from the tier (see
## TierDefs) plus the stage's bonus.

const GROUNDS := 9
const BUILDERS := 6

const STAGES := [
	{"title": "Keep", "art": "keep", "size": 5, "hp_bonus": 0.0, "capacity_bonus": 0},
	{"title": "Castle", "art": "castle", "size": 7, "tier": 2, "hp_bonus": 600.0, "capacity_bonus": 100,
		"materials": {"stone": 250, "wood": 150, "iron": 30}, "gold": 150, "work": 480.0},
	{"title": "Citadel", "art": "citadel", "size": 9, "tier": 4, "hp_bonus": 1500.0, "capacity_bonus": 250,
		"materials": {"stone": 500, "wood": 250, "iron": 80}, "gold": 400, "work": 900.0},
]
