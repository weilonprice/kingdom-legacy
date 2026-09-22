class_name BuildingPanel
extends PanelContainer
## Inspector for the selected building: status, workers, residents, recipe.

const REFRESH_SECONDS := 0.25
const WIDTH := 340.0

var world: WorldMap
var build: BuildController
var building: Building

var _title: Label
var _body: Label
var _demolish: Button
var _refresh_time := 0.0


func setup(p_build: BuildController, p_world: WorldMap) -> void:
	build = p_build
	world = p_world


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
	_body.text = building.inspect_text()
	_demolish.visible = building != world.keep
	# Shrink back to fit when the text gets shorter.
	reset_size()


func _on_demolish() -> void:
	if building != null:
		world.demolish_at(building.origin)
