class_name Sickness
extends Node
## Disease (M29). Once the town has MIN_POPULATION people, each lived-in
## home may fall sick now and then: more often when homes crowd around it,
## without water, and in unpleasant quarters; a Bathhouse nearby cuts the
## risk sharply. Sickness spreads to homes close by. Sick residents stay in
## bed. A Physician walks over and cures a sick home; left alone, a home
## recovers after a while or loses a resident.

const TICK := 10.0
const MIN_POPULATION := 30
const BASE_CHANCE := 0.006
const CROWD_BONUS := 0.12      # per other home within CROWD_RADIUS
const CROWD_RADIUS := 4
const SPREAD_RADIUS := 3
const SPREAD_CHANCE := 0.06
const BATH_FACTOR := 0.25
const NO_WATER_FACTOR := 1.6
const UGLY_FACTOR := 1.4
## Untreated: after this long the home recovers or loses someone.
const CRISIS_TIME := 150.0
const DEATH_CHANCE := 0.5

var world: WorldMap
var citizens: CitizenManager
var _timer := TICK


func setup(p_world: WorldMap, p_citizens: CitizenManager) -> void:
	world = p_world
	citizens = p_citizens


func sick_homes() -> Array:
	return world.buildings.filter(func(b: Building) -> bool: return b.sick)


func _process(delta: float) -> void:
	for h in sick_homes():
		h.sick_time += delta
		if h.sick_time >= CRISIS_TIME:
			_crisis(h)
	_timer -= delta
	if _timer > 0.0:
		return
	_timer = TICK
	if GameState.population < MIN_POPULATION:
		return
	var homes := world.buildings.filter(func(b: Building) -> bool:
		return b.is_home() and b != world.keep and not b.residents.is_empty())
	var sick_now := homes.filter(func(b: Building) -> bool: return b.sick)
	for h: Building in homes:
		if h.sick:
			continue
		var chance := BASE_CHANCE * (1.0 + CROWD_BONUS * _near(h, homes, CROWD_RADIUS))
		for s: Building in sick_now:
			if s.center().distance_to(h.center()) <= SPREAD_RADIUS * Terrain.TILE_SIZE + 32.0:
				chance += SPREAD_CHANCE
		if h.needs_met.get("hygiene", false):
			chance *= BATH_FACTOR
		if not h.needs_met.get("water", false):
			chance *= NO_WATER_FACTOR
		if world.building_desirability(h) < 0.0:
			chance *= UGLY_FACTOR
		if randf() < chance:
			fall_sick(h)


func fall_sick(h: Building) -> void:
	if h.sick:
		return
	h.sick = true
	h.sick_time = 0.0
	h.queue_redraw()
	GameState.notify("Sickness has broken out at a %s. A Physician can cure it." % h.level_name())


func cure(h: Building) -> void:
	if not h.sick:
		return
	h.sick = false
	h.sick_time = 0.0
	h.queue_redraw()
	GameState.notify("The physician cured the sick at a %s." % h.level_name())


func _crisis(h: Building) -> void:
	h.sick = false
	h.sick_time = 0.0
	h.queue_redraw()
	if randf() < DEATH_CHANCE and not h.residents.is_empty():
		var v: Villager = h.residents.back()
		GameState.notify("%s died of the sickness. A Physician would have saved them." % v.villager_name)
		citizens.remove_villager(v)
	else:
		GameState.notify("The sickness at a %s has passed." % h.level_name())


func _near(h: Building, homes: Array, radius: int) -> int:
	var n := 0
	for o: Building in homes:
		if o != h and o.center().distance_to(h.center()) <= radius * Terrain.TILE_SIZE + 32.0:
			n += 1
	return n
