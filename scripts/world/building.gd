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
## Which sprite to draw (the Keep becomes a castle, then a citadel).
var art_id := ""
## HP and storage before research bonuses; the Keep's grow with the tier.
var base_hp := 200.0
var base_capacity := 0
## Homes: which needs are met, happiness, level (1..3) and their timers.
## Storage buildings: goods held here (item -> amount). See Stock.
var inventory := {}
## Workplaces: finished goods waiting for pickup, and delivered inputs.
var output_stock := {}
var input_stock := {}
## Hauler currently fetching from / supplying this building (one at a time).
var pickup_claim: Object
var supply_claim: Object
## Fire: see FireSystem. Progress toward being put out, 0..1.
var burning := false
var extinguish_progress := 0.0
var needs_met := {}
var happiness := NeedDefs.BASE_HAPPINESS
var level := 1
var level_timer := 0.0
## Jobs on top of the def's (the castle's builders during an upgrade).
var extra_jobs := 0
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
	art_id = id
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


# --- Workplace piles --------------------------------------------------------

const OUTPUT_CAPACITY := 16


func output_total() -> int:
	var n := 0
	for item: String in output_stock:
		n += output_stock[item]
	return n


func output_space() -> int:
	return maxi(OUTPUT_CAPACITY - output_total(), 0)


func add_output(item: String, amount: int) -> int:
	var added := mini(amount, output_space())
	if added > 0:
		output_stock[item] = output_stock.get(item, 0) + added
		GameState.tally("produced", item, added)
		queue_redraw()
	return added


func take_output(item: String, amount: int) -> int:
	var taken := mini(amount, output_stock.get(item, 0))
	if taken > 0:
		output_stock[item] -= taken
		if output_stock[item] == 0:
			output_stock.erase(item)
		queue_redraw()
	return taken


## The item this workplace has most of in its output pile, or "".
func fullest_output() -> String:
	var best := ""
	for item: String in output_stock:
		if best == "" or output_stock[item] > output_stock[best]:
			best = item
	return best


## Producers: the single input item and batch size, or "" / 0.
func input_item() -> String:
	return def.input.keys()[0] if def.has("input") else ""


func input_batch() -> int:
	return def.input[input_item()] if def.has("input") else 0


func add_input(item: String, amount: int) -> void:
	input_stock[item] = input_stock.get(item, 0) + amount
	queue_redraw()


func take_input(item: String, amount: int) -> bool:
	if input_stock.get(item, 0) < amount:
		return false
	input_stock[item] -= amount
	queue_redraw()
	return true


## "wood 12, stone 4" for the non-empty entries of `stock`, minus `skip`.
func _stock_line(stock: Dictionary, skip: Array) -> String:
	var parts := PackedStringArray()
	for item: String in stock:
		if stock[item] > 0 and not item in skip:
			parts.append("%s %d" % [item, stock[item]])
	return ", ".join(parts)


func is_flammable() -> bool:
	return def.get("flammable", true)


## Sets the building alight. Returns true if it caught fire.
func ignite() -> bool:
	if burning or not is_flammable() or health.is_dead():
		return false
	burning = true
	extinguish_progress = 0.0
	GameState.notify("The %s is on fire!" % title)
	Sound.play("fire", center())
	queue_redraw()
	return true


func extinguish() -> void:
	burning = false
	extinguish_progress = 0.0
	queue_redraw()


## Flames over the top of the building, animated from the fire sprite when
## it exists (else simple flickering shapes).
func _draw_fire(px: Vector2) -> void:
	var t := Time.get_ticks_msec() / 1000.0
	var count := clampi(int(px.x / 24.0), 1, 4)
	for i in count:
		var at := Vector2((i + 0.5) * px.x / count, px.y * 0.35 + (i % 2) * 8.0)
		var frame := Art.fire_frame(t + i * 0.37)
		if frame != null:
			draw_texture(frame, at - Vector2(frame.get_size()) * Vector2(0.5, 0.8))
		else:
			var h := 10.0 + 3.0 * sin(t * 12.0 + i)
			draw_colored_polygon(PackedVector2Array([at + Vector2(-6, 0), at + Vector2(0, -h), at + Vector2(6, 0)]),
				Color(1.0, 0.45, 0.1, 0.9))
			draw_colored_polygon(PackedVector2Array([at + Vector2(-3, 0), at + Vector2(0, -h * 0.6), at + Vector2(3, 0)]),
				Color(1.0, 0.85, 0.3, 0.95))


func job_slots() -> int:
	return def.get("jobs", 0) + extra_jobs


