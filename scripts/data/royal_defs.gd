class_name RoyalDefs
extends RefCounted
## The royal family (see Royals): traits that shape the realm while their
## bearer rules, titles by tier, names, and the rules of aging and
## succession.

## Game seconds per year of royal age.
const YEAR := 100.0
## Rulers die of old age between these ages.
const LIFESPAN := [58.0, 72.0]
## A widowed or new ruler marries after this many years; a child follows
## this many years after the wedding (while the ruler is under CHILD_MAX_AGE).
const MARRY_AFTER := 2.0
const CHILD_AFTER := 2.0
const CHILD_MAX_AGE := 50.0

## Succession crisis (a ruler dies with no heir): no taxes and unhappy homes
## for CRISIS_TIME seconds, and a share of the treasury vanishes at once.
const CRISIS_TIME := 180.0
const CRISIS_GOLD_LOSS := 0.25
const CRISIS_MODS := {"happiness": {"add": -15.0}, "tax": {"mul": 0.0}}

## Castle breach: raiders who bring the castle below this share of its HP
## during a raid break in once (until it's repaired above it again).
const BREACH_AT := 0.5
const BREACH_GOLD := 0.3
const BREACH_BURN := 0.2
const BREACH_KILL_CHANCE := 0.35

const TRAITS := {
	"just": {"name": "Just", "desc": "+6 happiness in every home",
		"mods": {"happiness": {"add": 6.0}}},
	"greedy": {"name": "Greedy", "desc": "+30% taxes, but -6 happiness",
		"mods": {"tax": {"mul": 1.3}, "happiness": {"add": -6.0}}},
	"builder": {"name": "Builder", "desc": "Castle construction 60% faster",
		"mods": {"castle_work": {"mul": 1.6}}},
	"warlike": {"name": "Warlike", "desc": "Troops deal 15% more damage",
		"mods": {"troop_damage": {"mul": 1.15}}},
	"wise": {"name": "Wise", "desc": "Research 30% faster",
		"mods": {"research_speed": {"mul": 1.3}}},
	"thrifty": {"name": "Thrifty", "desc": "Troop upkeep 25% cheaper",
		"mods": {"troop_upkeep": {"mul": 0.75}}},
}
const CONFLICTS := [["just", "greedy"]]

## [male, female] titles of the ruling couple by tier index.
const TITLES := [["Lord", "Lady"], ["Lord", "Lady"], ["Duke", "Duchess"], ["Duke", "Duchess"], ["King", "Queen"]]
const HEIR_TITLES := [["Heir", "Heir"], ["Heir", "Heir"], ["Heir", "Heir"], ["Heir", "Heir"], ["Prince", "Princess"]]

const NAMES_M := ["Edric", "Aldous", "Godfrey", "Roland", "Osbert", "Hugh", "Leofwin", "Baldwin",
	"Geoffrey", "Ranulf", "Tristan", "Alaric", "Conrad", "Everard", "Walter", "Anselm"]
const NAMES_F := ["Matilda", "Eleanor", "Isabeau", "Adela", "Rosamund", "Gwendolyn", "Beatrice",
	"Edith", "Cecily", "Aveline", "Juliana", "Mahault", "Sybil", "Ysolde", "Alys", "Philippa"]
const HOUSES := ["Aldmoor", "Ravenhall", "Brightwater", "Stonecroft", "Ashbourne", "Wyndham",
	"Greymantle", "Oakheart", "Thornfield", "Blackwood", "Harrowgate", "Silverdale"]
