class_name RaidIndicator
extends Control
## Draws an arrow at the screen edge pointing toward incoming or active raiders
## when they're off-screen, and small dark markers toward known goblin lairs.

const MARGIN := 48.0
const COLOR := Color(0.95, 0.25, 0.15)
const LAIR_COLOR := Color(0.25, 0.18, 0.12, 0.85)

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
	for lair in world.lairs():
		_draw_arrow(lair.position, LAIR_COLOR, 0.6, "☠")
	var target: Variant = _target_world_pos()
	if target != null:
		_draw_arrow(target as Vector2, COLOR, 1.0, "!")


## An arrow at the screen edge toward `world_pos`, if that's off-screen.
func _draw_arrow(world_pos: Vector2, color: Color, scale: float, mark: String) -> void:
	var screen_pos: Vector2 = world.get_viewport().get_canvas_transform() * world_pos
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
	var side := dir.orthogonal() * 12.0 * scale
	var back := tip - dir * 24.0 * scale
	draw_colored_polygon(PackedVector2Array([tip, back + side, back - side]), color)
	var badge := tip - dir * 36.0 * scale
	draw_circle(badge, 9.0 * scale + 1.0, color)
	draw_string(ThemeDB.fallback_font, badge + Vector2(-5, 5) * scale, mark, HORIZONTAL_ALIGNMENT_LEFT, -1,
		int(14 * scale) + 2, Color.WHITE)


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
