extends Node
## Autoplayer: plays a whole game like a sensible player, for balance data.
## It uses the same rules a player does — costs, tier locks, placement rules,
## road access — through the game's own functions (no shortcuts, no grants),
## at 4x speed. Every few game seconds it takes the most urgent action from
## a priority list; every game minute it records a snapshot; at the end it
## writes report.json and summary.md.
##
##   tools/autoplay/run.sh --seeds 12345,7 --minutes 120
##
## Street plan: horizontal avenues every 3 rows around the Keep (2 rows of
## buildings above each road), joined by a north-south spine; avenues grow
## longer when there's no room left. Gatherers that need a resource the grid
## doesn't reach get a branch road out to it.

const TICK := 2.0            # game seconds between decisions
const SNAPSHOT := 60.0       # game seconds between timeline entries
const AVENUE_SPACING := 3
const AVENUES := 5           # on each side of the Keep's avenue
const RESEARCH_ORDER := ["sharp_tools", "crop_rotation", "fletching", "ledgers", "masonry",
	"tempered_steel", "wheelbarrows"]
## The town wall: a rectangle around the street grid (tiles from the Keep's
## entrance). Streets stop growing inside it.
const WALL_HALF_WIDTH := 25
const WALL_TOP := -15
const WALL_BOTTOM := 20
## A wall tower every this many wall segments (from Town).
const TOWER_EVERY := 8

var main: Node2D
var world: WorldMap
var out_dir := ""
var minutes_limit := 120.0

var game_time := 0.0
var _tick := 0.0
var _snap := 0.0
var _avenue_len := 7
var _done := false
var _lair_target: Enemy
var _last_action := ""

var timeline: Array = []
var events: Array = []
var counters := {"raids": 0, "buildings_lost": 0, "villagers_killed": 0, "troops_lost": 0,
	"stolen": 0, "hungry_warnings": 0, "starved_left": 0, "firewood_out": 0,
	"lairs_destroyed": 0, "fires": 0, "left_unhappy": 0}
var milestones := {}
var actions := {}
## Why builds failed: "<id>: <reason>" -> count.
var failures := {}
var _street_cooldown := 0.0
## Edible food made (bread + fish) over roughly the last game minute.
var _food_window: Array = []   # [game_time, total_edible_made]
const MAX_AVENUE := 21
## Buildings worth saving up for: when one is short, its cost is held back
## from everything lower on the list except income buildings.
const SAVE_FOR := ["barracks", "guard_tower", "trading_post", "scholars_hall", "stone_tower", "smithy"]
const INCOME := ["woodcutter", "forester", "quarry", "farm", "fisher", "iron_mine"]
var _reserve := {}
var _ring: Array[Vector2i] = []
var _ring_next := 0
var _ring_done_at := -1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and "=" in a:
			args[a.substr(2).get_slice("=", 0)] = a.get_slice("=", 1)
	out_dir = args.get("out", "/tmp/autoplay")
	minutes_limit = float(args.get("minutes", "120"))
	DirAccess.make_dir_recursive_absolute(out_dir)
	Engine.max_fps = 0
	OS.low_processor_usage_mode = false
	Settings.use_file("user://autoplay-settings.cfg")
	GameState.hints_enabled = false
	GameState.save_dir = "user://autoplay-saves"
	GameState.new_game_seed = int(args.get("seed", "12345"))
	GameState.difficulty = int(args.get("difficulty", "1"))
	Sound.set_process(false)
	main = load("res://scenes/main.tscn").instantiate()
	main.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(main)
	await get_tree().process_frame
	world = main.world
	GameState.notified.connect(_on_notice)
	main.raids.raid_started.connect(func(n: int) -> void:
		counters.raids += 1
		_event("raid %d starts: %d raiders %s" % [counters.raids, n, JSON.stringify(main.raids.composition())]))
	main.raids.raid_ended.connect(func(n: int) -> void: _event("raid over (survived %d)" % n))
	main.raids.final_siege_won.connect(func() -> void: _finish("victory"))
	world.keep_destroyed.connect(func() -> void: _finish("defeat: the Keep fell"))
	main.citizens.all_villagers_lost.connect(func() -> void: _finish("defeat: everyone left or died"))
	GameState.set_speed(3)
	print("AUTOPLAY seed=%d start" % world.map_seed)


