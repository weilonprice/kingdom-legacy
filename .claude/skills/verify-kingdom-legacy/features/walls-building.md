# Wall building and the Dragon challenge

Dragging Palisade or Stone Wall across a road builds a Gate on the road
tile. While dragging, each tile is tinted (green wall, gold gate, red can't
build, orange can't afford) and a label beside the cursor reads
`N segments + G gates — <cost>` (`(short for K)` when you can't pay for all).
Clicking a palisade offers `Upgrade to stone: N segments (<cost>)` (Town),
which rebuilds the whole connected palisade in stone, keeping gates and
towers. At Kingdom the message `The Dragon stirs` appears; the tier panel
(T) has `Challenge the Dragon`, which starts the final siege a minute later
(`You have challenged the Dragon`).

## Sub-features

- `gates` BuildController.wall_plan: road tiles become gates.
- `preview` wall_plan_text + tile tints; `shot` on drag_tile captures it.
- `upgrade` WorldMap.connected_wall / upgrade_wall_to_stone.
- `challenge` RaidDirector.can_challenge_dragon / begin_final_siege
  (FINAL_SIEGE_DELAY 60 s).
- `scale` tier requirements 20/60/130/250 people (TierDefs); raid growth
  capped per tier (RaidDirector.composition).

## Driving it with tools/verify/run.sh

- `tools/verify/run.sh tools/verify/scenarios/walls-building.json`: Town,
  palisade drag `[-6, 2]`→`[6, 2]` across the approach road (preview
  screenshot) → 1 gate, ≥10 palisades; click `[4, 2]` → `Upgrade to stone`
  → 0 palisades, ≥10 stone walls, gate kept; a long stone-wall preview;
  Kingdom → `The Dragon stirs`; T → `Challenge the Dragon` → `WARNING`
  with `The Dragon approaches`.
