class_name DayNight
extends CanvasModulate
## Day/night cycle. Tints the world (a CanvasModulate on the main canvas, so
## the HUD stays bright) and flags WorldMap.is_night, which sends villagers
## home to sleep.

signal night_started
signal day_started

const DAY_LENGTH := 150.0
const NIGHT_LENGTH := 50.0
## Seconds of dusk/dawn blending either side of night.
const TWILIGHT := 12.0
const NIGHT_TINT := Color(0.42, 0.48, 0.72)

var world: WorldMap
var day := 1
## Seconds since this day began (day first, then night).
var clock := 0.0


func _process(delta: float) -> void:
	clock += delta
	if clock >= DAY_LENGTH + NIGHT_LENGTH:
		clock -= DAY_LENGTH + NIGHT_LENGTH
		day += 1
	var night := clock >= DAY_LENGTH
	if night != world.is_night:
		world.is_night = night
		if night:
			GameState.notify("Night falls. Villagers head home to sleep.")
			night_started.emit()
		else:
			GameState.notify("Day %d begins." % day)
			day_started.emit()
	color = Color.WHITE.lerp(NIGHT_TINT, _darkness())


## 0 in full daylight, 1 at night, blended through dusk and dawn.
func _darkness() -> float:
	if clock < DAY_LENGTH - TWILIGHT:
		return 0.0
	if clock < DAY_LENGTH:
		return (clock - (DAY_LENGTH - TWILIGHT)) / TWILIGHT
	var into_night := clock - DAY_LENGTH
	if into_night > NIGHT_LENGTH - TWILIGHT:
		return 1.0 - (into_night - (NIGHT_LENGTH - TWILIGHT)) / TWILIGHT
	return 1.0


## "☀ Day 3" or "☾ Night 3".
func label() -> String:
	return "%s %d" % ["☾ Night" if world.is_night else "☀ Day", day]


## Seconds until night (by day) or until morning (at night).
func time_to_change() -> float:
	return DAY_LENGTH - clock if clock < DAY_LENGTH else DAY_LENGTH + NIGHT_LENGTH - clock
