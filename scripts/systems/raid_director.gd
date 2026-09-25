class_name RaidDirector
extends Node
## Schedules goblin raids: calm -> warning (30s, direction revealed) -> active
## (until every raider is dead or has fled) -> calm. Raids grow with the
## population and with each raid survived. Buildings slowly repair while calm.

signal warning_started(spawn_tile: Vector2i)
signal raid_started(count: int)
signal raid_ended(raids_survived: int)
signal final_siege_won

enum Phase { CALM, WARNING, ACTIVE }

const FIRST_RAID_TIME := 420.0
const RAID_INTERVAL := 300.0
const WARNING_TIME := 30.0
## Fraction of max HP repaired per second between raids.
const REPAIR_RATE := 0.02
const LAIR_COUNT := 2
## Lairs sit at least this many tiles from the Keep and from each other.
const LAIR_MIN_KEEP_TILES := 30
const LAIR_MIN_APART_TILES := 24

var world: WorldMap
## Set by main; raids grow with the settlement tier.
var progression: Progression
var phase := Phase.CALM
var raids_survived := 0
var spawn_tile := WorldMap.INVALID_TILE

var _timer := FIRST_RAID_TIME
## Final siege: armed when the realm reaches Kingdom; the next raid is led
## by the Dragon and winning it wins the game.
var final_siege := false
var dragon_spawned := false
var dragon_slain := false

## Warning time after the player challenges the Dragon.
const FINAL_SIEGE_DELAY := 60.0


func setup(p_world: WorldMap) -> void:
	world = p_world
	_timer = GameState.DIFFICULTIES[GameState.difficulty].first_raid


func _process(delta: float) -> void:
	match phase:
		Phase.CALM:
			_timer -= delta
			_repair(delta)
			if _timer <= WARNING_TIME:
				_begin_warning()
		Phase.WARNING:
			_timer -= delta
			if _timer <= 0.0:
				_launch_raid()
		Phase.ACTIVE:
			if world.enemies.is_empty():
				_end_raid()


func time_until_raid() -> float:
	return maxf(_timer, 0.0) if phase != Phase.ACTIVE else 0.0


## Debug/testing: start the warning countdown right away.
func call_raid_now() -> void:
	if phase == Phase.CALM:
		_timer = WARNING_TIME


## Which enemies the next raid brings.
func composition() -> Dictionary:
	var tier := progression.tier if progression != null else 0
	# Raids survived count only up to a cap per tier, so a long game spent
	# building doesn't snowball the raids: they follow the kingdom's size and
	# tier instead.
	var raids_survived := mini(self.raids_survived, 4 + tier * 2)
	var goblins := 2 + floori(GameState.population / 16.0) + raids_survived + tier
	# Lairs ramp up: +1 goblin each per raid survived, up to their full bonus,
	# so the first raid isn't doubled for a brand-new town.
	for lair in world.lairs():
		goblins += mini(int(lair.def.raid_bonus), raids_survived)
	# Brutes from the 3rd raid (the 2nd is goblins only, so a young village
	# isn't flattened), +1 per tier.
	var brutes := 0
	if raids_survived >= 2:
		brutes = 1 + floori((raids_survived - 2) / 2.0) + tier
	# Orcs from the 3rd raid (more at higher tiers), a shaman per 3 orcs,
	# wolf riders from Town, trolls once the kingdom is well established.
	var orcs := maxi(0, raids_survived - 2) + (tier if raids_survived >= 2 else 0)
	var shamans := floori(orcs / 3.0)
	var wolves := (2 + floori(raids_survived / 3.0)) if tier >= 2 else 0
	var trolls := (1 + maxi(0, floori((raids_survived - 5) / 3.0))) if raids_survived >= 5 or tier >= 3 else 0
	var mix := {"goblin": goblins, "goblin_brute": brutes, "orc": orcs, "orc_shaman": shamans,
		"wolf_rider": wolves, "troll": trolls}
	var scale: float = GameState.DIFFICULTIES[GameState.difficulty].raid_size
	if final_siege:
		scale *= 1.5
	for id: String in mix:
		mix[id] = ceili(mix[id] * scale) if mix[id] > 0 else 0
	return mix


## The player challenged the Dragon (Kingdom tier, from the tier panel): the
## next raid, a minute from now, is the Dragon's final siege.
func begin_final_siege() -> void:
	if final_siege:
		return
	final_siege = true
	if phase == Phase.CALM:
		_timer = FINAL_SIEGE_DELAY
	GameState.notify("You have challenged the Dragon! It comes in %d seconds. Survive its siege to win." % roundi(FINAL_SIEGE_DELAY))


## The Dragon can be challenged: Kingdom tier, not already coming, and no
## raid under way.
func can_challenge_dragon() -> bool:
	return progression != null and progression.is_max_tier() and not final_siege and phase == Phase.CALM


## Raid clock, record and lairs from a save (see SaveGame).
func restore(timer: float, survived: int, p_final_siege: bool, saved_lairs: Array) -> void:
	_timer = timer
	raids_survived = survived
	final_siege = p_final_siege
	for lair in world.lairs():
		lair.queue_free()
	for l: Dictionary in saved_lairs:
		var lair := spawn_lair(l.t, l.id)
		lair.health.hp = minf(l.hp, lair.health.max_hp)


