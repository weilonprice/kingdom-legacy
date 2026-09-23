class_name FireSystem
extends Node
## Burning buildings lose HP, can spread fire to neighbours, and are put out
## by a working Well whose coverage reaches them. Without one they burn down.

const TICK := 0.5
## Fraction of max HP lost per second while burning.
const BURN_RATE := 0.03
## Chance per second that a burning building ignites each flammable neighbour.
const SPREAD_CHANCE := 0.05
## Seconds a Well needs to put a fire out.
const WELL_PUT_OUT_TIME := 8.0

var world: WorldMap

var _tick := 0.0


func _process(delta: float) -> void:
	var burning := world.buildings.filter(func(b: Building) -> bool: return b.burning)
	for b: Building in burning:
		b.queue_redraw()  # animate the flames
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = TICK
	for b: Building in burning:
		_burn(b)


func _burn(b: Building) -> void:
	if not is_instance_valid(b) or not b.burning:
		return
	if _has_water(b):
		b.extinguish_progress += TICK / WELL_PUT_OUT_TIME
		if b.extinguish_progress >= 1.0:
			b.extinguish()
			GameState.notify("Villagers put out the fire at the %s" % b.title)
			return
	for other in _neighbours(b):
		if randf() < SPREAD_CHANCE * TICK:
			other.ignite()
	b.health.take_damage(b.health.max_hp * BURN_RATE * TICK)


func _has_water(b: Building) -> bool:
	for w in world.buildings:
		if w.def.get("provides", "") == "water" and w.service_active() and w.covers(b):
			return true
	return false


## Flammable buildings within one tile of `b`'s footprint.
func _neighbours(b: Building) -> Array[Building]:
	var area := Rect2i(b.origin, b.size).grow(1)
	var found: Array[Building] = []
	for other in world.buildings:
		if other != b and other.is_flammable() and not other.burning \
				and area.intersects(Rect2i(other.origin, other.size)):
			found.append(other)
	return found
