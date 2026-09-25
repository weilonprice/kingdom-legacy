class_name ClassDefs
extends RefCounted
## The three classes (M27). A villager's class comes from their home: a
## Cottage houses peasants, a Townhouse burghers, a Manor nobles (the
## castle's residents are peasants). Jobs have a class too:
##   peasant - labour: gathering, farming, hauling, building, guard duty
##   burgher - skilled trades: smithy, armory, tavern
##   noble   - scholars, clergy, officers (a Barracks captain)
## Market and Trading Post take burghers or nobles (merchants). Burghers
## with no skilled work take labour; nobles never labour. When nobody of a
## job's class is free, a lower-class villager fills in as an apprentice
## and works at APPRENTICE_SPEED (so no building is ever stuck) - except a
## Barracks captain, who must be a noble to train knights.

const NAMES := ["peasant", "burgher", "noble"]
const TITLES := ["Peasants", "Burghers", "Nobles"]
const APPRENTICE_SPEED := 0.6

const JOB_CLASS := {
	"smithy": "burgher", "armory": "burgher", "tavern": "burgher",
	"brewery": "burgher", "toolmaker": "burgher", "weaver": "burgher", "tailor": "burgher", "winery": "burgher",
	"market": "burgher", "trading_post": "burgher",
	"scholars_hall": "noble", "chapel": "noble", "barracks": "noble",
}
## Jobs a higher class may also take (merchants can be nobles).
const ALSO_NOBLE := ["market", "trading_post"]


static func rank(social_class: String) -> int:
	return NAMES.find(social_class)


static func job_class(b: Building) -> String:
	return JOB_CLASS.get(b.def_id, "peasant")


## Whether a villager of `social_class` properly fits a job at `b` (not as
## an apprentice).
static func fits(social_class: String, b: Building) -> bool:
	var want := job_class(b)
	if social_class == want:
		return true
	if social_class == "burgher" and want == "peasant":
		return true  # burghers take labour when there's no skilled work
	return social_class == "noble" and b.def_id in ALSO_NOBLE
