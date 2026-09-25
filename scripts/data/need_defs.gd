class_name NeedDefs
extends RefCounted
## Household needs, happiness and house levels.
##
## Happiness (0-100) = BASE + each need's bonus if met (or penalty if not)
## + the tax rate's effect. A home reaches a level once every need listed for
## that level is met, which raises its capacity (building `level_bonus`) and
## its tax.

const NEEDS := {
	"food": {"name": "Food", "met": 10.0, "unmet": -30.0},
	"water": {"name": "Water", "met": 10.0, "unmet": -10.0},
	"religion": {"name": "Religion", "met": 10.0, "unmet": 0.0},
	"market": {"name": "Market", "met": 10.0, "unmet": 0.0},
	"tavern": {"name": "Tavern", "met": 10.0, "unmet": 0.0},
	"hygiene": {"name": "Bathhouse", "met": 6.0, "unmet": 0.0},
	"order": {"name": "Town Watch", "met": 4.0, "unmet": 0.0},
	"education": {"name": "School", "met": 6.0, "unmet": -4.0},
	# Goods, delivered by a market (see GOODS).
	"ale": {"name": "Ale", "met": 6.0, "unmet": 0.0},
	"tools": {"name": "Tools", "met": 6.0, "unmet": -4.0},
	"cloth": {"name": "Cloth", "met": 6.0, "unmet": -4.0},
	"wine": {"name": "Wine", "met": 10.0, "unmet": -8.0},
	"fine_clothes": {"name": "Fine Clothes", "met": 10.0, "unmet": -8.0},
	# Winter only: homes need firewood (see Seasons).
	"warmth": {"name": "Warmth", "met": 0.0, "unmet": -20.0},
}
const ORDER := ["food", "water", "religion", "market", "tavern", "hygiene", "order", "education"]
## Goods homes want from the Cottage level (`from`) up; the lower classes
## want the cheaper goods. A home has a good when the kingdom has it in
## storage and a staffed Market covers the home (its traders deliver).
## Homes that have it use `rate` per resident per minute.
const GOODS := {
	"ale": {"from": 1, "rate": 0.10},
	"tools": {"from": 2, "rate": 0.05},
	"cloth": {"from": 2, "rate": 0.05},
	"wine": {"from": 3, "rate": 0.08},
	"fine_clothes": {"from": 3, "rate": 0.04},
}
const GOODS_ORDER := ["ale", "tools", "cloth", "wine", "fine_clothes"]
const BASE_HAPPINESS := 50.0

## Index = house level - 1.
const LEVELS := [
	{"name": "Cottage", "needs": ["food"], "tax": 1.0},
	{"name": "Townhouse", "needs": ["food", "water", "religion", "ale"], "tax": 2.0},
	{"name": "Manor", "needs": ["food", "water", "religion", "market", "tavern", "education", "ale", "tools", "cloth"], "tax": 3.5},
]

## Gold per resident per minute, and the happiness effect of each rate.
const TAX_RATES := [
	{"name": "None", "gold": 0.0, "happiness": 15.0},
	{"name": "Low", "gold": 0.5, "happiness": 7.0},
	{"name": "Normal", "gold": 1.0, "happiness": 0.0},
	{"name": "High", "gold": 1.5, "happiness": -12.0},
	{"name": "Harsh", "gold": 2.0, "happiness": -25.0},
]
const DEFAULT_TAX_RATE := 2

## Below this a home pays no tax, attracts no one, and slowly empties.
const UNHAPPY := 25.0
const MIN_TO_MOVE_IN := 35.0
const CONTENT := 70.0


## Work-time multiplier for villagers whose home has `happiness`.
static func work_multiplier(happiness: float) -> float:
	if happiness >= CONTENT:
		return 0.85
	if happiness < 40.0:
		return 1.25
	return 1.0
