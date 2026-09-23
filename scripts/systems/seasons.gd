class_name Seasons
extends Node
## The year: autumn → winter → spring → summer, DAYS_PER_SEASON days each,
## starting in autumn. Each season has its own art set (Art.season), and the
## map is redrawn when it turns. Winter bites: crops stop growing, and every
## home burns a piece of firewood (wood) each FIREWOOD_INTERVAL; homes without
## it are cold (a happiness penalty, see Needs).

signal season_changed(season: String)

const ORDER := ["autumn", "winter", "spring", "summer"]
const DAYS_PER_SEASON := 3
## Art set per season (spring shares summer's).
const ART := {"autumn": "autumn", "winter": "winter", "spring": "summer", "summer": "summer"}
const NAMES := {"autumn": "Autumn", "winter": "Winter", "spring": "Spring", "summer": "Summer"}
const ICONS := {"autumn": "🍂", "winter": "❄", "spring": "🌱", "summer": "☀"}
const FIREWOOD_INTERVAL := 60.0
const ANNOUNCE := {
	"autumn": "Autumn. Bring in the harvest: winter is coming.",
	"winter": "Winter has come! Crops stop growing, and every home burns 1 wood a minute.",
	"spring": "Spring. The fields can be sown again.",
	"summer": "Summer. Long days and full fields.",
}

var world: WorldMap
var index := 0
## Days already spent in this season.
var days_in := 0
## False when the last firewood burn came up short.
var warm := true

var _firewood_timer := FIREWOOD_INTERVAL


func current() -> String:
	return ORDER[index]


func is_winter() -> bool:
	return current() == "winter"


func label() -> String:
	return "%s %s" % [ICONS[current()], NAMES[current()]]


## Days left before the season turns (counting today).
func days_left() -> int:
	return DAYS_PER_SEASON - days_in


## Hooked to DayNight.day_started.
func on_new_day() -> void:
	days_in += 1
	if days_in >= DAYS_PER_SEASON:
		set_season((index + 1) % ORDER.size(), true)


func set_season(i: int, announce: bool) -> void:
	index = i
	days_in = 0
	warm = true
	_apply_art()
	if announce:
		GameState.notify(ANNOUNCE[current()])
		Sound.play("chime")
	season_changed.emit(current())


func _apply_art() -> void:
	var art: String = ART[current()]
	if art == Art.season:
		return
	Art.season = art
	GameState.season = art
	world.renderer.rebuild_art()
	for b in world.buildings:
		b.queue_redraw()


func _process(delta: float) -> void:
	if not is_winter():
		return
	_firewood_timer -= delta
	if _firewood_timer <= 0.0:
		_firewood_timer = FIREWOOD_INTERVAL
		_burn_firewood()


func _burn_firewood() -> void:
	var homes := world.buildings.filter(func(b: Building) -> bool: return b.is_home() and not b.residents.is_empty())
	if homes.is_empty():
		return
	var need := homes.size()
	var have := GameState.count("wood")
	GameState.remove_resource("wood", mini(need, have))
	var was_warm := warm
	warm = have >= need
	if was_warm and not warm:
		GameState.notify("Out of firewood! Homes are freezing. Gather more wood.")
