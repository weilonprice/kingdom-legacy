# Squads

At Village tier the player builds a Barracks, trains troops from villagers,
selects the squad, orders it to move or attack with right-click, and releases
it back to automatic guard duty with G.

## Sub-features

- `train` queues Militia/Spearmen (and Archers at Town) from the Barracks panel.
- `select` selects a squad by clicking a troop, dragging a box, or `Ctrl+N`.
- `order-move` right-click on ground sends the squad there (mode `MANUAL`).
- `order-attack` right-click on a raider focuses it.
- `release` `G` or `Guard here` returns the squad to `AUTO` at its position.

## How to get to it (user POV)

- Reach Village (15 pop, a Well and a Granary), then `Defense` → `Barracks`.
- Click the Barracks; the panel has `Militia`, `Spearman`, `Archer 🔒` buttons.
- `Ctrl+1` selects Squad 1; the squad panel appears bottom-left.

## Driving it with tools/verify/run.sh

Preconditions:

- `{"include": "village-setup.json"}` (reaches Village with 16 pop).

- **Build barracks.** `{"click_button": "Defense"}`, `find_site` barracks with `entrance_on_road`, `{"click_button": "Barracks"}`, `{"click_tile": "barracks"}`. `expect` `buildings.barracks` = 1.
- **Train.** Click the barracks tile, then `{"click_button": "Spearman"}`, `{"click_button": "Militia"}`. `expect` text `Training:`; `wait_until` `squad_troops_min` = 2 at `4x`.
- **Select.** `{"key": "Escape"}`, `{"key": "CTRL+1"}`. `expect` text `Squad 1`.
- **Move order.** `{"right_click_tile": [0, 8]}`. `expect` `squad_mode` = `MANUAL`; screenshot shows a green line from the squad to the target ring.
- **Release.** `{"key": "G"}`. `expect` `squad_mode` = `AUTO` and message `Squad released`.
- **Proof.** `tools/verify/run.sh tools/verify/scenarios/squads.json` exits 0 with `01-squad-ordered.png` and `02-squad-released.png`.

## Gotchas

- Training consumes a villager each time; population drops by one per recruit
  and refills from housing only while there's food.
- `Ctrl+N` counts only squads that have troops.
- Right-click with no squad selected just cancels the build tool.
- Box select and clicking a troop directly are untested by the scenario;
  troops move, so aim with a fresh `state` snapshot if you add them.
