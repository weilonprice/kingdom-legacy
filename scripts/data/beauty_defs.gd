class_name BeautyDefs
extends RefCounted
## Desirability (see WorldMap.desirability_at): what each building does to
## the tiles around it, [value, radius in tiles]. The value fades linearly
## to nothing just past the radius. Decorations and some civic buildings
## make a place nicer; industry, storage and soldiers make it worse.

const SOURCES := {
	# Decorations
	"flowerbed": [5.0, 2], "avenue_tree": [4.0, 2], "garden": [10.0, 4], "fountain": [15.0, 5],
	"statue": [12.0, 4], "monument": [25.0, 7],
	# Civic
	"keep": [10.0, 6], "chapel": [6.0, 4], "market": [3.0, 3], "well": [2.0, 2], "tavern": [-2.0, 3],
	# Industry and work
	"woodcutter": [-4.0, 3], "forester": [-1.0, 2], "quarry": [-10.0, 4], "iron_mine": [-12.0, 5],
	"smithy": [-10.0, 4], "armory": [-8.0, 4], "mill": [-4.0, 3], "bakery": [-2.0, 2], "fisher": [-3.0, 3],
	"farm": [-2.0, 2], "brewery": [-3.0, 3], "toolmaker": [-6.0, 3], "sheep_farm": [-2.0, 2],
	"weaver": [-2.0, 2], "winery": [-2.0, 2], "vineyard": [2.0, 3],
	# Storage and soldiers
	"stockpile": [-4.0, 3], "warehouse": [-5.0, 3], "granary": [-2.0, 2], "carter": [-5.0, 3],
	"barracks": [-6.0, 4],
}
## Each paved plaza tile.
const PLAZA := [2.0, 2]
## Road tiles by tier (dirt, cobblestone, paved): [value, radius].
const PAVING := [[0.0, 0], [1.0, 1], [2.0, 1]]
const MIN := -40.0
const MAX := 80.0
## Homes need at least this much desirability to reach a level (index =
## level - 1): Townhouses can't sit in the worst industrial spots, Manors
## need a genuinely pleasant quarter.
const HOME_LEVEL_MIN := [-1000.0, -10.0, 20.0]
