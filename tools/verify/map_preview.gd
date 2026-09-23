extends Node
## Saves a terrain overview (one pixel per tile, scaled up) for map seeds, and
## checks that raiders can reach the Keep from the map edge.
##   godot --headless --path . res://tools/verify/map_preview.tscn -- --seeds=12345,7,99 --out=/tmp/maps

const COLORS := [Color(0.2, 0.4, 0.8), Color(0.9, 0.8, 0.5), Color(0.55, 0.7, 0.3),
	Color(0.15, 0.4, 0.15), Color(0.5, 0.5, 0.5), Color(0.6, 0.45, 0.25)]


func _ready() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and "=" in a:
			args[a.substr(2).get_slice("=", 0)] = a.get_slice("=", 1)
	var out: String = args.get("out", "/tmp")
	WorldMap.rivers_enabled = args.get("rivers", "on") != "off"
	DirAccess.make_dir_recursive_absolute(out)
	for s in String(args.get("seeds", "12345")).split(","):
		var world := WorldMap.new()
		world.width = int(args.get("size", "128"))
		world.height = world.width
		add_child(world)
		world.generate(int(s))
		var img := Image.create(world.width, world.height, false, Image.FORMAT_RGB8)
		for y in world.height:
			for x in world.width:
				img.set_pixel(x, y, COLORS[world.get_terrain(Vector2i(x, y))])
		for t: Vector2i in world.roads:
			img.set_pixel(t.x, t.y, Color(0.9, 0.9, 0.9))
		var k := world.keep.origin
		img.fill_rect(Rect2i(k, Vector2i(3, 3)), Color(1, 0, 0))
		img.resize(world.width * 4, world.height * 4, Image.INTERPOLATE_NEAREST)
		img.save_png("%s/map_%s.png" % [out, s])
		# Can every map edge reach the Keep? (fords must connect the map)
		var goal := world.keep.entrance()
		var reach := 0
		var tried := 0
		for i in 40:
			var t := Vector2i((i * 37) % world.width, 0 if i % 2 == 0 else world.height - 1)
			if i % 4 >= 2:
				t = Vector2i(0 if i % 2 == 0 else world.width - 1, (i * 53) % world.height)
			if not world.is_walkable(t):
				continue
			tried += 1
			if not world.find_path(t, goal).is_empty():
				reach += 1
		var water := 0
		for y in world.height:
			for x in world.width:
				if world.get_terrain(Vector2i(x, y)) == Terrain.WATER:
					water += 1
		print("MAP seed=%s edge->keep reachable %d/%d water=%d" % [s, reach, tried, water])
		world.queue_free()
		GameState.reset()
	get_tree().quit()
