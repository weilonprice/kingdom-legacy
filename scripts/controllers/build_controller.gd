class_name BuildController
extends Node2D
## Handles placing buildings, dragging roads, demolishing and selecting
## buildings, plus the ghost preview. Building hotkeys (1-9) live in the HUD.

signal mode_changed(text: String)
signal message(text: String)
signal building_selected(building: Building)
## A member of the royal family was clicked (role: ruler/spouse/heir).
signal royal_clicked(role: String)

enum Mode { NONE, BUILD, ROAD, WALL, DEMOLISH }

const HOTKEYS := {KEY_R: "road", KEY_X: "demolish"}
const COLOR_OK := Color(0.3, 1.0, 0.4, 0.45)
const COLOR_BAD := Color(1.0, 0.25, 0.2, 0.45)
const COLOR_BRIDGE := Color(0.35, 0.7, 1.0, 0.5)
const COLOR_GATE := Color(1.0, 0.8, 0.25, 0.55)
## Wall tiles you couldn't pay for (the drag runs out of materials there).
const COLOR_SHORT := Color(1.0, 0.6, 0.15, 0.5)

var world: WorldMap
var progression: Progression
var mode := Mode.NONE
var build_id := ""
var hover_tile := Vector2i.ZERO
var selected: Building

## Last cursor position in screen space, taken from mouse events (polling the
## viewport would miss injected input and lag behind the event being handled).
var _mouse_screen := Vector2.ZERO
var _drag_start := Vector2i.ZERO
var _dragging := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 10
	GameState.resources_changed.connect(queue_redraw)
	world.building_removed.connect(func(b: Building) -> void:
		if b == selected:
			select_building(null))


func select(id: String) -> void:
	match id:
		"road":
			mode = Mode.ROAD
		"demolish":
			mode = Mode.DEMOLISH
		_:
			var locked := progression.locked_reason("buildings", id) if progression != null else ""
			if locked != "":
				message.emit("%s: %s" % [BuildingDefs.get_def(id).name, locked])
				return
			build_id = id
			mode = Mode.WALL if BuildingDefs.get_def(id).get("drag", false) else Mode.BUILD
	_dragging = false
	mode_changed.emit(mode_text())
	queue_redraw()


func select_building(b: Building) -> void:
	selected = b
	building_selected.emit(b)
	queue_redraw()


func cancel() -> void:
	mode = Mode.NONE
	_dragging = false
	mode_changed.emit(mode_text())
	queue_redraw()


func mode_text() -> String:
	match mode:
		Mode.BUILD:
			var def := BuildingDefs.get_def(build_id)
			return "Placing %s (%s) — right-click to cancel" % [def.name, BuildingDefs.cost_text(def.cost)]
		Mode.ROAD:
			return "Road — drag to lay a path (across water it builds a bridge: %s per tile), right-click to cancel" % \
				BuildingDefs.cost_text(WorldMap.BRIDGE_COST)
		Mode.WALL:
			var wdef := BuildingDefs.get_def(build_id)
			return "%s — drag to build (%s per segment; gates where it crosses a road), right-click to cancel" % [
				wdef.name, BuildingDefs.cost_text(wdef.cost)]
		Mode.DEMOLISH:
			return "Demolish — click a building or road (50% refund)"
	return ""


## Recomputed every frame too, since the camera can move under a still cursor.
func _process(_delta: float) -> void:
	_update_hover()


func _update_hover() -> void:
	var t: Vector2i = world.world_to_tile(get_canvas_transform().affine_inverse() * _mouse_screen)
	if t != hover_tile:
		hover_tile = t
		queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouse:
		_mouse_screen = event.position
		_update_hover()
	if event is InputEventKey and event.pressed and not event.echo:
		if HOTKEYS.has(event.keycode):
			select(HOTKEYS[event.keycode])
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE:
			if mode == Mode.NONE:
				select_building(null)
			cancel()
			get_viewport().set_input_as_handled()
		return

	if not event is InputEventMouseButton:
		return
	if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		cancel()
		get_viewport().set_input_as_handled()
		return
	if event.button_index != MOUSE_BUTTON_LEFT:
		return

	match mode:
		Mode.NONE:
			if not event.pressed:
				return
			# A royal takes the click only on open ground: buildings win, so a
			# stroll past the barracks never hides it.
			var royals: Royals = world.get_parent().get("royals")
			var role := ""
			if royals != null and not world.occupancy.has(hover_tile):
				role = royals.royal_at(get_canvas_transform().affine_inverse() * _mouse_screen)
			if role != "":
				royal_clicked.emit(role)
			else:
				select_building(world.occupancy.get(hover_tile))
		Mode.BUILD:
			if event.pressed:
				_try_build()
		Mode.ROAD, Mode.WALL:
			if event.pressed:
				_dragging = true
				_drag_start = hover_tile
			elif _dragging:
				var tiles := _drag_tiles()  # before clearing the flag it depends on
				_dragging = false
				if mode == Mode.ROAD:
					world.place_roads(tiles)
					_emit_if(world.road_problem)
				else:
					_build_wall(tiles)
		Mode.DEMOLISH:
			if event.pressed:
				_emit_if(world.demolish_at(hover_tile))
	queue_redraw()
	get_viewport().set_input_as_handled()