## Puts goblin lairs out in the wilds: reachable, far from the Keep and from
## each other. Deterministic per map seed.
func place_lairs(count := LAIR_COUNT) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = world.map_seed + 7
	var goal := world.keep.entrance()
	var placed: Array[Vector2i] = []
	for attempt in 400:
		if placed.size() >= count:
			break
		var t := Vector2i(rng.randi_range(4, world.width - 5), rng.randi_range(4, world.height - 5))
		if Vector2(t).distance_to(Vector2(goal)) < LAIR_MIN_KEEP_TILES:
			continue
		if placed.any(func(p: Vector2i) -> bool: return Vector2(p).distance_to(Vector2(t)) < LAIR_MIN_APART_TILES):
			continue
		if not _open_ground(t) or world.find_enemy_path(t, goal).is_empty():
			continue
		spawn_lair(t)
		placed.append(t)
	if not placed.is_empty():
		GameState.notify("Scouts found %d goblin lair%s in the wilds. Destroy them to weaken the raids." % [
			placed.size(), "" if placed.size() == 1 else "s"])


func spawn_lair(t: Vector2i, id := "goblin_lair") -> Enemy:
	var lair := Enemy.new()
	lair.wild = true
	lair.setup(world, id, t, t)
	world.unit_root.add_child(lair)
	return lair


## A 3x3 patch of walkable, unbuilt ground for a lair to sit on.
func _open_ground(t: Vector2i) -> bool:
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var c := t + Vector2i(dx, dy)
			if not world.is_walkable(c) or world.occupancy.has(c) or world.roads.has(c):
				return false
	return true


func direction_name() -> String:
	if spawn_tile == WorldMap.INVALID_TILE:
		return ""
	var offset := Vector2(spawn_tile) - Vector2(world.width, world.height) * 0.5
	if absf(offset.x) > absf(offset.y):
		return "east" if offset.x > 0 else "west"
	return "south" if offset.y > 0 else "north"


func _begin_warning() -> void:
	spawn_tile = _pick_spawn_tile()
	if final_siege and spawn_tile != WorldMap.INVALID_TILE:
		phase = Phase.WARNING
		_timer = WARNING_TIME
		GameState.notify("The Dragon approaches from the %s! Final siege in %ds" % [direction_name(), WARNING_TIME])
		Sound.play("horn")
		Sound.play("roar", null, -4.0)
		warning_started.emit(spawn_tile)
		return
	if spawn_tile == WorldMap.INVALID_TILE:
		_timer = 60.0  # No reachable edge right now; try again later.
		return
	phase = Phase.WARNING
	_timer = WARNING_TIME
	Sound.play("horn")
	GameState.notify("Goblins spotted to the %s! Raid in %ds" % [direction_name(), WARNING_TIME])
	warning_started.emit(spawn_tile)


func _launch_raid() -> void:
	var count := 0
	var mix := composition()
	for id: String in mix:
		for i in mix[id]:
			var tile := world.nearest_walkable(spawn_tile + Vector2i(randi_range(-2, 2), randi_range(-2, 2)))
			if tile == WorldMap.INVALID_TILE:
				tile = spawn_tile
			var enemy := Enemy.new()
			enemy.setup(world, id, tile, spawn_tile)
			world.unit_root.add_child(enemy)
			count += 1
	if final_siege and not dragon_spawned:
		dragon_spawned = true
		var dragon := Enemy.new()
		dragon.setup(world, "dragon", spawn_tile, spawn_tile)
		dragon.health.died.connect(func() -> void: dragon_slain = true)
		world.unit_root.add_child(dragon)
		count += 1
	phase = Phase.ACTIVE
	world.raid_active = true
	GameState.notify("The Dragon and its horde attack!" if final_siege
		else "The goblins attack! Villagers are taking shelter.")
	raid_started.emit(count)


func _end_raid() -> void:
	phase = Phase.CALM
	world.raid_active = false
	world.call_to_arms = false
	raids_survived += 1
	_timer = RAID_INTERVAL
	for v: Villager in get_tree().get_nodes_in_group("villagers"):
		v.health.heal(v.health.max_hp)
	if dragon_slain:
		final_siege_won.emit()
		return
	GameState.notify("The raid is over! Raids survived: %d" % raids_survived)
	Sound.play("chime")
	raid_ended.emit(raids_survived)


## A random walkable map-edge tile that can reach the Keep.
func _pick_spawn_tile() -> Vector2i:
	var goal := world.keep.entrance()
	for attempt in 40:
		var t: Vector2i
		match randi() % 4:
			0:
				t = Vector2i(randi_range(0, world.width - 1), 0)
			1:
				t = Vector2i(randi_range(0, world.width - 1), world.height - 1)
			2:
				t = Vector2i(0, randi_range(0, world.height - 1))
			_:
				t = Vector2i(world.width - 1, randi_range(0, world.height - 1))
		if world.is_walkable(t) and not world.find_enemy_path(t, goal).is_empty():
			return t
	return WorldMap.INVALID_TILE


func _repair(delta: float) -> void:
	for b in world.buildings:
		# Nobody patches a roof that's still on fire.
		if b.health.is_damaged() and not b.burning:
			b.health.heal(b.health.max_hp * REPAIR_RATE * delta)
