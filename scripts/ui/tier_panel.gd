class_name TierPanel
extends PanelContainer
## Shows the current settlement tier, what the next tier needs, and what it
## unlocks. Toggled from the tier button in the top bar (or T).

var progression: Progression

var _body: Label
var _refresh_timer := 0.0


func setup(p_progression: Progression) -> void:
	progression = p_progression


func _ready() -> void:
	custom_minimum_size = Vector2(360, 0)
	_body = Label.new()
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size = Vector2(340, 0)
	add_child(_body)
	progression.tier_changed.connect(func(_t: int) -> void: _refresh())
	hide()


func toggle() -> void:
	visible = not visible
	if visible:
		_refresh()


func _process(delta: float) -> void:
	if not visible:
		return
	_refresh_timer -= delta / maxf(Engine.time_scale, 0.001)
	if _refresh_timer <= 0.0:
		_refresh()


func _refresh() -> void:
	_refresh_timer = 0.5
	var lines := PackedStringArray(["Settlement: %s" % progression.tier_name(), ""])
	if progression.is_max_tier():
		lines.append("Your realm has reached its highest rank.")
	else:
		var next := progression.tier + 1
		lines.append("Next: %s" % progression.tier_name(next))
		for r: Dictionary in progression.requirement_status(next):
			lines.append("  %s %s" % ["✔" if r.met else "✘", r.text])
		lines.append("")
		lines.append("Unlocks: %s" % progression.unlock_summary(next))
	_body.text = "\n".join(lines)
	reset_size()
