class_name Progression
extends Node
## Tracks the settlement tier. Checks the next tier's requirements every few
## seconds; on reaching it, unlocks content and upgrades the Keep.

signal tier_changed(tier: int)

const CHECK_INTERVAL := 2.0

var world: WorldMap
var raids: RaidDirector
var research: Research
var tier := 0

var _check_timer := 0.0


func setup(p_world: WorldMap, p_raids: RaidDirector, p_research: Research) -> void:
	world = p_world
	raids = p_raids
	research = p_research


func _ready() -> void:
	_apply_keep_upgrade()


func tier_name(index := -1) -> String:
	return TierDefs.TIERS[tier if index < 0 else index].name


func is_max_tier() -> bool:
	return tier >= TierDefs.TIERS.size() - 1


func _process(delta: float) -> void:
	_check_timer -= delta
	if _check_timer > 0.0 or is_max_tier():
		return
	_check_timer = CHECK_INTERVAL
	if requirements_met(tier + 1):
		_advance()


# --- Unlocks ----------------------------------------------------------------

func is_unlocked(kind: String, id: String) -> bool:
	for i in tier + 1:
		if id in TierDefs.TIERS[i].unlocks.get(kind, []):
			return true
	return false


## Index of the tier that unlocks `id`, or -1 if none does.
func unlock_tier(kind: String, id: String) -> int:
	for i in TierDefs.TIERS.size():
		if id in TierDefs.TIERS[i].unlocks.get(kind, []):
			return i
	return -1


func locked_reason(kind: String, id: String) -> String:
	if is_unlocked(kind, id):
		return ""
	var t := unlock_tier(kind, id)
	return "Unlocks at %s" % tier_name(t) if t >= 0 else "Not available yet"


# --- Requirements -----------------------------------------------------------

## [{text, met}] for each requirement of tier `index`.
func requirement_status(index: int) -> Array:
	var req: Dictionary = TierDefs.TIERS[index].requires
	var status := []
	if req.has("population"):
		status.append({"text": "Population %d/%d" % [GameState.population, req.population],
			"met": GameState.population >= req.population})
	if req.has("raids_survived"):
		status.append({"text": "Raids survived %d/%d" % [raids.raids_survived, req.raids_survived],
			"met": raids.raids_survived >= req.raids_survived})
	if req.has("research"):
		status.append({"text": "Research completed %d/%d" % [research.completed.size(), req.research],
			"met": research.completed.size() >= req.research})
	if req.has("house_level"):
		var want: Dictionary = req.house_level
		var have := world.buildings.filter(func(b: Building) -> bool:
			return b.def.has("level_bonus") and b.level >= want.level).size()
		status.append({"text": "%ss or better %d/%d" % [NeedDefs.LEVELS[want.level - 1].name, have, want.count],
			"met": have >= want.count})
	if req.has("happiness"):
		status.append({"text": "Average happiness %d/%d" % [GameState.happiness, req.happiness],
			"met": GameState.happiness >= req.happiness})
	for id: String in req.get("buildings", []):
		var built := world.buildings.any(func(b: Building) -> bool: return b.def_id == id)
		status.append({"text": "Build a %s" % BuildingDefs.get_def(id).name, "met": built})
	return status


func requirements_met(index: int) -> bool:
	return requirement_status(index).all(func(r: Dictionary) -> bool: return r.met)


## Human-readable list of what tier `index` unlocks.
func unlock_summary(index: int) -> String:
	var unlocks: Dictionary = TierDefs.TIERS[index].unlocks
	var names := PackedStringArray()
	for id: String in unlocks.get("buildings", []):
		names.append(BuildingDefs.get_def(id).name)
	for id: String in unlocks.get("units", []):
		names.append(UnitDefs.get_def(id).name + "s")
	for id: String in unlocks.get("research", []):
		names.append(ResearchDefs.get_def(id).name)
	var keep: Dictionary = TierDefs.TIERS[index].keep
	names.append("%s: %d HP, %d storage" % [keep.title, keep.hp, keep.capacity])
	return ", ".join(names)


func _advance() -> void:
	tier += 1
	_apply_keep_upgrade()
	GameState.notify("Your settlement has grown into a %s! New buildings unlocked." % tier_name())
	tier_changed.emit(tier)
	if is_max_tier():
		raids.begin_final_siege()


func _apply_keep_upgrade() -> void:
	if world.keep == null:
		return
	var keep_def: Dictionary = TierDefs.TIERS[tier].keep
	world.keep.title = keep_def.title
	world.keep.base_capacity = keep_def.capacity
	world.keep.set_base_hp(keep_def.hp)
	world.recompute_capacity()
