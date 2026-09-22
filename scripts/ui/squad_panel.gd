class_name SquadPanel
extends PanelContainer
## Shows the selected squads with Guard / Back-to-barracks buttons.

var units: UnitController

var _body: Label


func setup(p_units: UnitController) -> void:
	units = p_units


func _ready() -> void:
	var col := VBoxContainer.new()
	add_child(col)
	_body = Label.new()
	col.add_child(_body)
	var row := HBoxContainer.new()
	col.add_child(row)
	_add_button(row, "Guard here [G]", "Stop following orders and defend this spot automatically",
		func() -> void:
			for s in units.selected:
				s.release())
	_add_button(row, "Back to barracks", "Return and guard the barracks",
		func() -> void:
			for s in units.selected:
				s.return_to_barracks())
	units.selection_changed.connect(_refresh)
	hide()


func _process(_delta: float) -> void:
	if visible:
		_refresh()


func _refresh() -> void:
	visible = not units.selected.is_empty()
	if not visible:
		return
	var lines := PackedStringArray()
	for s in units.selected:
		var mode := "guarding" if s.mode == Squad.Mode.AUTO else "following orders"
		lines.append("%s — %s (%s)" % [s.display_name(), s.summary(), mode])
	lines.append("Right-click: move / attack    Ctrl+%s: select" % "1-9")
	_body.text = "\n".join(lines)
	reset_size()


func _add_button(parent: Control, text: String, tip: String, action: Callable) -> void:
	var btn := Button.new()
	btn.text = text
	btn.tooltip_text = tip
	btn.focus_mode = Control.FOCUS_NONE
	btn.pressed.connect(action)
	parent.add_child(btn)
