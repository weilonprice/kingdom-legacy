# Save and load

F5 saves and F8 loads, or use the ☰ game menu (which pauses: Resume, Save
Game, Load Game, Main Menu). The game autosaves after every raid and every 5
minutes, and the title screen's Continue loads the newest save. Saving is
refused while raiders are coming.

## Sub-features

- `save` message `Game saved.`; during a raid warning or attack:
  `Not saved: Can't save while raiders are coming.`
- `load` message `Game loaded (saved <date>).`; buildings, tier, research,
  roads, population, jobs, fields, squads, lairs, house levels and stock match
  the save.
- `menu` ☰ opens `Paused` with Save/Load/Main Menu; Resume unpauses.
- `continue` title-screen Continue (see menu-and-hints).

## How to get to it (user POV)

- F5 / F8 anywhere in a game, or the ☰ button at the top-left.

## Driving it with tools/verify/run.sh

- **Round trip.** `tools/verify/run.sh tools/verify/scenarios/save-load.json`:
  village setup + woodcutter, farm, barracks with a militia; `Pause`,
  `state` `before`, `F5`; build an extra House; `F8`; `expect` `house` 3
  and `expect_same_as` `before` on buildings, tier, research, roads,
  population, raids, lairs, house levels, fields, squads, employment (resources
  within a few units).
- **Menu.** Click `☰` → text `Paused` → `Save Game` → `Resume`.
- **Refusal.** `F9`, `wait_until` `WARNING`, `F5` → `Not saved: …`.

## Gotchas

- Under the driver, saves go to `user://verify-saves` (never the player's
  `user://saves`), and loading swaps the game scene in place instead of
  changing scenes.
- Pause before taking the `before` snapshot so nothing moves between it and
  the save.
