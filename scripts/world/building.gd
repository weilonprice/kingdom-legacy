class_name Building
extends Node2D
## A placed building. Drawn as a placeholder block until PixelLab sprites exist.

var world: WorldMap
var def_id := ""
var def: Dictionary
var origin := Vector2i.ZERO
var size := Vector2i.ONE
var has_road := false
var residents: Array = []
var workers: Array = []
var fields: Array[Vector2i] = []
var health: Health

var _attack_cooldown := 0.0


func setup(p_world: WorldMap, id: String, p_origin: Vector2i) -> void:
	world = p_world
	def_id = id
	def = BuildingDefs.get_def(id)
	origin = p_origin
	size = def.size
	position = Vector2(origin * Terrain.TILE_SIZE)
	health = Health.new(def.get("hp", 200.0))
	health.changed.connect(queue_redraw)
	health.died.connect(func() -> void: world.destroy_building(self))
	set_process(def.has("damage"))


func center() -> Vector2:
	return position + Vector2(size * Terrain.TILE_SIZE) * 0.5


## A guard is inside and on watch.
func is_manned() -> bool:
	for v in workers:
		if v.state == Villager.State.STATIONED:
			return true
	return false


## Towers: shoot the nearest raider in range while manned.
func _process(delta: float) -> void:
	_attack_cooldown -= delta
	if _attack_cooldown > 0.0 or not is_manned():
		return
	var target: Enemy = world.nearest_enemy(center(), def.range * Terrain.TILE_SIZE)
	if target == null:
		return
	_attack_cooldown = def.attack_cooldown
	var arrow := Projectile.new()
	arrow.setup(center() + Vector2(0, -8), target, def.damage)
	world.unit_root.add_child(arrow)


func entrance() -> Vector2i:
	return BuildingDefs.entrance_of(origin, size)


func footprint() -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for dy in size.y:
		for dx in size.x:
			tiles.append(origin + Vector2i(dx, dy))
	return tiles


## The Keep is the kingdom's heart and always counts as connected.
func refresh_road_access() -> void:
	has_road = self == world.keep or world.is_road(entrance())
	queue_redraw()


## A short problem summary, or "" when running normally.
func status() -> String:
	if not has_road:
		return "No road access! Connect the entrance to a road."
	if def.get("jobs", 0) > 0 and workers.is_empty():
		return "No workers"
	if def.get("work", "") == "guard" and not is_manned():
		return "Guard on the way"
	return ""


## One-line summary for hover info.
func describe() -> String:
	var lines := PackedStringArray([def.name])
	if health.is_damaged():
		lines.append("HP: %d/%d" % [health.hp, health.max_hp])
	if def.get("housing", 0) > 0:
		lines.append("Residents: %d/%d" % [residents.size(), def.housing])
	if def.get("jobs", 0) > 0:
		lines.append("Workers: %d/%d" % [workers.size(), def.jobs])
	var problem := status()
	if problem != "":
		lines.append(problem)
	return "\n".join(lines)


## Full detail text for the inspector panel.
func inspect_text() -> String:
	var lines := PackedStringArray([def.desc, "", "HP: %d/%d" % [health.hp, health.max_hp]])
	var problem := status()
	if problem != "":
		lines.append("⚠ " + problem)

	match def.get("work", ""):
		"gather":
			lines.append("Gathers %s from %s within %d tiles." % [
				def.resource, Terrain.NAMES[def.gather_terrain].to_lower(), def.radius])
		"farm":
			lines.append("Fields: %d   (tilled %d · growing %d · ripe %d)" % [
				fields.size(),
				world.count_fields(self, WorldMap.FieldStage.TILLED),
				world.count_fields(self, WorldMap.FieldStage.GROWING),
				world.count_fields(self, WorldMap.FieldStage.RIPE)])
		"guard":
			lines.append("Shoots raiders within %d tiles for %d damage every %.1fs." % [
				def.range, def.damage, def.attack_cooldown])
		"produce":
			lines.append("Recipe: %s → %s  (%ds)" % [
				BuildingDefs.stack_text(def.input), BuildingDefs.stack_text(def.output), def.work_time])

	if def.has("accepts"):
		for category: String in def.accepts:
			lines.append("Stores %s: %d/%d kingdom-wide" % [
				category, GameState.used(category), GameState.capacity.get(category, 0)])
	if def.has("coverage"):
		lines.append("Covers homes within %d tiles." % def.coverage)

	if def.get("housing", 0) > 0:
		lines.append("")
		lines.append("Residents: %d/%d" % [residents.size(), def.housing])
		for v in residents:
			var hunger := "  (hungry)" if v.missed_meals > 0 else ""
			lines.append("  • %s%s" % [v.villager_name, hunger])
	if def.get("jobs", 0) > 0:
		lines.append("")
		lines.append("Workers: %d/%d" % [workers.size(), def.jobs])
		for v in workers:
			lines.append("  • %s — %s" % [v.villager_name, v.note])
	return "\n".join(lines)


func _draw() -> void:
	var tile := Terrain.TILE_SIZE
	var px := Vector2(size * tile)
	var base: Color = def.color
	draw_rect(Rect2(Vector2(4, 4), px - Vector2(4, 4)), Color(0, 0, 0, 0.3))
	draw_rect(Rect2(Vector2(2, 2), px - Vector2(4, 4)), base)
	if size.x > 1:
		draw_rect(Rect2(Vector2(6, 6), px - Vector2(12, 20)), base.darkened(0.25))
	draw_rect(Rect2(Vector2(2, 2), px - Vector2(4, 4)), base.darkened(0.55), false, 2.0)

	var door_x := (int(size.x * 0.5) + 0.5) * tile
	draw_rect(Rect2(Vector2(door_x - 5, px.y - 12), Vector2(10, 10)), Color(0.25, 0.15, 0.08))

	var font := ThemeDB.fallback_font
	if size.x > 1:
		draw_string(font, Vector2(6, 18), def.name, HORIZONTAL_ALIGNMENT_LEFT, px.x - 10, 11, Color(1, 1, 1, 0.95))

	if def.has("damage"):
		# Crenellations so towers read differently from houses.
		for i in 3:
			draw_rect(Rect2(Vector2(3 + i * 10, 0), Vector2(6, 5)), base.darkened(0.4))
		draw_circle(px * 0.5, 6, base.darkened(0.3))

	health.draw_bar(self, Vector2(px.x * 0.5, -7), minf(px.x - 4, 40))

	if not has_road:
		var c := Vector2(px.x - 9, 9)
		draw_circle(c, 7, Color(0.85, 0.15, 0.1))
		draw_string(font, c + Vector2(-2, 5), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
