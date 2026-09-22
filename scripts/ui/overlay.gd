class_name Overlay
extends Node2D
## Map overlays, cycled with O: happiness heatmap on homes, service coverage
## (which needs each home has), and road access for every building.

enum Mode { OFF, HAPPINESS, SERVICES, ROADS }

const NAMES := ["Off", "Happiness", "Services", "Road access"]
const NEED_COLORS := {
	"food": Color(0.95, 0.75, 0.3), "water": Color(0.35, 0.6, 1.0),
	"religion": Color(0.95, 0.95, 0.95), "market": Color(0.9, 0.4, 0.35),
	"tavern": Color(0.6, 0.4, 0.2),
}

var world: WorldMap
var mode := Mode.OFF


func _ready() -> void:
	z_index = 9
	process_mode = Node.PROCESS_MODE_ALWAYS


func cycle() -> String:
	mode = ((mode + 1) % NAMES.size()) as Mode
	queue_redraw()
	return "Overlay: %s (O to cycle)" % NAMES[mode]


func _process(_delta: float) -> void:
	if mode != Mode.OFF:
		queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	for b in world.buildings:
		var rect := Rect2(b.position, Vector2(b.size * Terrain.TILE_SIZE))
		match mode:
			Mode.HAPPINESS:
				if b.is_home():
					var t := b.happiness / 100.0
					draw_rect(rect, Color(1.0 - t, t, 0.2, 0.55))
					draw_string(font, rect.get_center() + Vector2(-10, 6), "%d" % b.happiness,
						HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
			Mode.SERVICES:
				if b.is_home():
					draw_rect(rect, Color(0, 0, 0, 0.45))
					var i := 0
					for need: String in NeedDefs.ORDER:
						var c: Color = NEED_COLORS[need]
						if not b.needs_met.get(need, false):
							c = Color(c, 0.15)
						draw_circle(rect.position + Vector2(8 + i * 11, rect.size.y * 0.5), 4.5, c)
						i += 1
				elif b.def.has("provides") and b.service_active():
					var c: Color = NEED_COLORS[b.def.provides]
					draw_arc(b.center(), b.def.coverage * Terrain.TILE_SIZE, 0, TAU, 64, Color(c, 0.6), 2.0)
			Mode.ROADS:
				draw_rect(rect, Color(0.2, 0.9, 0.3, 0.4) if b.has_road else Color(1, 0.15, 0.1, 0.55))
