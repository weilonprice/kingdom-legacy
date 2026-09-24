class_name Needs
extends Node
## Every UPDATE_INTERVAL, works out which needs each home has met (service
## coverage + fed residents), its happiness, and its level; collects taxes
## each minute; and makes long-unhappy homes lose residents.

const UPDATE_INTERVAL := 2.0
const TAX_INTERVAL := 60.0
## Seconds a home's needs must hold (or stay lost) before its level changes.
const LEVEL_DELAY := 10.0
## Seconds below NeedDefs.UNHAPPY before a resident leaves.
const EMIGRATION_DELAY := 45.0

var world: WorldMap
var citizens: CitizenManager
var seasons: Seasons
## Gold collected at the last tax time, for the HUD.
var last_tax := 0

var _update_timer := 0.0
var _tax_timer := TAX_INTERVAL


func setup(p_world: WorldMap, p_citizens: CitizenManager) -> void:
	world = p_world
	citizens = p_citizens


func _process(delta: float) -> void:
	_update_timer -= delta
	if _update_timer <= 0.0:
		_update_timer = UPDATE_INTERVAL
		_update_homes(UPDATE_INTERVAL)
	_tax_timer -= delta
	if _tax_timer <= 0.0:
		_tax_timer = TAX_INTERVAL
		_collect_taxes()


func homes() -> Array[Building]:
	var found: Array[Building] = []
	for b in world.buildings:
		if b.is_home():
			found.append(b)
	return found


## Services currently providing `need` (staffed if they have jobs).
func _providers(need: String) -> Array[Building]:
	var found: Array[Building] = []
	for b in world.buildings:
		if b.def.get("provides", "") == need and b.service_active():
			found.append(b)
	return found


func _update_homes(elapsed: float) -> void:
	var providers := {}
	for need: String in NeedDefs.ORDER:
		if need != "food":
			providers[need] = _providers(need)
	var total := 0.0
	var list := homes()
	for home in list:
		var met := {"food": _fed(home)}
		if seasons != null and seasons.is_winter():
			met["warmth"] = seasons.warm
		for need: String in providers:
			met[need] = providers[need].any(func(p: Building) -> bool: return p.covers(home))
		home.needs_met = met
		home.happiness = _happiness(met)
		_update_level(home, elapsed)
		_update_emigration(home, elapsed)
		total += home.happiness
		home.queue_redraw()
	GameState.set_happiness(total / list.size() if not list.is_empty() else NeedDefs.BASE_HAPPINESS)


func _fed(home: Building) -> bool:
	if GameState.edible_total() <= 0:
		return false
	return home.residents.all(func(v: Villager) -> bool: return v.missed_meals == 0)


func _happiness(met: Dictionary) -> float:
	var h := NeedDefs.BASE_HAPPINESS
	for need: String in met:
		h += NeedDefs.NEEDS[need].met if met[need] else NeedDefs.NEEDS[need].unmet
	h += NeedDefs.TAX_RATES[GameState.tax_rate].happiness
	h += GameState.mod("happiness", 0.0)  # the ruler's traits, a succession crisis
	return clampf(h, 0.0, 100.0)


## Level the home's needs currently qualify it for.
func _eligible_level(home: Building) -> int:
	var level := 1
	for i in NeedDefs.LEVELS.size():
		var needs: Array = NeedDefs.LEVELS[i].needs
		if needs.all(func(n: String) -> bool: return home.needs_met.get(n, false)):
			level = i + 1
	return level


func _update_level(home: Building, elapsed: float) -> void:
	if home.def.get("level_bonus", 0) == 0:
		return  # the Keep houses settlers but doesn't level up
	var target := _eligible_level(home)
	if target == home.level:
		home.level_timer = 0.0
		return
	home.level_timer += elapsed
	if home.level_timer < LEVEL_DELAY:
		return
	home.level_timer = 0.0
	var old := home.level
	home.level += 1 if target > home.level else -1
	if home.level > old:
		GameState.notify("A home grew into a %s" % home.level_name())
	else:
		GameState.notify("A %s fell into disrepair" % NeedDefs.LEVELS[old - 1].name)
		# Evict anyone who no longer fits.
		while home.residents.size() > home.housing_capacity():
			citizens.remove_villager(home.residents.back())


func _update_emigration(home: Building, elapsed: float) -> void:
	if home.happiness >= NeedDefs.UNHAPPY or home.residents.is_empty():
		home.unhappy_time = 0.0
		return
	home.unhappy_time += elapsed
	if home.unhappy_time >= EMIGRATION_DELAY:
		home.unhappy_time = 0.0
		var leaver: Villager = home.residents.back()
		GameState.notify("%s left an unhappy home" % leaver.villager_name)
		citizens.remove_villager(leaver)


func tax_per_minute() -> int:
	var rate: float = NeedDefs.TAX_RATES[GameState.tax_rate].gold
	var total := 0.0
	for home in homes():
		if home.happiness >= NeedDefs.UNHAPPY:
			total += home.residents.size() * rate * NeedDefs.LEVELS[home.level - 1].tax
	return roundi(total * GameState.mod("tax"))


func _collect_taxes() -> void:
	last_tax = tax_per_minute()
	if last_tax > 0:
		GameState.add_resource("gold", last_tax)
		Sound.play("coins", null, -8.0)