## What this building's workers do ("build" for the castle's builders).
func work_type() -> String:
	return "build" if extra_jobs > 0 and self == world.keep else def.get("work", "")


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


## Towers: shoot the nearest raider in range while manned (wall towers have
## their own archers).
func _process(delta: float) -> void:
	_attack_cooldown -= delta
	if _attack_cooldown > 0.0 or not (def.get("auto_guard", false) or is_manned()):
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
	has_road = self == world.keep or BuildingDefs.is_fortification(def) or world.is_road(entrance())
	queue_redraw()


## A short problem summary, or "" when running normally.
func status() -> String:
	if not has_road:
		return "No road access! Connect the entrance to a road."
	if job_slots() > 0 and workers.is_empty():
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
	if job_slots() > 0:
		lines.append("Workers: %d/%d" % [workers.size(), job_slots()])
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
		"guard", "":
			if def.has("damage"):
				lines.append("Shoots raiders within %d tiles for %d damage every %.1fs." % [
					attack_range_tiles(), def.damage, def.attack_cooldown])
		"study":
			lines.append("Scholars studying: %d" % stationed_count())
		"forester":
			lines.append("Plants saplings within %d tiles (not beside roads or buildings)." % def.radius)
			lines.append("Saplings growing nearby: %d" % world.count_saplings(entrance(), def.radius))
		"produce":
			lines.append("Recipe: %s → %s  (%ds)" % [
				BuildingDefs.stack_text(def.input), BuildingDefs.stack_text(def.output), def.work_time])

	if def.has("accepts"):
		for category: String in def.accepts:
			lines.append("Holds %s: %d/%d" % [category, world.stock.used_at(self, category), storage_capacity()])
		if self == world.keep:
			lines.append("Treasury: %d gold" % inventory.get("gold", 0))
		var goods := _stock_line(inventory, ["gold"])
		lines.append("Stored here: %s" % (goods if goods != "" else "nothing"))
	if def.has("work") and def.work in ["gather", "farm", "produce"]:
		var out := _stock_line(output_stock, [])
		lines.append("Ready for pickup: %s (%d/%d)" % [out if out != "" else "nothing", output_total(), OUTPUT_CAPACITY])
		if def.has("input"):
			lines.append("Delivered %s: %d" % [input_item(), input_stock.get(input_item(), 0)])
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
	if BuildingDefs.is_fortification(def):
		_draw_fortification()
		health.draw_bar(self, Vector2(px.x * 0.5, -23.0 if def.has("damage") else -7.0), px.x - 4)
		return
	if self == world.keep:
		_draw_castle_works()
	var sprite := Art.building(art_id)
	# Top edge of what's drawn, for the health bar (tall sprites rise above
	# their footprint).
	var top := 0.0
	if sprite != null:
		# Bottom-aligned and centred on the footprint.
		var at := Vector2((px.x - sprite.get_width()) * 0.5, px.y - sprite.get_height())
		draw_texture(sprite, at)
		top = minf(at.y, 0.0)
	else:
		_draw_placeholder(px)

	if def.has("level_bonus"):
		# One pip per house level, bottom-left.
		for i in level:
			draw_circle(Vector2(8 + i * 8, px.y - 6), 3, Color(1, 0.85, 0.3))
			draw_arc(Vector2(8 + i * 8, px.y - 6), 3, 0, TAU, 8, Color(0.3, 0.2, 0.05), 1.0)

	if burning:
		_draw_fire(px)

	health.draw_bar(self, Vector2(px.x * 0.5, top - 7), minf(px.x - 4, 40))

	if not has_road:
		var font := ThemeDB.fallback_font
		var c := Vector2(px.x - 9, maxf(top, 0.0) + 9)
		draw_circle(c, 7, Color(0.85, 0.15, 0.1))
		draw_string(font, c + Vector2(-2, 5), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)