func _try_build() -> void:
	var origin := _build_origin()
	var def := BuildingDefs.get_def(build_id)
	var err: String = world.can_place_building(build_id, origin)
	if err != "":
		message.emit(err)
	elif not GameState.spend(def.cost):
		message.emit("Not enough resources — needs %s" % BuildingDefs.cost_text(def.cost))
	else:
		world.place_building(build_id, origin)


## Places a segment on each free tile of the drag, paying per segment, and
## stops when materials run out.
## What a wall drag would build: per tile {t, id ("" = can't build there),
## affordable}. Where the wall crosses a road it becomes a gate, so walls
## never cut the town off.
func wall_plan(tiles: Array[Vector2i]) -> Array:
	var plan := []
	var left := GameState.resources.duplicate()
	for t in tiles:
		var id := build_id
		if world.is_road(t) and not world.occupancy.has(t):
			id = "gate"
		if world.can_place_building(id, t) != "":
			plan.append({"t": t, "id": "", "affordable": false})
			continue
		var cost: Dictionary = BuildingDefs.get_def(id).cost
		var ok := cost.keys().all(func(item: String) -> bool: return left.get(item, 0) >= cost[item])
		if ok:
			for item: String in cost:
				left[item] = left.get(item, 0) - cost[item]
		plan.append({"t": t, "id": id, "affordable": ok})
	return plan


## "12 segments + 2 gates — 72 stone, 40 wood" for a plan.
func wall_plan_text(plan: Array) -> String:
	var walls := 0
	var gates := 0
	var total := {}
	var short := 0
	for p: Dictionary in plan:
		if p.id == "":
			continue
		if not p.affordable:
			short += 1
		if p.id == "gate":
			gates += 1
		else:
			walls += 1
		var cost: Dictionary = BuildingDefs.get_def(p.id).cost
		for item: String in cost:
			total[item] = total.get(item, 0) + cost[item]
	var text := "%d segment%s" % [walls, "" if walls == 1 else "s"]
	if gates > 0:
		text += " + %d gate%s" % [gates, "" if gates == 1 else "s"]
	text += " — " + BuildingDefs.cost_text(total)
	if short > 0:
		text += "  (short for %d)" % short
	return text


func _build_wall(tiles: Array[Vector2i]) -> void:
	var built := 0
	for p: Dictionary in wall_plan(tiles):
		if p.id == "":
			continue
		var cost: Dictionary = BuildingDefs.get_def(p.id).cost
		if not GameState.spend(cost):
			message.emit("Ran out of materials after %d segments" % built)
			return
		world.place_building(p.id, p.t)
		built += 1


func _emit_if(text: String) -> void:
	if text != "":
		message.emit(text)


func _build_origin() -> Vector2i:
	var size: Vector2i = BuildingDefs.get_def(build_id).size
	return hover_tile - Vector2i(int(size.x * 0.5), int(size.y * 0.5))


## Road/wall drag: an L-shaped path, horizontal from the drag start, then vertical to the cursor.
func _drag_tiles() -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	if not _dragging:
		tiles.append(hover_tile)
		return tiles
	var a := _drag_start
	var b := hover_tile
	var step_x := 1 if b.x >= a.x else -1
	for x in range(a.x, b.x + step_x, step_x):
		tiles.append(Vector2i(x, a.y))
	var step_y := 1 if b.y >= a.y else -1
	for y in range(a.y + step_y, b.y + step_y, step_y):
		tiles.append(Vector2i(b.x, y))
	return tiles


