class_name Minimap
extends PanelContainer
## Corner map: terrain in the season's colours, roads and bridges, buildings,
## walls, lairs, raiders and troops, and a frame showing what the camera
## sees. Click or drag on it to move the camera. M toggles it.

const SIZE := 200.0
const REFRESH := 3.0
## Terrain colours per art season (index = Terrain type).
const PALETTES := {
	"autumn": [Color("3a6fb0"), Color("e6cf8f"), Color("b59a3c"), Color("c9651f"), Color("8a8a86"), Color("8b6a3a")],
	"winter": [Color("33609e"), Color("e0d2a8"), Color("e8eef2"), Color("5d7a6a"), Color("9aa0a6"), Color("b9b3a6")],
	"summer": [Color("3a6fb0"), Color("e6cf8f"), Color("6f9a3a"), Color("2f6a2a"), Color("8a8a86"), Color("8b6a3a")],
	"": [Color("3a6fb0"), Color("e6cf8f"), Color("6f9a3a"), Color("2f6a2a"), Color("8a8a86"), Color("8b6a3a")],
}
const ROAD := Color("efe4c8")
const BRIDGE := Color("8a5a2b")
const BUILDING := Color("7a3b2e")
const KEEP := Color("f2c14e")
const WALL := Color("d9d9d9")
const RAIDER := Color("ff3b30")
const TROOP := Color("4fc3ff")
const LAIR := Color("2a0f0f")

var world: WorldMap
var camera: Camera2D

var _map: TextureRect
var _overlay: Control
var _image: Image
var _texture: ImageTexture
var _refresh := 0.0
var _season_drawn := "?"
var _dragging := false


func setup(p_world: WorldMap, p_camera: Camera2D) -> void:
	world = p_world
	camera = p_camera


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(SIZE, SIZE) + Vector2(12, 12)
	_map = TextureRect.new()
	_map.custom_minimum_size = Vector2(SIZE, SIZE)
	_map.stretch_mode = TextureRect.STRETCH_SCALE
	_map.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_map)
	_overlay = Control.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	_map.add_child(_overlay)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tooltip_text = "Minimap: click or drag to look around (M hides it)"
	_image = Image.create(world.width, world.height, false, Image.FORMAT_RGB8)
	_texture = ImageTexture.create_from_image(_image)
	_map.texture = _texture
	_paint()


func _process(delta: float) -> void:
	if not visible:
		return
	_refresh -= delta / maxf(Engine.time_scale, 0.001)
	if _refresh <= 0.0 or _season_drawn != Art.season:
		_paint()
	_overlay.queue_redraw()


## Terrain and roads into the image (cheap enough every few seconds).
func _paint() -> void:
	_refresh = REFRESH
	_season_drawn = Art.season
	var colors: Array = PALETTES.get(Art.season, PALETTES[""])
	for y in world.height:
		for x in world.width:
			_image.set_pixel(x, y, colors[world.terrain[y * world.width + x]])
	for t: Vector2i in world.roads:
		_image.set_pixel(t.x, t.y, BRIDGE if world.get_terrain(t) == Terrain.WATER else ROAD)
	_texture.update(_image)


func _scale() -> Vector2:
	return _map.size / Vector2(world.width, world.height)


func _draw_overlay() -> void:
	var k := _scale()
	for b in world.buildings:
		var r := Rect2(Vector2(b.origin) * k, Vector2(b.size) * k)
		var c := KEEP if b == world.keep else (WALL if BuildingDefs.is_fortification(b.def) else BUILDING)
		_overlay.draw_rect(r.grow(0.5) if b.size.x == 1 else r, c)
	var px := k / Terrain.TILE_SIZE
	for lair in world.lairs():
		var p := lair.position * px
		_overlay.draw_rect(Rect2(p - Vector2(3, 3), Vector2(6, 6)), LAIR)
		_overlay.draw_rect(Rect2(p - Vector2(3, 3), Vector2(6, 6)), RAIDER, false, 1.0)
	for t: Troop in get_tree().get_nodes_in_group("troops"):
		_overlay.draw_circle(t.position * px, 1.6, TROOP)
	for e in world.enemies:
		_overlay.draw_circle(e.position * px, 2.2 if e.def.get("large", false) else 1.6, RAIDER)
	# What the camera sees.
	var view := get_viewport().get_visible_rect()
	var inv := camera.get_canvas_transform().affine_inverse()
	var tl: Vector2 = inv * view.position
	var br: Vector2 = inv * view.end
	_overlay.draw_rect(Rect2(tl * px, (br - tl) * px), Color(1, 1, 1, 0.9), false, 1.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if event.pressed:
			_look_at(event.position)
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_look_at(event.position)
		accept_event()


## Centres the camera on the map point under `local` (minimap coordinates).
func _look_at(local: Vector2) -> void:
	var on_map := (local - _map.position) / _scale()
	on_map = on_map.clamp(Vector2.ZERO, Vector2(world.width, world.height))
	camera.position = on_map * Terrain.TILE_SIZE