## Coloured block with a door and name, for buildings without a sprite yet.
## During a castle upgrade: the new footprint as a building site, with
## scaffolding round its edge, the delivered materials stacked by the gate
## and a progress bar.
func _draw_castle_works() -> void:
	var castle: Castle = world.get_parent().get("castle")
	if castle == null or not castle.is_building():
		return
	var tile := Terrain.TILE_SIZE
	var s: int = CastleDefs.STAGES[castle.project.stage].size
	var site_origin := world.castle_grounds.get_center() - Vector2i(s / 2, s / 2)
	var site := Rect2(Vector2((site_origin - origin) * tile), Vector2(s, s) * tile)
	draw_rect(site, Color(0.45, 0.33, 0.2, 0.55))
	var wood := Color(0.55, 0.38, 0.2)
	var dark := Color(0.3, 0.2, 0.1)
	# Poles every tile along the edge, with planks between them.
	for i in s + 1:
		for p: Vector2 in [site.position + Vector2(i * tile, 0), site.position + Vector2(i * tile, site.size.y)]:
			draw_line(p + Vector2(0, 4), p - Vector2(0, 22), dark, 3.0)
			draw_line(p + Vector2(0, 4), p - Vector2(0, 22), wood, 1.5)
		for p: Vector2 in [site.position + Vector2(0, i * tile), site.position + Vector2(site.size.x, i * tile)]:
			draw_line(p + Vector2(0, 4), p - Vector2(0, 22), dark, 3.0)
			draw_line(p + Vector2(0, 4), p - Vector2(0, 22), wood, 1.5)
	for y_off in [-8.0, -18.0]:
		for edge: Array in [[site.position, site.position + Vector2(site.size.x, 0)],
				[site.position + Vector2(0, site.size.y), site.end],
				[site.position, site.position + Vector2(0, site.size.y)],
				[site.position + Vector2(site.size.x, 0), site.end]]:
			draw_line(edge[0] + Vector2(0, y_off), edge[1] + Vector2(0, y_off), wood, 2.0)
	# Delivered materials, one stack per good, beside the site's gate.
	var target: Dictionary = CastleDefs.STAGES[castle.project.stage]
	var x := site.position.x + 6.0
	for item: String in target.materials:
		var share := clampf(castle.project.delivered.get(item, 0) / float(target.materials[item]), 0.0, 1.0)
		var h := 4.0 + 20.0 * share
		var base := Vector2(x, site.end.y - 6.0)
		draw_rect(Rect2(base - Vector2(0, h), Vector2(14, h)), ItemDefs.color_of(item))
		draw_rect(Rect2(base - Vector2(0, h), Vector2(14, h)), dark, false, 1.0)
		x += 18.0
	var bar := Rect2(site.position + Vector2(8, site.size.y + 8), Vector2(site.size.x - 16, 6))
	draw_rect(bar, Color(0, 0, 0, 0.6))
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * castle.progress(), bar.size.y)), Color(0.95, 0.8, 0.3))


func _draw_placeholder(px: Vector2) -> void:
	var tile := Terrain.TILE_SIZE
	var base: Color = def.color
	draw_rect(Rect2(Vector2(4, 4), px - Vector2(4, 4)), Color(0, 0, 0, 0.3))
	draw_rect(Rect2(Vector2(2, 2), px - Vector2(4, 4)), base)
	if size.x > 1:
		draw_rect(Rect2(Vector2(6, 6), px - Vector2(12, 20)), base.darkened(0.25))
	draw_rect(Rect2(Vector2(2, 2), px - Vector2(4, 4)), base.darkened(0.55), false, 2.0)
	var door_x := (int(size.x * 0.5) + 0.5) * tile
	draw_rect(Rect2(Vector2(door_x - 5, px.y - 12), Vector2(10, 10)), Color(0.25, 0.15, 0.08))
	if size.x > 1:
		draw_string(ThemeDB.fallback_font, Vector2(6, 18), title, HORIZONTAL_ALIGNMENT_LEFT, px.x - 10, 11,
			Color(1, 1, 1, 0.95))
	if def.has("damage"):
		# Crenellations so towers read differently from houses.
		for i in 3:
			draw_rect(Rect2(Vector2(3 + i * 10, 0), Vector2(6, 5)), base.darkened(0.4))
		draw_circle(px * 0.5, 6, base.darkened(0.3))


# --- Walls & gates -----------------------------------------------------------

const _DIRS := {"n": Vector2i(0, -1), "e": Vector2i(1, 0), "s": Vector2i(0, 1), "w": Vector2i(-1, 0)}


## Which neighbouring tiles hold a wall or gate (so segments join up).
func _links() -> Dictionary:
	var links := {}
	for d: String in _DIRS:
		links[d] = world.fortification_at(origin + _DIRS[d]) != null
	return links


