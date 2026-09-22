# Build and inspect

The player picks a building from the bottom build bar, places it on the map
with a green/red preview, drags roads, watches villagers move into housing,
and clicks a building to open its panel with residents, workers and status.

## Sub-features

- `build-menu` opens placement mode from a category tab and item button.
- `build-place` places a building where the preview is valid and spends its cost.
- `road-drag` lays an L-shaped road from the drag start to the release point.
- `housing-growth` fills new housing with villagers over time.
- `inspect` shows the building panel with residents when a building is clicked.

## How to get to it (user POV)

- Click a category tab (`Housing`) then an item (`[1] House`), or press `Tab`
  to cycle categories and `1`-`9` to pick an item.
- Press `R` (or click `[R] Road`) and drag on the map for roads.
- Left-click an existing building to open its panel; `Escape` closes it.

## Driving it with tools/verify/run.sh

Preconditions:

- Fresh run, Hamlet tier, 120 wood (a House costs 20).

- **Open placement.** Run steps `{"click_button": "Housing"}`, `{"click_button": "] House"}`. `expect` `build_mode` = `BUILD` and visible text `Placing House`.
- **Place.** `{"find_site": {"building": "house", "as": "h1", "entrance_on_road": true}}` then `{"click_tile": "h1"}`. `expect` `buildings.house` = 1.
- **Drag road.** `{"key": "R"}`, `{"drag_tile": [[6, 3], [12, 3]]}`. `expect` `min.roads` = 21 (14 starting tiles + 7).
- **Villagers move in.** `{"wait_game": 30}`. `expect` `min.population` = 6.
- **Inspect.** `{"key": "Escape"}`, `{"click_tile": "h1"}`. `expect` `selected_building` = `House` and text `Residents:`.
- **Proof.** `tools/verify/run.sh tools/verify/scenarios/build-and-inspect.json` exits 0; `03-house-inspector.png` shows the yellow selection outline and the panel listing residents by name.

## Gotchas

- `click_button` matches substrings: `House` also matches `Stone House` and
  would miss if ordering changes. Use `] House`.
- A building whose entrance isn't on a road shows a red `!` and never gets
  residents; use `"entrance_on_road": true` or drag a road to it.
- Roads are free, but dragging over water skips those tiles; assert the road
  count, not just that the drag happened.
- The first 4 villagers live in the Keep. Population above 4 is what proves the
  new house works.
