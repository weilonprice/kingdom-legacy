extends Node
## Verification driver. Loads the real game (scenes/main.tscn), then plays a
## JSON scenario by injecting real mouse/keyboard events through
## Input.parse_input_event, so every action takes the same path a player's
## would. Writes evidence (screenshots, state snapshots, report.json) to --out.
##
## Launch via tools/verify/run.sh, not directly. Scenario step reference:
## tools/verify/README.md.

var main: Node2D
var world: WorldMap
var out_dir := ""
var report := {"steps": [], "failures": [], "messages": [], "setup_shortcuts": []}
## Named tiles (keep-relative) produced by find_site.
var aliases := {}
## Snapshots saved by `state` steps, for expect_same_as.
var snapshots := {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args := _parse_args()
	out_dir = args.get("out", "")
	if out_dir == "" or not args.has("scenario"):
		push_error("driver needs --scenario=<json> and --out=<dir>")
		get_tree().quit(2)
		return
	var scenario: Array = JSON.parse_string(FileAccess.get_file_as_string(args.scenario))
	# Headless starts with a tiny window, which would put most HUD buttons
	# outside it; match the windowed layout so the same clicks land.
	get_window().size = Vector2i(1600, 900)
	if DisplayServer.get_name() != "headless":
		# macOS throttles and stops drawing windows hidden behind others, which
		# starves the game of frames. Keep the verify window in front.
		get_window().always_on_top = true
		DisplayServer.window_move_to_foreground()
	# Hints would cover top-left tiles that scenarios click; scenarios that
	# test them turn them on with setup_hints.
	GameState.hints_enabled = false
	# Never touch the player's own saves or settings.
	Settings.use_file("user://verify-settings.cfg")
	GameState.save_dir = "user://verify-saves"
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://verify-saves/savegame.json"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://verify-saves/autosave.json"))
	await _start_game()
	# Let the window finish resizing/raising and the HUD lay out before the
	# first click, or early clicks can land on stale button positions.
	await get_tree().create_timer(1.0, true, false, true).timeout
	await _frames(5)
	# The first injected click after the window appears is swallowed; spend it
	# on empty sky above the Keep (selects nothing, costs nothing).
	await _click(_screen_of([0, -8]), MOUSE_BUTTON_LEFT)
	main.build.select_building(null)
	GameState.notified.connect(func(m: String) -> void: report.messages.append(m))
	main.build.message.connect(_record_message)
	report["seed"] = world.map_seed
	report["display"] = DisplayServer.get_name()
	print("VERIFY READY seed=%d display=%s" % [world.map_seed, DisplayServer.get_name()])
	for i in scenario.size():
		var step: Dictionary = scenario[i]
		print("VERIFY STEP %d %s" % [i, JSON.stringify(step)])
		var result: String = await _run_step(step)
		report.steps.append({"index": i, "step": step, "result": result})
		if result.begins_with("FAIL"):
			report.failures.append("step %d: %s" % [i, result])
			print("VERIFY %s" % result)
	_write_json("report.json", report)
	var ok: bool = report.failures.is_empty()
	print("VERIFY DONE %s failures=%d out=%s" % ["PASS" if ok else "FAIL", report.failures.size(), out_dir])
	get_tree().quit(0 if ok else 1)


## Instantiates the game scene under the driver (again, after a load).
func _start_game() -> void:
	main = load("res://scenes/main.tscn").instantiate()
	# The driver itself must keep running while the game is paused, but the
	# game must not inherit that, or pause and game over wouldn't stop it.
	main.process_mode = Node.PROCESS_MODE_PAUSABLE
	# Loading a save normally changes scene, which would free the driver.
	main.reloader = _reload_game
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	world = main.world


func _reload_game() -> void:
	# Called from inside the old game's input handling: swap on the next frame.
	await get_tree().process_frame
	var old := main
	remove_child(old)
	old.queue_free()
	await _start_game()
	main.build.message.connect(_record_message)


func _record_message(m: String) -> void:
	report.messages.append(m)


func _parse_args() -> Dictionary:
	var args := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and "=" in a:
			args[a.substr(2).get_slice("=", 0)] = a.get_slice("=", 1)
	return args


# --- Steps ------------------------------------------------------------------

func _run_step(step: Dictionary) -> String:
	if step.has("include"):
		return await _include(step.include)
	elif step.has("wait_until"):
		return await _wait_until(step.wait_until, float(step.get("timeout", 120)))
	elif step.has("wait"):
		await get_tree().create_timer(step.wait, true, false, true).timeout
	elif step.has("wait_game"):
		await get_tree().create_timer(step.wait_game, false).timeout
	elif step.has("key"):
		await _press_key(step.key)
	elif step.has("click_button"):
		return await _click_button(step.click_button)
	elif step.has("click_tile"):
		await _click(_screen_of(step.click_tile), MOUSE_BUTTON_LEFT)
	elif step.has("right_click_tile"):
		await _click(_screen_of(step.right_click_tile), MOUSE_BUTTON_RIGHT)
	elif step.has("drag_tile"):
		await _drag(_screen_of(step.drag_tile[0]), _screen_of(step.drag_tile[1]))
	elif step.has("find_site"):
		return _find_site(step.find_site)
	elif step.has("find_crossing"):
		return _find_crossing(step.find_crossing)
	elif step.has("click_minimap"):
		# A point on the minimap as fractions of its width and height.
		var mm: Control = main.hud._minimap
		if not mm.is_visible_in_tree():
			return "FAIL minimap is hidden"
		var f: Array = step.click_minimap
		var r: Rect2 = mm._map.get_global_rect()
		await _click(r.position + r.size * Vector2(f[0], f[1]), MOUSE_BUTTON_LEFT)
		return "ok"
	elif step.has("pan_to"):
		# Test-only: centres the camera on a tile (a player would scroll there).
		main.camera.position = world.tile_center(_tile_of(step.pan_to))
		report.setup_shortcuts.append(step)
		await _frames(3)
	elif step.has("screenshot"):
		return await _screenshot(step.screenshot)
	elif step.has("state"):
		snapshots[step.state] = _snapshot()
		_write_json("%s.state.json" % step.state, snapshots[step.state])
	elif step.has("expect_same_as"):
		return _same_as(step.expect_same_as)
	elif step.has("expect"):
		return _check(step.expect)
	elif step.has("setup_grant"):
		# Test-only shortcut: skips waiting for gatherers. Recorded in the report.
		var short := PackedStringArray()
		for item: String in step.setup_grant:
			var before := GameState.count(item)
			GameState.add_resource(item, int(step.setup_grant[item]))
			var added := GameState.count(item) - before
			if added < int(step.setup_grant[item]):
				short.append("%s %d/%d" % [item, added, step.setup_grant[item]])
		report.setup_shortcuts.append(step)
		if not short.is_empty():
			return "ok (storage full, only added %s)" % ", ".join(short)
	elif step.has("setup_tier"):
		# Test-only: advance straight to a tier by name.
		while main.progression.tier_name() != step.setup_tier and not main.progression.is_max_tier():
			main.progression._advance()
		report.setup_shortcuts.append(step)
		return "ok (tier %s)" % main.progression.tier_name()
	elif step.has("setup_ignite"):
		# Test-only: sets the building on this tile alight (as a raider would).
		var b: Building = world.occupancy.get(_tile_of(step.setup_ignite))
		report.setup_shortcuts.append(step)
		if b == null or not b.ignite():
			return "FAIL nothing flammable at %s" % str(step.setup_ignite)
		return "ok (%s burning)" % b.title
	elif step.has("setup_research"):
		# Test-only: completes research topics instantly.
		for id: String in step.setup_research:
			main.research._complete(id)
		report.setup_shortcuts.append(step)
	elif step.has("setup_season"):
		# Test-only: jump to a season ("none" = the original art, no season art).
		report.setup_shortcuts.append(step)
		if step.setup_season == "none":
			Art.season = ""
			world.renderer.rebuild_art()
		else:
			main.seasons.set_season(Seasons.ORDER.find(step.setup_season), true)
		await _frames(3)
		return "ok (%s)" % step.setup_season
	elif step.has("setup_merchant"):
		# Test-only: a merchant of that type arrives at the Trading Post now.
		report.setup_shortcuts.append(step)
		if main.trade.post() == null:
			return "FAIL no Trading Post with road access"
		main.trade.arrive(step.setup_merchant, main.trade.post().entrance())
		return "ok (%s)" % main.trade.merchant_name()
	elif step.has("move_mouse"):
		# Viewport position, e.g. against the window edge. Edge scrolling
		# ignores unfocused windows, so bring ours to the front first.
		if DisplayServer.get_name() != "headless":
			DisplayServer.window_move_to_foreground()
			get_window().grab_focus()
			await _frames(5)
		await _move_mouse(Vector2(step.move_mouse[0], step.move_mouse[1]))
		if DisplayServer.get_name() != "headless" and not get_window().has_focus():
			return "ok (window has no focus; edge checks will show it)"
	elif step.has("gesture"):
		# Trackpad input: {"magnify": 1.5, "at": [x, y]} pinches (factor per
		# event, sent in 4 steps); {"pan": [dx, dy]} is a two-finger scroll.
		var g: Dictionary = step.gesture
		var at := _to_window(Vector2(g.get("at", [800, 450])[0], g.get("at", [800, 450])[1]))
		for i in 4:
			var ev: InputEventGesture
			if g.has("magnify"):
				ev = InputEventMagnifyGesture.new()
				ev.factor = pow(float(g.magnify), 0.25)
			else:
				ev = InputEventPanGesture.new()
				ev.delta = Vector2(g.pan[0], g.pan[1]) * 0.25
			ev.position = at
			Input.parse_input_event(ev)
			await _frames(1)
		await _frames(2)
	elif step.has("reload_settings"):
		# Re-read the settings file, as the next launch would.
		Settings.load_file()
	elif step.has("setup_cut_forest"):
		# Test-only: fells the forest tile nearest a keep-relative spot (one
		# with forest beside it and nothing built nearby), as a woodcutter
		# would. Saved as alias "cut".
		report.setup_shortcuts.append(step)
		var near := _tile_of(step.setup_cut_forest)
		var best := WorldMap.INVALID_TILE
		for r in 30:
			for t in _ring(near, r):
				if best == WorldMap.INVALID_TILE and world.is_in_bounds(t) \
						and world.get_terrain(t) == Terrain.FOREST and world._touches_trees(t) \
						and _clear_around(t):
					best = t
		if best == WorldMap.INVALID_TILE:
			return "FAIL no forest tile to cut near %s" % near
		while world.get_terrain(best) == Terrain.FOREST:
			world.harvest(best, Terrain.FOREST, 0)
		aliases["cut"] = best
		return "ok (cut %s)" % best
	elif step.has("setup_forest_time"):
		# Test-only: runs forest growth forward this many game seconds.
		report.setup_shortcuts.append(step)
		world._grow_forests(float(step.setup_forest_time))
	elif step.has("setup_hints"):
		GameState.hints_enabled = bool(step.setup_hints)
		report.setup_shortcuts.append(step)
	elif step.has("setup_delay_raids"):
		# Test-only: pushes the next natural raid this many game seconds out.
		main.raids._timer = maxf(main.raids._timer, float(step.setup_delay_raids))
		report.setup_shortcuts.append(step)
	elif step.has("setup_lair"):
		# Test-only: puts a goblin lair at a keep-relative tile.
		var lair: Enemy = main.raids.spawn_lair(world.nearest_walkable(_tile_of(step.setup_lair)))
		report.setup_shortcuts.append(step)
		return "ok (lair at %s)" % lair.current_tile()
	elif step.has("setup_spawn"):
		# Test-only: {"setup_spawn": {"enemy": "troll", "count": 1, "at": [dx, dy]}}
		var spec: Dictionary = step.setup_spawn
		var tile := world.nearest_walkable(_tile_of(spec.at))
		for i in int(spec.get("count", 1)):
			var enemy := Enemy.new()
			enemy.setup(world, spec.enemy, tile, main.raids._pick_spawn_tile())
			world.unit_root.add_child(enemy)
		report.setup_shortcuts.append(step)
		return "ok (%s x%d at %s)" % [spec.enemy, int(spec.get("count", 1)), tile]
	else:
		return "FAIL unknown step"
	return "ok"


## Runs another scenario file's steps inline (path relative to scenarios/).
func _include(file: String) -> String:
	var steps: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tools/verify/scenarios/" + file))
	for sub: Dictionary in steps:
		var result: String = await _run_step(sub)
		if result.begins_with("FAIL"):
			return "FAIL in %s %s: %s" % [file, JSON.stringify(sub), result]
	return "ok (%d steps from %s)" % [steps.size(), file]


## Polls an expect-style condition every 0.5s (real time) until it holds.
func _wait_until(expect: Dictionary, timeout: float) -> String:
	var waited := 0.0
	var result := _check(expect)
	while result != "ok" and waited < timeout:
		await get_tree().create_timer(0.5, true, false, true).timeout
		waited += 0.5
		result = _check(expect)
	return "ok (after %.1fs)" % waited if result == "ok" else "FAIL timed out after %ds: %s" % [timeout, result]


func _press_key(spec: String) -> void:
	var ev := InputEventKey.new()
	var parts := spec.split("+")
	ev.keycode = OS.find_keycode_from_string(parts[parts.size() - 1])
	ev.ctrl_pressed = "CTRL" in parts
	ev.shift_pressed = "SHIFT" in parts
	ev.pressed = true
	Input.parse_input_event(ev)
	await _frames(2)
	var up := ev.duplicate()
	up.pressed = false
	Input.parse_input_event(up)
	await _frames(2)


## Positions are in viewport coordinates (what get_global_rect and the
## camera give); events carry window pixels, which differ under UI scale.
func _to_window(pos: Vector2) -> Vector2:
	return get_tree().root.get_final_transform() * pos


func _move_mouse(pos: Vector2) -> void:
	pos = _to_window(pos)
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	ev.global_position = pos
	Input.parse_input_event(ev)
	await _frames(2)


func _click(pos: Vector2, button: MouseButton) -> void:
	await _move_mouse(pos)
	# Moving off a control whose tooltip is showing closes the tooltip; give
	# that a few frames so it doesn't swallow the press.
	await _frames(6)
	pos = _to_window(pos)
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.position = pos
		ev.global_position = pos
		ev.button_index = button
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await _frames(2)


func _drag(from: Vector2, to: Vector2) -> void:
	await _move_mouse(from)
	from = _to_window(from)
	to = _to_window(to)
	var down := InputEventMouseButton.new()
	down.position = from
	down.global_position = from
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	Input.parse_input_event(down)
	await _frames(2)
	for i in range(1, 9):
		var ev := InputEventMouseMotion.new()
		ev.position = from.lerp(to, i / 8.0)
		ev.global_position = ev.position
		ev.button_mask = MOUSE_BUTTON_MASK_LEFT
		Input.parse_input_event(ev)
		await _frames(1)
	await _frames(2)
	var up := down.duplicate()
	up.position = to
	up.global_position = to
	up.pressed = false
	Input.parse_input_event(up)
	await _frames(2)


func _click_button(text: String) -> String:
	var btn := _find_button(get_tree().root, text)
	if btn == null:
		return "FAIL no visible button containing '%s'" % text
	# Hover first, then aim again: panels can re-lay themselves out while
	# the cursor travels (a person tracks the button the same way).
	await _move_mouse(btn.get_global_rect().get_center())
	await _frames(3)
	if not is_instance_valid(btn) or not btn.is_visible_in_tree():
		return "FAIL button '%s' went away" % text
	await _click(btn.get_global_rect().get_center(), MOUSE_BUTTON_LEFT)
	# Windowed runs occasionally lose a click while macOS shuffles window
	# focus. Toggle buttons (category tabs, speeds) show whether it landed.
	if btn.toggle_mode and not btn.button_pressed and is_instance_valid(btn):
		var hovered := get_viewport().gui_get_hovered_control()
		await _click(btn.get_global_rect().get_center(), MOUSE_BUTTON_LEFT)
		return "ok (clicked '%s' after one retry; first click hovered %s)" % [
			btn.text, hovered.get_path() if hovered != null else "nothing"]
	var under := get_viewport().gui_get_hovered_control()
	return "ok (clicked '%s'; cursor over %s)" % [btn.text, under.name if under != null else "nothing"]


func _find_button(node: Node, text: String) -> Button:
	if node is Button and node.is_visible_in_tree() and text in node.text:
		return node
	for child in node.get_children():
		var found := _find_button(child, text)
		if found != null:
			return found
	return null


func _ring(center: Vector2i, r: int) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			if maxi(absi(dx), absi(dy)) == r:
				tiles.append(center + Vector2i(dx, dy))
	return tiles


## No building, road, door or field on or beside `t`.
func _clear_around(t: Vector2i) -> bool:
	for off in WorldMap.NEIGHBORS + [Vector2i.ZERO]:
		var n: Vector2i = t + off
		if world.occupancy.has(n) or world.roads.has(n) or world.entrances.has(n) or world.fields.has(n):
			return false
	return true


## Keep-relative tile offset ([dx, dy]) or a find_site alias -> screen position.
func _tile_of(ref: Variant) -> Vector2i:
	if ref is String:
		return aliases[ref]
	return world.keep.entrance() + Vector2i(int(ref[0]), int(ref[1]))


func _screen_of(ref: Variant) -> Vector2:
	return get_viewport().get_canvas_transform() * world.tile_center(_tile_of(ref))


## Finds where a building could go and stores the tile to click as an alias.
## {"building": "house", "as": "h1", "entrance_on_road": true, "near": [dx, dy]}
func _find_site(spec: Dictionary) -> String:
	var id: String = spec.building
	var size: Vector2i = BuildingDefs.get_def(id).size
	var near: Vector2i = world.keep.entrance() + Vector2i(spec.get("near", [0, 0])[0], spec.get("near", [0, 0])[1])
	for r in 20:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var origin := near + Vector2i(dx, dy)
				if world.can_place_building(id, origin) != "":
					continue
				if spec.get("entrance_on_road", false) and not world.is_road(BuildingDefs.entrance_of(origin, size)):
					continue
				var cursor := origin + Vector2i(int(size.x * 0.5), int(size.y * 0.5))
				aliases[spec["as"]] = cursor
				return "ok (%s at keep%+d,%+d)" % [id, cursor.x - world.keep.entrance().x, cursor.y - world.keep.entrance().y]
	return "FAIL no site for %s" % id


## Finds a straight north-south or east-west water crossing near a tile:
## land, then `min`..`max` water tiles, then land. Names the land tile on
## each bank, and the first water tile as "<as>_water". Read-only.
## {"as": "south_bank", "as_end": "north_bank", "near": [0, -20], "min": 1, "max": 5}
func _find_crossing(spec: Dictionary) -> String:
	var near := _tile_of(spec.get("near", [0, 0]))
	var lo := int(spec.get("min", 1))
	var hi := int(spec.get("max", 5))
	for r in 30:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r:
					continue
				var start := near + Vector2i(dx, dy)
				if not world.is_in_bounds(start) or world.get_terrain(start) == Terrain.WATER \
						or world.occupancy.has(start):
					continue
				for dir in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
					var n := 0
					var t: Vector2i = start + dir
					while world.is_in_bounds(t) and world.get_terrain(t) == Terrain.WATER and n <= hi:
						n += 1
						t += dir
					if n >= lo and n <= hi and world.is_in_bounds(t) and not world.occupancy.has(t):
						var base := world.keep.entrance()
						aliases[spec["as"]] = start
						aliases[spec["as_end"]] = t
						aliases[spec["as"] + "_water"] = start + dir
						return "ok (%d water tiles from keep%+d,%+d)" % [n, start.x - base.x, start.y - base.y]
	return "FAIL no crossing of %d-%d water tiles" % [lo, hi]


func _screenshot(name: String) -> String:
	if DisplayServer.get_name() == "headless":
		return "skipped (headless has no renderer)"
	# macOS stops drawing a window that is fully covered or minimized; don't
	# wait forever for a frame that will never come.
	var drawn := [false]
	RenderingServer.frame_post_draw.connect(func() -> void: drawn[0] = true, CONNECT_ONE_SHOT)
	var waited := 0.0
	while not drawn[0] and waited < 3.0:
		await get_tree().create_timer(0.1, true, false, true).timeout
		waited += 0.1
	if not drawn[0]:
		return "FAIL screenshot '%s': the game window is not drawing (covered or minimized?)" % name
	get_viewport().get_texture().get_image().save_png(out_dir.path_join(name + ".png"))
	return "ok"


# --- Observation ------------------------------------------------------------

func _snapshot() -> Dictionary:
	var buildings := {}
	for b in world.buildings:
		buildings[b.def_id] = buildings.get(b.def_id, 0) + 1
	return {
		"resources": GameState.resources.duplicate(),
		"capacity": GameState.capacity.duplicate(),
		"population": GameState.population,
		"happiness": snappedf(GameState.happiness, 0.1),
		"tax_rate": NeedDefs.TAX_RATES[GameState.tax_rate].name,
		"house_levels": world.buildings.filter(func(b: Building) -> bool: return b.def.has("level_bonus")).map(
			func(b: Building) -> int: return b.level),
		"tier": main.progression.tier_name(),
		"raid_phase": ["CALM", "WARNING", "ACTIVE"][main.raids.phase],
		"raids_survived": main.raids.raids_survived,
		"enemies": world.enemies.size(),
		"enemy_types": _count_enemy_types(),
		"lairs": world.lairs().size(),
		"game_over": GameState.game_over,
		"hint": main.hud._hints.current_hint() if GameState.hints_enabled else "",
		"final_siege": main.raids.final_siege,
		"boss_hp": _boss_hp(),
		"fields": world.fields.size(),
		"camera_tile": [world.world_to_tile(main.camera.position).x, world.world_to_tile(main.camera.position).y],
		"minimap_visible": main.hud._minimap.visible,
		"sounds": Sound.played.duplicate(),
		"music_mood": Music.mood,
		"merchant": main.trade.merchant_name() if main.trade.is_open() else "",
		"settings": Settings.values.duplicate(),
		"castle": main.castle.title(),
		"castle_size": world.keep.size.x,
		"castle_building": main.castle.is_building(),
		"castle_progress": snappedf(main.castle.progress(), 0.01),
		"builders": world.keep.workers.size(),
		"keep_hp": roundi(world.keep.health.max_hp),
		"zoom": snappedf(main.camera.zoom.x, 0.001),
		"fps": Engine.get_frames_per_second(),
		"min_zoom": snappedf(main.camera.min_zoom(), 0.001),
		"saplings": world.saplings.size(),
		"cleared": world.cleared.size(),
		"forest": Array(world.terrain).count(Terrain.FOREST),
		"speed": GameState.speed,
		"ui_scale": get_window().content_scale_factor,
		"music_notes": Music.notes_played,
		"bridges": world.roads.keys().filter(func(t: Vector2i) -> bool: return world.is_bridge(t)).size(),
		"bridges_walkable": world.roads.keys().all(func(t: Vector2i) -> bool: return world.is_walkable(t)),
		"season": main.seasons.current(),
		"warm": main.seasons.warm,
		"art_season": Art.season,
		"employed": GameState.employed,
		"lair_hp": world.lairs().map(func(l: Enemy) -> int: return int(l.health.hp)),
		"wild": world.wild.size(),
		"troop_detail": get_tree().get_nodes_in_group("troops").map(func(t: Troop) -> String:
			return "%s@%s hp%d ->%s" % [t.unit_id, t.current_tile(), t.health.hp,
				t.target.def.name if t.target != null and is_instance_valid(t.target) else "-"]),
		"call_to_arms": world.call_to_arms,
		"villagers_fighting": get_tree().get_nodes_in_group("villagers").filter(
			func(v: Villager) -> bool: return v.state == Villager.State.FIGHTING).size(),
		"burning": world.buildings.filter(func(b: Building) -> bool: return b.burning).size(),
		"buildings": buildings,
		"roads": world.roads.size(),
		"night": world.is_night,
		"villagers_awake": get_tree().get_nodes_in_group("villagers").filter(
			func(v: Villager) -> bool: return v.visible).size(),
		"stored": _sum_by_building("inventory"),
		"piles": _sum_by_building("output_stock"),
		"build_mode": BuildController.Mode.keys()[main.build.mode],
		"selected_building": main.build.selected.title if main.build.selected != null else "",
		"squads": main.military.squads.map(func(s: Squad) -> Dictionary: return {
			"name": s.display_name(), "troops": s.troops.size(), "selected": s.selected,
			"mode": "AUTO" if s.mode == Squad.Mode.AUTO else "MANUAL"}),
		"research_done": main.research.completed.duplicate(),
		"research_queue": main.research.queue.duplicate(),
		"visible_text": _visible_text(main.hud),
		"messages": report.messages.duplicate(),
	}


## The dragon's HP as a percentage, or -1 when none is on the map.
func _boss_hp() -> int:
	for e in world.enemies:
		if e.def.behavior == "dragon":
			return roundi(e.health.hp / e.health.max_hp * 100.0)
	return -1


func _count_enemy_types() -> Dictionary:
	var counts := {}
	for e in world.enemies:
		counts[e.enemy_id] = counts.get(e.enemy_id, 0) + 1
	return counts


func _visible_text(node: Node) -> Array:
	var texts := []
	if node is CanvasItem and not node.is_visible_in_tree():
		return texts
	if (node is Label or node is Button) and node.text != "":
		texts.append(node.text)
	for child in node.get_children():
		texts.append_array(_visible_text(child))
	return texts


## {"buildings": {"house": 1}, "tier": "Village", "text": "Farm", "message": "stole",
##  "min": {"population": 4, "wood": 10}, "raid_phase": "ACTIVE", "squad_troops_min": 1}
func _check(expect: Dictionary) -> String:
	var s := _snapshot()
	var problems := []
	for id: String in expect.get("buildings", {}):
		if s.buildings.get(id, 0) != int(expect.buildings[id]):
			problems.append("%s count %d != %d" % [id, s.buildings.get(id, 0), expect.buildings[id]])
	for id: String in expect.get("buildings_min", {}):
		if s.buildings.get(id, 0) < int(expect.buildings_min[id]):
			problems.append("%s count %d < %d" % [id, s.buildings.get(id, 0), expect.buildings_min[id]])
	for id: String in expect.get("buildings_max", {}):
		if s.buildings.get(id, 0) > int(expect.buildings_max[id]):
			problems.append("%s count %d > %d" % [id, s.buildings.get(id, 0), expect.buildings_max[id]])
	for key in ["tier", "raid_phase", "build_mode", "selected_building", "season", "music_mood", "merchant", "castle"]:
		if expect.has(key) and s[key] != expect[key]:
			problems.append("%s '%s' != '%s'" % [key, s[key], expect[key]])
	if expect.has("text") and not s.visible_text.any(func(t: String) -> bool: return expect.text in t):
		problems.append("no visible text containing '%s'" % expect.text)
	if expect.has("text_absent") and s.visible_text.any(func(t: String) -> bool: return expect.text_absent in t):
		problems.append("visible text still contains '%s'" % expect.text_absent)
	if expect.has("message") and not s.messages.any(func(m: String) -> bool: return expect.message in m):
		problems.append("no message containing '%s'" % expect.message)
	for key: String in expect.get("min", {}):
		var have := _metric(s, key)
		if have < float(expect["min"][key]):
			problems.append("%s %s < %s" % [key, have, expect["min"][key]])
	for key: String in expect.get("max", {}):
		var have := _metric(s, key)
		if have > float(expect["max"][key]):
			problems.append("%s %s > %s" % [key, have, expect["max"][key]])
	if expect.has("call_to_arms") and s.call_to_arms != expect.call_to_arms:
		problems.append("call_to_arms %s != %s" % [s.call_to_arms, expect.call_to_arms])
	if expect.has("hint") and not expect.hint in s.hint:
		problems.append("hint '%s' doesn't contain '%s'" % [s.hint, expect.hint])
	if expect.has("minimap_visible") and s.minimap_visible != expect.minimap_visible:
		problems.append("minimap_visible %s != %s" % [s.minimap_visible, expect.minimap_visible])
	for n: String in expect.get("sounds_min", {}):
		if s.sounds.get(n, 0) < int(expect.sounds_min[n]):
			problems.append("sound %s played %d < %s" % [n, s.sounds.get(n, 0), expect.sounds_min[n]])
	if expect.has("camera_near"):
		var want: Vector2i = Vector2i(int(expect.camera_near[0]), int(expect.camera_near[1]))
		var have := Vector2i(s.camera_tile[0], s.camera_tile[1])
		if Vector2(have).distance_to(Vector2(want)) > float(expect.camera_near[2]):
			problems.append("camera at %s, not within %s of %s" % [have, expect.camera_near[2], want])
	if expect.has("bridges_walkable") and s.bridges_walkable != expect.bridges_walkable:
		problems.append("bridges_walkable %s != %s" % [s.bridges_walkable, expect.bridges_walkable])
	if expect.has("game_over") and s.game_over != expect.game_over:
		problems.append("game_over %s != %s" % [s.game_over, expect.game_over])
	if expect.has("night") and s.night != expect.night:
		problems.append("night %s != %s" % [s.night, expect.night])
	for field in ["stored_min", "pile_min"]:
		var have_by_building: Dictionary = s.stored if field == "stored_min" else s.piles
		for id: String in expect.get(field, {}):
			for item: String in expect[field][id]:
				var have: int = have_by_building.get(id, {}).get(item, 0)
				if have < int(expect[field][id][item]):
					problems.append("%s %s.%s %d < %s" % [field, id, item, have, expect[field][id][item]])
	if expect.has("tax_rate") and s.tax_rate != expect.tax_rate:
		problems.append("tax_rate '%s' != '%s'" % [s.tax_rate, expect.tax_rate])
	if expect.has("house_level_min"):
		var want: Dictionary = expect.house_level_min
		var have: int = s.house_levels.filter(func(l: int) -> bool: return l >= int(want.level)).size()
		if have < int(want.count):
			problems.append("homes at level %d+: %d < %d" % [want.level, have, want.count])
	if expect.has("squad_troops_min"):
		var troops: int = s.squads.reduce(func(acc: int, q: Dictionary) -> int: return acc + q.troops, 0)
		if troops < int(expect.squad_troops_min):
			problems.append("troops %d < %d" % [troops, expect.squad_troops_min])
	if expect.has("squad_mode") and not s.squads.any(func(q: Dictionary) -> bool: return q.mode == expect.squad_mode):
		problems.append("no squad in mode %s" % expect.squad_mode)
	if expect.has("button_on_screen"):
		var btn := _find_button(get_tree().root, expect.button_on_screen)
		if btn == null or not get_viewport().get_visible_rect().encloses(btn.get_global_rect()):
			problems.append("button '%s' is %s" % [expect.button_on_screen, "missing" if btn == null else "off-screen at %s" % btn.get_global_rect()])
	for key: String in expect.get("settings", {}):
		var want: Variant = expect.settings[key]
		var have: Variant = s.settings.get(key)
		if have == null or not is_equal_approx(float(have), float(want)):
			problems.append("setting %s = %s, not %s" % [key, have, want])
	if expect.has("camera_moved"):
		# {"since": "<state name>", "min": tiles} or "max": tiles.
		var spec: Dictionary = expect.camera_moved
		var then: Array = snapshots.get(spec.since, {}).get("camera_tile", s.camera_tile)
		var moved := Vector2(s.camera_tile[0] - then[0], s.camera_tile[1] - then[1]).length()
		if moved < float(spec.get("min", 0)) or moved > float(spec.get("max", INF)):
			problems.append("camera moved %.1f tiles since %s (want %s..%s)" % [
				moved, spec.since, spec.get("min", 0), spec.get("max", "any")])
	if expect.has("sapling_at") and not world.saplings.has(_tile_of(expect.sapling_at)):
		problems.append("no sapling at %s" % _tile_of(expect.sapling_at))
	if expect.has("increased"):
		# {"since": "<state>", "forest": 3}: metric grew by at least that much.
		var then: Dictionary = snapshots.get(expect.increased.since, s)
		for key: String in expect.increased:
			if key == "since":
				continue
			var grew := _metric(s, key) - _metric(then, key)
			if grew < float(expect.increased[key]):
				problems.append("%s grew %s since %s, want %s+" % [key, grew, expect.increased.since, expect.increased[key]])
	if expect.has("castle_building") and s.castle_building != expect.castle_building:
		problems.append("castle_building %s != %s" % [s.castle_building, expect.castle_building])
	if expect.has("speed") and s.speed != int(expect.speed):
		problems.append("speed %d != %s" % [s.speed, expect.speed])
	if expect.has("ui_scale") and not is_equal_approx(s.ui_scale, float(expect.ui_scale)):
		problems.append("ui_scale %s != %s" % [s.ui_scale, expect.ui_scale])
	if expect.has("research_done") and not expect.research_done in s.research_done:
		problems.append("research %s not done" % expect.research_done)
	return "ok" if problems.is_empty() else "FAIL " + "; ".join(problems)


## {"state": "before", "keys": ["buildings", "tier"], "close": {"wood": 5}}:
## those snapshot fields equal the named earlier snapshot; `close` resources
## may differ by up to the given amount (work goes on for a few frames).
func _same_as(spec: Dictionary) -> String:
	if not snapshots.has(spec.state):
		return "FAIL no snapshot named %s" % spec.state
	var then: Dictionary = snapshots[spec.state]
	var now := _snapshot()
	var problems := []
	for key: String in spec.get("keys", []):
		if JSON.stringify(now[key]) != JSON.stringify(then[key]):
			problems.append("%s now %s, was %s" % [key, JSON.stringify(now[key]), JSON.stringify(then[key])])
	for item: String in spec.get("close", {}):
		var a: int = now.resources.get(item, 0)
		var b: int = then.resources.get(item, 0)
		if absi(a - b) > int(spec.close[item]):
			problems.append("%s now %d, was %d" % [item, a, b])
	return "ok" if problems.is_empty() else "FAIL " + "; ".join(problems)


## {building id: {item: amount}} summed over buildings of each type.
func _sum_by_building(field: String) -> Dictionary:
	var result := {}
	for b in world.buildings:
		var goods: Dictionary = b.get(field)
		for item: String in goods:
			if not result.has(b.def_id):
				result[b.def_id] = {}
			result[b.def_id][item] = result[b.def_id].get(item, 0) + goods[item]
	return result


## Numeric state for min/max: population, roads, happiness, villagers_awake,
## or a kingdom resource total.
func _metric(s: Dictionary, key: String) -> float:
	if key in ["population", "roads", "happiness", "villagers_awake", "enemies", "burning", "lairs",
			"villagers_fighting", "boss_hp", "bridges", "music_notes", "saplings", "cleared", "forest", "zoom", "min_zoom", "fps", "castle_size", "castle_progress", "builders", "keep_hp"]:
		return float(s[key])
	return float(s.resources.get(key, 0))


func _write_json(name: String, data: Variant) -> void:
	var f := FileAccess.open(out_dir.path_join(name), FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "  "))


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
