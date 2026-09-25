class_name TradeDefs
extends RefCounted
## Prices and travelling merchants.
##
## Every tradeable good has a base price in gold per unit. A merchant sells
## its specialty (`sells`) cheaply and pays well for what it `wants`; any
## other good it trades at a worse rate. Merchants arrive with limited stock
## and a purse of gold, so they can't take everything off your hands.

const LOT := 10
const PRICES := {
	"wood": 1.0, "stone": 1.5, "iron": 4.0, "weapons": 12.0, "armor": 18.0,
	"wheat": 1.0, "flour": 2.0, "bread": 2.5, "fish": 2.0,
	"wool": 1.5, "grapes": 1.5, "ale": 3.0, "tools": 6.0, "cloth": 4.0, "wine": 8.0, "fine_clothes": 14.0,
}
## Multipliers on the base price.
const SELL_SPECIALTY := 0.9     # what you pay for the merchant's specialty
const SELL_OTHER := 1.4         # what you pay for anything else it carries
const BUY_WANTED := 1.2         # what it pays for goods it wants
const BUY_OTHER := 0.6          # what it pays for anything else

const MERCHANTS := {
	"timber": {"name": "Timber merchant", "sells": {"wood": 120, "stone": 60},
		"carries": {"bread": 20}, "wants": ["bread", "fish", "wheat"], "gold": 250},
	"grain": {"name": "Grain trader", "sells": {"wheat": 80, "bread": 60, "fish": 40},
		"carries": {"wood": 20}, "wants": ["wood", "stone"], "gold": 250},
	"iron": {"name": "Ironmonger", "sells": {"iron": 40, "weapons": 10, "armor": 4},
		"carries": {"stone": 30}, "wants": ["stone", "bread", "fish"], "gold": 350},
	"clothier": {"name": "Cloth & wine merchant", "sells": {"wine": 20, "fine_clothes": 10, "cloth": 20},
		"carries": {"ale": 20}, "wants": ["tools", "wool", "grapes"], "gold": 400},
	"peddler": {"name": "Peddler", "sells": {},
		"carries": {"wood": 40, "stone": 30, "bread": 30, "fish": 20, "iron": 10, "ale": 10, "cloth": 5},
		"wants": [], "gold": 200},
}
## Which merchants can appear at each tier (index = tier).
const BY_TIER := [
	["timber", "grain", "peddler"],
	["timber", "grain", "peddler"],
	["timber", "grain", "iron", "clothier", "peddler"],
	["timber", "grain", "iron", "clothier", "peddler"],
	["timber", "grain", "iron", "clothier", "peddler"],
]


static func items() -> Array:
	return PRICES.keys()
