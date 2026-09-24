class_name Royals
extends Node
## The royal family living in the castle: a ruler, a spouse and an heir,
## each with a name, age and (for the ruler) traits that shape the realm.
## They age a year every RoyalDefs.YEAR seconds; the ruler dies of old age
## and the heir inherits, marries and has a child. A ruler who dies with no
## heir leaves a succession crisis until a noble claims the throne.
## The castle also holds the treasury and stores: raiders who bring it
## below half HP during a raid break in, steal gold, burn goods and may
## kill a royal. On the map the family strolls the castle grounds
## (RoyalAgent).

signal changed

var world: WorldMap
var progression: Progression
var house := ""
## Each person: {"name", "male": bool, "age": float, "lifespan": float,
## "traits": Array}. Empty when there's nobody in that place.
var ruler := {}
var spouse := {}
var heir := {}
## Seconds left of a succession crisis (0 = none).
var crisis_left := 0.0
## True once raiders broke into the castle, until it's repaired.
var breached := false

var _marry_timer := 0.0
var _child_timer := 0.0
var _rng := RandomNumberGenerator.new()
var _agents := {}  # role -> RoyalAgent


func setup(p_world: WorldMap, p_progression: Progression) -> void:
	world = p_world
	progression = p_progression


## A new game: the founding family, the same for the same map seed.
func found(seed_value: int) -> void:
	_rng.seed = seed_value
	house = RoyalDefs.HOUSES[_rng.randi() % RoyalDefs.HOUSES.size()]
	ruler = _person(_rng.randf() < 0.5, _rng.randf_range(30.0, 34.0))
	spouse = _person(not ruler.male, ruler.age + _rng.randf_range(-3.0, 3.0))
	heir = _person(_rng.randf() < 0.5, _rng.randf_range(6.0, 9.0))
	_after_change()


func _ready() -> void:
	world.keep.health.changed.connect(_on_castle_hurt)


# --- Names and titles ----------------------------------------------------------

func title_of(role: String) -> String:
	var p := person(role)
	if p.is_empty():
		return ""
	var tier := clampi(progression.tier, 0, RoyalDefs.TITLES.size() - 1)
	var titles: Array = RoyalDefs.HEIR_TITLES[tier] if role == "heir" else RoyalDefs.TITLES[tier]
	return "%s %s" % [titles[0] if p.male else titles[1], p.name]


func person(role: String) -> Dictionary:
	return {"ruler": ruler, "spouse": spouse, "heir": heir}.get(role, {})


func in_crisis() -> bool:
	return crisis_left > 0.0


func trait_names(p: Dictionary) -> String:
	return ", ".join(p.get("traits", []).map(func(t: String) -> String: return RoyalDefs.TRAITS[t].name))


# --- Time --------------------------------------------------------------------

func _process(delta: float) -> void:
	var years := delta / RoyalDefs.YEAR
	for p: Dictionary in [ruler, spouse, heir]:
		if not p.is_empty():
			p.age += years
	if in_crisis():
		crisis_left -= delta
		if crisis_left <= 0.0:
			_new_dynasty()
		return
	if not spouse.is_empty() and spouse.age >= spouse.lifespan:
		GameState.notify("%s has died at %d. The court mourns." % [title_of("spouse"), spouse.age])
		spouse = {}
		_marry_timer = RoyalDefs.MARRY_AFTER * RoyalDefs.YEAR
		_after_change()
	if not ruler.is_empty() and ruler.age >= ruler.lifespan:
		ruler_dies("died peacefully at %d" % ruler.age)
		return
	if spouse.is_empty() and not ruler.is_empty():
		_marry_timer -= delta
		if _marry_timer <= 0.0:
			spouse = _person(not ruler.male, ruler.age + _rng.randf_range(-6.0, 1.0))
			_child_timer = RoyalDefs.CHILD_AFTER * RoyalDefs.YEAR
			GameState.notify("%s has married %s. The realm celebrates!" % [title_of("ruler"), spouse.name])
			_after_change()
	elif heir.is_empty() and not spouse.is_empty() and ruler.age < RoyalDefs.CHILD_MAX_AGE:
		_child_timer -= delta
		if _child_timer <= 0.0:
			heir = _person(_rng.randf() < 0.5, 0.0)
			GameState.notify("An heir is born to %s: %s!" % [title_of("ruler"), heir.name])
			Sound.play("chime")
			_after_change()


## The ruler is gone: the heir takes the throne, or a crisis begins.
func ruler_dies(how: String) -> void:
	var old := title_of("ruler")
	if not heir.is_empty():
		ruler = heir
		heir = {}
		spouse = {}
		_marry_timer = RoyalDefs.MARRY_AFTER * RoyalDefs.YEAR
		GameState.notify("%s has %s. Long live %s!" % [old, how, title_of("ruler")])
		Sound.play("chime")
	else:
		ruler = {}
		spouse = {}
		crisis_left = RoyalDefs.CRISIS_TIME
		var lost := int(GameState.count("gold") * RoyalDefs.CRISIS_GOLD_LOSS)
		if lost > 0:
			GameState.spend({"gold": lost})
		GameState.notify("%s has %s with no heir! A succession crisis grips the realm: no taxes, unrest, %d gold lost." % [
			old, how, lost])
		Sound.play("defeat", null, -6.0)
	_after_change()


func _new_dynasty() -> void:
	crisis_left = 0.0
	house = RoyalDefs.HOUSES[_rng.randi() % RoyalDefs.HOUSES.size()]
	ruler = _person(_rng.randf() < 0.5, _rng.randf_range(30.0, 40.0))
	spouse = {}
	heir = {}
	_marry_timer = RoyalDefs.MARRY_AFTER * RoyalDefs.YEAR
	GameState.notify("%s of House %s claims the throne. The crisis is over." % [title_of("ruler"), house])
	Sound.play("tier")
	_after_change()


