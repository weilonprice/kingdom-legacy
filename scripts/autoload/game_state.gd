extends Node
## Global kingdom state: the pooled resource stock, storage capacity,
## population stats and game speed.
##
## Stock is pooled across all storage buildings; capacity per category is the
## sum of every storage that accepts it. Villagers still physically carry goods
## to and from the nearest suitable storage.

signal resources_changed
signal population_changed
signal speed_changed
signal notified(text: String)
signal modifiers_changed

const SPEEDS := [0.0, 1.0, 2.0, 4.0]
const START_RESOURCES := {"wood": 120, "stone": 20, "gold": 50, "bread": 40}

var resources := {}
var capacity := {}     # category -> int
var reserved_space := {}  # category -> int held for producers' pending output
var population := 0
var housing := 0
var employed := 0
var jobs := 0
var speed := 1
var game_over := false
## Research bonuses: key -> value. Multipliers default to 1.0, additive
## bonuses to 0 (see ResearchDefs).
var modifiers := {}

var _last_speed := 1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	reset()


## Fresh state for a new game (the autoload survives scene reloads).
func reset() -> void:
	resources = START_RESOURCES.duplicate()
	reserved_space = {}
	capacity = {}
	population = 0
	housing = 0
	employed = 0
	jobs = 0
	game_over = false
	modifiers = {}
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

func count(item: String) -> int:
	return resources.get(item, 0)


func used(category: String) -> int:
	var total := 0
	for item: String in resources:
		if ItemDefs.category_of(item) == category:
			total += resources[item]
	return total


func space_for(item: String) -> int:
	var category := ItemDefs.category_of(item)
	if not category in ItemDefs.CAPPED_CATEGORIES:
		return 1 << 30
	return maxi(capacity.get(category, 0) - used(category) - reserved_space.get(category, 0), 0)


func set_capacity(p_capacity: Dictionary) -> void:
	capacity = p_capacity
	resources_changed.emit()


func can_afford(cost: Dictionary) -> bool:
	for item in cost:
		if count(item) < cost[item]:
			return false
	return true


func spend(cost: Dictionary) -> bool:
	if not can_afford(cost):
		return false
	for item in cost:
		resources[item] -= cost[item]
	resources_changed.emit()
	return true


func remove_resource(item: String, amount: int) -> bool:
	if count(item) < amount:
		return false
	resources[item] -= amount
	resources_changed.emit()
	return true


## Holds free space for `item` so nobody else fills it. Returns the amount held.
func reserve_space(item: String, amount: int) -> int:
	var held := mini(amount, space_for(item))
	var category := ItemDefs.category_of(item)
	reserved_space[category] = reserved_space.get(category, 0) + held
	return held


func release_space(item: String, amount: int) -> void:
	var category := ItemDefs.category_of(item)
	reserved_space[category] = maxi(reserved_space.get(category, 0) - amount, 0)


## Adds up to the free capacity (plus any space the caller had reserved).
## Returns how much was accepted.
func store(item: String, amount: int, reserved := 0) -> int:
	if reserved > 0:
		release_space(item, reserved)
	var accepted := mini(amount, space_for(item))
	if accepted > 0:
		resources[item] = count(item) + accepted
		resources_changed.emit()
	return accepted


## Ignores capacity (refunds, starting stock).
func add_resource(item: String, amount: int) -> void:
	resources[item] = count(item) + amount
	resources_changed.emit()


func refund(cost: Dictionary, fraction: float) -> void:
	for item in cost:
		resources[item] = count(item) + floori(cost[item] * fraction)
	resources_changed.emit()


# --- Food -------------------------------------------------------------------

func edible_total() -> int:
	var total := 0
	for item in ItemDefs.EDIBLE:
		total += count(item)
	return total


## Eats up to `meals` food, drawing from whichever edible item is most plentiful.
## Returns how many meals were actually eaten.
func eat(meals: int) -> int:
	var eaten := 0
	while eaten < meals:
		var best := ""
		for item in ItemDefs.EDIBLE:
			if count(item) > 0 and (best == "" or count(item) > count(best)):
				best = item
		if best == "":
			break
		resources[best] -= 1
		eaten += 1
	if eaten > 0:
		resources_changed.emit()
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