func _draw() -> void:
	var tile := Terrain.TILE_SIZE
	if selected != null:
		_draw_selection(selected)
	if mode in [Mode.BUILD, Mode.WALL] and world.castle_grounds.has_area():
		# The castle's reserved grounds, so players see why they can't build there.
		var g := Rect2(Vector2(world.castle_grounds.position * tile), Vector2(world.castle_grounds.size * tile))
		draw_rect(g, Color(0.95, 0.8, 0.3, 0.12))
		draw_rect(g, Color(0.95, 0.8, 0.3, 0.8), false, 2.0)
		draw_string(ThemeDB.fallback_font, g.position + Vector2(4, -6), "Castle grounds",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 0.9, 0.5))
	match mode:
		Mode.BUILD:
			var def := BuildingDefs.get_def(build_id)
			var origin := _build_origin()
			var size: Vector2i = def.size
			var ok: bool = world.can_place_building(build_id, origin) == "" and GameState.can_afford(def.cost)
			if def.has("fields") and ok:
				for t in world.field_candidates(origin, size, def.field_radius).slice(0, def.fields):
					draw_rect(Rect2(Vector2(t * tile), Vector2(tile, tile)), Color(0.9, 0.75, 0.3, 0.35))
			var color := COLOR_OK if ok else COLOR_BAD
			var rect := Rect2(Vector2(origin * tile), Vector2(size * tile))
			draw_rect(rect, color)
			draw_rect(rect, color.lightened(0.4), false, 2.0)
			var e := BuildingDefs.entrance_of(origin, size)
			draw_rect(Rect2(Vector2(e * tile), Vector2(tile, tile)), Color(1, 0.9, 0.3, 0.45))
			_draw_area(def, e)
		Mode.ROAD:
			var path := _drag_tiles()
			var bridge := {}
			for span: Array in world.bridge_spans(path).valid:
				var ok := GameState.can_afford(WorldMap.bridge_cost(span.size()))
				for t: Vector2i in span:
					bridge[t] = ok
			for t in path:
				var color := COLOR_OK if world.can_place_road(t) or world.is_road(t) else COLOR_BAD
				if bridge.has(t):
					color = COLOR_BRIDGE if bridge[t] else COLOR_BAD
				draw_rect(Rect2(Vector2(t * tile), Vector2(tile, tile)), color)
		Mode.WALL:
			var plan := wall_plan(_drag_tiles())
			for p: Dictionary in plan:
				var color := COLOR_BAD if p.id == "" else (
					COLOR_SHORT if not p.affordable else (COLOR_GATE if p.id == "gate" else COLOR_OK))
				draw_rect(Rect2(Vector2(p.t * tile), Vector2(tile, tile)), color)
			if _dragging:
				# Length and cost beside the cursor, readable at any zoom.
				var at := Vector2(hover_tile * tile) + Vector2(tile * 1.2, -4)
				var size := 14.0 / get_canvas_transform().get_scale().x
				var text := wall_plan_text(plan)
				var font := ThemeDB.fallback_font
				var box := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(size))
				draw_rect(Rect2(at + Vector2(-4, -box.y * 0.85), box + Vector2(8, 4)), Color(0.1, 0.07, 0.04, 0.8))
				draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, int(size), Color(1, 0.95, 0.75))
		Mode.DEMOLISH:
			var rect := Rect2(Vector2(hover_tile * tile), Vector2(tile, tile))
			if world.occupancy.has(hover_tile):
				var b: Building = world.occupancy[hover_tile]
				rect = Rect2(Vector2(b.origin * tile), Vector2(b.size * tile))
			draw_rect(rect, COLOR_BAD)


func _draw_selection(b: Building) -> void:
	var tile := Terrain.TILE_SIZE
	draw_rect(Rect2(Vector2(b.origin * tile), Vector2(b.size * tile)), Color(1, 0.9, 0.3), false, 3.0)
	for t in b.fields:
		draw_rect(Rect2(Vector2(t * tile), Vector2(tile, tile)), Color(1, 0.9, 0.3, 0.8), false, 1.0)
	_draw_area(b.def, b.entrance())


## Outlines the work radius (gatherers), or the coverage circle of services.
func _draw_area(def: Dictionary, e: Vector2i) -> void:
	if def.has("coverage"):
		# Coverage is measured from the building's center, as a circle.
		var origin := e - Vector2i(int(def.size.x * 0.5), def.size.y)
		var c := Vector2(origin * Terrain.TILE_SIZE) + Vector2(def.size * Terrain.TILE_SIZE) * 0.5
		draw_arc(c, def.coverage * Terrain.TILE_SIZE, 0, TAU, 64, Color(0.5, 0.8, 1.0, 0.6), 2.0)
		return
	var r: int = def.get("radius", def.get("range", 0))
	if r <= 0:
		return
	var tile := Terrain.TILE_SIZE
	var area := Rect2(Vector2((e - Vector2i(r, r)) * tile), Vector2.ONE * (2 * r + 1) * tile)
	draw_rect(area, Color(1, 1, 1, 0.35), false, 2.0)
