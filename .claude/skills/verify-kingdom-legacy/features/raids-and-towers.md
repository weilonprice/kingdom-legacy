# Raids and towers

Goblin raids arrive on a timer with a 30-second warning naming a direction,
a red arrow points at off-screen raiders, villagers hide when raiders come
close, manned guard towers shoot arrows, and the raid ends when every raider
is dead or has fled.

## Sub-features

- `tower-build` places a guard tower that a villager walks to and mans.
- `raid-warning` shows `Goblins approach from the <direction> — Ns!` for 30 s.
- `raid-active` shows `⚔ Raid! N goblins remaining ⚔` while raiders are on the map.
- `raid-end` announces `The raid is over! Raids survived: N`.
- `raid-steal` goblins steal from storage (`A goblin stole …`) and flee.

## How to get to it (user POV)

- `Defense` tab → `[1] Guard Tower`, click on the map.
- Wait for `Raid in m:ss` in the top bar to reach 0, or press `F9` to call a
  raid now (30 s warning).

## Driving it with tools/verify/run.sh

Preconditions:

- Fresh run. `setup_grant` 200 wood / 100 stone (a tower costs 40 wood + 20 stone).

- **Build towers.** `{"click_button": "Defense"}`, `{"click_button": "Guard Tower"}`, two `find_site`/`click_tile` pairs near `[3, 1]` and `[-3, 1]`. `expect` `buildings.guard_tower` = 2.
- **Call raid.** `{"click_button": "4x"}`, `{"key": "F9"}`. `wait_until` `raid_phase` = `WARNING`; `expect` text `Goblins approach from the`.
- **Raid starts.** `wait_until` `raid_phase` = `ACTIVE` (timeout 30); `expect` text `Raid!`.
- **Raid ends.** `wait_until` `raid_phase` = `CALM` (timeout 150); `expect` message `The raid is over!`.
- **Proof.** `tools/verify/run.sh tools/verify/scenarios/raid-defense.json` exits 0 with screenshots `01-raid-warning`, `02-raid-active`, `03-raid-over`.

## Gotchas

- `F9` only starts a raid from the calm phase; pressing it during a warning or
  raid does nothing.
- Raiders take 1-2 game minutes to walk in from the map edge. Use `4x` and
  `wait_until`, never a fixed wait.
- Towers only shoot once the guard arrives (`status: Guard on the way` in the
  panel until then).
- With seed 12345 the first raid is 2 goblins; whether any steal before dying
  varies, so don't assert on `A goblin stole` unless the scenario leaves
  storage undefended.
