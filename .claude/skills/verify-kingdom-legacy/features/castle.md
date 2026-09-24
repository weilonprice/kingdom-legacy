# The growing castle

The castle starts as a 5x5 Keep in 9x9 reserved grounds at the map centre;
nothing else can be built in them (`Castle grounds are reserved`; the Build
and Wall tools outline them as `Castle grounds`). From the castle's panel,
`Upgrade to Castle (150 gold)` (Town) and `Upgrade to Citadel (400 gold)`
(Kingdom) start a construction project: the castle gets 6 builder jobs
(unemployed villagers), builders carry stone/wood/iron from storage to the
site, then build. The panel shows `Building the Castle — N%`, materials
delivered, construction progress and builders. On completion the castle
grows to 7x7 / 9x9 in place, gains HP and storage, and the message
`The Castle is complete!` shows.

## Sub-features

- `grounds` placement refused inside the grounds; outline in build mode.
- `start` button disabled with the reason (tier, gold); gold paid at start.
- `haul` builders fetch from the nearest storage (the castle's own store
  counts); `missing`/claims stop over-delivery.
- `build` after all materials, builders work at spots around the site.
- `grow` footprint, gate and approach road move; HP = tier + stage bonus.
- `save` stage and project (delivered, work done) survive F5/F8.
- `dragon` the Dragon arrives 10 minutes after Kingdom.

## How to get to it (user POV)

- Reach Town, click the castle, press `Upgrade to Castle`, keep some
  villagers unemployed.

## Driving it with tools/verify/run.sh

- `tools/verify/run.sh tools/verify/scenarios/castle.json`: `castle` `Keep`,
  size 5; a House at `[4, -2]` → `Castle grounds are reserved`; village
  setup, `setup_delay_raids`, `setup_tier` Town, grants; click `[0, -3]` →
  `Upgrade to Castle`; `builders` ≥ 3 and progress ≥ 0.15; pause, `F5`/`F8`
  → still building, progress kept; 4x until `castle` `Castle` → size 7,
  `keep_hp` ≥ 2100, panel `Next: Citadel`.

## Gotchas

- Builders are only unemployed villagers; a fully employed town gets none.
- The game resumes after loading, so compare progress with `min`, not
  exact equality.
- Scenario offsets are relative to the castle gate, which moves down one
  tile per stage.
