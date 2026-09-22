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
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	world = main.world
	GameState.notified.connect(func(m: String) -> void: report.messages.append(m))
	main.build.message.connect(func(m: String) -> void: report.messages.append(m))
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
	elif step.has("screenshot"):
		return await _screenshot(step.screenshot)
	elif step.has("state"):
		_write_json("%s.state.json" % step.state, _snapshot())
	elif step.has("expect"):
		return _check(step.expect)
	elif step.has("setup_grant"):
		# Test-only shortcut: skips waiting for gatherers. Recorded in the report.
		for item: String in step.setup_grant:
			GameState.add_resource(item, int(step.setup_grant[item]))
		report.setup_shortcuts.append(step)
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


func _move_mouse(pos: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	ev.global_position = pos
	Input.parse_input_event(ev)
	await _frames(2)


func _click(pos: Vector2, button: MouseButton) -> void:
	await _move_mouse(pos)
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
	await _click(btn.get_global_rect().get_center(), MOUSE_BUTTON_LEFT)
	return "ok (clicked '%s')" % btn.text


func _find_button(node: Node, text: String) -> Button:
	if node is Button and node.is_visible_in_tree() and text in node.text:
		return node
	for child in node.get_children():
		var found := _find_button(child, text)
		if found != null:
			return found
	return null


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
		"tier": main.progression.tier_name(),
		"raid_phase": ["CALM", "WARNING", "ACTIVE"][main.raids.phase],
		"raids_survived": main.raids.raids_survived,
		"enemies": world.enemies.size(),
		"buildings": buildings,
		"roads": world.roads.size(),
		"build_mode": ["NONE", "BUILD", "ROAD", "DEMOLISH"][main.build.mode],
		"selected_building": main.build.selected.title if main.build.selected != null else "",
		"squads": main.military.squads.map(func(s: Squad) -> Dictionary: return {
			"name": s.display_name(), "troops": s.troops.size(), "selected": s.selected,
			"mode": "AUTO" if s.mode == Squad.Mode.AUTO else "MANUAL"}),
		"research_done": main.research.completed.duplicate(),
		"research_queue": main.research.queue.duplicate(),
		"visible_text": _visible_text(main.hud),
		"messages": report.messages.duplicate(),
	}


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
	for key in ["tier", "raid_phase", "build_mode", "selected_building"]:
		if expect.has(key) and s[key] != expect[key]:
			problems.append("%s '%s' != '%s'" % [key, s[key], expect[key]])
	if expect.has("text") and not s.visible_text.any(func(t: String) -> bool: return expect.text in t):
		problems.append("no visible text containing '%s'" % expect.text)
	if expect.has("message") and not s.messages.any(func(m: String) -> bool: return expect.message in m):
		problems.append("no message containing '%s'" % expect.message)
	for key: String in expect.get("min", {}):
		var have: float = s.population if key == "population" else (s.roads if key == "roads" else s.resources.get(key, 0))
		if have < float(expect["min"][key]):
			problems.append("%s %s < %s" % [key, have, expect["min"][key]])
	if expect.has("squad_troops_min"):
		var troops: int = s.squads.reduce(func(acc: int, q: Dictionary) -> int: return acc + q.troops, 0)
		if troops < int(expect.squad_troops_min):
			problems.append("troops %d < %d" % [troops, expect.squad_troops_min])
	if expect.has("squad_mode") and not s.squads.any(func(q: Dictionary) -> bool: return q.mode == expect.squad_mode):
		problems.append("no squad in mode %s" % expect.squad_mode)
	if expect.has("research_done") and not expect.research_done in s.research_done:
		problems.append("research %s not done" % expect.research_done)
	return "ok" if problems.is_empty() else "FAIL " + "; ".join(problems)


func _write_json(name: String, data: Variant) -> void:
	var f := FileAccess.open(out_dir.path_join(name), FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "  "))


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
