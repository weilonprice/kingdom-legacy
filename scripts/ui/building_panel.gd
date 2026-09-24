class_name BuildingPanel
extends PanelContainer
## Inspector for the selected building: status, workers, residents, recipe,
## and troop training for barracks.

const REFRESH_SECONDS := 0.25
const WIDTH := 340.0

var world: WorldMap
var build: BuildController
var military: Military
var progression: Progression
var research: Research
var needs: Needs
var building: Building

var _title: Label
var _body: Label
var _demolish: Button
var _train_row: HBoxContainer
var _train_buttons := {}  # unit id -> Button
var _tax_row: HBoxContainer
var _tax_buttons: Array[Button] = []
var _research_box: VBoxContainer
var _research_buttons := {}  # research id -> Button
var trade: Trade
var castle: Castle
var _castle_button: Button
var _court_button: Button
## Opens the Royal Court (set by the HUD).
var royal_court: Callable
var _trade_box: VBoxContainer
var _trade_rows := {}  # item -> {"label": Label, "buy": Button, "sell": Button}
var _refresh_time := 0.0


func setup(p_build: BuildController, p_world: WorldMap, p_military: Military,
		p_progression: Progression, p_research: Research, p_needs: Needs) -> void:
	needs = p_needs
	build = p_build
	world = p_world
	military = p_military
	progression = p_progression
	research = p_research


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

	_tax_row = HBoxContainer.new()
	col.add_child(_tax_row)
	var tax_label := Label.new()
	tax_label.text = "Tax:"
	_tax_row.add_child(tax_label)
	for i in NeedDefs.TAX_RATES.size():
		var rate: Dictionary = NeedDefs.TAX_RATES[i]
		var tbtn := Button.new()
		tbtn.text = rate.name
		tbtn.toggle_mode = true
		tbtn.focus_mode = Control.FOCUS_NONE
		tbtn.tooltip_text = "%.1f gold per resident per minute, happiness %+d" % [rate.gold, rate.happiness]
		tbtn.pressed.connect(func() -> void:
			GameState.set_tax_rate(i)
			_refresh())
		_tax_row.add_child(tbtn)
		_tax_buttons.append(tbtn)

	_castle_button = Button.new()
	_castle_button.focus_mode = Control.FOCUS_NONE
	_castle_button.pressed.connect(func() -> void:
		var problem := castle.start_upgrade()
		if problem != "":
			GameState.notify(problem)
		_refresh())
	col.add_child(_castle_button)
	_court_button = Button.new()
	_court_button.text = "Royal Court"
	_court_button.tooltip_text = "The ruling family, their traits and the treasury (K)"
	_court_button.focus_mode = Control.FOCUS_NONE
	_court_button.pressed.connect(func() -> void: royal_court.call())
	col.add_child(_court_button)

	_research_box = VBoxContainer.new()
	col.add_child(_research_box)
	for id: String in ResearchDefs.ORDER:
		var rdef := ResearchDefs.get_def(id)
		var rbtn := Button.new()
		rbtn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		rbtn.tooltip_text = "%s\nCost: %s   Time: %ds with 1 scholar" % [
			rdef.desc, BuildingDefs.cost_text(rdef.cost), rdef.time]
		rbtn.focus_mode = Control.FOCUS_NONE
		rbtn.pressed.connect(_on_research.bind(id))
		_research_box.add_child(rbtn)
		_research_buttons[id] = rbtn

	_trade_box = VBoxContainer.new()
	col.add_child(_trade_box)
	for item: String in TradeDefs.items():
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		_trade_box.add_child(row)
		# Fixed widths so the buttons don't shift as prices change.
		var label := Label.new()
		label.custom_minimum_size = Vector2(118, 0)
		label.clip_text = true
		row.add_child(label)
		var buy := Button.new()
		buy.custom_minimum_size = Vector2(100, 0)
		buy.focus_mode = Control.FOCUS_NONE
		buy.pressed.connect(_on_trade.bind(item, true))
		row.add_child(buy)
		var sell := Button.new()
		sell.custom_minimum_size = Vector2(100, 0)
		sell.focus_mode = Control.FOCUS_NONE
		sell.pressed.connect(_on_trade.bind(item, false))
		row.add_child(sell)
		_trade_rows[item] = {"row": row, "label": label, "buy": buy, "sell": sell}

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
	_title.text = building.title
	var text := building.inspect_text()
	var trains := building.def.has("trains")
	_train_row.visible = trains
	if trains:
		text += "\n\n" + _military_text()
		for unit_id: String in _train_buttons:
			var btn: Button = _train_buttons[unit_id]
			var locked := progression.locked_reason("units", unit_id)
			btn.text = UnitDefs.get_def(unit_id).name + (" 🔒" if locked != "" else "")
			btn.disabled = locked != "" or not GameState.can_afford(UnitDefs.get_def(unit_id).cost)
	var is_keep := building == world.keep
	_tax_row.visible = is_keep
	if is_keep:
		for i in _tax_buttons.size():
			_tax_buttons[i].set_pressed_no_signal(i == GameState.tax_rate)
		text += "\n\nTax rate: %s — about %d gold/min from homes\nAverage happiness: %d" % [
			NeedDefs.TAX_RATES[GameState.tax_rate].name, needs.tax_per_minute(), GameState.happiness]
		text += "\n\n" + _castle_text()
	_court_button.visible = is_keep and royal_court.is_valid()
	var next := castle.next_stage() if is_keep and castle != null else {}
	_castle_button.visible = not next.is_empty() and not castle.is_building()
	if _castle_button.visible:
		_castle_button.text = "Upgrade to %s (%d gold)" % [next.title, next.gold]
		_castle_button.disabled = castle.upgrade_problem() != ""
		_castle_button.tooltip_text = "Grows the castle to %dx%d. Builders haul %s, then build.%s" % [
			next.size, next.size, BuildingDefs.cost_text(next.materials),
			"" if castle.upgrade_problem() == "" else "\n" + castle.upgrade_problem()]
	var studies: bool = building.def.get("work", "") == "study"
	_research_box.visible = studies
	if studies:
		text += "\n\n" + _research_text()
		_refresh_research_buttons()
	var trading := building.def_id == "trading_post" and trade != null
	_trade_box.visible = trading and trade.is_open()
	if trading:
		text += "\n\n" + _trade_text()
		if trade.is_open():
			_refresh_trade_rows()
	_body.text = text
	_demolish.visible = building != world.keep
	# Shrink back to fit when the text gets shorter.
	reset_size()


