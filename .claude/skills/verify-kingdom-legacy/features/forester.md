# Forester and forest regrowth

A Forester's Lodge (Resources tab, Hamlet) has one worker who plants a
sapling on open grass within 8 tiles (never on or beside roads, buildings,
doors or fields), preferring tiles next to trees. Saplings show as small
trees (two sizes) and become forest tiles after ~3 minutes; growth pauses in
winter. Forest cut down by woodcutters grows back by itself after 7 minutes
if it still touches forest. Hovering a sapling shows `Sapling — forest in
m:ss` (or `resting for winter`); the lodge's panel shows
`Saplings growing nearby: N`.

## Sub-features

- `plant` the forester's note `Going to plant a sapling` / `Planting a
  sapling`; `No open ground left to plant` when the area is full.
- `grow` saplings → forest (snapshot `saplings`, `forest`).
- `regrow` cut forest (`cleared`) → sapling after 420 s beside forest.
- `build-over` placing a building or road on a sapling removes it.
- `save` saves keep saplings and cleared tiles with their timers.

## How to get to it (user POV)

- Resources tab → Forester's Lodge on a road near a Woodcutter; wait at 4x.

## Driving it with tools/verify/run.sh

- `tools/verify/run.sh tools/verify/scenarios/forester.json`: village setup;
  place the lodge; `wait_until` `min.saplings` 3; lodge panel shows
  `Saplings growing nearby`; `setup_forest_time` 200 → `increased.forest`
  ≥ 2; `setup_cut_forest` `[0, -10]` → `min.cleared` 1; after 200 + 250 s
  → `sapling_at` `cut`; pause, `F5`/`F8` → same
  `saplings`/`cleared`/`forest`.

## Gotchas

- `setup_forest_time` only advances saplings and regrowth, not the clock;
  it's logged as a shortcut. Growth in real time is ~45 s at 4x.
- Woodcutters keep felling during the scenario, so compare forest counts
  across instant steps only.
