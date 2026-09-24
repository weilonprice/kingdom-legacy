class_name SaveGame
extends RefCounted
## Saving and loading a game. A save is JSON: the map seed plus everything
## that has changed since the map was generated (terrain, roads, buildings
## and their stock, fields, villagers, squads, research, tier, raid clock,
## lairs, day and time). Loading regenerates the map from the seed, then
## applies the save on top (see apply()).
##
## Saves can't be made while a raid is warning or under way: enemies in
## flight are not stored.

## 2: the castle grows in reserved grounds (M22); 3: the royal family (M23).
## Older saves can't load.
const VERSION := 3
const SLOT := "savegame"
const AUTO := "autosave"


static func path(slot: String) -> String:
	return "%s/%s.json" % [GameState.save_dir, slot]


static func exists(slot: String) -> bool:
	return FileAccess.file_exists(path(slot))


## The newer of the manual save and the autosave, or "" if neither exists
## (saves from an older version don't count).
static func latest_slot() -> String:
	var best := ""
	var best_time := -1
	for slot in [SLOT, AUTO]:
		if exists(slot) and not read(slot).is_empty():
			var t := FileAccess.get_modified_time(path(slot))
			if t > best_time:
				best_time = t
				best = slot
	return best


## "" when saved, else why not.
static func save(main: Node, slot: String) -> String:
	if GameState.game_over:
		return "The game is over."
	if main.raids.phase != RaidDirector.Phase.CALM:
		return "Can't save while raiders are coming."
	DirAccess.make_dir_recursive_absolute(GameState.save_dir)
	var f := FileAccess.open(path(slot), FileAccess.WRITE)
	if f == null:
		return "Couldn't write the save (%s)." % error_string(FileAccess.get_open_error())
	f.store_string(JSON.stringify(capture(main)))
	return ""


static func read(slot: String) -> Dictionary:
	if not exists(slot):
		return {}
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path(slot)))
	if not data is Dictionary or int(data.get("version", 0)) != VERSION:
		return {}
	return data


# --- Capture -----------------------------------------------------------------

static func capture(main: Node) -> Dictionary:
	var world: WorldMap = main.world
	var buildings := []
	for b in world.buildings:
		buildings.append({
			"id": b.def_id, "origin": _v(b.origin), "hp": b.health.hp,
			"level": b.level, "level_timer": b.level_timer, "unhappy_time": b.unhappy_time,
			"happiness": b.happiness, "inventory": b.inventory, "output": b.output_stock,
			"input": b.input_stock, "burning": b.burning,
		})
	var fields := []
	for t: Vector2i in world.fields:
		var field: Dictionary = world.fields[t]
		fields.append({"t": _v(t), "farm": _v(field.farm.origin), "stage": field.stage, "timer": field.timer})
	var villagers := []
	for v: Villager in main.citizens.villagers:
		villagers.append({
			"name": v.villager_name, "home": _v(v.home.origin) if is_instance_valid(v.home) else null,
			"job": _v(v.job.origin) if v.job != null else null, "hp": v.health.hp,
			"missed": v.missed_meals,
		})
	var squads := []
	for s: Squad in main.military.squads:
		if s.barracks == null or not is_instance_valid(s.barracks):
			continue
		squads.append({
			"barracks": _v(s.barracks.origin), "id": s.id, "manual": s.mode == Squad.Mode.MANUAL,
			"rally": _v(s.rally_tile), "order": _v(s.order_tile),
			"troops": s.troops.map(func(t: Troop) -> Dictionary: return {"unit": t.unit_id, "hp": t.health.hp}),
			"training": main.military.queue_for(s.barracks),
		})
	var lairs := []
	for lair in world.lairs():
		lairs.append({"t": _v(lair.current_tile()), "id": lair.enemy_id, "hp": lair.health.hp})
	var cam: Vector2 = main.camera.position
	return {
		"version": VERSION,
		"saved_at": Time.get_datetime_string_from_system(false, true),
		"seed": world.map_seed,
		"difficulty": GameState.difficulty,
		"size": world.width,
		"terrain": Marshalls.raw_to_base64(world.terrain),
		"resource_left": Marshalls.raw_to_base64(world.resource_left.to_byte_array()),
		"roads": world.roads.keys().map(func(t: Vector2i) -> Array: return _v(t)),
		"buildings": buildings,
		"fields": fields,
		"saplings": world.saplings.keys().map(func(t: Vector2i) -> Array: return [t.x, t.y, world.saplings[t]]),
		"cleared": world.cleared.keys().map(func(t: Vector2i) -> Array: return [t.x, t.y, world.cleared[t]]),
		"villagers": villagers,
		"settlers_arrived": main.citizens._settlers_arrived,
		"squads": squads,
		"lairs": lairs,
		"research": {"completed": main.research.completed, "queue": main.research.queue,
			"progress": main.research.progress},
		"tier": main.progression.tier,
		"raids": {"timer": main.raids._timer, "survived": main.raids.raids_survived,
			"final_siege": main.raids.final_siege},
		"day": main.day_night.day,
		"season": main.seasons.index,
		"trade": {"timer": main.trade.timer, "merchant": main.trade.merchant},
		"castle": main.castle.to_save(),
		"royals": main.royals.to_save(),
		"season_days": main.seasons.days_in,
		"clock": main.day_night.clock,
		"tax_rate": GameState.tax_rate,
		"camera": [cam.x, cam.y],
	}