func _castle_text() -> String:
	if castle == null:
		return ""
	var st: Dictionary = CastleDefs.STAGES[castle.stage]
	var lines := PackedStringArray(["%s (%dx%d)" % [st.title, st.size, st.size]])
	if castle.is_building():
		var target: Dictionary = CastleDefs.STAGES[castle.project.stage]
		lines.append("Building the %s — %d%%" % [target.title, roundi(castle.progress() * 100)])
		var parts := PackedStringArray()
		for item: String in target.materials:
			parts.append("%s %d/%d" % [item, mini(castle.project.delivered.get(item, 0), target.materials[item]),
				target.materials[item]])
		lines.append("Materials: " + ", ".join(parts))
		if castle.materials_done():
			lines.append("Construction: %d/%d" % [castle.project.work_done, target.work])
		lines.append("Builders: %d/%d%s" % [building.workers.size(), CastleDefs.BUILDERS,
			"  (builders are unemployed villagers: build homes to free some)" if building.workers.is_empty() else ""])
	elif not castle.next_stage().is_empty():
		var next := castle.next_stage()
		var problem := castle.upgrade_problem()
		lines.append("Next: %s (%dx%d) — %s" % [next.title, next.size, next.size,
			"ready to begin" if problem == "" else problem])
	return "\n".join(lines)


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


func _research_text() -> String:
	var lines := PackedStringArray()
	var current := research.active()
	if current == "":
		lines.append("Research: idle — pick a topic below")
	else:
		lines.append("Researching %s: %d%%  (%d scholar%s working)" % [
			ResearchDefs.get_def(current).name, research.progress_ratio() * 100,
			research.scholars_working(), "" if research.scholars_working() == 1 else "s"])
		if research.scholars_working() == 0:
			lines.append("⚠ No scholars at work — research is paused")
	if research.queue.size() > 1:
		lines.append("Queued: %d more" % (research.queue.size() - 1))
	lines.append("Completed: %d/%d" % [research.completed.size(), ResearchDefs.ORDER.size()])
	return "\n".join(lines)


func _refresh_research_buttons() -> void:
	for id: String in _research_buttons:
		var btn: Button = _research_buttons[id]
		var rdef := ResearchDefs.get_def(id)
		var locked := progression.locked_reason("research", id)
		if research.is_done(id):
			btn.text = "✔ %s" % rdef.name
			btn.disabled = true
		elif research.is_queued(id):
			btn.text = "⏳ %s" % rdef.name
			btn.disabled = true
		elif locked != "":
			btn.text = "🔒 %s — %s" % [rdef.name, locked]
			btn.disabled = true
		else:
			btn.text = "%s  (%s)" % [rdef.name, BuildingDefs.cost_text(rdef.cost)]
			btn.disabled = not GameState.can_afford(rdef.cost)


func _trade_text() -> String:
	if trade.is_open():
		return "%s in town for %d:%02d — has %d gold to spend.\nBuy or sell %d at a time:" % [
			trade.merchant_name(), floori(trade.merchant.time_left / 60.0), floori(trade.merchant.time_left) % 60,
			trade.merchant.gold, TradeDefs.LOT]
	if not trade.merchant.is_empty():
		return "A %s is on the way." % trade.merchant_name().to_lower()
	if not building.has_road:
		return "Merchants can't reach it: connect it to a road."
	return "Next caravan in about %d:%02d." % [floori(trade.timer / 60.0), floori(trade.timer) % 60]


func _refresh_trade_rows() -> void:
	for item: String in _trade_rows:
		var r: Dictionary = _trade_rows[item]
		var buy_price := trade.buy_price(item)
		var sell_price := trade.sell_price(item)
		var stock: int = trade.merchant.stock.get(item, 0)
		r.label.text = "%s (%d)" % [ItemDefs.display_name(item), GameState.count(item)]
		r.buy.text = "Buy for %dg" % buy_price if buy_price > 0 else "Buy —"
		r.buy.disabled = buy_price <= 0 or GameState.count("gold") < buy_price
		r.buy.tooltip_text = "The merchant has %d %s" % [stock, item]
		r.sell.text = "Sell for %dg" % sell_price
		r.sell.disabled = GameState.count(item) < TradeDefs.LOT or trade.merchant.gold < sell_price


func _on_trade(item: String, buying: bool) -> void:
	var err := trade.buy(item) if buying else trade.sell(item)
	if err != "":
		build.message.emit(err)
	_refresh()


func _on_research(id: String) -> void:
	var err := research.start(id, progression)
	if err != "":
		build.message.emit(err)
	_refresh()


func _on_train(unit_id: String) -> void:
	var err := military.train(building, unit_id)
	if err != "":
		build.message.emit(err)
	_refresh()


func _on_demolish() -> void:
	if building != null:
		world.demolish_at(building.origin)
