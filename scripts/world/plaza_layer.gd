class_name PlazaLayer
extends Node2D
## Draws plaza paving (WorldMap.plazas) over the road tiles it sits on:
## the cobblestone tile art, or grey setts drawn in code without it.

const ART := "res://assets/tiles/plaza.png"

var world: WorldMap


func _draw() -> void:
	var tex := Art.texture(ART)
	var tile := Terrain.TILE_SIZE
	for t: Vector2i in world.plazas:
		var r := Rect2(Vector2(t * tile), Vector2(tile, tile))
		if tex != null:
			draw_texture_rect(tex, r, false)
		else:
			draw_rect(r, Color(0.66, 0.64, 0.6))
			for i in 4:
				draw_line(r.position + Vector2(0, i * 8), r.position + Vector2(tile, i * 8), Color(0.45, 0.43, 0.4), 1.0)
