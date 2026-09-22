class_name Health
extends RefCounted
## Hit points shared by buildings, villagers and enemies.

signal changed
signal died

var max_hp := 1.0
var hp := 1.0


func _init(p_max_hp: float) -> void:
	max_hp = p_max_hp
	hp = p_max_hp


func take_damage(amount: float) -> void:
	if is_dead():
		return
	hp = maxf(hp - amount, 0.0)
	changed.emit()
	if is_dead():
		died.emit()


func heal(amount: float) -> void:
	if is_dead() or hp >= max_hp:
		return
	hp = minf(hp + amount, max_hp)
	changed.emit()


func is_dead() -> bool:
	return hp <= 0.0


func is_damaged() -> bool:
	return hp < max_hp


## Draws a small health bar centered at `center` when damaged.
func draw_bar(canvas: CanvasItem, center: Vector2, width: float) -> void:
	if not is_damaged():
		return
	var rect := Rect2(center - Vector2(width * 0.5, 0), Vector2(width, 4))
	canvas.draw_rect(rect.grow(1), Color(0, 0, 0, 0.7))
	var ratio := hp / max_hp
	var color := Color(0.3, 0.85, 0.3) if ratio > 0.5 else (Color(0.95, 0.75, 0.2) if ratio > 0.25 else Color(0.9, 0.2, 0.15))
	canvas.draw_rect(Rect2(rect.position, Vector2(width * ratio, 4)), color)