func _process(delta: float) -> void:
	if _done or GameState.speed == 0:
		return
	var dt := delta  # already scaled by the game speed
	game_time += dt
	_snap -= dt
	if _snap <= 0.0:
		_snap = SNAPSHOT
		_snapshot()
	if game_time >= minutes_limit * 60.0:
		_finish("time limit")
		return
	_street_cooldown -= dt
	_tick -= dt
	if _tick <= 0.0:
		_tick = TICK
		_act()


# --- Decisions ---------------------------------------------------------------

func _act() -> void:
	_reserve = {}
	var tier: int = main.progression.tier
	var pop := GameState.population
	var homes := _count("house") + _count("stone_house")
	var free_housing := GameState.housing - pop
	var food_min := GameState.edible_total() / float(maxi(pop, 1)) * CitizenManager.MEAL_INTERVAL / 60.0
	var raid_near: bool = main.raids.phase != RaidDirector.Phase.CALM
	var winter_soon: bool = main.seasons.is_winter() or (main.seasons.current() == "autumn" and main.seasons.days_left() <= 2)
	var wood_reserve := homes * (10 if main.seasons.current() in ["autumn", "winter"] else 2)
	_manage_war()
	_trade(food_min, homes)
	_grow_castle()
	# A tower before the first raid, more as raids grow.
	if game_time > 180.0 and _count("guard_tower") < mini(1 + main.raids.raids_survived, 5) and _try("guard_tower"):
		return
	if tier >= 1 and _count("barracks") < 1 and _try("barracks"):
		return
	if tier >= 1 and pop >= 20 and _count("trading_post") < 1 and _try("trading_post"):
		return
	if tier >= 2 and _count("barracks") < 2 and _try("barracks"):
		return
	if tier >= 1 and pop >= 25 and _build_walls(wood_reserve):
		return
	# Survival first: food, then firewood before winter.
	if food_min < 6.0 and _count("fisher") < 1 + pop / 12 and _try("fisher", Terrain.WATER):
		return
	if food_min < 8.0 and _count("farm") < 1 + pop / 10 and _try("farm"):
		return
	if _count("farm") >= 2 and _count("mill") < 1 + _count("farm") / 3 and _try("mill"):
		return
	if _count("mill") >= 1 and _count("bakery") < _count("mill") and _try("bakery"):
		return
	if winter_soon and GameState.count("wood") < homes * 8 and _count("woodcutter") < 2 + homes / 4 and _try("woodcutter", Terrain.FOREST):
		return
	# Basic economy: wood is the first bottleneck, so keep enough woodcutters.
	if _count("woodcutter") < 1 and _try("woodcutter", Terrain.FOREST):
		return
	if GameState.count("wood") < 80 and _count("woodcutter") < 2 + pop / 6 and _try("woodcutter", Terrain.FOREST):
		return
	# Grow only while food income covers everyone with some to spare (and,
	# before winter, on a real stock too).
	var food_needed := 5.0 if winter_soon else 2.0
	var income := _food_income()
	var can_grow := (pop < 12 or (food_min >= food_needed and income >= pop * 1.15)) \
		and GameState.count("wood") >= wood_reserve
	if income < pop and food_min < 8.0:
		if _count("fisher") < 2 + pop / 8 and _try("fisher", Terrain.WATER):
			return
		if _count("farm") < 2 + pop / 8 and _try("farm"):
			return
	if free_housing < 2 and homes < 40 and can_grow:
		if tier >= 1 and _unlocked("stone_house") and GameState.count("stone") > 60 and _try("stone_house"):
			return
		if _try("house"):
			return
	if _count("woodcutter") < 1 + pop / 8 and _try("woodcutter", Terrain.FOREST):
		return
	if _count("quarry") < 1 + pop / 20 and _try("quarry", Terrain.STONE):
		return
	# Replant: a Forester beside any woodcutter whose woods are thinning.
	var thinning := _thinning_woodcutter()
	if thinning != null and _count("forester") < 1 + _count("woodcutter") / 4 \
			and _try("forester", -1, 0, thinning.entrance()):
		return
	if _near_full("materials") and _try("stockpile" if tier < 2 else "warehouse"):
		return
	if (_near_full("food") or _near_full("grain")) and _try("granary"):
		return
	# Tier requirements and services. Wells go where homes lack water (they
	# are also the town's firefighting).
	var dry := _dry_home()
	if dry != null and _try("well", -1, 0, dry.entrance()):
		return
	if _count("granary") < 1 and _try("granary"):
		return
	if _count("guard_tower") < mini(2 + main.raids.raids_survived, 8) and _try("guard_tower"):
		return
	if tier >= 1:
		if _count("barracks") < 1 and _try("barracks"):
			return
		if _count("scholars_hall") < 1 and _try("scholars_hall"):
			return
		if _count("trading_post") < 1 and pop >= 20 and _try("trading_post"):
			return
		if _count("chapel") < 1 + homes / 12 and _try("chapel"):
			return
		if _count("market") < 1 + homes / 12 and _try("market"):
			return
		var workplaces := _count("farm") + _count("mill") + _count("bakery") + _count("woodcutter") + _count("quarry")
		if _count("carter") < 1 + workplaces / 8 and pop >= 20 and _try("carter"):
			return
		if _count("iron_mine") < 1 and _try("iron_mine", Terrain.STONE):
			return
		if _count("smithy") < 1 and _count("iron_mine") >= 1 and _try("smithy"):
			return
	if tier >= 2:
		if _count("tavern") < 1 + homes / 12 and _try("tavern"):
			return
		if _count("warehouse") < 1 and _try("warehouse"):
			return
		if _count("stone_tower") < mini(main.raids.raids_survived, 4) and _try("stone_tower"):
			return
		if _count("armory") < 1 and _try("armory"):
			return
		if _upgrade_ring_towers():
			return

	_research()
	_train()
	if not raid_near and free_housing < 4 and can_grow and _try("house"):
		return


