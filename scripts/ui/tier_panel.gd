class_name TierPanel
extends PanelContainer
## Shows the current settlement tier, what the next tier needs, and what it
## unlocks. Toggled from the tier button in the top bar (or T).

var progression: Progression

var _body: Label
var _challenge: Button
var _refresh_timer := 0.0


func setup(p_progression: Progression) -> void:
	progression = p_progression


func _ready() -> void:
	custom_minimum_size = Vector2(360, 0)
	_body = Label.new()
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.custom_minimum_size = Vector2(340, 0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	add_child(col)
	col.add_child(_body)
	_challenge = Button.new()
	_challenge.text = "Challenge the Dragon"
	_challenge.tooltip_text = "Call the Dragon's siege: it comes a minute later, leading the largest horde yet. Survive it to win."
	_challenge.focus_mode = Control.FOCUS_NONE
	_challenge.pressed.connect(func() -> void:
		progression.raids.begin_final_siege()
		_refresh())
	col.add_child(_challenge)
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
		lines.append("")
		lines.append("Final goal: survive the Dragon's siege.")
		var raids := progression.raids
		if not raids.final_siege:
			lines.append("The Dragon waits in the mountains. Build up your kingdom, then challenge it when you're ready. Raids go on meanwhile.")
		elif raids.phase == RaidDirector.Phase.CALM:
			var t := raids.time_until_raid()
			lines.append("The Dragon arrives in %d:%02d." % [floori(t / 60.0), floori(t) % 60])
		else:
			lines.append("The siege is under way!")
	else:
		var next := progression.tier + 1
		lines.append("Next: %s" % progression.tier_name(next))
		for r: Dictionary in progression.requirement_status(next):
			lines.append("  %s %s" % ["✔" if r.met else "✘", r.text])
		lines.append("")
		lines.append("Unlocks: %s" % progression.unlock_summary(next))
	_body.text = "\n".join(lines)
	_challenge.visible = progression.raids.can_challenge_dragon()
	reset_size()
