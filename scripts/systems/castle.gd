class_name Castle
extends Node
## The castle's growth (see CastleDefs). Starting an upgrade pays its gold
## and gives the castle BUILDERS jobs; builders carry the materials in from
## storage (Villager._plan_build), then work on the site. When the work is
## done the castle grows to the next stage's size in place, the builders
## are released, and the stage's HP and storage bonus apply.

signal changed

var world: WorldMap
var progression: Progression
var stage := 0
## The upgrade under way, or empty: {"stage", "delivered", "pending", "work_done"}.
var project := {}


func setup(p_world: WorldMap, p_progression: Progression) -> void:
	world = p_world
	progression = p_progression
	changed.connect(func() -> void:
		if world.keep != null:
			world.keep.queue_redraw())


func title() -> String:
	return CastleDefs.STAGES[stage].title


func next_stage() -> Dictionary:
	return CastleDefs.STAGES[stage + 1] if stage + 1 < CastleDefs.STAGES.size() else {}


## "" if the next upgrade can start now, otherwise why not.
func upgrade_problem() -> String:
	var next := next_stage()
	if next.is_empty():
		return "The castle is complete."
	if is_building():
		return "Already under construction."
	if progression.tier < next.tier:
		return "Needs the %s tier." % progression.tier_name(next.tier)
	if GameState.count("gold") < next.gold:
		return "Needs %d gold to begin." % next.gold
	return ""


func is_building() -> bool:
	return not project.is_empty()


func start_upgrade() -> String:
	var problem := upgrade_problem()
	if problem != "":
		return problem
	var next := next_stage()
	GameState.spend({"gold": next.gold})
	project = {"stage": stage + 1, "delivered": {}, "pending": {}, "work_done": 0.0}
	world.keep.extra_jobs = CastleDefs.BUILDERS
	GameState.notify("Work begins on the %s! Builders will haul %s to the site." % [
		next.title, BuildingDefs.cost_text(next.materials)])
	Sound.play("build", world.keep.center())
	changed.emit()
	return ""


# --- Materials ---------------------------------------------------------------

## Goods still to be brought (not delivered, not on the way): item -> amount.
func missing() -> Dictionary:
	var result := {}
	if project.is_empty():
		return result
	var needed: Dictionary = CastleDefs.STAGES[project.stage].materials
	for item: String in needed:
		var left: int = needed[item] - project.delivered.get(item, 0) - project.pending.get(item, 0)
		if left > 0:
			result[item] = left
	return result


func materials_done() -> bool:
	if project.is_empty():
		return false
	var needed: Dictionary = CastleDefs.STAGES[project.stage].materials
	for item: String in needed:
		if project.delivered.get(item, 0) < needed[item]:
			return false
	return true


## A builder set off with `amount` of `item`.
func claim(item: String, amount: int) -> void:
	project.pending[item] = project.pending.get(item, 0) + amount


## A builder dropped `amount` of `item` at the site (or gave up: delivered=false).
func deliver(item: String, amount: int, delivered := true) -> void:
	if project.is_empty():
		return
	project.pending[item] = maxi(project.pending.get(item, 0) - amount, 0)
	if delivered:
		project.delivered[item] = project.delivered.get(item, 0) + amount
		changed.emit()


# --- Work --------------------------------------------------------------------

## Somewhere for a builder to stand: open ground inside the new footprint,
## or around its edge.
func work_spot() -> Vector2i:
	var size: int = CastleDefs.STAGES[project.stage].size
	var center := world.castle_grounds.get_center()
	var area := Rect2i(center - Vector2i(size / 2, size / 2), Vector2i(size, size)).grow(1)
	var spots: Array[Vector2i] = []
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var t := Vector2i(x, y)
			if world.is_walkable(t):
				spots.append(t)
	return spots.pick_random() if not spots.is_empty() else WorldMap.INVALID_TILE


func add_work(seconds: float) -> void:
	if project.is_empty() or not materials_done():
		return
	project.work_done += seconds
	changed.emit()
	if project.work_done >= CastleDefs.STAGES[project.stage].work:
		_complete()


## 0..1 over the whole project (materials count for half).
func progress() -> float:
	if project.is_empty():
		return 0.0
	var st: Dictionary = CastleDefs.STAGES[project.stage]
	var need := 0
	var have := 0
	for item: String in st.materials:
		need += st.materials[item]
		have += mini(project.delivered.get(item, 0), st.materials[item])
	return 0.5 * have / float(need) + 0.5 * minf(project.work_done / st.work, 1.0)


func _complete() -> void:
	var st: Dictionary = CastleDefs.STAGES[project.stage]
	project = {}
	world.keep.extra_jobs = 0
	for v in world.keep.workers.duplicate():
		v.lose_job()
	set_stage(stage + 1)
	GameState.notify("The %s is complete! It stands %dx%d over your kingdom." % [st.title, st.size, st.size])
	Sound.play("tier")
	changed.emit()


## Sets the stage (grows the castle's footprint) and applies its bonuses.
func set_stage(value: int) -> void:
	stage = value
	world.resize_keep(CastleDefs.STAGES[stage].size)
	progression.apply_keep_upgrade()


# --- Saves -------------------------------------------------------------------

func to_save() -> Dictionary:
	return {"stage": stage, "project": project}


func restore(data: Dictionary) -> void:
	set_stage(int(data.get("stage", 0)))
	var p: Dictionary = data.get("project", {})
	project = {}
	if not p.is_empty():
		project = {"stage": int(p.stage), "delivered": _ints(p.delivered), "pending": {},
			"work_done": float(p.work_done)}
	world.keep.extra_jobs = CastleDefs.BUILDERS if is_building() else 0
	changed.emit()


static func _ints(d: Dictionary) -> Dictionary:
	var out := {}
	for k: String in d:
		out[k] = int(d[k])
	return out
