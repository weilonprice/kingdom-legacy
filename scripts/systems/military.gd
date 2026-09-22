class_name Military
extends Node
## Owns squads and troops: training at barracks (one villager + cost per
## recruit), feeding, and gold upkeep. Each barracks fields one squad.

signal squads_changed

const UPKEEP_INTERVAL := 60.0
## Fraction of max HP an unfed troop loses at each missed meal.
const HUNGER_DAMAGE := 0.25

var world: WorldMap
var citizens: CitizenManager
var progression: Progression
var squads: Array[Squad] = []
## Barracks -> {"queue": Array[String], "timer": float}
var training := {}

var _next_squad_id := 1
var _upkeep_timer := UPKEEP_INTERVAL


func setup(p_world: WorldMap, p_citizens: CitizenManager) -> void:
	world = p_world
	citizens = p_citizens
	world.building_removed.connect(_on_building_removed)


func troops() -> Array[Troop]:
	var all: Array[Troop] = []
	for s in squads:
		all.append_array(s.troops)
	return all


func upkeep_per_minute() -> int:
	var total := 0
	for t in troops():
		total += t.def.upkeep
	return total


func squad_for(barracks: Building) -> Squad:
	for s in squads:
		if s.barracks == barracks:
			return s
	var s := Squad.new()
	s.id = _next_squad_id
	_next_squad_id += 1
	s.barracks = barracks
	s.rally_tile = barracks.entrance()
	squads.append(s)
	squads_changed.emit()
	return s


func queue_for(barracks: Building) -> Array:
	return training.get(barracks, {}).get("queue", [])


func training_progress(barracks: Building) -> float:
	var entry: Dictionary = training.get(barracks, {})
	if entry.is_empty() or entry.queue.is_empty():
		return 0.0
	var total: float = UnitDefs.get_def(entry.queue[0]).train_time
	return 1.0 - entry.timer / total


## Starts training a recruit. Returns "" on success or a reason it can't.
func train(barracks: Building, unit_id: String) -> String:
	var def := UnitDefs.get_def(unit_id)
	if progression != null and not progression.is_unlocked("units", unit_id):
		return "%s: %s" % [def.name, progression.locked_reason("units", unit_id)]
	var squad := squad_for(barracks)
	var capacity: int = barracks.def.troop_capacity
	if squad.troops.size() + queue_for(barracks).size() >= capacity:
		return "Barracks is full (%d troops)" % capacity
	if not barracks.has_road:
		return "Barracks needs road access"
	if not GameState.can_afford(def.cost):
		return "Not enough resources — needs %s" % BuildingDefs.cost_text(def.cost)
	if not citizens.draft_villager(barracks.entrance()):
		return "No villager available to recruit"
	GameState.spend(def.cost)
	if not training.has(barracks):
		training[barracks] = {"queue": [], "timer": 0.0}
	var entry: Dictionary = training[barracks]
	if entry.queue.is_empty():
		entry.timer = def.train_time
	entry.queue.append(unit_id)
	return ""


func _process(delta: float) -> void:
	for barracks: Building in training.keys():
		var entry: Dictionary = training[barracks]
		if entry.queue.is_empty():
			continue
		entry.timer -= delta
		if entry.timer <= 0.0:
			_spawn_troop(barracks, entry.queue.pop_front())
			if not entry.queue.is_empty():
				entry.timer = UnitDefs.get_def(entry.queue[0]).train_time
	_upkeep_timer -= delta
	if _upkeep_timer <= 0.0:
		_upkeep_timer = UPKEEP_INTERVAL
		_feed_and_pay()


func _spawn_troop(barracks: Building, unit_id: String) -> void:
	var squad := squad_for(barracks)
	var troop := Troop.new()
	troop.setup(world, unit_id, squad, barracks.entrance())
	troop.slot = squad.troops.size()
	troop.died.connect(_on_troop_died)
	squad.troops.append(troop)
	world.unit_root.add_child(troop)
	GameState.notify("%s joined %s" % [_with_article(troop.def.name), squad.display_name()])
	squads_changed.emit()


func _feed_and_pay() -> void:
	var all := troops()
	if all.is_empty():
		return
	var eaten := GameState.eat(all.size())
	for i in range(eaten, all.size()):
		all[i].health.take_damage(all[i].health.max_hp * HUNGER_DAMAGE)
	if eaten < all.size():
		GameState.notify("%d troops went hungry!" % (all.size() - eaten))

	var owed := upkeep_per_minute()
	var paid := mini(owed, GameState.count("gold"))
	GameState.remove_resource("gold", paid)
	if paid < owed:
		# Unpaid soldiers desert, most expensive first.
		var deserter: Troop = all[0]
		for t in all:
			if t.def.upkeep > deserter.def.upkeep:
				deserter = t
		GameState.notify("Unpaid, %s deserted!" % _with_article(deserter.def.name).to_lower())
		_remove_troop(deserter)


func _on_troop_died(troop: Troop) -> void:
	GameState.notify("%s fell in battle" % _with_article(troop.def.name))
	_remove_troop(troop)


func _remove_troop(troop: Troop) -> void:
	var squad := troop.squad
	squad.troops.erase(troop)
	for i in squad.troops.size():
		squad.troops[i].slot = i
	troop.queue_free()
	squads_changed.emit()


static func _with_article(noun: String) -> String:
	return ("An " if noun.substr(0, 1).to_lower() in ["a", "e", "i", "o", "u"] else "A ") + noun.to_lower()


func _on_building_removed(b: Building) -> void:
	training.erase(b)
	for s in squads:
		if s.barracks == b:
			s.barracks = null
	squads_changed.emit()
