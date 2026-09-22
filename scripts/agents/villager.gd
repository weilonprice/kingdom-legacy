class_name Villager
extends Node2D
## A citizen agent. Lives in `home`, works at `job`, and physically walks
## goods between resource tiles, workplaces and storage.
##
## Work loops by the job's `work` type:
##   gather:  go to resource tile -> work -> carry output to storage
##   farm:    go to ripe field -> harvest -> carry wheat to storage
##            (or go to tilled field -> plant)
##   produce: go to storage -> take input -> carry to workplace -> work
##            -> carry output to storage

enum State { IDLE, WANDER, TO_TARGET, WORKING, TO_DEPOSIT, TO_FETCH, TO_WORKPLACE }
enum Task { NONE, GATHER, PLANT, HARVEST, PRODUCE }

const SPEED := 42.0
const COLOR_UNEMPLOYED := Color(0.87, 0.75, 0.55)
const COLOR_SKIN := Color(0.96, 0.80, 0.65)
const NAMES := [
	"Aldric", "Bertram", "Cedric", "Edda", "Elspeth", "Godwin", "Hilda", "Isolde",
	"Jocelyn", "Leofric", "Maud", "Osric", "Rowena", "Sigrid", "Tamsin", "Ulric",
	"Wilfred", "Agnes", "Beatrix", "Cuthbert", "Emmeline", "Gareth", "Ingrid", "Oswin",
]

var world: WorldMap
var home: Building
var job: Building
var villager_name := ""
var state := State.IDLE
var task := Task.NONE
var timer := 0.0
var path: Array[Vector2i] = []
var carrying := ""
var carry_amount := 0
var missed_meals := 0
## What this villager is doing, shown in the building inspector.
var note := "Settling in"

var _jitter := Vector2.ZERO
var _target_tile := WorldMap.INVALID_TILE
var _storage: Building
## Storage space held for the output we're about to produce.
var _held_space := 0
var _held_item := ""


func setup(p_world: WorldMap, p_home: Building) -> void:
	world = p_world
	home = p_home
	villager_name = NAMES.pick_random()
	_jitter = Vector2(randf_range(-7, 7), randf_range(-7, 7))
	position = world.tile_center(home.entrance()) + _jitter
	timer = randf()


func current_tile() -> Vector2i:
	return world.world_to_tile(position)


func set_job(building: Building) -> void:
	job = building
	job.workers.append(self)
	_reset()


func lose_job() -> void:
	if job != null:
		job.workers.erase(self)
		job = null
	_reset()


func _exit_tree() -> void:
	_release_target()
	_release_held_space()


## Drops the current plan. Anything carried is kept and returned to storage.
func _reset() -> void:
	path.clear()
	_release_target()
	_release_held_space()
	state = State.IDLE
	task = Task.NONE
	timer = 0.5
	queue_redraw()


func _release_held_space() -> void:
	if _held_space > 0:
		GameState.release_space(_held_item, _held_space)
		_held_space = 0


func _release_target() -> void:
	if _target_tile != WorldMap.INVALID_TILE:
		world.release(_target_tile, self)
		_target_tile = WorldMap.INVALID_TILE


func _claim(t: Vector2i) -> void:
	world.reserve(t, self)
	_target_tile = t


func _wait(reason: String, seconds := 2.0) -> void:
	note = reason
	state = State.IDLE
	timer = seconds


func _process(delta: float) -> void:
	if not path.is_empty():
		_step(delta)
		return
	match state:
		State.IDLE:
			timer -= delta
			if timer <= 0.0:
				_think()
		State.WORKING:
			timer -= delta
			if timer <= 0.0:
				_finish_work()
		_:
			_arrive()


func _step(delta: float) -> void:
	var target := world.tile_center(path[0]) + _jitter
	var to_target := target - position
	var move := SPEED * world.speed_multiplier(current_tile()) * delta
	if to_target.length() <= move:
		position = target
		path.remove_at(0)
	else:
		position += to_target.normalized() * move


func _walk_to(t: Vector2i) -> bool:
	var p := world.find_path(current_tile(), t)
	if p.is_empty():
		return false
	p.remove_at(0)
	path = p
	return true


# --- Decisions --------------------------------------------------------------

func _think() -> void:
	if carrying != "":
		_go_deposit()
		return
	if job == null:
		note = "Unemployed"
		_wander()
		return
	if not job.has_road:
		note = "Workplace has no road"
		_wander()
		return
	match job.def.get("work", ""):
		"gather":
			_plan_gather()
		"farm":
			_plan_farm()
		"produce":
			_plan_produce()
		_:
			_wander()


func _plan_gather() -> void:
	var def := job.def
	if GameState.space_for(def.resource) <= 0:
		_wait("Storage full", 3.0)
		return
	for t in world.find_resource_tiles(job.entrance(), def.gather_terrain, def.radius, 6):
		var stand := world.approach_tile(t)
		if stand != WorldMap.INVALID_TILE and _walk_to(stand):
			_claim(t)
			task = Task.GATHER
			state = State.TO_TARGET
			note = "Going to gather %s" % def.resource
			return
	_wait("No %s left nearby" % Terrain.NAMES[def.gather_terrain].to_lower(), 4.0)