## Troops, towers and lairs.
func _manage_war() -> void:
	var raid: bool = main.raids.phase == RaidDirector.Phase.ACTIVE
	# Call to Arms when raiders outnumber troops near the Keep.
	var close := 0
	for e in world.enemies:
		if e.position.distance_to(world.keep.center()) < 12 * Terrain.TILE_SIZE:
			close += 1
	if raid and not world.call_to_arms and close > main.military.troops().size() * 2 + 4:
		world.call_to_arms = true
		_event("Call to Arms (%d raiders near the Keep)" % close)
	elif world.call_to_arms and close < 4:
		# Back to work once the worst is over.
		world.call_to_arms = false
		_event("stand down (%d raiders left near the Keep)" % close)
	# Assault a lair once the army is strong.
	if not raid and main.progression.tier >= 3 and _lair_target == null and main.military.troops().size() >= 6:
		var lairs := world.lairs()
		if not lairs.is_empty():
			_lair_target = lairs[0]
			for s: Squad in main.military.squads:
				s.order_attack(_lair_target, world)
			_event("army marches on a goblin lair")
	if _lair_target != null and (not is_instance_valid(_lair_target) or _lair_target.health.is_dead()):
		_lair_target = null
		for s: Squad in main.military.squads:
			s.return_to_barracks()


