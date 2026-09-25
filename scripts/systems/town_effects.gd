class_name TownEffects
extends Node2D
## Small signs of life on the buildings: smoke curling from chimneys of
## lived-in homes and working bakeries and smithies (more in winter), and
## warm light in the windows of homes at night. The window glow is drawn on
## its own canvas layer so the night tint doesn't dim it.

## Buildings with a chimney, and where it sits on the sprite (fractions of
## the sprite's width and height from its top-left).
const CHIMNEYS := {
	"house": Vector2(0.72, 0.12), "stone_house": Vector2(0.7, 0.1), "bakery": Vector2(0.7, 0.1),
	"smithy": Vector2(0.72, 0.12), "armory": Vector2(0.7, 0.12), "tavern": Vector2(0.7, 0.1),
	"keep": Vector2(0.62, 0.08),
}
const PUFF_LIFE := 3.2
const PUFF_EVERY := [0.9, 1.6]

var world: WorldMap
var puffs: Array = []  # {"pos", "age", "drift"}
var glows := 0

var _emit_timers := {}  # Building -> seconds to next puff
var _glow_layer: CanvasLayer
var _glow_canvas: Node2D
var _glow_tex: Texture2D
var _night := 0.0  # 0 day .. 1 night (eases)


func _ready() -> void:
	z_index = 5
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.78, 0.4, 0.75))
	grad.set_color(1, Color(1.0, 0.6, 0.2, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 32
	tex.height = 32
	_glow_tex = tex
	_glow_layer = CanvasLayer.new()
	_glow_layer.follow_viewport_enabled = true
	_glow_layer.layer = 0
	add_child(_glow_layer)
	_glow_canvas = Node2D.new()
	_glow_canvas.draw.connect(_draw_glows)
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow_canvas.material = mat
	_glow_layer.add_child(_glow_canvas)


func _process(delta: float) -> void:
	_night = move_toward(_night, 1.0 if world.is_night else 0.0, delta * 0.5)
	var winter := Art.season == "winter"
	for b in world.buildings:
		if not CHIMNEYS.has(b.def_id) or not _smokes(b):
			continue
		var t: float = _emit_timers.get(b, randf() * PUFF_EVERY[1])
		t -= delta * (1.6 if winter else 1.0)
		if t <= 0.0:
			t = randf_range(PUFF_EVERY[0], PUFF_EVERY[1])
			puffs.append({"pos": _chimney(b), "age": 0.0, "drift": randf_range(3.0, 7.0)})
		_emit_timers[b] = t
	for p: Dictionary in puffs:
		p.age += delta
		p.pos += Vector2(p.drift, -14.0) * delta
	puffs = puffs.filter(func(p: Dictionary) -> bool: return p.age < PUFF_LIFE)
	queue_redraw()
	_glow_canvas.queue_redraw()


## Homes smoke when someone lives there; workshops while someone works.
func _smokes(b: Building) -> bool:
	if b == world.keep:
		return true
	if b.is_home():
		return not b.residents.is_empty()
	return not b.workers.is_empty()


func _chimney(b: Building) -> Vector2:
	var sprite := Art.building(b.sprite_id())
	var px := Vector2(b.size * Terrain.TILE_SIZE)
	if sprite == null:
		return b.position + Vector2(px.x * 0.7, 0)
	var size := Vector2(sprite.get_size())
	var top_left := b.position + Vector2((px.x - size.x) * 0.5, px.y - size.y)
	return top_left + size * CHIMNEYS[b.def_id]


func _draw() -> void:
	for p: Dictionary in puffs:
		var k: float = p.age / PUFF_LIFE
		var r := lerpf(3.0, 10.0, k)
		var a := (1.0 - k) * 0.6 * (0.6 if k < 0.1 else 1.0)
		draw_circle(p.pos, r, Color(0.78, 0.76, 0.74, a))
		draw_circle(p.pos + Vector2(-r * 0.3, -r * 0.2), r * 0.6, Color(0.9, 0.88, 0.86, a * 0.6))


## Warm window light in lived-in homes (and the castle) at night.
func _draw_glows() -> void:
	glows = 0
	if _night <= 0.01:
		return
	var flicker := 0.92 + 0.08 * sin(Time.get_ticks_msec() / 180.0)
	for b in world.buildings:
		if not (b == world.keep or (b.is_home() and not b.residents.is_empty())):
			continue
		var px := Vector2(b.size * Terrain.TILE_SIZE)
		var at := b.position + Vector2(px.x * 0.5, px.y * 0.62)
		var r := 18.0 if b == world.keep else 11.0
		var c := Color(1, 1, 1, _night * flicker)
		_glow_canvas.draw_texture_rect(_glow_tex, Rect2(at - Vector2(r, r), Vector2(r, r) * 2.0), false, c)
		glows += 1
