# Final siege and victory

Reaching the Kingdom tier wakes the Dragon. The next raid comes three minutes
later (1.5x the usual size) and the Dragon leads it: it flies over walls to
the nearest building and breathes fire, lands every 24 s for 9 s, summons a
horde at half HP and enrages below a quarter. Killing it and clearing the
raid shows the victory screen.

## Sub-features

- `wake` message `The Dragon has woken! …`; the tier panel (T) says
  `Final goal: survive the Dragon's siege.` and counts down.
- `warning` `The Dragon approaches from the <dir>! Final siege in 30s`.
- `attack` `The Dragon and its horde attack!`; `boss_hp` drops as towers hit it.
- `phases` `The Dragon lands to rest. Strike it now!` / `takes to the air
  again.`, `…its horde answers!`, `The Dragon is enraged!`.
- `victory` `The Dragon is slain!`, then the end screen `Victory! The Dragon
  is slain.` with `New Game` and `Main Menu`.

## How to get to it (user POV)

- Grow to Kingdom (T lists the requirements). The siege comes by itself;
  `F9` calls it early.

## Driving it with tools/verify/run.sh

Preconditions: `setup_tier` `Kingdom`, `setup_research` masonry + fletching,
`setup_grant` 500 stone.

- **Wake.** `expect` message `The Dragon has woken`; `T` → text `Final goal`.
- **Defenses.** Two houses on the road (targets to burn) and 14 Wall Towers
  around the Keep; `expect` `buildings_min.wall_tower` 12.
- **Siege.** `4x`, `F9`; `wait_until` `WARNING` then `ACTIVE`;
  `wait_until` `max.boss_hp` 95; `wait_until` messages for landing, the horde,
  and `The Dragon is slain` (timeout 300).
- **Victory.** `wait_until` text `Victory!`; `expect` `game_over` true, text
  `Main Menu`.
- **Proof.** `tools/verify/run.sh tools/verify/scenarios/final-siege.json
  --timeout 700` exits 0; windowed runs save `00-dragon-attacks`,
  `01-dragon-lands`, `02-victory`.

## Gotchas

- With only 8 towers the horde's trolls wreck them and the Keep can fall.
  That's a real loss, not a test bug.
- The driver makes the game scene pausable; before M8a the game kept running
  under the driver after game over.
