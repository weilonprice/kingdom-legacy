class_name HUD
extends CanvasLayer
## Top bar (stock, population, food, speed), categorized build bar,
## building inspector, hover info and messages.

const SPEED_LABELS := ["Pause", "1x", "2x", "4x"]
const MESSAGE_SECONDS := 3.0
const ITEM_HOTKEYS := [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9]

var build: BuildController
var world: WorldMap
var citizens: CitizenManager
var raids: RaidDirector
var military: Military
var units: UnitController
var progression: Progression
var research: Research
var needs: Needs
var overlay: Overlay
var day_night: DayNight

var _materials_label: Label
var _food_label: Label
var _gold_label: Label
var _pop_label: Label
var _raid_label: Label
var _clock_label: Label
var _banner: Label
var _game_over: GameOverPanel
var _squad_panel: SquadPanel
var _tier_button: Button
var _tier_panel: TierPanel
var _mode_label: Label
var _info_label: Label
var _msg_label: Label
var _msg_time := 0.0
var _speed_buttons: Array[Button] = []
var _category_buttons: Array[Button] = []
var _item_row: HBoxContainer
var _category := 0
var _panel: BuildingPanel


func setup(p_build: BuildController, p_world: WorldMap, p_citizens: CitizenManager,
		p_raids: RaidDirector, p_military: Military, p_units: UnitController,
		p_progression: Progression, p_research: Research, p_needs: Needs, p_overlay: Overlay,
		p_day_night: DayNight) -> void:
	day_night = p_day_night
	progression = p_progression
	research = p_research
	needs = p_needs
	overlay = p_overlay
	build = p_build
	world = p_world
	citizens = p_citizens
	raids = p_raids
	military = p_military
	units = p_units


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_top_bar()
	_build_bottom_bar()
	_info_label = _outlined_label(Vector2(12, 48))
	_msg_label = _outlined_label(Vector2.ZERO)
	_msg_label.add_theme_color_override("font_color", Color(1, 0.85, 0.5))
	_msg_label.add_theme_font_size_override("font_size", 20)

	_panel = BuildingPanel.new()
	_panel.setup(build, world, military, progression, research, needs)
	add_child(_panel)

	_tier_panel = TierPanel.new()
	_tier_panel.setup(progression)
	add_child(_tier_panel)
	_tier_panel.position = Vector2(10, 80)
	progression.tier_changed.connect(func(_t: int) -> void:
		_show_category(_category)
		_refresh_tier())
	_refresh_tier()

	_squad_panel = SquadPanel.new()
	_squad_panel.setup(units)
	add_child(_squad_panel)

	var indicator := RaidIndicator.new()
	indicator.setup(world, raids)
	add_child(indicator)
	_banner = _outlined_label(Vector2.ZERO)
	_banner.add_theme_font_size_override("font_size", 24)
	_banner.add_theme_color_override("font_color", Color(1, 0.4, 0.3))
	_game_over = GameOverPanel.new()
	add_child(_game_over)

	GameState.resources_changed.connect(_refresh_resources)
	GameState.population_changed.connect(_refresh_population)
	GameState.population_changed.connect(_refresh_resources)
	GameState.happiness_changed.connect(_refresh_population)
	GameState.happiness_changed.connect(_refresh_resources)
	military.squads_changed.connect(_refresh_resources)
	GameState.speed_changed.connect(_refresh_speed)
	GameState.notified.connect(show_message)
	build.mode_changed.connect(func(text: String) -> void: _mode_label.text = text)
	build.message.connect(show_message)
	_show_category(0)
	for child in get_children():
		if child is Control:
			child.theme = UiTheme.get_theme()
	_refresh_resources()
	_refresh_population()
	_refresh_speed()


func show_message(text: String) -> void:
	_msg_label.text = text
	_msg_time = MESSAGE_SECONDS


