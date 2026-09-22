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
## Display name (the Keep is renamed as the settlement grows).
var title := ""
## HP and storage before research bonuses; the Keep's grow with the tier.
var base_hp := 200.0
var base_capacity := 0
## Homes: which needs are met, happiness, level (1..3) and their timers.
var needs_met := {}
var happiness := NeedDefs.BASE_HAPPINESS
var level := 1
var level_timer := 0.0
var unhappy_time := 0.0

var _attack_cooldown := 0.0


func setup(p_world: WorldMap, id: String, p_origin: Vector2i) -> void:
	world = p_world
	def_id = id
	def = BuildingDefs.get_def(id)
	origin = p_origin
	size = def.size
	position = Vector2(origin * Terrain.TILE_SIZE)
	title = def.name
	base_hp = def.get("hp", 200.0)
	base_capacity = def.get("capacity", 0)
	health = Health.new(base_hp * GameState.mod("building_hp"))
	health.changed.connect(queue_redraw)
	health.died.connect(func() -> void: world.destroy_building(self))
	GameState.modifiers_changed.connect(refresh_max_hp)


func _ready() -> void:
	# Only towers need per-frame logic (Godot re-enables processing on
	# entering the tree, so this must happen here rather than in setup()).
	set_process(def.has("damage"))


func set_base_hp(value: float) -> void:
	base_hp = value
	refresh_max_hp()


## Re-derives max HP from base HP and research; any increase is added as HP.
func refresh_max_hp() -> void:
	var new_max := base_hp * GameState.mod("building_hp")
	var gain := new_max - health.max_hp
	health.max_hp = new_max
	health.hp = clampf(health.hp + maxf(gain, 0.0), 0.0, new_max)
	health.changed.emit()


func is_home() -> bool:
	return def.get("housing", 0) > 0


func housing_capacity() -> int:
	return def.get("housing", 0) + def.get("level_bonus", 0) * (level - 1)


func level_name() -> String:
	return NeedDefs.LEVELS[level - 1].name


## Service buildings work only with road access and, if they have jobs, a
## worker inside.
func service_active() -> bool:
	if not has_road:
		return false
	return def.get("jobs", 0) == 0 or stationed_count() > 0


func covers(home: Building) -> bool:
	return center().distance_to(home.center()) <= def.coverage * Terrain.TILE_SIZE


func storage_capacity() -> int:
	return int(base_capacity * GameState.mod("storage_capacity"))


func attack_range_tiles() -> float:
	return def.range + GameState.mod("tower_range", 0.0)


## Workers inside the building (guards on watch, scholars studying).
func stationed_count() -> int:
	var n := 0
	for v in workers:
		if v.state == Villager.State.STATIONED:
			n += 1
	return n


func center() -> Vector2:
	return position + Vector2(size * Terrain.TILE_SIZE) * 0.5


## A guard is inside and on watch.
func is_manned() -> bool:
	return stationed_count() > 0


## Towers: shoot the nearest raider in range while manned.
func _process(delta: float) -> void:
	_attack_cooldown -= delta
	if _attack_cooldown > 0.0 or not is_manned():
		return
	var target: Enemy = world.nearest_enemy(center(), attack_range_tiles() * Terrain.TILE_SIZE)
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
	if def.get("work", "") == "study" and not is_manned():
		return "Scholars on the way"
	if def.get("work", "") == "service" and not is_manned():
		return "Waiting for a worker"
	return ""


## One-line summary for hover info.
func describe() -> String:
	var lines := PackedStringArray([title])
	if is_home() and def.has("level_bonus"):
		lines[0] = "%s (%s) — happiness %d" % [title, level_name(), happiness]
	if health.is_damaged():
		lines.append("HP: %d/%d" % [health.hp, health.max_hp])
	if is_home():
		lines.append("Residents: %d/%d" % [residents.size(), housing_capacity()])
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
				attack_range_tiles(), def.damage, def.attack_cooldown])
		"study":
			lines.append("Scholars studying: %d" % stationed_count())
		"produce":
			lines.append("Recipe: %s → %s  (%ds)" % [
				BuildingDefs.stack_text(def.input), BuildingDefs.stack_text(def.output), def.work_time])

	if def.has("accepts"):
		for category: String in def.accepts:
			lines.append("Stores %s: %d/%d kingdom-wide" % [
				category, GameState.used(category), GameState.capacity.get(category, 0)])
	if def.has("provides"):
		lines.append("Provides %s to homes within %d tiles%s." % [
			NeedDefs.NEEDS[def.provides].name.to_lower(), def.coverage,
			"" if service_active() else " (inactive: needs road access and a worker)"])
	if is_home() and def.has("level_bonus"):
		lines.append("")
		lines.append("%s — happiness %d/100" % [level_name(), happiness])
		for need: String in NeedDefs.ORDER:
			lines.append("  %s %s" % ["✔" if needs_met.get(need, false) else "✘", NeedDefs.NEEDS[need].name])
		if level < NeedDefs.LEVELS.size():
			var next: Dictionary = NeedDefs.LEVELS[level]
			var names := PackedStringArray()
			for n: String in next.needs:
				names.append(NeedDefs.NEEDS[n].name)
			lines.append("Upgrades to %s with: %s" % [next.name, ", ".join(names)])
		if happiness < NeedDefs.UNHAPPY:
			lines.append("⚠ Miserable: pays no tax, residents will leave")
	if base_capacity > 0:
		lines.append("This building adds %d storage per category." % storage_capacity())

	if is_home():
		lines.append("")
		lines.append("Residents: %d/%d" % [residents.size(), housing_capacity()])
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
		draw_string(font, Vector2(6, 18), title, HORIZONTAL_ALIGNMENT_LEFT, px.x - 10, 11, Color(1, 1, 1, 0.95))

	if def.has("damage"):
		# Crenellations so towers read differently from houses.
		for i in 3:
			draw_rect(Rect2(Vector2(3 + i * 10, 0), Vector2(6, 5)), base.darkened(0.4))
		draw_circle(px * 0.5, 6, base.darkened(0.3))

	if def.has("level_bonus"):
		# One pip per house level, bottom-left.
		for i in level:
			draw_circle(Vector2(8 + i * 8, px.y - 8), 3, Color(1, 0.85, 0.3))

	health.draw_bar(self, Vector2(px.x * 0.5, -7), minf(px.x - 4, 40))

	if not has_road:
		var c := Vector2(px.x - 9, 9)
		draw_circle(c, 7, Color(0.85, 0.15, 0.1))
		draw_string(font, c + Vector2(-2, 5), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
