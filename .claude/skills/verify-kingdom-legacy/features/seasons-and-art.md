# Seasons and art

The year cycles autumn → winter → spring → summer, 3 days each, starting in
autumn; the top bar shows `🍂 Autumn · ☀ Day N`. Each season redraws the map
with its art set (golden autumn, snowy winter with snow on every roof,
green summer). Winter stops crops growing and burns 1 wood per occupied home
per minute; without wood homes are cold (-20 happiness, `Out of firewood!`).
Forests show individual trees, rocky ground scattered boulders, and props
sit on open ground and beside buildings. Stone walls use art pieces with
round corner towers; gates show a gatehouse; the Keep's art becomes a Castle
and a Citadel.

## Sub-features

- `cycle` messages `Winter has come! …`, `Spring. …`, `Summer. …`, `Autumn. …`.
- `firewood` wood drops by the number of occupied homes each winter minute.
- `frozen-fields` farm fields don't ripen in winter (`world.growth_paused`).
- `art` seasonal tilesets, trees, snowy buildings; props; walls; castle tiers.
- `save` saves keep the season and days into it.

## How to get to it (user POV)

- Just play: winter comes after 3 days (about 10 minutes at 1x).

## Driving it with tools/verify/run.sh

- **Cycle and winter.** `tools/verify/run.sh tools/verify/scenarios/seasons.json`
  (headless, `--timeout 600`): village setup, bread grants (the test village
  grows no food), `4x`, `wait_until` `season` `winter` → message `Winter has
  come!`; after a while wood has dropped; `F5`/`F8` keeps `season` `winter`;
  `wait_until` `season` `spring`; `expect` `game_over` false.
- **Look.** `tools/verify/scenarios/art-showcase.json` (windowed) builds a
  walled town with a gate and a farm and screenshots it in autumn, winter
  and summer via `setup_season`.

## Gotchas

- Headless runs render nothing: judge the art only from windowed screenshots.
- A season change rebuilds the whole map's art (a short hitch).
- Long waits starve the test village; grant bread.