func _process(delta: float) -> void:
	_info_label.text = world.describe_tile(build.hover_tile)
	var real_delta := delta / maxf(Engine.time_scale, 0.001)
	_msg_time = maxf(_msg_time - real_delta, 0.0)
	_msg_label.visible = _msg_time > 0.0
	var vp := get_viewport().get_visible_rect().size
	_msg_label.position = Vector2((vp.x - _msg_label.size.x) * 0.5, vp.y - 130)
	_panel.position = Vector2(vp.x - _panel.size.x - 10, 50)
	_update_raid_ui(vp)
	_set_bar(_clock_label, day_night.label(), "%s — %d:%02d until %s" % [
		day_night.label(), floori(day_night.time_to_change() / 60.0), floori(day_night.time_to_change()) % 60,
		"morning" if world.is_night else "nightfall"])
	_squad_panel.position = Vector2(10, vp.y - _squad_panel.size.y - 90)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	if event.keycode == KEY_SPACE:
		GameState.toggle_pause()
	elif event.keycode == KEY_O:
		GameState.notify(overlay.cycle())
	elif event.keycode == KEY_T:
		_tier_panel.toggle()
	elif event.keycode == KEY_F9:
		raids.call_raid_now()
	elif event.keycode == KEY_TAB:
		_show_category((_category + 1) % BuildingDefs.CATEGORIES.size())
	elif event.keycode in ITEM_HOTKEYS and not event.ctrl_pressed:
		var items: Array = BuildingDefs.CATEGORIES[_category].items
		var index := ITEM_HOTKEYS.find(event.keycode)
		if index >= items.size():
			return
		build.select(items[index])
	else:
		return
	get_viewport().set_input_as_handled()


# --- Layout -----------------------------------------------------------------

func _build_top_bar() -> void:
	var bar := PanelContainer.new()
	add_child(bar)
	bar.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	bar.add_child(row)
	_tier_button = _button(row, "", "Settlement tier — click (or T) for what the next tier needs")
	_tier_button.pressed.connect(func() -> void: _tier_panel.toggle())
	# Info labels share the leftover width and truncate, so the speed buttons
	# on the right always stay on screen however long the numbers get.
	_bar_icon(row, "wood")
	_materials_label = _bar_label(row, 1.3)
	_bar_icon(row, "bread")
	_food_label = _bar_label(row, 1.8)
	_bar_icon(row, "gold")
	_gold_label = _bar_label(row, 1.0)
	_bar_icon(row, "villager")
	_pop_label = _bar_label(row, 1.0)
	_raid_label = _bar_label(row, 0.8)
	_clock_label = _bar_label(row, 0.6)
	for i in SPEED_LABELS.size():
		var btn := _button(row, SPEED_LABELS[i], "Space toggles pause")
		btn.toggle_mode = true
		btn.pressed.connect(GameState.set_speed.bind(i))
		_speed_buttons.append(btn)


func _build_bottom_bar() -> void:
	var bar := PanelContainer.new()
	add_child(bar)
	bar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	var col := VBoxContainer.new()
	bar.add_child(col)

	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	col.add_child(tabs)
	_button(tabs, "[R] Road", "Drag to build roads (free)").pressed.connect(build.select.bind("road"))
	_button(tabs, "[X] Demolish", "Remove buildings and roads").pressed.connect(build.select.bind("demolish"))
	tabs.add_child(VSeparator.new())
	for i in BuildingDefs.CATEGORIES.size():
		var btn := _button(tabs, BuildingDefs.CATEGORIES[i].name, "Tab cycles categories")
		btn.toggle_mode = true
		btn.pressed.connect(_show_category.bind(i))
		_category_buttons.append(btn)
	_mode_label = Label.new()
	_mode_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tabs.add_child(_mode_label)

	_item_row = HBoxContainer.new()
	_item_row.add_theme_constant_override("separation", 8)
	col.add_child(_item_row)


func _show_category(index: int) -> void:
	_category = index
	for i in _category_buttons.size():
		_category_buttons[i].set_pressed_no_signal(i == index)
	for child in _item_row.get_children():
		child.queue_free()
	var items: Array = BuildingDefs.CATEGORIES[index].items
	for i in items.size():
		var def := BuildingDefs.get_def(items[i])
		var tip := "%s\nCost: %s" % [def.desc, BuildingDefs.cost_text(def.cost)]
		var locked := progression.locked_reason("buildings", items[i])
		var label := "[%d] %s" % [i + 1, def.name]
		if locked != "":
			label += " 🔒"
			tip += "\n\n🔒 " + locked
		var btn := _button(_item_row, label, tip)
		btn.modulate = Color(1, 1, 1, 0.5) if locked != "" else Color.WHITE
		btn.pressed.connect(build.select.bind(items[i]))


func _button(parent: Control, text: String, tip: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.tooltip_text = tip
	btn.focus_mode = Control.FOCUS_NONE
	parent.add_child(btn)
	return btn


func _bar_label(parent: Control, stretch: float) -> Label:
	var label := Label.new()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_stretch_ratio = stretch
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.mouse_filter = Control.MOUSE_FILTER_PASS  # for the full-text tooltip
	parent.add_child(label)
	return label


## A small icon before a top-bar label (skipped if the icon art is missing).
func _bar_icon(parent: Control, name: String) -> void:
	var tex := UiTheme.icon(name)
	if tex == null:
		return
	var rect := TextureRect.new()
	rect.texture = tex
	rect.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	rect.custom_minimum_size = Vector2(24, 24)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rect)


