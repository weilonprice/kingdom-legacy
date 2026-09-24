class_name Research
extends Node
## Research queue. Topics are paid for up front, then progress while scholars
## are stationed in a Scholar's Hall (each scholar adds 1x speed).

signal changed

var world: WorldMap
var completed: Array[String] = []
var queue: Array[String] = []
var progress := 0.0   # seconds of single-scholar work done on queue[0]


func setup(p_world: WorldMap) -> void:
	world = p_world


func is_done(id: String) -> bool:
	return id in completed


func is_queued(id: String) -> bool:
	return id in queue


func active() -> String:
	return queue[0] if not queue.is_empty() else ""


func progress_ratio() -> float:
	if queue.is_empty():
		return 0.0
	return progress / ResearchDefs.get_def(queue[0]).time


## Scholars currently studying across all halls.
func scholars_working() -> int:
	var n := 0
	for b in world.buildings:
		if b.def.get("work", "") == "study":
			n += b.stationed_count()
	return n


## Pays for and queues a topic. Returns "" on success or a reason it can't.
func start(id: String, progression: Progression) -> String:
	if is_done(id) or is_queued(id):
		return "Already researched or queued"
	if not progression.is_unlocked("research", id):
		return progression.locked_reason("research", id)
	var def := ResearchDefs.get_def(id)
	if not GameState.spend(def.cost):
		return "Not enough resources — needs %s" % BuildingDefs.cost_text(def.cost)
	queue.append(id)
	changed.emit()
	return ""


func _process(delta: float) -> void:
	if queue.is_empty():
		return
	progress += delta * scholars_working() * GameState.mod("research_speed")
	if progress >= ResearchDefs.get_def(queue[0]).time:
		_complete(queue.pop_front())


## Marks saved research done and re-applies its effects, quietly.
func restore_completed(id: String) -> void:
	completed.append(id)
	for effect: Dictionary in ResearchDefs.get_def(id).effects:
		GameState.apply_effect(effect)
	changed.emit()


func _complete(id: String) -> void:
	progress = 0.0
	completed.append(id)
	var def := ResearchDefs.get_def(id)
	for effect: Dictionary in def.effects:
		GameState.apply_effect(effect)
	GameState.notify("Research complete: %s — %s" % [def.name, def.desc])
	changed.emit()
