extends Node
## Performance benchmark: loads the game, adds villagers and raiders, and
## measures frame time over a few hundred frames at 4x speed.
##   godot --headless --path . res://tools/verify/bench.tscn -- --villagers=300 --enemies=60

const FRAMES := 400
const WARMUP := 60


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and "=" in a:
			args[a.substr(2).get_slice("=", 0)] = int(a.get_slice("=", 1))
	GameState.hints_enabled = false
	GameState.new_game_seed = 12345
	var main: Node = load("res://scenes/main.tscn").instantiate()
	main.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(main)
	await get_tree().process_frame
	var world: WorldMap = main.world
	GameState.add_resource("bread", 150)
	for i in args.get("villagers", 100):
		main.citizens.restore_villager(world.keep, null, "Bench", 20.0, 0)
	var raids: RaidDirector = main.raids
	for i in args.get("enemies", 0):
		var edge := raids._pick_spawn_tile()
		var e := Enemy.new()
		e.setup(world, ["goblin", "goblin_brute", "orc", "wolf_rider"][i % 4], edge, edge)
		world.unit_root.add_child(e)
	if args.get("enemies", 0) > 0:
		world.raid_active = true
	GameState.set_speed(3)
	var times := PackedFloat64Array()
	var last := Time.get_ticks_usec()
	for i in FRAMES + WARMUP:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		if i >= WARMUP:
			times.append((now - last) / 1000.0)
		last = now
	var sorted := times.duplicate()
	sorted.sort()
	var total := 0.0
	for t in times:
		total += t
	print("BENCH villagers=%d enemies=%d agents=%d avg=%.2fms p95=%.2fms max=%.2fms" % [
		main.citizens.villagers.size(), world.enemies.size(),
		main.citizens.villagers.size() + world.enemies.size(),
		total / times.size(), sorted[int(sorted.size() * 0.95)], sorted[-1]])
	get_tree().quit()
