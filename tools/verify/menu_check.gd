extends Node
## Menu smoke test: opens the title screen, types a seed, picks Hard, turns
## hints off and clicks New Game with injected mouse events; checks the game
## starts with those settings (after opening and closing Settings); then shows the victory screen and clicks Main
## Menu to check the way back. Lives on the root so it survives scene changes.
##   godot --headless --path . res://tools/verify/menu_check.tscn

var failures := PackedStringArray()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Re-parent to the root so change_scene_to_file doesn't free us.
	get_parent().remove_child.call_deferred(self)
	get_tree().root.add_child.call_deferred(self)
	_run.call_deferred()


func _run() -> void:
	get_window().size = Vector2i(1600, 900)
	Settings.use_file("user://verify-settings.cfg")
	GameState.save_dir = "user://verify-saves"
	for slot in ["savegame", "autosave"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://verify-saves/%s.json" % slot))
	get_tree().change_scene_to_file("res://scenes/menu.tscn")
	await _frames(10)
	var menu := get_tree().current_scene
	_check(menu is MainMenu, "menu scene is up (got %s)" % menu)
	_check(_button(menu, "Continue") == null, "no Continue without a save")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		var out := ProjectSettings.globalize_path("res://.verify-evidence/menu-title.png")
		get_viewport().get_texture().get_image().save_png(out)
	await _click(_button(menu, "Settings"))
	await _frames(5)
	var panel := _find(menu, func(n: Node) -> bool: return n is SettingsPanel) as SettingsPanel
	_check(panel != null and panel.visible, "Settings opens from the title screen")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(
			ProjectSettings.globalize_path("res://.verify-evidence/menu-settings.png"))
	await _click(_button(menu, "Back"))
	await _frames(5)
	_check(not panel.visible and _button(menu, "New Game") != null, "Back returns to the title screen")
	var seed_edit := _find(menu, func(n: Node) -> bool: return n is LineEdit) as LineEdit
	seed_edit.text = "4242"
	await _click(_button(menu, "Hard"))
	await _click(_button(menu, "Large"))
	await _click(_find(menu, func(n: Node) -> bool: return n is CheckBox) as Control)
	await _click(_button(menu, "New Game"))
	await _frames(20)
	var main := get_tree().current_scene
	_check(main != null and main.name == "Main", "game scene started (got %s)" % main)
	_check(GameState.difficulty == 2, "difficulty Hard (got %d)" % GameState.difficulty)
	_check(GameState.new_game_seed == 4242, "seed 4242 (got %d)" % GameState.new_game_seed)
	_check(not GameState.hints_enabled, "hints off")
	if main != null and main.get("world") != null:
		_check(main.world.map_seed == 4242, "map uses seed (got %d)" % main.world.map_seed)
		_check(main.world.width == 160, "Large map is 160 tiles (got %d)" % main.world.width)
		_check(absf(main.raids.time_until_raid() - 300.0) < 5.0, "Hard first raid ~5:00 (got %.1f)" % main.raids.time_until_raid())
		main.save_game()
		_check(SaveGame.exists(SaveGame.SLOT), "game saved")
		main._on_victory()
		await _frames(5)
		await _click(_button(main.hud, "Main Menu"))
		await _frames(20)
		_check(get_tree().current_scene is MainMenu, "Main Menu returns to title (got %s)" % get_tree().current_scene)
		_check(not get_tree().paused, "title screen isn't paused")
		await _click(_button(get_tree().current_scene, "Continue"))
		await _frames(20)
		var loaded := get_tree().current_scene
		_check(loaded != null and loaded.name == "Main", "Continue starts the game (got %s)" % loaded)
		if loaded != null and loaded.get("world") != null:
			_check(loaded.world.map_seed == 4242, "Continue loads the saved map (seed %d)" % loaded.world.map_seed)
			_check(GameState.difficulty == 2, "Continue keeps the saved difficulty")
			_check(loaded.world.width == 160, "Continue keeps the map size (got %d)" % loaded.world.width)
	print("MENU CHECK %s %s" % ["PASS" if failures.is_empty() else "FAIL", "; ".join(failures)])
	get_tree().quit(0 if failures.is_empty() else 1)


func _check(ok: bool, what: String) -> void:
	print("  %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		failures.append(what)


func _button(root: Node, text: String) -> Control:
	return _find(root, func(n: Node) -> bool: return n is Button and n.is_visible_in_tree() and n.text == text) as Control


func _find(node: Node, pred: Callable) -> Node:
	if pred.call(node):
		return node
	for child in node.get_children():
		var found := _find(child, pred)
		if found != null:
			return found
	return null


func _click(control: Control) -> void:
	if control == null:
		failures.append("missing control to click")
		return
	var pos := control.get_global_rect().get_center()
	var move := InputEventMouseMotion.new()
	move.position = pos
	Input.parse_input_event(move)
	await _frames(3)
	for pressed in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.position = pos
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = pressed
		Input.parse_input_event(ev)
		await _frames(2)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame
