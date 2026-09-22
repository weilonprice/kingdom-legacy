class_name BuildController
extends Node2D
## Handles placing buildings, dragging roads, demolishing and selecting
## buildings, plus the ghost preview. Building hotkeys (1-9) live in the HUD.

signal mode_changed(text: String)
signal message(text: String)
signal building_selected(building: Building)

enum Mode { NONE, BUILD, ROAD, DEMOLISH }

const HOTKEYS := {KEY_R: "road", KEY_X: "demolish"}
const COLOR_OK := Color(0.3, 1.0, 0.4, 0.45)
const COLOR_BAD := Color(1.0, 0.25, 0.2, 0.45)

var world: WorldMap
var mode := Mode.NONE
var build_id := ""
var hover_tile := Vector2i.ZERO
var selected: Building

var _road_start := Vector2i.ZERO
var _dragging_road := false


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
			mode = Mode.BUILD
			build_id = id
	_dragging_road = false
	mode_changed.emit(mode_text())
	queue_redraw()


func select_building(b: Building) -> void:
	selected = b
	building_selected.emit(b)
	queue_redraw()


func cancel() -> void:
	mode = Mode.NONE
	_dragging_road = false
	mode_changed.emit(mode_text())
	queue_redraw()


func mode_text() -> String:
	match mode:
		Mode.BUILD:
			var def := BuildingDefs.get_def(build_id)
			return "Placing %s (%s) — right-click to cancel" % [def.name, BuildingDefs.cost_text(def.cost)]
		Mode.ROAD:
			return "Road — drag to lay a path, right-click to cancel"
		Mode.DEMOLISH:
			return "Demolish — click a building or road (50% refund)"
	return ""


func _process(_delta: float) -> void:
	var t: Vector2i = world.world_to_tile(get_global_mouse_position())
	if t != hover_tile:
		hover_tile = t
		queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
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
			select_building(world.occupancy.get(hover_tile))
		Mode.BUILD:
			if event.pressed:
				_try_build()
		Mode.ROAD:
			if event.pressed:
				_dragging_road = true
				_road_start = hover_tile
			elif _dragging_road:
				_dragging_road = false
				world.place_roads(_road_tiles())
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


func _emit_if(text: String) -> void:
	if text != "":
		message.emit(text)


func _build_origin() -> Vector2i:
	var size: Vector2i = BuildingDefs.get_def(build_id).size
	return hover_tile - Vector2i(int(size.x * 0.5), int(size.y * 0.5))


## An L-shaped path: horizontal from the drag start, then vertical to the cursor.
func _road_tiles() -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	if not _dragging_road:
		tiles.append(hover_tile)
		return tiles
	var a := _road_start
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
			for t in _road_tiles():
				var color := COLOR_OK if world.can_place_road(t) or world.is_road(t) else COLOR_BAD
				draw_rect(Rect2(Vector2(t * tile), Vector2(tile, tile)), color)
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


## Outlines the work radius (gatherers) or coverage radius (services).
func _draw_area(def: Dictionary, e: Vector2i) -> void:
	var r: int = def.get("radius", def.get("coverage", def.get("range", 0)))
	if r <= 0:
		return
	var tile := Terrain.TILE_SIZE
	var area := Rect2(Vector2((e - Vector2i(r, r)) * tile), Vector2.ONE * (2 * r + 1) * tile)
	draw_rect(area, Color(1, 1, 1, 0.35), false, 2.0)
