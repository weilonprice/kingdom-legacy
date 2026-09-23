# Rivers and bridges

Every map has a river (two on Large) winding edge to edge 14-26 tiles from
the start, with two sandy fords anyone can wade. Dragging the Road tool
across water builds a bridge over each crossing of at most 5 tiles with land
at both ends (6 wood + 2 stone per tile, all or nothing per span). Bridges are
walkable for villagers, troops and raiders; demolishing a bridge tile
refunds half. Hovering shows `Bridge` or `Ford (shallow crossing)`.

## Sub-features

- `river` generated with the map (deterministic per seed).
- `ford` sand crossings with dry banks on both sides.
- `bridge-build` Road drag over water: blue preview for valid spans, red for
  too long or unaffordable; mode text mentions bridges.
- `bridge-refuse` `Bridges can span at most 5 tiles of water, with land at both
  ends` / `Not enough for a N-tile bridge (…)`.
- `bridge-demolish` `X` on a bridge tile removes it and refunds half.
- `bridge-art` plank sections (autumn/summer) and snowy ones in winter.

## How to get to it (user POV)

- `R`, then drag from one bank straight across the river to the other.

## Driving it with tools/verify/run.sh

- `tools/verify/run.sh tools/verify/scenarios/rivers-bridges.json`:
  `find_crossing` (2-5 water tiles near `[0,-20]`) → `pan_to` → `R` →
  `drag_tile` bank to bank → `expect` `min.bridges` 2, `bridges_walkable`;
  winter screenshot via `setup_season`; `find_crossing` 7+ tiles across a
  lake → drag → message `Bridges can span at most 5 tiles`; `X` on
  `bank_a_water` → one bridge fewer.
- Map checks: `godot --headless --path . res://tools/verify/map_preview.tscn --
  --seeds=12345,7 --out=/tmp/maps` saves overview images and prints how many
  edge points can reach the Keep (`--rivers=off` to compare).

## Gotchas

- Rivers changed seed 12345's map in M10; scenarios with hard-coded tiles far
  from the Keep may need re-checking.
- Crossings far from the Keep are off-screen: `pan_to` first.
