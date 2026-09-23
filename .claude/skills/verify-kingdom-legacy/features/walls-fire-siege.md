# Walls, fire and siege

Palisades and stone walls are dragged like roads, charge per segment and join
up with their neighbours; gates can sit on roads and let villagers and troops
through. Raiders path through walls and gates at a cost and stop to smash one
that blocks their next step. Orcs can set wooden buildings on fire; fire
spreads between flammable neighbours unless a Well covers the building.
Orc shamans heal nearby raiders, wolf riders go for farms, trolls break walls.

## Sub-features

- `wall-drag` `Defense` → `Palisade` / `Stone Wall` enters WALL mode
  (`… drag to build (N per segment) …`); a drag places one segment per free tile
  and stops with `Ran out of materials after N segments` when money runs out.
- `gate` `Defense` → `Gate` is a normal single-click build and can go on a road.
- `fire` `The <building> is on fire!`, then `Palisade was destroyed!` or
  `Villagers put out the fire at the <building>` when a Well covers it.
- `siege` trolls/orcs smash walls: `Stone Wall was destroyed!`.
- `raid-mix` orcs from raid 2, a shaman per 3 orcs, wolves from Town, trolls
  from raid 5 or City (`RaidDirector.composition()`).

## How to get to it (user POV)

- Palisade and Gate unlock at Hamlet, Stone Wall at Town. `Defense` tab.
- Drag across the map with the wall selected; right-click cancels.
- Fire and new monsters appear in later raids (`F9` calls one now).

## Driving it with tools/verify/run.sh

Preconditions: fresh run; `setup_grant` 400 wood / 400 stone; `setup_tier`
`Town` (unlocks Stone Wall).

- **Palisade.** `click_button` `Defense`, `Palisade`; `expect` `build_mode`
  `WALL`; `drag_tile` `[[-5,-5],[5,-5]]`; `expect` `buildings_min.palisade` 6.
- **Gate.** `click_button` `Gate`; `click_tile` `[0,2]` (on the starting road);
  `expect` `buildings.gate` 1.
- **Stone wall.** `click_button` `Stone Wall`; `drag_tile` `[[-5,-8],[5,-8]]`;
  `expect` `buildings_min.stone_wall` 6.
- **Fire.** `setup_ignite` `[0,-5]`; `expect` message `is on fire`, `min.burning`
  1; at `4x`, `wait_until` message `Palisade was destroyed` (timeout 30).
- **Siege.** `setup_spawn` troll at `[0,-12]`, orcs, a shaman and a wolf rider
  nearby; `expect` `min.enemies` 5; `wait_until` message
  `Stone Wall was destroyed` (timeout 60).
- **Proof.** `tools/verify/run.sh tools/verify/scenarios/walls-fire-siege.json`
  exits 0; windowed runs save `00-palisade` … `04-breach`.

## Gotchas

- Drag north of the Keep: tiles more than ~5 rows below it sit under the build
  bar, which swallows the mouse events.
- `setup_ignite`/`setup_spawn`/`setup_tier` are test shortcuts; say so in proof.
- Stone buildings (Keep, Stone Tower, Stone Wall) never catch fire.