## When a merchant is in town: buy what's short, sell what's piling up.
func _trade(food_min: float, homes: int) -> void:
	var trade: Trade = main.trade
	if not trade.is_open():
		return
	for i in 3:  # a few lots per tick
		if food_min < 3.0:
			for item in ["bread", "fish"]:
				if trade.buy(item) == "":
					_note_action("buy " + item)
					return
		if GameState.count("wood") < 40 and trade.buy("wood") == "":
			_note_action("buy wood")
			continue
		if _count("barracks") > 0 and GameState.count("weapons") < 2 and GameState.count("gold") > 150 \
				and trade.buy("weapons") == "":
			_note_action("buy weapons")
			continue
		if GameState.count("wood") > homes * 10 + 250 and trade.sell("wood") == "":
			_note_action("sell wood")
			continue
		if GameState.count("stone") > 300 and trade.sell("stone") == "":
			_note_action("sell stone")
			continue
		if food_min > 12.0:
			for item in ["bread", "fish"]:
				if GameState.count(item) > 60 and trade.sell(item) == "":
					_note_action("sell " + item)
					break
		return


func _train() -> void:
	var tier: int = main.progression.tier
	for b in world.buildings:
		if b.def_id != "barracks":
			continue
		var squad: Squad = main.military.squad_for(b)
		if GameState.population < 20:
			return  # every recruit is a villager: grow first
		var target := clampi(GameState.population / 5, 3, 6)
		if squad.troops.size() + main.military.queue_for(b).size() >= target:
			continue
		var order := ["knight", "archer", "spearman", "militia"] if tier >= 3 else (
			["archer", "spearman", "militia"] if tier >= 2 else ["spearman", "militia"])
		for unit: String in order:
			if main.progression.is_unlocked("units", unit) and GameState.can_afford(UnitDefs.get_def(unit).cost) \
					and GameState.count("gold") > UnitDefs.get_def(unit).cost.get("gold", 0) + 20:
				if main.military.train(b, unit) == "":
					_note_action("train " + unit)
					return


func _research() -> void:
	if _count("scholars_hall") == 0 or not main.research.queue.is_empty():
		return
	for id: String in RESEARCH_ORDER:
		if main.research.start(id, main.progression) == "":
			_note_action("research " + id)
			_event("research started: " + id)
			return


# --- Building ------------------------------------------------------------------

## Tries to build `id`: near its resource if `terrain` is given, else in the
## street grid (or a ring `ring` tiles out for wall towers). Extends roads when
## there's no room. True when built.
func _try(id: String, terrain := -1, ring := 0, near := WorldMap.INVALID_TILE) -> bool:
	var def := BuildingDefs.get_def(id)
	if not _unlocked(id):
		return _fail(id, "locked")
	if not GameState.can_afford(def.cost):
		# Save up only once the town can spare it (20+ people).
		if id in SAVE_FOR and _reserve.is_empty() and GameState.population >= 20:
			_reserve = def.cost.duplicate()
		return _fail(id, "can't afford")
	if id not in INCOME and not _affordable_after_reserve(def.cost):
		return _fail(id, "saving for %s" % JSON.stringify(_reserve))
	# Keep a firewood reserve going into winter.
	if def.cost.has("wood") and main.seasons.current() in ["autumn", "winter"] \
			and id not in ["woodcutter", "fisher", "farm", "house"] \
			and GameState.count("wood") - def.cost.wood < (_count("house") + _count("stone_house")) * 4:
		return _fail(id, "saving firewood")
	var site := _find_site(id, terrain, ring, near)
	if site == WorldMap.INVALID_TILE:
		if terrain >= 0:
			_road_toward(terrain)
		elif ring == 0:
			_grow_streets()
		return _fail(id, "no site")
	if not GameState.spend(def.cost):
		return false
	world.place_building(id, site)
	_note_action("build " + id)
	if not milestones.has("first_" + id):
		milestones["first_" + id] = _minute()
	return true


