class_name Squad
extends RefCounted
## A group of troops from one barracks.
##   AUTO:   hold the rally point, engage raiders within GUARD_TILES of it.
##   MANUAL: go where ordered, fight only what comes close (or the focus target).

enum Mode { AUTO, MANUAL }

const GUARD_TILES := 8
## Squads on guard also rush to any raider this close to the Keep.
const KEEP_DEFENSE_TILES := 12
## How far troops will chase from their anchor before giving up.
const LEASH_TILES := 12
const MANUAL_AGGRO_TILES := 4
const SLOT_SPACING := 12.0

var id := 0
var barracks: Building
var troops: Array[Troop] = []
var mode := Mode.AUTO
var rally_tile := Vector2i.ZERO
var order_tile := Vector2i.ZERO
var focus: Enemy
var selected := false


func display_name() -> String:
	return "Squad %d" % id


## Where the squad is standing: the rally point in AUTO, the order spot in MANUAL.
func anchor_tile() -> Vector2i:
	return rally_tile if mode == Mode.AUTO else order_tile


func engage_radius_tiles() -> int:
	return GUARD_TILES if mode == Mode.AUTO else MANUAL_AGGRO_TILES


## Whether this squad should fight `e` given its current mode and position.
func is_threat(e: Enemy, world: WorldMap) -> bool:
	if e.health.is_dead():
		return false
	var anchor_pos := world.tile_center(anchor_tile())
	if e.position.distance_to(anchor_pos) <= engage_radius_tiles() * Terrain.TILE_SIZE:
		return true
	return mode == Mode.AUTO and world.keep != null \
			and e.position.distance_to(world.keep.center()) <= KEEP_DEFENSE_TILES * Terrain.TILE_SIZE


func order_move(tile: Vector2i) -> void:
	mode = Mode.MANUAL
	order_tile = tile
	focus = null


func order_attack(enemy: Enemy, world: WorldMap) -> void:
	mode = Mode.MANUAL
	order_tile = world.world_to_tile(enemy.position)
	focus = enemy


## Back to automatic defense, guarding wherever the squad was sent.
func release() -> void:
	if mode == Mode.MANUAL:
		rally_tile = order_tile
	mode = Mode.AUTO
	focus = null


## Formation offset for the i-th troop: a 3-wide grid around the anchor.
## Back to guarding the barracks entrance.
func return_to_barracks() -> void:
	if barracks != null and is_instance_valid(barracks):
		rally_tile = barracks.entrance()
	mode = Mode.AUTO
	focus = null


func slot_offset(index: int) -> Vector2:
	var col := index % 3 - 1
	var row := int(index / 3.0)
	return Vector2(col * SLOT_SPACING, (row - 0.5) * SLOT_SPACING)


func center() -> Vector2:
	if troops.is_empty():
		return Vector2.ZERO
	var sum := Vector2.ZERO
	for t in troops:
		sum += t.position
	return sum / troops.size()


func summary() -> String:
	var counts := {}
	for t in troops:
		counts[t.def.name] = counts.get(t.def.name, 0) + 1
	var parts := PackedStringArray()
	for n: String in counts:
		parts.append("%d %s" % [counts[n], n])
	return ", ".join(parts) if not parts.is_empty() else "no troops"
