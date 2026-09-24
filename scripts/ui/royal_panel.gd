class_name RoyalPanel
extends PanelContainer
## The Royal Court: the ruling house, the ruler (with traits and what they
## do), spouse and heir with portraits and ages, any succession crisis, and
## the treasury (breached or sealed). Toggled by the crown button, K, the
## castle panel's Royal Court button or clicking a royal on the map.

var royals: Royals

var _house: Label
var _rows: VBoxContainer
var _footer: Label
var _refresh_timer := 0.0


func _ready() -> void:
	custom_minimum_size = Vector2(380, 0)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	add_child(col)
	_house = Label.new()
	_house.add_theme_font_size_override("font_size", 20)
	_house.add_theme_color_override("font_color", UiTheme.GOLD)
	col.add_child(_house)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 6)
	col.add_child(_rows)
	_footer = Label.new()
	_footer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_footer.custom_minimum_size = Vector2(360, 0)
	_footer.add_theme_font_size_override("font_size", 14)
	col.add_child(_footer)
	royals.changed.connect(_refresh)
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
	_refresh_timer = 1.0
	_house.text = "The Royal Court — House %s" % royals.house
	for child in _rows.get_children():
		_rows.remove_child(child)  # now, so the panel can shrink this frame
		child.queue_free()
	if royals.in_crisis():
		_add_row(null, "The throne is empty!", "Succession crisis: no taxes and unrest for %d more seconds, until a noble claims the crown." % ceili(royals.crisis_left))
	for role: String in ["ruler", "spouse", "heir"]:
		var p := royals.person(role)
		if p.is_empty():
			continue
		var look := "heir" if role == "heir" else ("king" if p.male else "queen")
		var lines := PackedStringArray(["Age %d%s" % [p.age, " — heir to the throne" if role == "heir" else ""]])
		if role == "ruler":
			for t: String in p.traits:
				lines.append("%s: %s" % [RoyalDefs.TRAITS[t].name, RoyalDefs.TRAITS[t].desc])
		elif role == "heir" and not p.traits.is_empty():
			lines.append("Temperament: %s" % royals.trait_names(p))
		_add_row(Art.texture(Art.CHARACTER_ROTATION % [look, "south"]), royals.title_of(role), "\n".join(lines))
	if not royals.in_crisis() and royals.heir.is_empty():
		_add_row(null, "No heir yet", "If the ruler dies without one, the realm falls into a succession crisis.")
	_footer.text = "Treasury: %d gold (kept in the %s).\n%s" % [GameState.count("gold"), royals.world.keep.title,
		"BREACHED — raiders got in. Repair the castle above half its HP to seal it." if royals.breached
		else "Raiders who bring the castle below half its HP break in, steal gold, burn stores and may kill a royal."]
	reset_size()


func _add_row(portrait: Texture2D, title: String, body: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_rows.add_child(row)
	var pic := TextureRect.new()
	pic.custom_minimum_size = Vector2(48, 48)
	pic.texture = portrait
	pic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pic.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	row.add_child(pic)
	var text := VBoxContainer.new()
	row.add_child(text)
	var name := Label.new()
	name.text = title
	name.add_theme_color_override("font_color", UiTheme.GOLD.lightened(0.2))
	text.add_child(name)
	var info := Label.new()
	info.text = body
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(300, 0)
	info.add_theme_font_size_override("font_size", 13)
	text.add_child(info)