## Can we pay `cost` and still keep what we're saving up for?
func _affordable_after_reserve(cost: Dictionary) -> bool:
	for item: String in cost:
		if GameState.count(item) - int(_reserve.get(item, 0)) < int(cost[item]):
			return false
	return true


## Start the next castle upgrade once it's allowed and the materials are
## on hand (with a margin, so building doesn't stall the town).
func _grow_castle() -> void:
	var castle: Castle = main.castle
	var next := castle.next_stage()
	if next.is_empty() or castle.upgrade_problem() != "":
		return
	for item: String in next.materials:
		if GameState.count(item) < next.materials[item] + 50:
			return
	if castle.start_upgrade() == "":
		_note_action("castle " + next.title)
		milestones["castle_" + next.title] = _minute()


## A woodcutter with little forest left in reach and no Forester near it.
func _thinning_woodcutter() -> Building:
	for wc in world.buildings:
		if wc.def_id != "woodcutter":
			continue
		var r: int = wc.def.radius
		if world.find_resource_tiles(wc.entrance(), Terrain.FOREST, r, 20).size() >= 20:
			continue
		var covered := world.buildings.any(func(b: Building) -> bool:
			return b.def_id == "forester" and b.entrance().distance_to(wc.entrance()) <= 10.0)
		if not covered:
			return wc
	return null


func _dry_home() -> Building:
	for b in world.buildings:
		if b.is_home() and b.def.has("level_bonus") and not b.needs_met.get("water", true):
			return b
	return null


func _find_site(id: String, terrain: int, ring: int, near_tile := WorldMap.INVALID_TILE) -> Vector2i:
	var def := BuildingDefs.get_def(id)
	var size: Vector2i = def.size
	var center := world.keep.entrance()
	if ring > 0:
		# Wall towers: first free spot on a ring around the town.
		for i in 64:
			var a := TAU * float(i) / 64.0 + float(_count(id)) * 0.7
			var t := center + Vector2i(roundi(cos(a) * ring), roundi(sin(a) * ring))
			if world.can_place_building(id, t) == "":
				return t
		return WorldMap.INVALID_TILE
	var near := center if near_tile == WorldMap.INVALID_TILE else near_tile
	if terrain >= 0:
		var spot := _nearest_terrain(terrain)
		if spot == WorldMap.INVALID_TILE:
			return WorldMap.INVALID_TILE
		near = spot
	for r in 22:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var origin := near + Vector2i(dx, dy)
				if world.can_place_building(id, origin) != "":
					continue
				if not world.is_road(BuildingDefs.entrance_of(origin, size)):
					continue
				return origin
	return WorldMap.INVALID_TILE


## Nearest tile of `terrain` to the Keep that isn't already crowded by
## workplaces gathering it.
func _nearest_terrain(terrain: int) -> Vector2i:
	var center := world.keep.entrance()
	var best := WorldMap.INVALID_TILE
	var best_d := INF
	for y in range(maxi(0, center.y - 40), mini(world.height, center.y + 40), 2):
		for x in range(maxi(0, center.x - 40), mini(world.width, center.x + 40), 2):
			var t := Vector2i(x, y)
			if world.get_terrain(t) != terrain:
				continue
			var d := Vector2(t).distance_to(Vector2(center))
			if d < best_d:
				best_d = d
				best = t
	return best


# --- Walls ----------------------------------------------------------------------

## The wall's tiles in order round the rectangle.
func _wall_ring() -> Array[Vector2i]:
	if _ring.is_empty():
		var e := world.keep.entrance()
		var x0 := e.x - WALL_HALF_WIDTH
		var x1 := e.x + WALL_HALF_WIDTH
		var y0 := e.y + WALL_TOP
		var y1 := e.y + WALL_BOTTOM
		for x in range(x0, x1 + 1):
			_ring.append(Vector2i(x, y0))
		for y in range(y0 + 1, y1 + 1):
			_ring.append(Vector2i(x1, y))
		for x in range(x1 - 1, x0 - 1, -1):
			_ring.append(Vector2i(x, y1))
		for y in range(y1 - 1, y0, -1):
			_ring.append(Vector2i(x0, y))
	return _ring


