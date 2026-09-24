class_name SettingsPanel
extends PanelContainer
## The Settings window, shared by the title screen and the in-game menu:
## Audio, Display, Game and Controls pages. Every change applies and saves
## at once (see the Settings autoload); Back or Esc closes it.

signal closed

const PAGES := ["Audio", "Display", "Game", "Controls"]
const BUS_LABELS := {"Master": "Volume", "SFX": "Effects", "Ambience": "Ambience", "Music": "Music"}
const CONTROLS := [
	["WASD / arrows", "Pan the camera (or drag with the middle mouse button)"],
	["Mouse wheel", "Zoom"],
	["Space", "Pause / resume"],
	["Tab, 1–9", "Next build category, pick a building in it"],
	["R / X", "Road tool / demolish tool"],
	["Right-click, Esc", "Cancel the tool or selection"],
	["Esc", "Game menu (when nothing is selected)"],
	["Left-drag", "Select squads; right-click to move or attack"],
	["Ctrl+1–9, G", "Select squad N / release it to guard"],
	["C", "Call to Arms during a raid"],
	["O / T / M", "Overlays / tier goals / minimap"],
	["F5 / F8", "Save / load"],
	["F11", "Fullscreen"],
]

var _tabs: Array[Button] = []
var _pages: Array[Control] = []
## Callables that re-read the settings into the controls.
var _syncs: Array[Callable] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	add_child(col)
	var title := Label.new()
	title.text = "Settings"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	col.add_child(title)

	var tab_row := HBoxContainer.new()
	tab_row.alignment = BoxContainer.ALIGNMENT_CENTER
	tab_row.add_theme_constant_override("separation", 6)
	col.add_child(tab_row)
	var group := ButtonGroup.new()
	for i in PAGES.size():
		var tab := _toggle(tab_row, PAGES[i], group)
		tab.custom_minimum_size = Vector2(100, 32)
		tab.pressed.connect(show_page.bind(i))
		_tabs.append(tab)

	for build: Callable in [_audio_page, _display_page, _game_page, _controls_page]:
		var page := VBoxContainer.new()
		page.add_theme_constant_override("separation", 10)
		page.custom_minimum_size = Vector2(560, 250)
		col.add_child(page)
		build.call(page)
		_pages.append(page)

	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(160, 36)
	back.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back.focus_mode = Control.FOCUS_NONE
	back.pressed.connect(close)
	col.add_child(back)

	Settings.changed.connect(func(_key: String) -> void: _sync())
	Sound.wire_buttons(self)
	show_page(0)
	hide()


func open() -> void:
	_sync()
	show()
	reset_size()


func close() -> void:
	hide()
	closed.emit()


func show_page(i: int) -> void:
	for p in _pages.size():
		_pages[p].visible = p == i
	_tabs[i].button_pressed = true
	reset_size()


func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()


func _sync() -> void:
	for s in _syncs:
		s.call()


# --- Pages ------------------------------------------------------------------

func _audio_page(page: Control) -> void:
	for bus: String in BUS_LABELS:
		var row := _row(page, BUS_LABELS[bus])
		var slider := HSlider.new()
		slider.min_value = 0.0
		slider.max_value = 1.0
		slider.step = 0.05
		slider.custom_minimum_size = Vector2(240, 24)
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slider.focus_mode = Control.FOCUS_NONE
		row.add_child(slider)
		var pct := Label.new()
		pct.custom_minimum_size = Vector2(60, 0)
		row.add_child(pct)
		var key := "audio/" + bus
		slider.value_changed.connect(func(v: float) -> void:
			pct.text = "%d%%" % roundi(v * 100)
			if not is_equal_approx(v, Settings.get_value(key)):
				Settings.set_value(key, v)
				Sound.play("click", null, -6.0, 0.0))
		_syncs.append(func() -> void:
			slider.set_value_no_signal(Settings.get_value(key))
			pct.text = "%d%%" % roundi(slider.value * 100))


func _display_page(page: Control) -> void:
	_choices(page, "Window", "display/fullscreen", {"Windowed": false, "Fullscreen": true},
		"F11 switches at any time")
	_check(page, "VSync", "display/vsync", "Match the monitor's refresh rate (no tearing)")
	var scales := {}
	for s: float in Settings.UI_SCALES:
		scales["%d%%" % roundi(s * 100)] = s
	_choices(page, "Interface scale", "display/ui_scale", scales,
		"Bigger text and buttons (the map zooms with them)")


func _game_page(page: Control) -> void:
	_check(page, "Tutorial hints", "game/hints", "Step-by-step hints for a new kingdom")
	var saves := {}
	for m: int in Settings.AUTOSAVE_CHOICES:
		saves["Off" if m == 0 else "%d min" % m] = m
	_choices(page, "Autosave", "game/autosave_minutes", saves, "Also saves after every raid unless Off")
	_choices(page, "Camera speed", "game/pan_speed", Settings.PAN_SPEEDS)
	_check(page, "Edge scrolling", "game/edge_scroll", "Move the camera by pushing the mouse against the screen edge")
	_check(page, "Pause when raiders are sighted", "game/pause_on_raid",
		"Stops the clock when a raid warning sounds, so you can prepare")


func _controls_page(page: Control) -> void:
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 4)
	page.add_child(grid)
	for pair: Array in CONTROLS:
		var key := Label.new()
		key.text = pair[0]
		key.add_theme_color_override("font_color", UiTheme.GOLD)
		key.add_theme_font_size_override("font_size", 14)
		grid.add_child(key)
		var what := Label.new()
		what.text = pair[1]
		what.add_theme_font_size_override("font_size", 14)
		grid.add_child(what)


# --- Controls ---------------------------------------------------------------

func _row(page: Control, text: String, tip := "") -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	page.add_child(row)
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(170, 0)
	label.tooltip_text = tip
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	row.add_child(label)
	return row


## A row of toggle buttons, one per {label: value}.
func _choices(page: Control, text: String, key: String, options: Dictionary, tip := "") -> void:
	var row := _row(page, text, tip)
	var group := ButtonGroup.new()
	for label: String in options:
		var value: Variant = options[label]
		var b := _toggle(row, label, group)
		b.tooltip_text = tip
		b.pressed.connect(func() -> void: Settings.set_value(key, value))
		_syncs.append(func() -> void: b.set_pressed_no_signal(is_equal_approx(
			float(Settings.get_value(key)), float(value))))


func _check(page: Control, text: String, key: String, tip := "") -> void:
	var box := CheckBox.new()
	box.text = text
	box.tooltip_text = tip
	box.focus_mode = Control.FOCUS_NONE
	box.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	box.toggled.connect(func(on: bool) -> void: Settings.set_value(key, on))
	page.add_child(box)
	_syncs.append(func() -> void: box.set_pressed_no_signal(Settings.get_value(key)))


func _toggle(parent: Control, text: String, group: ButtonGroup) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_group = group
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(64, 30)
	parent.add_child(b)
	return b
