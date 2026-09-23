extends Node
## Global kingdom state: resource totals (fronting the world's per-building
## Stock), population stats, happiness, research modifiers and game speed.

signal resources_changed
signal population_changed
signal speed_changed
signal notified(text: String)
signal modifiers_changed
signal happiness_changed

const SPEEDS := [0.0, 1.0, 2.0, 4.0]
const START_RESOURCES := {"wood": 120, "stone": 20, "gold": 50, "bread": 40}
## Difficulty presets picked in the main menu. `raid_size` scales raid
## headcounts, `first_raid` is seconds until the first raid.
const DIFFICULTIES := [
	{"name": "Easy", "raid_size": 0.7, "first_raid": 600.0, "bonus": {"wood": 60, "stone": 20, "gold": 50}},
	{"name": "Normal", "raid_size": 1.0, "first_raid": 420.0, "bonus": {}},
	{"name": "Hard", "raid_size": 1.35, "first_raid": 300.0, "bonus": {}},
]

## Kingdom totals of everything in storage (cache of `stock`).
var resources := {}
var capacity := {}     # category -> int
var stock: Stock
var population := 0
var housing := 0
var employed := 0
var jobs := 0
var speed := 1
var game_over := false
## New-game settings chosen in the main menu; they survive scene changes.
## seed 0 = random.
var new_game_seed := 0
var difficulty := 1
## Map edge length in tiles (main menu: Small / Normal / Large).
const MAP_SIZES := [{"name": "Small", "tiles": 96}, {"name": "Normal", "tiles": 128}, {"name": "Large", "tiles": 160}]
var map_size := 1
var hints_enabled := true
## Which seasonal art set the map uses ("" = the original green one).
var season := "autumn"
## Where saves go (tests point this elsewhere so they never touch real saves).
var save_dir := "user://saves"
## A save to apply when the game scene starts (set by Load / Continue).
var pending_load := {}
## Research bonuses: key -> value. Multipliers default to 1.0, additive
## bonuses to 0 (see ResearchDefs).
var modifiers := {}
## Index into NeedDefs.TAX_RATES.
var tax_rate := NeedDefs.DEFAULT_TAX_RATE
## Average happiness over all homes (0-100).
var happiness := NeedDefs.BASE_HAPPINESS

var _last_speed := 1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	reset()


## Fresh state for a new game (the autoload survives scene reloads).
func reset() -> void:
	resources = {}
	capacity = {}
	stock = null
	population = 0
	housing = 0
	employed = 0
	jobs = 0
	game_over = false
	season = "autumn"
	modifiers = {}
	tax_rate = NeedDefs.DEFAULT_TAX_RATE
	happiness = NeedDefs.BASE_HAPPINESS
	speed = 1
	_last_speed = 1
	Engine.time_scale = 1.0
	get_tree().paused = false
	resources_changed.emit()
	population_changed.emit()
	speed_changed.emit()


## Freezes the simulation for good; only a new game resumes it.
func end_game() -> void:
	game_over = true
	speed = 0
	get_tree().paused = true
	speed_changed.emit()


func notify(text: String) -> void:
	notified.emit(text)


# --- Happiness & taxes -------------------------------------------------------

func set_happiness(value: float) -> void:
	if absf(value - happiness) < 0.01:
		return
	happiness = value
	happiness_changed.emit()


func set_tax_rate(index: int) -> void:
	tax_rate = clampi(index, 0, NeedDefs.TAX_RATES.size() - 1)
	happiness_changed.emit()


# --- Modifiers --------------------------------------------------------------

func mod(key: String, default := 1.0) -> float:
	return modifiers.get(key, default)


func apply_effect(effect: Dictionary) -> void:
	var key: String = effect.key
	if effect.has("mul"):
		modifiers[key] = mod(key, 1.0) * effect.mul
	if effect.has("add"):
		modifiers[key] = mod(key, 0.0) + effect.add
	modifiers_changed.emit()


# --- Stock ------------------------------------------------------------------
# Thin front for the world's Stock (per-building inventories). `resources` and
# `capacity` are cached kingdom totals for the HUD, refreshed on every change.

func attach_stock(p_stock: Stock) -> void:
	stock = p_stock
	stock.changed.connect(_recount)
	var start := START_RESOURCES.duplicate()
	var bonus: Dictionary = DIFFICULTIES[difficulty].bonus
	for item: String in bonus:
		start[item] = start.get(item, 0) + bonus[item]
	for item: String in start:
		stock.store_at(stock.world.keep, item, start[item], true)
	_recount()


func _recount() -> void:
	resources = stock.totals()
	for category: String in ItemDefs.CAPPED_CATEGORIES:
		capacity[category] = stock.capacity(category)
	resources_changed.emit()


## Storage buildings were added/removed or research changed their capacity.
func refresh_capacity() -> void:
	if stock != null:
		_recount()


func count(item: String) -> int:
	return resources.get(item, 0)


func used(category: String) -> int:
	return stock.used(category) if stock != null else 0


## Free storage space for `item` across the kingdom.
func space_for(item: String) -> int:
	return stock.total_space(item) if stock != null else 0


func can_afford(cost: Dictionary) -> bool:
	for item in cost:
		if count(item) < cost[item]:
			return false
	return true


func spend(cost: Dictionary) -> bool:
	return can_afford(cost) and stock.spend(cost)


func remove_resource(item: String, amount: int) -> bool:
	if count(item) < amount:
		return false
	stock.take_anywhere(item, amount)
	return true


## Stores wherever there's room; overflow goes into the Keep (refunds, loot,
## taxes, test grants).
func add_resource(item: String, amount: int) -> void:
	stock.store_anywhere(item, amount)


func refund(cost: Dictionary, fraction: float) -> void:
	for item: String in cost:
		var amount := floori(cost[item] * fraction)
		if amount > 0:
			add_resource(item, amount)


# --- Food -------------------------------------------------------------------

func edible_total() -> int:
	var total := 0
	for item in ItemDefs.EDIBLE:
		total += count(item)
	return total


## Eats up to `meals` food from storage, drawing from whichever edible item is
## most plentiful. Returns how many meals were actually eaten.
func eat(meals: int) -> int:
	var eaten := 0
	while eaten < meals:
		var best := ""
		for item in ItemDefs.EDIBLE:
			if count(item) > 0 and (best == "" or count(item) > count(best)):
				best = item
		if best == "":
			break
		eaten += stock.take_anywhere(best, mini(meals - eaten, count(best)))
	return eaten


# --- Population & speed -----------------------------------------------------

func set_population(p_population: int, p_housing: int, p_employed: int, p_jobs: int) -> void:
	if p_population == population and p_housing == housing and p_employed == employed and p_jobs == jobs:
		return
	population = p_population
	housing = p_housing
	employed = p_employed
	jobs = p_jobs
	population_changed.emit()


## 0 = paused, 1..3 = normal / fast / fastest.
func set_speed(value: int) -> void:
	if game_over:
		return
	speed = clampi(value, 0, SPEEDS.size() - 1)
	if speed > 0:
		_last_speed = speed
		Engine.time_scale = SPEEDS[speed]
	get_tree().paused = speed == 0
	speed_changed.emit()


func toggle_pause() -> void:
	set_speed(_last_speed if speed == 0 else 0)