## Builds the next stretch of wall (up to 12 segments a tick): palisade until
## stone walls unlock, a gate wherever a road crosses, a wall tower every
## TOWER_EVERY segments once they unlock. Tiles that can't hold a wall
## (water, forest, rock, buildings) are skipped. True if anything was built.
func _build_walls(reserve: int) -> bool:
	var ring := _wall_ring()
	if _ring_next >= ring.size():
		return false
	var built := 0
	while _ring_next < ring.size() and built < 12:
		var t: Vector2i = ring[_ring_next]
		var id := "stone_wall" if _unlocked("stone_wall") else "palisade"
		if world.roads.has(t):
			id = "gate"
		elif _ring_next % TOWER_EVERY == 0 and _unlocked("wall_tower"):
			id = "wall_tower"
		if world.occupancy.has(t) or world.can_place_building(id, t) != "":
			_ring_next += 1
			continue
		var cost: Dictionary = BuildingDefs.get_def(id).cost
		if not _affordable_after_reserve(cost) or GameState.count("wood") - cost.get("wood", 0) < reserve:
			break
		GameState.spend(cost)
		world.place_building(id, t)
		_note_action("build " + id)
		built += 1
		_ring_next += 1
	if _ring_next >= ring.size() and _ring_done_at < 0.0:
		_ring_done_at = _minute()
		milestones["wall_closed"] = _ring_done_at
		_event("town wall finished")
	return built > 0


## From Town: swaps palisade on the ring for wall towers every TOWER_EVERY
## segments, then for stone walls, as money allows (one per tick).
func _upgrade_ring_towers() -> bool:
	var ring := _wall_ring()
	for i in mini(_ring_next, ring.size()):
		var t: Vector2i = ring[i]
		var b: Building = world.occupancy.get(t)
		if b == null or b.def_id != "palisade":
			continue
		var id := "wall_tower" if i % TOWER_EVERY == 0 else "stone_wall"
		var cost: Dictionary = BuildingDefs.get_def(id).cost
		if not _unlocked(id) or not GameState.can_afford(cost) or GameState.count("stone") < cost.get("stone", 0) + 40:
			return false
		world.remove_building(b)
		if world.can_place_building(id, t) == "" and GameState.spend(cost):
			world.place_building(id, t)
			_note_action("upgrade to " + id)
			return true
		return false
	return false


## Lengthens the avenues (and the spine joining them) by a few tiles, at
## most every 30 game seconds and up to MAX_AVENUE.
func _grow_streets() -> void:
	if _street_cooldown > 0.0 or _avenue_len >= MAX_AVENUE:
		return
	_street_cooldown = 30.0
	_avenue_len += 3
	var e := world.keep.entrance()
	var y0 := e.y + 3
	var tiles: Array[Vector2i] = []
	for k in range(-AVENUES, AVENUES + 1):
		var y := y0 + k * AVENUE_SPACING
		for x in range(e.x - _avenue_len, e.x + _avenue_len + 1):
			tiles.append(Vector2i(x, y))
	for y in range(y0 - AVENUES * AVENUE_SPACING, y0 + AVENUES * AVENUE_SPACING + 1):
		tiles.append(Vector2i(e.x + _avenue_len + 1, y))
		tiles.append(Vector2i(e.x - _avenue_len - 1, y))
		tiles.append(Vector2i(e.x, y))
	_place_road_tiles(tiles)
	_note_action("grow streets to %d" % _avenue_len)


