class_name PlazaLayer
extends Node2D
## Draws paving over road tiles: plazas (WorldMap.plazas) and upgraded
## roads (WorldMap.road_tiers: cobblestone, paved street), with the tile
## art or a code-drawn stand-in.

const ART := "res://assets/tiles/plaza.png"
const TIER_ART := ["", "res://assets/tiles/road_cobble.png", "res://assets/tiles/road_paved.png"]
const TIER_COLORS := [Color.TRANSPARENT, Color(0.55, 0.5, 0.45), Color(0.82, 0.76, 0.62)]

var world: WorldMap


func _draw() -> void:
	var tex := Art.texture(ART)
	var tile := Terrain.TILE_SIZE
	for t: Vector2i in world.road_tiers:
		if world.plazas.has(t):
			continue
		var tier: int = world.road_tiers[t]
		var r := Rect2(Vector2(t * tile), Vector2(tile, tile))
		var ttex := Art.texture(TIER_ART[tier])
		if ttex != null:
			draw_texture_rect(ttex, r, false)
		else:
			draw_rect(r, TIER_COLORS[tier])
	for t: Vector2i in world.plazas:
		var r := Rect2(Vector2(t * tile), Vector2(tile, tile))
		if tex != null:
			draw_texture_rect(tex, r, false)
		else:
			draw_rect(r, Color(0.66, 0.64, 0.6))
			for i in 4:
				draw_line(r.position + Vector2(0, i * 8), r.position + Vector2(tile, i * 8), Color(0.45, 0.43, 0.4), 1.0)
