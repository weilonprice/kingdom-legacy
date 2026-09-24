class_name MainMenu
extends Control
## Title screen: new game with an optional seed, difficulty and tutorial
## hints, settings, or quit. New-game choices live on GameState so the game
## scene reads them.

const GAME_SCENE := "res://scenes/main.tscn"
const BACKDROP := ["house", "woodcutter", "keep", "mill", "stone_tower"]

var _seed: LineEdit
var _difficulty: Array[Button] = []
var _hints: CheckBox
var _sizes: Array[Button] = []
var _settings: SettingsPanel
var _center: CenterContainer


func _ready() -> void:
	theme = UiTheme.get_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.13, 0.17, 0.10)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_center = center
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 14)
	center.add_child(col)

	var town := HBoxContainer.new()
	town.alignment = BoxContainer.ALIGNMENT_CENTER
	town.add_theme_constant_override("separation", 6)
	col.add_child(town)
	for id: String in BACKDROP:
		var tex := Art.building(id)
		if tex == null:
			continue
		var pic := TextureRect.new()
		pic.texture = tex
		pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		pic.custom_minimum_size = Vector2(tex.get_size()) * 2.0
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.size_flags_vertical = Control.SIZE_SHRINK_END
		town.add_child(pic)

	var title := Label.new()
	title.text = "Kingdom Legacy"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", UiTheme.GOLD)
	col.add_child(title)
	var tagline := Label.new()
	tagline.text = "Grow a hamlet into a kingdom. Hold it against the monsters."
	tagline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tagline.add_theme_color_override("font_color", UiTheme.TEXT_MUTED)
	col.add_child(tagline)

	var panel := PanelContainer.new()
	col.add_child(panel)
	var form := VBoxContainer.new()
	form.add_theme_constant_override("separation", 10)
	panel.add_child(form)

	var seed_row := HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", 8)
	form.add_child(seed_row)
	seed_row.add_child(_label("Map seed"))
	_seed = LineEdit.new()
	_seed.placeholder_text = "random"
	_seed.custom_minimum_size = Vector2(200, 0)
	_seed.text = str(GameState.new_game_seed) if GameState.new_game_seed != 0 else ""
	seed_row.add_child(_seed)

	var diff_row := HBoxContainer.new()
	diff_row.add_theme_constant_override("separation", 8)
	form.add_child(diff_row)
	diff_row.add_child(_label("Difficulty"))
	var group := ButtonGroup.new()
	for i in GameState.DIFFICULTIES.size():
		var btn := Button.new()
		btn.text = GameState.DIFFICULTIES[i].name
		btn.toggle_mode = true
		btn.button_group = group
		btn.button_pressed = i == GameState.difficulty
		btn.focus_mode = Control.FOCUS_NONE
		btn.tooltip_text = _difficulty_tip(i)
		diff_row.add_child(btn)
		_difficulty.append(btn)

	var size_row := HBoxContainer.new()
	size_row.add_theme_constant_override("separation", 8)
	form.add_child(size_row)
	size_row.add_child(_label("Map size"))
	var size_group := ButtonGroup.new()
	for i in GameState.MAP_SIZES.size():
		var sbtn := Button.new()
		var tiles: int = GameState.MAP_SIZES[i].tiles
		sbtn.text = GameState.MAP_SIZES[i].name
		sbtn.tooltip_text = "%d × %d tiles" % [tiles, tiles]
		sbtn.toggle_mode = true
		sbtn.button_group = size_group
		sbtn.button_pressed = i == GameState.map_size
		sbtn.focus_mode = Control.FOCUS_NONE
		size_row.add_child(sbtn)
		_sizes.append(sbtn)

	_hints = CheckBox.new()
	_hints.text = "Tutorial hints"
	_hints.button_pressed = Settings.get_value("game/hints")
	_hints.focus_mode = Control.FOCUS_NONE
	_hints.toggled.connect(func(on: bool) -> void: Settings.set_value("game/hints", on))
	form.add_child(_hints)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	form.add_child(buttons)
	if SaveGame.latest_slot() != "":
		var cont := Button.new()
		cont.text = "Continue"
		cont.tooltip_text = "Load your most recent save"
		cont.custom_minimum_size = Vector2(140, 40)
		cont.focus_mode = Control.FOCUS_NONE
		cont.pressed.connect(_continue)
		buttons.add_child(cont)
	var play := Button.new()
	play.text = "New Game"
	play.custom_minimum_size = Vector2(160, 40)
	play.focus_mode = Control.FOCUS_NONE
	play.pressed.connect(_start)
	buttons.add_child(play)
	var settings := Button.new()
	settings.text = "Settings"
	settings.custom_minimum_size = Vector2(120, 40)
	settings.focus_mode = Control.FOCUS_NONE
	settings.pressed.connect(func() -> void:
		_center.hide()
		_settings.open())
	buttons.add_child(settings)
	var quit := Button.new()
	quit.text = "Quit"
	quit.custom_minimum_size = Vector2(100, 40)
	quit.focus_mode = Control.FOCUS_NONE
	quit.pressed.connect(func() -> void: get_tree().quit())
	buttons.add_child(quit)

	Sound.ambience_mode = ""
	Music.set_mood("title")
	var goal := Label.new()
	goal.text = "Goal: reach the Kingdom tier, then survive the Dragon's siege."
	goal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	goal.add_theme_color_override("font_color", UiTheme.TEXT_MUTED)
	col.add_child(goal)
	Sound.wire_buttons(self)

	var settings_center := CenterContainer.new()
	settings_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	settings_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(settings_center)
	_settings = SettingsPanel.new()
	settings_center.add_child(_settings)
	_settings.closed.connect(func() -> void:
		_hints.set_pressed_no_signal(Settings.get_value("game/hints"))
		_center.show())


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(110, 0)
	return l


func _difficulty_tip(i: int) -> String:
	var d: Dictionary = GameState.DIFFICULTIES[i]
	return "Raids %d%% size, first raid after %d min%s" % [
		roundi(d.raid_size * 100), roundi(d.first_raid / 60.0),
		", extra starting supplies" if not d.bonus.is_empty() else ""]


func _continue() -> void:
	var data := SaveGame.read(SaveGame.latest_slot())
	if data.is_empty():
		return
	GameState.reset()
	GameState.pending_load = data
	get_tree().change_scene_to_file(GAME_SCENE)


func _start() -> void:
	var text := _seed.text.strip_edges()
	GameState.new_game_seed = int(text) if text.is_valid_int() else (hash(text) if text != "" else 0)
	for i in _difficulty.size():
		if _difficulty[i].button_pressed:
			GameState.difficulty = i
	for i in _sizes.size():
		if _sizes[i].button_pressed:
			GameState.map_size = i
	GameState.hints_enabled = Settings.get_value("game/hints")
	GameState.reset()
	get_tree().change_scene_to_file(GAME_SCENE)