## Sets a bar label's text, keeping the untruncated version in its tooltip.
func _set_bar(label: Label, text: String, tooltip := "") -> void:
	label.text = text
	label.tooltip_text = tooltip if tooltip != "" else text


func _outlined_label(pos: Vector2) -> Label:
	var label := Label.new()
	label.position = pos
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_constant_override("outline_size", 5)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	add_child(label)
	return label


func _refresh_tier() -> void:
	_tier_button.text = "⚑ %s" % progression.tier_name()


func show_defeat(title: String, body: String) -> void:
	_game_over.show_defeat(title, body)


func _update_raid_ui(vp: Vector2) -> void:
	match raids.phase:
		RaidDirector.Phase.CALM:
			var t := raids.time_until_raid()
			_set_bar(_raid_label, "Raid in %d:%02d" % [floori(t / 60.0), floori(t) % 60], "Next goblin raid")
			_banner.text = ""
		RaidDirector.Phase.WARNING:
			_set_bar(_raid_label, "Raid incoming!")
			_banner.text = "⚔ Goblins approach from the %s — %ds! ⚔" % [
				raids.direction_name(), ceili(raids.time_until_raid())]
		RaidDirector.Phase.ACTIVE:
			_set_bar(_raid_label, "Raid!", "Raid in progress")
			_banner.text = "⚔ Raid! %d goblin%s remaining ⚔" % [
				world.enemies.size(), "" if world.enemies.size() == 1 else "s"]
	_banner.visible = _banner.text != ""
	_banner.reset_size()
	_banner.position = Vector2((vp.x - _banner.size.x) * 0.5, 48)


# --- Refresh ----------------------------------------------------------------

func _refresh_resources() -> void:
	var mats := ItemDefs.items_in("materials")
	_set_bar(_materials_label, "%s  %d/%d" % [
		_stock_text(mats, false), GameState.used("materials"), GameState.capacity.get("materials", 0)],
		"Materials: %s\nStorage %d/%d" % [_stock_text(mats, true), GameState.used("materials"),
			GameState.capacity.get("materials", 0)])
	var pop := maxi(GameState.population, 1)
	var minutes := GameState.edible_total() / float(pop) * CitizenManager.MEAL_INTERVAL / 60.0
	var foods := ItemDefs.items_in("food")
	_set_bar(_food_label, "%s  %d/%d · %.0f min" % [
		_stock_text(foods, false), GameState.used("food"), GameState.capacity.get("food", 0), minutes],
		"Food: %s\nStorage %d/%d\nAbout %.0f minutes of food for %d people" % [
			_stock_text(foods, true), GameState.used("food"), GameState.capacity.get("food", 0), minutes, GameState.population])
	_food_label.add_theme_color_override("font_color", Color(1, 0.45, 0.35) if minutes < 2.0 else Color.WHITE)
	var upkeep := military.upkeep_per_minute() if military != null else 0
	var tax := needs.tax_per_minute() if needs != null else 0
	_set_bar(_gold_label, "Gold %d (%+d/min)" % [GameState.count("gold"), tax - upkeep],
		"Gold %d\nTaxes about +%d/min (%s rate — change it on the Keep)\nTroop upkeep −%d/min" % [
			GameState.count("gold"), tax, NeedDefs.TAX_RATES[GameState.tax_rate].name, upkeep])


## "Wood 120 · Stone 20". Without `include_empty`, items at 0 are left out
## (showing "Food" if everything is empty).
func _stock_text(items: Array[String], include_empty: bool) -> String:
	var parts := PackedStringArray()
	for item in items:
		if include_empty or GameState.count(item) > 0:
			parts.append("%s %d" % [ItemDefs.display_name(item), GameState.count(item)])
	return " · ".join(parts) if not parts.is_empty() else "none"


func _refresh_population() -> void:
	_set_bar(_pop_label, "Pop %d/%d · Jobs %d/%d · ☺%d" % [
		GameState.population, GameState.housing, GameState.employed, GameState.jobs, GameState.happiness],
		"Population %d (housing for %d)\nWorkers %d of %d jobs filled\nAverage happiness %d/100 (O shows the map)" % [
			GameState.population, GameState.housing, GameState.employed, GameState.jobs, GameState.happiness])


func _refresh_speed() -> void:
	for i in _speed_buttons.size():
		_speed_buttons[i].set_pressed_no_signal(i == GameState.speed)
