class_name BuildingPanel
extends PanelContainer
## Inspector for the selected building: status, workers, residents, recipe,
## and troop training for barracks.

const REFRESH_SECONDS := 0.25
const WIDTH := 340.0

var world: WorldMap
var build: BuildController
var military: Military
var building: Building

var _title: Label
var _body: Label
var _demolish: Button
var _train_row: HBoxContainer
var _train_buttons := {}  # unit id -> Button
var _refresh_time := 0.0


func setup(p_build: BuildController, p_world: WorldMap, p_military: Military) -> void:
	build = p_build
	world = p_world
	military = p_military


func _ready() -> void:
	custom_minimum_size = Vector2(WIDTH, 0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	add_child(col)

	var header := HBoxContainer.new()
	col.add_child(header)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 20)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_title)
	var close := Button.new()
	close.text = "✕"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(build.select_building.bind(null))
	header.add_child(close)

	_body = Label.new()
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size = Vector2(WIDTH - 20, 0)
	col.add_child(_body)

	_train_row = HBoxContainer.new()
	col.add_child(_train_row)
	for unit_id: String in UnitDefs.TRAIN_ORDER:
		var def := UnitDefs.get_def(unit_id)
		var btn := Button.new()
		btn.text = def.name
		btn.tooltip_text = "%s\nCost: 1 villager + %s\nUpkeep: %d gold/min" % [
			def.desc, BuildingDefs.cost_text(def.cost), def.upkeep]
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(_on_train.bind(unit_id))
		_train_row.add_child(btn)
		_train_buttons[unit_id] = btn

	_demolish = Button.new()
	_demolish.text = "Demolish (50% refund)"
	_demolish.focus_mode = Control.FOCUS_NONE
	_demolish.pressed.connect(_on_demolish)
	col.add_child(_demolish)

	build.building_selected.connect(show_building)
	hide()


func show_building(b: Building) -> void:
	building = b
	visible = b != null
	if b != null:
		_refresh()


func _process(delta: float) -> void:
	if building == null:
		return
	_refresh_time -= delta / maxf(Engine.time_scale, 0.001)
	if _refresh_time <= 0.0:
		_refresh()


func _refresh() -> void:
	_refresh_time = REFRESH_SECONDS
	_title.text = building.def.name
	var text := building.inspect_text()
	var trains := building.def.has("trains")
	_train_row.visible = trains
	if trains:
		text += "\n\n" + _military_text()
		for unit_id: String in _train_buttons:
			_train_buttons[unit_id].disabled = not GameState.can_afford(UnitDefs.get_def(unit_id).cost)
	_body.text = text
	_demolish.visible = building != world.keep
	# Shrink back to fit when the text gets shorter.
	reset_size()


func _military_text() -> String:
	var squad := military.squad_for(building)
	var lines := PackedStringArray([
		"%s: %s  (%d/%d)" % [squad.display_name(), squad.summary(), squad.troops.size(), building.def.troop_capacity],
		"Mode: %s" % ("guarding rally point" if squad.mode == Squad.Mode.AUTO else "under your command"),
	])
	var queue := military.queue_for(building)
	if not queue.is_empty():
		var names := PackedStringArray()
		for unit_id: String in queue:
			names.append(UnitDefs.get_def(unit_id).name)
		lines.append("Training: %s  (%d%%)" % [", ".join(names), military.training_progress(building) * 100])
	lines.append("Upkeep (all troops): %d gold/min" % military.upkeep_per_minute())
	return "\n".join(lines)


func _on_train(unit_id: String) -> void:
	var err := military.train(building, unit_id)
	if err != "":
		build.message.emit(err)
	_refresh()


func _on_demolish() -> void:
	if building != null:
		world.demolish_at(building.origin)