func _person(male: bool, age: float) -> Dictionary:
	var names: Array = RoyalDefs.NAMES_M if male else RoyalDefs.NAMES_F
	var traits := []
	var keys := RoyalDefs.TRAITS.keys()
	while traits.size() < 2:
		var t: String = keys[_rng.randi() % keys.size()]
		if t in traits or RoyalDefs.CONFLICTS.any(func(pair: Array) -> bool: return t in pair and traits.any(
				func(o: String) -> bool: return o in pair)):
			continue
		traits.append(t)
		if _rng.randf() < 0.4:
			break  # some have just one
	return {"name": names[_rng.randi() % names.size()], "male": male, "age": maxf(age, 0.0),
		"lifespan": _rng.randf_range(RoyalDefs.LIFESPAN[0], RoyalDefs.LIFESPAN[1]), "traits": traits}


## Re-applies the ruler's traits (or the crisis) and refreshes the family on
## the map.
func _after_change() -> void:
	var mods := {}
	var sources: Array = [RoyalDefs.CRISIS_MODS] if in_crisis() else ruler.get("traits", []).map(
		func(t: String) -> Dictionary: return RoyalDefs.TRAITS[t].mods)
	for m: Dictionary in sources:
		for key: String in m:
			var cur: Dictionary = mods.get(key, {})
			if m[key].has("mul"):
				cur["mul"] = cur.get("mul", 1.0) * m[key].mul
			if m[key].has("add"):
				cur["add"] = cur.get("add", 0.0) + m[key].add
			mods[key] = cur
	GameState.set_royal_mods(mods)
	_refresh_agents()
	changed.emit()


# --- The castle breached -------------------------------------------------------

func _on_castle_hurt() -> void:
	var h := world.keep.health
	if h.hp >= h.max_hp * RoyalDefs.BREACH_AT:
		if breached:
			breached = false
			GameState.notify("The castle's walls are whole again: the breach is sealed.")
			changed.emit()
		return
	if breached or not world.raid_active or h.is_dead():
		return
	breach()


## Raiders break into the castle: they steal gold, burn stored goods and may
## kill one of the family.
func breach() -> void:
	breached = true
	var keep := world.keep
	var stolen := int(GameState.count("gold") * RoyalDefs.BREACH_GOLD)
	if stolen > 0:
		GameState.spend({"gold": stolen})
	var burned := 0
	for item: String in keep.inventory.keys():
		if item == "gold":
			continue
		var n := int(keep.inventory[item] * RoyalDefs.BREACH_BURN)
		if n > 0:
			burned += world.stock.take_from(keep, item, n)
	var text := "Raiders have broken into the %s! They stole %d gold and burned %d stored goods." % [
		keep.title, stolen, burned]
	Sound.play("crash", keep.center())
	var present := ["ruler", "spouse", "heir"].filter(func(r: String) -> bool: return not person(r).is_empty())
	if not present.is_empty() and _rng.randf() < RoyalDefs.BREACH_KILL_CHANCE:
		var victim: String = present[_rng.randi() % present.size()]
		GameState.notify(text)
		if victim == "ruler":
			ruler_dies("been slain by raiders")
		else:
			GameState.notify("%s was slain by the raiders!" % title_of(victim))
			if victim == "spouse":
				spouse = {}
				_marry_timer = RoyalDefs.MARRY_AFTER * RoyalDefs.YEAR
			else:
				heir = {}
				_child_timer = RoyalDefs.CHILD_AFTER * RoyalDefs.YEAR
			_after_change()
		return
	GameState.notify(text)
	changed.emit()


# --- On the map ------------------------------------------------------------------

func _refresh_agents() -> void:
	if world == null or world.unit_root == null:
		return
	for role: String in ["ruler", "spouse", "heir"]:
		var p := person(role)
		var agent: RoyalAgent = _agents.get(role)
		if p.is_empty():
			if agent != null:
				agent.queue_free()
				_agents.erase(role)
			continue
		var look := "heir" if role == "heir" else ("king" if p.male else "queen")
		if agent == null:
			agent = RoyalAgent.new()
			agent.setup(world, look)
			world.unit_root.add_child(agent)
			_agents[role] = agent
		agent.look = look
		agent.role = role
		agent.tooltip = title_of(role)


## The family member drawn under `world_pos` (a role), or "".
func royal_at(world_pos: Vector2) -> String:
	for role: String in _agents:
		var a: RoyalAgent = _agents[role]
		if a.visible and (a.position + Vector2(0, -12)).distance_to(world_pos) <= 12.0:
			return role
	return ""


# --- Saves -------------------------------------------------------------------

func to_save() -> Dictionary:
	return {"house": house, "ruler": ruler, "spouse": spouse, "heir": heir, "crisis_left": crisis_left,
		"breached": breached, "marry": _marry_timer, "child": _child_timer, "rng": _rng.state}


func restore(data: Dictionary) -> void:
	house = data.house
	ruler = _load_person(data.ruler)
	spouse = _load_person(data.spouse)
	heir = _load_person(data.heir)
	crisis_left = float(data.crisis_left)
	breached = bool(data.breached)
	_marry_timer = float(data.marry)
	_child_timer = float(data.child)
	_rng.state = int(data.rng)
	_after_change()


static func _load_person(d: Dictionary) -> Dictionary:
	if d.is_empty():
		return {}
	return {"name": d.name, "male": bool(d.male), "age": float(d.age), "lifespan": float(d.lifespan),
		"traits": Array(d.traits)}
