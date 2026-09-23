class_name ItemDefs
extends RefCounted
## Every tradeable good. `category` decides which storage buildings accept it
## and which capacity pool it counts against. Gold is a treasury (uncapped).

const ITEMS := {
	"wood": {"name": "Wood", "category": "materials", "color": Color(0.55, 0.36, 0.18)},
	"stone": {"name": "Stone", "category": "materials", "color": Color(0.75, 0.75, 0.75)},
	"iron": {"name": "Iron", "category": "materials", "color": Color(0.62, 0.36, 0.28)},
	"weapons": {"name": "Weapons", "category": "materials", "color": Color(0.80, 0.82, 0.88)},
	"armor": {"name": "Armor", "category": "materials", "color": Color(0.45, 0.50, 0.62)},
	"wheat": {"name": "Wheat", "category": "food", "color": Color(0.93, 0.80, 0.35)},
	"flour": {"name": "Flour", "category": "food", "color": Color(0.97, 0.95, 0.88)},
	"bread": {"name": "Bread", "category": "food", "color": Color(0.80, 0.52, 0.25), "edible": true},
	"fish": {"name": "Fish", "category": "food", "color": Color(0.55, 0.70, 0.85), "edible": true},
	"gold": {"name": "Gold", "category": "treasury", "color": Color(0.95, 0.80, 0.25)},
}

## Categories limited by storage capacity.
const CAPPED_CATEGORIES := ["materials", "food"]
const EDIBLE := ["bread", "fish"]


static func category_of(item: String) -> String:
	return ITEMS[item].category


static func is_edible(item: String) -> bool:
	return ITEMS[item].get("edible", false)


static func color_of(item: String) -> Color:
	return ITEMS[item].color


static func display_name(item: String) -> String:
	return ITEMS[item].name


static func items_in(category: String) -> Array[String]:
	var result: Array[String] = []
	for id: String in ITEMS:
		if ITEMS[id].category == category:
			result.append(id)
	return result
