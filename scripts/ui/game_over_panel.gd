class_name GameOverPanel
extends Control
## Full-screen overlay shown when the kingdom falls, or when it wins.

const MENU_SCENE := "res://scenes/menu.tscn"

var _title: Label
var _body: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	panel.add_child(col)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 36)
	_title.add_theme_color_override("font_color", Color(0.95, 0.35, 0.25))
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_title)
	_body = Label.new()
	_body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_body)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	col.add_child(row)
	var again := Button.new()
	again.text = "New Game"
	again.pressed.connect(_new_game)
	row.add_child(again)
	var menu := Button.new()
	menu.text = "Main Menu"
	menu.pressed.connect(_main_menu)
	row.add_child(menu)
	hide()


func show_defeat(title: String, body: String) -> void:
	_title.add_theme_color_override("font_color", Color(0.95, 0.35, 0.25))
	_title.text = title
	_body.text = body
	show()


func show_victory(title: String, body: String) -> void:
	_title.add_theme_color_override("font_color", Color(1.0, 0.82, 0.35))
	_title.text = title
	_body.text = body
	show()


func _new_game() -> void:
	GameState.reset()
	get_tree().reload_current_scene()


func _main_menu() -> void:
	GameState.reset()
	get_tree().change_scene_to_file(MENU_SCENE)