## A branch road from the nearest existing road out to `terrain`.
func _road_toward(terrain: int) -> void:
	var goal := _nearest_terrain(terrain)
	if goal == WorldMap.INVALID_TILE:
		return
	var from := WorldMap.INVALID_TILE
	var best := INF
	for t: Vector2i in world.roads:
		var d := Vector2(t).distance_squared_to(Vector2(goal))
		if d < best:
			best = d
			from = t
	var target := world.nearest_walkable(goal)
	if from == WorldMap.INVALID_TILE or target == WorldMap.INVALID_TILE:
		return
	var path: Array[Vector2i] = world.find_path(from, target)
	var tiles: Array[Vector2i] = []
	for t in path:
		if world.get_terrain(t) != Terrain.WATER and not world.occupancy.has(t):
			tiles.append(t)
	# Stop a few tiles short so the resource stays next to the road end.
	_place_road_tiles(tiles.slice(0, maxi(0, tiles.size() - 2)))
	_note_action("road toward " + Terrain.NAMES[terrain])


func _place_road_tiles(tiles: Array[Vector2i]) -> void:
	var land: Array[Vector2i] = []
	for t in tiles:
		if world.is_in_bounds(t) and world.get_terrain(t) != Terrain.WATER:
			land.append(t)
	world.place_roads(land)


# --- Bookkeeping ------------------------------------------------------------------

## Bread + fish made per game minute, over the last minute or so.
func _food_income() -> float:
	var made: int = GameState.stats.produced.get("bread", 0) + GameState.stats.produced.get("fish", 0)
	_food_window.append([game_time, made])
	while _food_window.size() > 2 and game_time - _food_window[1][0] >= 60.0:
		_food_window.pop_front()
	var span: float = game_time - _food_window[0][0]
	if span < 20.0:
		return 999.0  # not enough history yet
	return (made - _food_window[0][1]) / span * 60.0


func _fail(id: String, why: String) -> bool:
	var key := "%s: %s" % [id, why]
	failures[key] = failures.get(key, 0) + 1
	return false


func _count(id: String) -> int:
	var n := 0
	for b in world.buildings:
		if b.def_id == id:
			n += 1
	return n


func _unlocked(id: String) -> bool:
	return main.progression.is_unlocked("buildings", id)


func _near_full(category: String) -> bool:
	var cap: int = GameState.capacity.get(category, 0)
	return cap > 0 and GameState.used(category) > cap * 0.85


func _minute() -> float:
	return snappedf(game_time / 60.0, 0.1)


func _note_action(what: String) -> void:
	var key := what.get_slice(" ", 0) + " " + what.get_slice(" ", 1)
	actions[key] = actions.get(key, 0) + 1


func _event(text: String) -> void:
	events.append({"min": _minute(), "event": text})


func _on_notice(text: String) -> void:
	var t := text.to_lower()
	if "grown into a" in t:
		var tier: String = main.progression.tier_name()
		milestones["tier_" + tier] = _minute()
		_event(text)
	elif "was destroyed" in t:
		counters.buildings_lost += 1
		_event(text)
	elif "killed by raiders" in t:
		counters.villagers_killed += 1
	elif "fell in battle" in t:
		counters.troops_lost += 1
	elif "stole" in t:
		counters.stolen += 1
	elif "went hungry" in t:
		counters.hungry_warnings += 1
	elif "starving villager" in t:
		counters.starved_left += int(text.get_slice(" ", 0))
		_event(text)
	elif "out of firewood" in t:
		counters.firewood_out += 1
		_event(text)
	elif "lair is destroyed" in t:
		counters.lairs_destroyed += 1
		_event(text)
	elif "on fire" in t:
		counters.fires += 1
	elif "left an unhappy home" in t:
		counters.left_unhappy += 1
	elif "has arrived at the trading post" in t or "packs up" in t or "moves on" in t:
		_event(text)
	elif "winter has come" in t or "dragon" in t or "research complete" in t:
		_event(text)


var _last_stats := {}


## Per-minute rates since the last snapshot: produced / spent / used.
func _rates() -> Dictionary:
	var rates := {}
	for kind: String in GameState.stats:
		for item: String in GameState.stats[kind]:
			var now: int = GameState.stats[kind][item]
			var before: int = _last_stats.get(kind + ":" + item, 0)
			if now != before:
				rates[kind.substr(0, 4) + "_" + item] = now - before
			_last_stats[kind + ":" + item] = now
	return rates


