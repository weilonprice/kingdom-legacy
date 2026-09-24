# Kingdom Legacy verification map

This directory is the maintained source for verifying the player-facing
behavior of Kingdom Legacy. Read this index before driving the game, then use
the matching feature file as the recipe.

## Baseline preconditions

- `tools/verify/doctor.sh` prints `DOCTOR OK`.
- Every run starts a fresh game through `tools/verify/run.sh` with seed 12345
  unless the recipe says otherwise. Never drive the user's own game or editor.
- The game window stays uncovered while screenshots are taken.

## Driving conventions

- Start every recipe from a fresh run; scenarios don't share state.
- Prefer visible button labels (`click_button`) and hotkeys over coordinates.
- Place buildings with `find_site` aliases, not hard-coded tiles.
- Wait with `wait_until` on observable state, not fixed sleeps.
- `setup_grant` may only replace gathering time, and the proof must say so.

## Proof and skip reporting

- Capture the player action and the resulting state: an `expect` or screenshot
  after each action, not only the final screen.
- UI proof includes a windowed screenshot with the HUD visible.
- State proof includes `report.json` and a `state` snapshot.
- Record the scenario file and seed with every artifact (`scenario.json` and
  `report.json` in the evidence dir do this).
- Report an unreachable path with the attempted step and the failed `expect`.
- Do not report a skipped entry point as verified through a different path.

## Feature entry contract

Each feature file starts with an H1 title and one paragraph describing the
player-visible behavior, then exactly four H2 sections in this order:
`Sub-features`, `How to get to it (user POV)`, `Driving it with
tools/verify/run.sh`, `Gotchas`.

## Features

- [Build and inspect](./build-and-inspect.md): build menu, placing buildings, dragging roads, villagers moving in, the building panel. Scenario `build-and-inspect.json`.
- [Raids and towers](./raids-and-towers.md): guard towers, raid warning, raid banner, raid end. Scenario `raid-defense.json`.
- [Squads](./squads.md): barracks training, squad selection, move orders, release to guard. Scenario `squads.json`.
- [Needs and happiness](./needs-and-happiness.md): home needs, service coverage, house levels, tax rate, overlays. Scenario `needs-happiness.json`.
- [Storage and hauling](./storage-and-hauling.md): workplace piles, per-building storage, Carter's Yard haulers. Scenario `hauling.json`.
- [Day and night](./day-night.md): clock, night tint, villagers sleeping and waking. Scenario `day-night.json`.
- [Walls, fire and siege](./walls-fire-siege.md): wall drag tool, gates, fire spreading, orcs/shamans/wolf riders/trolls breaching walls. Scenario `walls-fire-siege.json`.
- [War economy](./war-economy.md): iron mine, smithy, wall tower, knights, goblin lairs, Call to Arms. Scenario `war-economy.json`.
- [Final siege and victory](./final-siege.md): Kingdom tier wakes the Dragon, its phases, the victory screen. Scenario `final-siege.json`.
- [Menu and tutorial hints](./menu-and-hints.md): title screen (seed, difficulty, hints), end-screen Main Menu, the goal panel. `menu_check.tscn` + scenario `tutorial-hints.json`.
- [Save and load](./save-load.md): F5/F8, the ☰ game menu, autosave, refusal during raids. Scenario `save-load.json`.
- [Seasons and art](./seasons-and-art.md): the season cycle, winter firewood and frozen fields, seasonal art, trees/props/walls. Scenarios `seasons.json`, `art-showcase.json`.
- [Rivers and bridges](./rivers-bridges.md): rivers, fords, building/refusing/demolishing bridges. Scenario `rivers-bridges.json`, tool `map_preview.tscn`.
- [Sound and minimap](./sound-minimap.md): synthesized effects, ambience, volume sliders, the minimap. Scenario `sound-minimap.json`.
- [Merchants and trade](./trade.md): Trading Post, merchant arrival, buying and selling, leaving on raids, saves. Scenario `trade.json`.
- [Tiers and research](./tiers-and-research.md): locked content, tier panel, reaching Village, Scholar's Hall research. Scenario `tiers-research.json`.

Not yet mapped: food chain (farm, mill, bakery, fisher), demolish, storage
full, starvation, game over, raid theft from a specific storage, box-selecting squads, attack orders, Town
tier content. Add a feature file and scenario when a change touches them.
