class_name BridgeLayer
extends Node2D
## Draws bridges: road tiles laid over water. Each tile shows a plank
## section running toward its road neighbours (east-west or north-south).
## Sits under the building and unit layers so people walk across on top.

const ART := "res://assets/sprites/bridges/%s.png"

var world: WorldMap


func _draw() -> void:
	var h := Art.seasonal(ART, "wood_h")
	var v := Art.seasonal(ART, "wood_v")
	var tile := float(Terrain.TILE_SIZE)
	for t: Vector2i in world.roads:
		if world.get_terrain(t) != Terrain.WATER:
			continue
		var across_x := world.roads.has(t + Vector2i.LEFT) or world.roads.has(t + Vector2i.RIGHT)
		var across_y := world.roads.has(t + Vector2i.UP) or world.roads.has(t + Vector2i.DOWN)
		var rect := Rect2(Vector2(t) * tile, Vector2(tile, tile))
		var tex := v if across_y and not across_x else h
		if tex != null:
			# The plank section is centred on the tile, stretched along the
			# crossing only (the art tiles seamlessly that way).
			var along_x := tex == h
			var size := Vector2(tile, tex.get_height()) if along_x else Vector2(tex.get_width(), tile)
			var at := rect.get_center() - size * 0.5
			draw_texture_rect(tex, Rect2(at, size), true)
		else:
			draw_rect(rect.grow(-3), Color(0.45, 0.30, 0.16))
			for i in 4:
				var y := rect.position.y + 5 + i * 7
				draw_line(Vector2(rect.position.x + 3, y), Vector2(rect.end.x - 3, y), Color(0.3, 0.2, 0.1), 1.0)