func _snapshot() -> void:
	var troops: Array = main.military.troops()
	timeline.append({
		"min": _minute(), "tier": main.progression.tier_name(), "season": main.seasons.current(),
		"pop": GameState.population, "housing": GameState.housing,
		"jobs": "%d/%d" % [GameState.employed, GameState.jobs],
		"happiness": roundi(GameState.happiness),
		"food": GameState.edible_total(), "wood": GameState.count("wood"), "stone": GameState.count("stone"),
		"gold": GameState.count("gold"), "iron": GameState.count("iron"), "weapons": GameState.count("weapons"),
		"troops": troops.size(), "buildings": world.buildings.size(), "roads": world.roads.size(),
		"raids_survived": main.raids.raids_survived, "warm": main.seasons.warm,
		"rates": _rates(),
		"counts": {"woodcutter": _count("woodcutter"), "quarry": _count("quarry"), "farm": _count("farm"),
			"fisher": _count("fisher"), "well": _count("well"), "homes": _count("house") + _count("stone_house"),
			"forester": _count("forester")},
		"forest": Array(world.terrain).count(Terrain.FOREST), "saplings": world.saplings.size(),
	})


func _finish(result: String) -> void:
	if _done:
		return
	_done = true
	_snapshot()
	var report := {
		"seed": world.map_seed, "difficulty": GameState.DIFFICULTIES[GameState.difficulty].name,
		"result": result, "minutes": _minute(), "milestones": milestones, "counters": counters,
		"actions": actions, "failures": failures, "events": events, "timeline": timeline,
		"trade": {"bought": GameState.stats.bought, "sold": GameState.stats.sold},
	}
	var f := FileAccess.open(out_dir.path_join("report.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	var md := FileAccess.open(out_dir.path_join("summary.md"), FileAccess.WRITE)
	md.store_string(_summary(report))
	print("AUTOPLAY seed=%d result=%s minutes=%.1f" % [world.map_seed, result, _minute()])
	get_tree().quit()


func _summary(r: Dictionary) -> String:
	var lines := PackedStringArray()
	lines.append("# Autoplay: seed %d (%s) — %s at minute %.1f" % [r.seed, r.difficulty, r.result, r.minutes])
	lines.append("")
	lines.append("Tiers: " + ", ".join(["Village", "Town", "City", "Kingdom"].map(func(t: String) -> String:
		return "%s %s" % [t, ("min %.1f" % r.milestones["tier_" + t]) if r.milestones.has("tier_" + t) else "—"])))
	lines.append("Counters: " + JSON.stringify(r.counters))
	lines.append("Actions: " + JSON.stringify(r.actions))
	lines.append("Trade: " + JSON.stringify(r.trade))
	var top: Array = r.failures.keys()
	top.sort_custom(func(a: String, b: String) -> bool: return r.failures[a] > r.failures[b])
	lines.append("Most frequent build failures: " + ", ".join(top.slice(0, 8).map(func(k: String) -> String:
		return "%s ×%d" % [k, r.failures[k]])))
	lines.append("")
	lines.append("| min | tier | season | pop/housing | happy | food | wood | stone | gold | troops | raids |")
	lines.append("|---|---|---|---|---|---|---|---|---|---|---|")
	for s: Dictionary in r.timeline:
		lines.append("| %s | %s | %s | %d/%d | %d | %d | %d | %d | %d | %d | %d |" % [s.min, s.tier, s.season,
			s.pop, s.housing, s.happiness, s.food, s.wood, s.stone, s.gold, s.troops, s.raids_survived])
	lines.append("")
	lines.append("Events:")
	for e: Dictionary in r.events:
		lines.append("- %s: %s" % [e.min, e.event])
	return "\n".join(lines) + "\n"