## A post in the middle plus a beam toward each linked neighbour, drawn in
## 3/4 view: wall faces are 12px tall, their tops a lighter band.
func _draw_fortification() -> void:
	var links := _links()
	if not def.get("flammable", true) or def.get("gate", false):
		if _draw_stone_art(links):
			if burning:
				_draw_fire(Vector2(32, 32))
			return
	var stone: bool = not def.get("flammable", true)
	var base: Color = def.color
	var face := base.darkened(0.25)
	var top := base.lightened(0.15)
	var dark := base.darkened(0.6)
	var c := Vector2(16, 16)
	# Horizontal run (east-west): a wall face along the tile's middle.
	for d in ["w", "e"]:
		if links[d]:
			var x0 := 0.0 if d == "w" else 16.0
			_wall_block(Rect2(x0, 10, 16, 14), face, top, dark, stone)
	# Vertical run (north-south): a narrower band seen from above.
	for d in ["n", "s"]:
		if links[d]:
			var y0 := 0.0 if d == "n" else 16.0
			_wall_block(Rect2(10, y0, 12, 16), face, top, dark, stone)
	# Central post / tower.
	_wall_block(Rect2(c - Vector2(8, 9), Vector2(16, 18)), face, top, dark, stone)
	if stone:
		for i in 3:
			draw_rect(Rect2(Vector2(9 + i * 5, 5), Vector2(3, 3)), top)
	if def.has("damage"):
		# Wall tower: the stone tower sprite standing on the wall.
		var sprite := Art.building("stone_tower")
		if sprite != null:
			draw_texture(sprite, Vector2((32 - sprite.get_width()) * 0.5, 32 - sprite.get_height()))
		else:
			_wall_block(Rect2(Vector2(6, -6), Vector2(20, 30)), face, top, dark, true)
			for i in 3:
				draw_rect(Rect2(Vector2(7 + i * 7, -10), Vector2(4, 4)), top)
	if def.get("gate", false):
		# Arched wooden door on the post, iron bands.
		var door := Rect2(Vector2(10, 12), Vector2(12, 14))
		draw_rect(door, Color(0.42, 0.26, 0.12))
		draw_circle(Vector2(16, 12), 6, Color(0.42, 0.26, 0.12))
		for yy in [15.0, 21.0]:
			draw_line(Vector2(10, yy), Vector2(22, yy), Color(0.25, 0.25, 0.28), 1.5)
		draw_rect(Rect2(Vector2(10, 6), Vector2(12, 20)), dark, false, 1.0)
	if burning:
		_draw_fire(Vector2(32, 32))


const WALL_ART := "res://assets/sprites/walls/%s.png"
## Where the foot of a wall face sits within the tile.
const WALL_BASE := 28.0


## Stone walls, gates and wall towers from PixelLab pieces: a wall run toward
## each linked neighbour, and a round tower where the wall turns or ends.
## False when the art isn't there (the code-drawn wall is used instead).
func _draw_stone_art(links: Dictionary) -> bool:
	var h := Art.texture(WALL_ART % "stone_h")
	var v := Art.texture(WALL_ART % "stone_v")
	var tower := Art.texture(WALL_ART % "tower")
	if h == null or v == null or tower == null:
		return false
	if def.get("gate", false):
		var gate := Art.texture(WALL_ART % "gatehouse")
		if gate != null:
			draw_texture(gate, Vector2(16 - gate.get_width() * 0.5, WALL_BASE + 6 - gate.get_height()))
			return true
	var hh := float(h.get_height())
	if links.n or links.s:
		var top := -12.0 if links.n else 8.0
		var bottom := 20.0 if links.s else WALL_BASE
		draw_texture_rect(v, Rect2(16 - v.get_width() * 0.5, top, v.get_width(), bottom - top), true)
	if links.w or links.e:
		var x0 := 0.0 if links.w else 16.0
		var x1 := 32.0 if links.e else 16.0
		draw_texture_rect(h, Rect2(x0, WALL_BASE - hh, x1 - x0, hh), true)
	var straight: bool = (links.w and links.e and not links.n and not links.s) \
		or (links.n and links.s and not links.w and not links.e)
	if not straight or def.has("damage"):
		draw_texture(tower, Vector2(16 - tower.get_width() * 0.5, WALL_BASE + 6 - tower.get_height()))
	return true


func _wall_block(r: Rect2, face: Color, top: Color, dark: Color, stone: bool) -> void:
	var top_h := minf(6.0, r.size.y * 0.4)
	draw_rect(r, face)
	draw_rect(Rect2(r.position, Vector2(r.size.x, top_h)), top)
	if stone:
		# Mortar courses.
		for yy in range(int(r.position.y + top_h + 4), int(r.end.y), 5):
			draw_line(Vector2(r.position.x, yy), Vector2(r.end.x, yy), dark.lightened(0.2), 1.0)
	else:
		# Pointed stakes.
		var x := r.position.x + 2
		while x < r.end.x - 1:
			draw_line(Vector2(x, r.position.y + 1), Vector2(x, r.end.y - 1), dark.lightened(0.15), 1.0)
			x += 4
	draw_rect(r, dark, false, 1.0)
