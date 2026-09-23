class_name GameMenu
extends PanelContainer
## In-game menu from the top bar's ☰ button: resume, save, load, main menu.
## The game is paused while it's open.

var on_save: Callable
var on_load: Callable

var _load_button: Button
var _info: Label
var _was_speed := 1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	add_child(col)
	var title := Label.new()
	title.text = "Paused"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	col.add_child(title)
	_add(col, "Resume", close)
	_add(col, "Save Game (F5)", func() -> void:
		on_save.call()
		_refresh())
	_load_button = _add(col, "Load Game (F8)", func() -> void: on_load.call(SaveGame.latest_slot()))
	_add(col, "Main Menu", func() -> void:
		GameState.reset()
		get_tree().change_scene_to_file("res://scenes/menu.tscn"))
	_info = Label.new()
	_info.add_theme_color_override("font_color", UiTheme.TEXT_MUTED)
	_info.add_theme_font_size_override("font_size", 13)
	_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_info)
	hide()


func _add(parent: Control, text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(220, 36)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(action)
	parent.add_child(b)
	return b


func toggle() -> void:
	if visible:
		close()
	else:
		open()


func open() -> void:
	_was_speed = GameState.speed if GameState.speed > 0 else 1
	GameState.set_speed(0)
	_refresh()
	show()


func close() -> void:
	hide()
	if not GameState.game_over:
		GameState.set_speed(_was_speed)


func _refresh() -> void:
	var slot := SaveGame.latest_slot()
	_load_button.disabled = slot == ""
	_info.text = "No saved game yet" if slot == "" else "Last save: %s" % (
		"autosave" if slot == SaveGame.AUTO else "manual save")
	reset_size()
