class_name HintPanel
extends PanelContainer
## First-game objectives, one at a time, top-left. Each step is done when
## its check passes; the panel then moves on. Hidden when hints are off
## (main menu) or dismissed.

var world: WorldMap
var military: Military
var progression: Progression
## Set by the HUD while another panel covers this spot.
var suppressed := false

var _steps: Array[Dictionary] = []
var _index := 0
var _text: Label
var _start_roads := 0
var _check_timer := 0.0


func setup(p_world: WorldMap, p_military: Military, p_progression: Progression) -> void:
	world = p_world
	military = p_military
	progression = p_progression


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_start_roads = world.roads.size()
	_steps = [
		{"text": "Press R and drag from the Keep's road to lay more road.",
			"done": func() -> bool: return world.roads.size() > _start_roads},
		{"text": "Housing tab: build a House with its door on a road. Settlers move in.",
			"done": func() -> bool: return _count("house") > 0},
		{"text": "Resources tab: build a Woodcutter near a forest.",
			"done": func() -> bool: return _count("woodcutter") > 0},
		{"text": "Food: a Fisher's Hut by water, or a Farm on open grass.",
			"done": func() -> bool: return _count("fisher") + _count("farm") > 0},
		{"text": "Raids come every few minutes. Defense tab: build a Guard Tower on a road.",
			"done": func() -> bool: return _count("guard_tower") > 0},
		{"text": "Press T to see what the next tier needs. A Well and a Granary help reach Village.",
			"done": func() -> bool: return progression.tier >= 1},
		{"text": "Village! Build a Barracks and train troops. Select a squad, right-click to order it.",
			"done": func() -> bool: return not military.troops().is_empty()},
		{"text": "Keep growing: homes level up with services (Chapel, Market). Press O for overlays.",
			"done": func() -> bool: return progression.tier >= 2},
		{"text": "Town! Raise the Keep into a Castle (click it). Walls: drag them; they gate your roads.",
			"done": func() -> bool: return progression.tier >= 3},
		{"text": "Goblin lairs make raids bigger. Follow the dark arrows and send a squad.",
			"done": func() -> bool: return progression.is_max_tier()},
		{"text": "Kingdom! The Dragon waits. Raise the Citadel, then challenge it from the tier panel (T).",
			"done": func() -> bool: return progression.raids.final_siege},
		{"text": "The Dragon is coming! Towers and archers can hit it in the air.",
			"done": func() -> bool: return false},
	]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	add_child(row)
	_text = Label.new()
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.custom_minimum_size = Vector2(300, 0)
	_text.add_theme_font_size_override("font_size", 14)
	row.add_child(_text)
	var close := Button.new()
	close.text = "✕"
	close.tooltip_text = "Hide hints (turn them back on in Settings)"
	close.focus_mode = Control.FOCUS_NONE
	close.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	close.pressed.connect(func() -> void: Settings.set_value("game/hints", false))
	row.add_child(close)
	_show_step()


func _process(delta: float) -> void:
	visible = GameState.hints_enabled and not suppressed and _index < _steps.size()
	if not visible:
		return
	_check_timer -= delta / maxf(Engine.time_scale, 0.001)
	if _check_timer > 0.0:
		return
	_check_timer = 0.5
	var advanced := false
	while _index < _steps.size() and _steps[_index].done.call():
		_index += 1
		advanced = true
	if advanced:
		_show_step()


func current_hint() -> String:
	return _steps[_index].text if _index < _steps.size() else ""


func _show_step() -> void:
	if _index < _steps.size():
		_text.text = "Goal %d/%d: %s" % [_index + 1, _steps.size(), _steps[_index].text]
	reset_size()


func _count(id: String) -> int:
	var n := 0
	for b in world.buildings:
		if b.def_id == id:
			n += 1
	return n
