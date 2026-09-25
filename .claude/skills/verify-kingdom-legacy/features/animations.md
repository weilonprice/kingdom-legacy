# Villager animations

Villagers show what they're doing: `walk`, `carry` (walking with goods),
`idle` (breathing), `chop` (woodcutters), `mine` (quarry, iron mine),
`farm` (planting, harvesting, forester planting), `hammer` (castle
builders, smithy, armory), and a short `pickup` / `putdown` pause whenever
goods change hands. Four directions each; they face the tile they work.

Five outfits: the original man, `villager_redhead`, `villager_elder` (men's
names) and `villager_woman`, `villager_blonde` (women's names), picked at
random and saved. Trees and boulders are solid: people walk around them and
chop or mine from a tile beside (preferring one not just north of a tree,
whose crown would hide them).

## Sub-features

- `select` Villager.current_anim() picks the animation from state and task.
- `one-shot` pickup/putdown play once while the villager stands still
  (~0.45 s); putdown is pickup reversed.
- `fallback` a missing animation falls back to walk (carry) or the
  standing pose, so other characters are unaffected. An outfit missing an
  animation stands idle in its own clothes (never swaps to another look).
- `outfits` Villager.outfit, random_outfit(name); saved as "outfit".
- `obstacles` WorldMap.is_obstacle(): Nature.has_tree() (forest tiles
  showing a tree; gaps stay open) and Nature.has_boulder() (35% of rocky
  tiles; the rest look like open ground and stay open). A road clears
  them. Raiders may still cross at 4x cost; animals turn back. New roads
  (find_road_path: test connector, bot) route through trees orthogonally;
  a diagonal road link between two trees would be impassable.

## How to get to it (user POV)

- Build a Woodcutter, Quarry and Farm, zoom in with + and watch.

## Driving it with tools/verify/run.sh

- `tools/verify/run.sh tools/verify/scenarios/animations.json`: village
  setup; Woodcutter, Quarry, Farm; `wait_until` `anims_seen` walk, idle,
  chop, mine, farm, pickup, putdown, carry; Town + castle upgrade →
  `hammer`; `on_obstacle` 0; `pan_to_anim` chop / mine close-ups
  (00b-chopping, 00c-mining); zoomed screenshots of woodcutters and
  builders.
- `living.json` checks `outfits` ≥ 3 and `outfit_mismatch` 0.

## Gotchas

- A worker who can't path to their job shows "Can't reach workplace";
  the `villager_notes` snapshot key counts "<job>: <note>" pairs.

- `anims_seen` is sampled every frame by the driver from visible
  villagers; it only proves the state machine chose the animation. Check
  the screenshots for the art itself.
- Frames live in assets/sprites/<outfit>/<anim>_<dir>_<n>.png (v3
  animations with their reference pose dropped; carry trimmed to the
  frames where the crate is held; villager_blonde's carry_east is her
  carry_west mirrored because the east take never lifted the crate).
