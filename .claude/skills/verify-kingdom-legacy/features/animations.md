# Villager animations

Villagers show what they're doing: `walk`, `carry` (walking with goods),
`idle` (breathing), `chop` (woodcutters), `mine` (quarry, iron mine),
`farm` (planting, harvesting, forester planting), `hammer` (castle
builders, smithy, armory), and a short `pickup` / `putdown` pause whenever
goods change hands. Four directions each; they face the tile they work.

## Sub-features

- `select` Villager.current_anim() picks the animation from state and task.
- `one-shot` pickup/putdown play once while the villager stands still
  (~0.45 s); putdown is pickup reversed.
- `fallback` a missing animation falls back to walk (carry) or the
  standing pose, so other characters are unaffected.

## How to get to it (user POV)

- Build a Woodcutter, Quarry and Farm, zoom in with + and watch.

## Driving it with tools/verify/run.sh

- `tools/verify/run.sh tools/verify/scenarios/animations.json`: village
  setup; Woodcutter, Quarry, Farm; `wait_until` `anims_seen` walk, idle,
  chop, mine, farm, pickup, putdown, carry; Town + castle upgrade →
  `hammer`; zoomed screenshots of woodcutters and builders.

## Gotchas

- `anims_seen` is sampled every frame by the driver from visible
  villagers; it only proves the state machine chose the animation. Check
  the screenshots for the art itself.
- Frames live in assets/sprites/villager/<anim>_<dir>_<n>.png (v3
  animations with their reference pose dropped; carry trimmed to the four
  frames where the crate is held).