func _plan_farm() -> void:
	var t := world.find_field(job, WorldMap.FieldStage.RIPE)
	if t != WorldMap.INVALID_TILE and GameState.space_for("wheat") > 0 and _walk_to(t):
		_claim(t)
		task = Task.HARVEST
		state = State.TO_TARGET
		note = "Going to harvest"
		return
	t = world.find_field(job, WorldMap.FieldStage.TILLED)
	if t != WorldMap.INVALID_TILE and _walk_to(t):
		_claim(t)
		task = Task.PLANT
		state = State.TO_TARGET
		note = "Going to plant"
		return
	if GameState.space_for("wheat") <= 0 and world.count_fields(job, WorldMap.FieldStage.RIPE) > 0:
		_wait("Storage full", 3.0)
	else:
		_wait("Waiting for crops to grow", 3.0)


func _plan_produce() -> void:
	var input: String = job.def.input.keys()[0]
	var output: String = job.def.output.keys()[0]
	# Taking the input frees space, so only the net gain must fit.
	var freed: int = job.def.input[input] if ItemDefs.category_of(input) == ItemDefs.category_of(output) else 0
	if GameState.space_for(output) + freed < job.def.output[output]:
		_wait("Storage full", 3.0)
		return
	if GameState.count(input) < job.def.input[input]:
		_wait("Waiting for %s" % input, 3.0)
		return
	var storage := world.nearest_storage_for(input, current_tile())
	if storage != null and _walk_to(storage.entrance()):
		_storage = storage
		state = State.TO_FETCH
		note = "Fetching %s" % input
	else:
		_wait("Can't reach storage", 3.0)


func _go_deposit() -> void:
	var own_held := _held_space if _held_item == carrying else 0
	if GameState.space_for(carrying) + own_held <= 0:
		_wait("Storage full (holding %s)" % carrying, 3.0)
		return
	var storage := world.nearest_storage_for(carrying, current_tile())
	if storage != null and _walk_to(storage.entrance()):
		_storage = storage
		state = State.TO_DEPOSIT
		note = "Hauling %s to %s" % [carrying, storage.def.name]
		return
	_wait("No storage for %s" % carrying, 3.0)


func _wander() -> void:
	var anchor := home.entrance() if is_instance_valid(home) else current_tile()
	for i in 6:
		var t := anchor + Vector2i(randi_range(-4, 4), randi_range(-4, 4))
		if world.is_walkable(t) and _walk_to(t):
			state = State.WANDER
			return
	state = State.IDLE
	timer = randf_range(2.0, 4.0)


# --- Arrivals & work --------------------------------------------------------

func _arrive() -> void:
	match state:
		State.TO_TARGET:
			if job == null or _target_tile == WorldMap.INVALID_TILE:
				_reset()
				return
			state = State.WORKING
			timer = job.def.work_time
			note = {Task.GATHER: "Gathering %s" % job.def.get("resource", ""),
					Task.PLANT: "Planting", Task.HARVEST: "Harvesting"}.get(task, "Working")
		State.TO_FETCH:
			if job == null or not is_instance_valid(_storage):
				_reset()
				return
			var input: String = job.def.input.keys()[0]
			var amount: int = job.def.input[input]
			if not GameState.remove_resource(input, amount):
				_wait("Waiting for %s" % input, 3.0)
				return
			carrying = input
			carry_amount = amount
			_held_item = job.def.output.keys()[0]
			_held_space = GameState.reserve_space(_held_item, job.def.output[_held_item])
			queue_redraw()
			if _walk_to(job.entrance()):
				state = State.TO_WORKPLACE
				note = "Carrying %s to %s" % [input, job.def.name]
			else:
				_wait("Can't reach workplace")
		State.TO_WORKPLACE:
			if job == null:
				_reset()
				return
			carrying = ""
			carry_amount = 0
			queue_redraw()
			task = Task.PRODUCE
			state = State.WORKING
			timer = job.def.work_time
			note = "Working"
		State.TO_DEPOSIT:
			if is_instance_valid(_storage):
				var held := _held_space if _held_item == carrying else 0
				if held > 0:
					_held_space = 0
				carry_amount -= GameState.store(carrying, carry_amount, held)
				if carry_amount <= 0:
					carrying = ""
					carry_amount = 0
				queue_redraw()
			_wait(note, 0.3)
		State.WANDER:
			state = State.IDLE
			timer = randf_range(2.0, 5.0)


func _finish_work() -> void:
	if job == null:
		_reset()
		return
	var def := job.def
	var amount := 0
	var item := ""
	match task:
		Task.GATHER:
			amount = world.harvest(_target_tile, def.gather_terrain, def.yield)
			item = def.resource
		Task.PLANT:
			world.plant_field(_target_tile)
		Task.HARVEST:
			amount = world.harvest_field(_target_tile)
			item = def.resource
		Task.PRODUCE:
			item = def.output.keys()[0]
			amount = def.output[item]
	_release_target()
	task = Task.NONE
	if amount > 0:
		carrying = item
		carry_amount = amount
		queue_redraw()
		_go_deposit()
	else:
		_wait(note, 0.2)


func _draw() -> void:
	var body := COLOR_UNEMPLOYED
	if job != null:
		body = (job.def.color as Color).lightened(0.25)
	draw_circle(Vector2(0, 3), 5.0, body.darkened(0.6))
	draw_circle(Vector2(0, 3), 4.0, body)
	draw_circle(Vector2(0, -4), 3.0, COLOR_SKIN)
	if carrying != "":
		var c := ItemDefs.color_of(carrying)
		draw_rect(Rect2(Vector2(3, -3), Vector2(6, 6)), c)
		draw_rect(Rect2(Vector2(3, -3), Vector2(6, 6)), c.darkened(0.5), false, 1.0)
	if missed_meals > 0:
		draw_circle(Vector2(-5, -8), 2.0, Color(0.9, 0.15, 0.1))


func set_missed_meals(value: int) -> void:
	missed_meals = value
	queue_redraw()
