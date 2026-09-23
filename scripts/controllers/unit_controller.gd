class_name UnitController
extends Node2D
## Selecting and commanding squads (only when no build tool is active).
##   Left-click a troop: select its squad.   Left-drag: box-select squads.
##   Right-click ground: move there.         Right-click a raider: attack it.
##   G: release to automatic guard at the current spot.
##   Ctrl+1..9: select squad N.              Esc: deselect.

signal selection_changed

const CLICK_RADIUS := 12.0
const DRAG_THRESHOLD := 6.0

var world: WorldMap
var build: BuildController
var military: Military
var selected: Array[Squad] = []

var _press_pos := Vector2.ZERO
## Cursor in world space, from the latest mouse event.
var _mouse_world := Vector2.ZERO
var _pressing := false
var _box_active := false


func setup(p_world: WorldMap, p_build: BuildController, p_military: Military) -> void:
	world = p_world
	build = p_build
	military = p_military


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 11
	military.squads_changed.connect(_prune_selection)
	build.building_selected.connect(func(b: Building) -> void:
		if b != null:
			_set_selection([]))


func _process(_delta: float) -> void:
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouse:
		_mouse_world = get_canvas_transform().affine_inverse() * event.position
	if build.mode != BuildController.Mode.NONE:
		_pressing = false
		_box_active = false
		return
	if event is InputEventKey and event.pressed and not event.echo:
		_handle_key(event)
	elif event is InputEventMouseButton:
		_handle_button(event)
	elif event is InputEventMouseMotion and _pressing:
		if _mouse_world.distance_to(_press_pos) > DRAG_THRESHOLD:
			_box_active = true


func _handle_key(event: InputEventKey) -> void:
	if event.ctrl_pressed and event.keycode >= KEY_1 and event.keycode <= KEY_9:
		var index := event.keycode - KEY_1
		var live := military.squads.filter(func(s: Squad) -> bool: return not s.troops.is_empty())
		if index < live.size():
			build.select_building(null)
			_set_selection([live[index]])
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_G and not selected.is_empty():
		for s in selected:
			s.release()
		GameState.notify("Squad released: guarding this position")
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ESCAPE and not selected.is_empty():
		_set_selection([])
		get_viewport().set_input_as_handled()


func _handle_button(event: InputEventMouseButton) -> void:
	var pos := _mouse_world
	if event.button_index == MOUSE_BUTTON_LEFT:
		# Presses fall through so the build controller can select buildings;
		# on release we override that if a troop or box was selected.
		if event.pressed:
			_pressing = true
			_box_active = false
			_press_pos = pos
			return
		if not _pressing:
			return
		_pressing = false
		if _box_active:
			_box_active = false
			_set_selection(_squads_in_rect(Rect2(_press_pos, pos - _press_pos).abs()))
		else:
			var troop := _troop_at(pos)
			_set_selection([troop.squad] if troop != null else [])
		if not selected.is_empty():
			build.select_building(null)
	elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed and not selected.is_empty():
		var enemy := _enemy_at(pos)
		for s in selected:
			if enemy != null:
				s.order_attack(enemy, world)
			else:
				s.order_move(world.world_to_tile(pos))
		get_viewport().set_input_as_handled()


func _set_selection(squads: Array) -> void:
	for s in selected:
		s.selected = false
		_redraw_troops(s)
	selected.clear()
	for s: Squad in squads:
		if not s.troops.is_empty():
			s.selected = true
			selected.append(s)
			_redraw_troops(s)
	selection_changed.emit()


func _prune_selection() -> void:
	var live := selected.filter(func(s: Squad) -> bool: return not s.troops.is_empty())
	if live.size() != selected.size():
		_set_selection(live)
	else:
		selection_changed.emit()


func _redraw_troops(s: Squad) -> void:
	for t in s.troops:
		t.queue_redraw()


func _troop_at(pos: Vector2) -> Troop:
	for t: Troop in get_tree().get_nodes_in_group("troops"):
		if t.position.distance_to(pos) <= CLICK_RADIUS:
			return t
	return null


func _enemy_at(pos: Vector2) -> Enemy:
	for e in world.hostiles():
		if e.is_lair():
			# The den is drawn well above its foot point: hit-test the sprite.
			var r: float = e.def.radius
			if Rect2(e.position + Vector2(-r * 1.7, -r * 3.2), Vector2(r * 3.4, r * 3.8)).has_point(pos):
				return e
		elif e.position.distance_to(pos) <= CLICK_RADIUS + 4.0:
			return e
	return null


func _squads_in_rect(rect: Rect2) -> Array:
	var found: Array = []
	for s in military.squads:
		for t in s.troops:
			if rect.has_point(t.position):
				found.append(s)
				break
	return found


func _draw() -> void:
	var tile := Terrain.TILE_SIZE
	# Rally flags for every squad; order markers for selected manual squads.
	for s in military.squads:
		if s.troops.is_empty():
			continue
		var flag := world.tile_center(s.rally_tile)
		var color := Color(0.4, 1.0, 0.4) if s.selected else Color(0.9, 0.9, 0.9, 0.7)
		draw_line(flag + Vector2(-6, 8), flag + Vector2(-6, -10), Color(0.3, 0.2, 0.1), 2.0)
		draw_colored_polygon(PackedVector2Array([flag + Vector2(-6, -10), flag + Vector2(6, -6), flag + Vector2(-6, -2)]), color)
		if s.selected:
			draw_arc(flag, Squad.GUARD_TILES * tile, 0, TAU, 48, Color(0.4, 1.0, 0.4, 0.25), 1.5)
			if s.mode == Squad.Mode.MANUAL:
				var goal := world.tile_center(s.order_tile)
				draw_line(s.center(), goal, Color(0.4, 1.0, 0.4, 0.5), 1.5)
				draw_arc(goal, 6.0, 0, TAU, 16, Color(0.4, 1.0, 0.4), 2.0)
	if _box_active:
		var rect := Rect2(_press_pos, _mouse_world - _press_pos).abs()
		draw_rect(rect, Color(0.4, 1.0, 0.4, 0.15))
		draw_rect(rect, Color(0.4, 1.0, 0.4, 0.8), false, 1.5)