# --- Apply -------------------------------------------------------------------

## Brings a freshly generated game (same seed) to the saved state.
static func apply(main: Node, data: Dictionary) -> void:
	var world: WorldMap = main.world
	GameState.tax_rate = int(data.tax_rate)

	# Research first, so buildings are created with the right HP and storage.
	for id: String in data.research.completed:
		main.research.restore_completed(id)
	main.research.queue.assign(data.research.queue)
	main.research.progress = float(data.research.progress)

	main.progression.restore_tier(int(data.tier))

	world.restore_roads(data.roads.map(func(a: Array) -> Vector2i: return _t(a)))
	main.castle.restore(data.castle)
	main.royals.restore(data.royals)

	var by_origin := {world.keep.origin: world.keep}
	for entry: Dictionary in data.buildings:
		var origin := _t(entry.origin)
		var b: Building = world.keep if entry.id == "keep" else world.place_building(entry.id, origin)
		by_origin[origin] = b
	world.restore_terrain(Marshalls.base64_to_raw(data.terrain),
		Marshalls.base64_to_raw(data.resource_left).to_int32_array())
	world.restore_fields(data.fields.map(func(f: Dictionary) -> Dictionary: return {
		"t": _t(f.t), "farm": by_origin.get(_t(f.farm)), "stage": int(f.stage), "timer": float(f.timer)}))
	world.restore_forests(data.get("saplings", []), data.get("cleared", []))

	for entry: Dictionary in data.buildings:
		var b: Building = by_origin[_t(entry.origin)]
		b.inventory = _ints(entry.inventory)
		b.output_stock = _ints(entry.output)
		b.input_stock = _ints(entry.input)
		b.level = int(entry.level)
		b.level_timer = float(entry.level_timer)
		b.unhappy_time = float(entry.unhappy_time)
		b.happiness = float(entry.happiness)
		b.health.hp = minf(float(entry.hp), b.health.max_hp)
		b.health.changed.emit()
		if entry.burning:
			b.burning = true
		b.queue_redraw()
	world.stock.changed.emit()
	world.recompute_capacity()

	for v: Dictionary in data.villagers:
		var home: Building = by_origin.get(_t(v.home)) if v.home != null else null
		if home == null:
			continue
		var job: Building = by_origin.get(_t(v.job)) if v.job != null else null
		main.citizens.restore_villager(home, job, v.name, float(v.hp), int(v.missed))
	main.citizens._settlers_arrived = int(data.settlers_arrived)

	for s: Dictionary in data.squads:
		var barracks: Building = by_origin.get(_t(s.barracks))
		if barracks != null:
			main.military.restore_squad(barracks, int(s.id), bool(s.manual), _t(s.rally), _t(s.order),
				s.troops, s.training)

	main.raids.restore(float(data.raids.timer), int(data.raids.survived), bool(data.raids.final_siege),
		data.lairs.map(func(l: Dictionary) -> Dictionary: return {"t": _t(l.t), "id": l.id, "hp": float(l.hp)}))

	if data.has("trade"):
		main.trade.timer = float(data.trade.timer)
		var m: Dictionary = data.trade.merchant
		if not m.is_empty() and main.trade.post() != null:
			main.trade.arrive(m.id, main.trade.post().entrance())
			main.trade.merchant.stock = _ints(m.stock)
			main.trade.merchant.gold = int(m.gold)
			main.trade.merchant.time_left = float(m.time_left)
	main.seasons.set_season(int(data.get("season", 0)), false)
	main.seasons.days_in = int(data.get("season_days", 0))
	main.world.growth_paused = main.seasons.is_winter()
	main.day_night.day = int(data.day)
	main.day_night.clock = float(data.clock)
	main.camera.position = Vector2(data.camera[0], data.camera[1])


static func _v(t: Vector2i) -> Array:
	return [t.x, t.y]


static func _t(a: Array) -> Vector2i:
	return Vector2i(int(a[0]), int(a[1]))


## JSON numbers come back as floats; inventories hold ints.
static func _ints(d: Dictionary) -> Dictionary:
	var out := {}
	for k: String in d:
		out[k] = int(d[k])
	return out
