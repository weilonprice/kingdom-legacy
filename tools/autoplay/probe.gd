extends Node
## Measures one workplace's real output in a quiet game (no raids): builds a
## woodcutter (or --building) on the starting road, lets it work for
## --minutes game minutes at 4x, and prints produced/min plus what its
## workers were doing (sampled notes).

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and "=" in a:
			args[a.substr(2).get_slice("=", 0)] = a.get_slice("=", 1)
	Engine.max_fps = 0
	Settings.use_file("user://verify-settings.cfg")
	GameState.hints_enabled = false
	GameState.new_game_seed = 12345
	var main: Node2D = load("res://scenes/main.tscn").instantiate()
	main.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(main)
	await get_tree().process_frame
	var world: WorldMap = main.world
	main.raids._timer = 99999.0
	var id: String = args.get("building", "woodcutter")
	GameState.add_resource("bread", 150)
	var site := Vector2i(-1, -1)
	var e := world.keep.entrance()
	for dx in range(-5, 6):
		var origin := e + Vector2i(dx, 1)
		if world.can_place_building(id, origin) == "" and world.is_road(BuildingDefs.entrance_of(origin, BuildingDefs.get_def(id).size)):
			site = origin
			break
	if site.x < 0:
		print("PROBE no site"); get_tree().quit(); return
	var b := world.place_building(id, site)
	GameState.set_speed(3)
	var notes := {}
	var t := 0.0
	var minutes := float(args.get("minutes", "4"))
	while t < minutes * 60.0:
		await get_tree().process_frame
		t += get_process_delta_time()
		for v in b.workers:
			notes[v.note] = notes.get(v.note, 0) + 1
	var produced: int = GameState.stats.produced.get(BuildingDefs.get_def(id).get("resource", "wood"), 0)
	print("PROBE %s workers=%d produced=%d per_min=%.1f night=%s" % [id, b.workers.size(), produced, produced / minutes, world.is_night])
	var total := 0
	for k in notes:
		total += notes[k]
	var keys := notes.keys()
	keys.sort_custom(func(a, c) -> bool: return notes[a] > notes[c])
	for k in keys.slice(0, 8):
		print("  %5.1f%%  %s" % [100.0 * notes[k] / maxi(total, 1), k])
	get_tree().quit()
