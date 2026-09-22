class_name RaidIndicator
extends Control
## Draws an arrow at the screen edge pointing toward incoming or active raiders
## when they're off-screen.

const MARGIN := 48.0
const COLOR := Color(0.95, 0.25, 0.15)

var world: WorldMap
var raids: RaidDirector


func setup(p_world: WorldMap, p_raids: RaidDirector) -> void:
	world = p_world
	raids = p_raids


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var target: Variant = _target_world_pos()
	if target == null:
		return
	var screen_pos: Vector2 = world.get_viewport().get_canvas_transform() * (target as Vector2)
	var view := get_viewport_rect()
	if view.size.x <= MARGIN * 3.0 or view.size.y <= MARGIN * 3.0:
		return
	if view.grow(-MARGIN).has_point(screen_pos):
		return
	var center := view.size * 0.5
	var dir := (screen_pos - center).normalized()
	# Push the arrow from the center to the edge of the inner margin rect.
	var half := center - Vector2(MARGIN, MARGIN)
	var reach := minf(half.x / maxf(absf(dir.x), 0.001), half.y / maxf(absf(dir.y), 0.001))
	var tip := center + dir * reach
	var side := dir.orthogonal() * 12.0
	draw_colored_polygon(PackedVector2Array([tip, tip - dir * 24.0 + side, tip - dir * 24.0 - side]), COLOR)
	draw_circle(tip - dir * 36.0, 9.0, COLOR)
	draw_string(ThemeDB.fallback_font, tip - dir * 36.0 + Vector2(-4, 5), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)


## Spawn point during the warning; the raiders' average position during a raid.
func _target_world_pos() -> Variant:
	match raids.phase:
		RaidDirector.Phase.WARNING:
			return world.tile_center(raids.spawn_tile)
		RaidDirector.Phase.ACTIVE:
			if world.enemies.is_empty():
				return null
			var sum := Vector2.ZERO
			for e in world.enemies:
				sum += e.position
			return sum / world.enemies.size()
	return null
