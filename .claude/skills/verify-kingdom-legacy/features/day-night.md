# Day and night

Each day lasts 150 game seconds, then 50 seconds of night. The map darkens
at dusk while the HUD stays bright, the top bar shows `☀ Day N` / `☾ Night N`,
and villagers finish what they're carrying, go home and sleep. Guards,
scholars and service workers stay at their posts. Morning brings everyone
back out.

## Sub-features

- `clock` top-bar label `☀ Day N` / `☾ Night N`, tooltip shows time until the change.
- `tint` the world fades to a blue-dark tint over 12 s of dusk and back at dawn.
- `sleep` villagers not working inside go home and disappear until morning.
- `announcements` `Night falls. Villagers head home to sleep.` and `Day N begins.`

## How to get to it (user POV)

- Play, or click `4x`, and wait about 2.5 game minutes.

## Driving it with tools/verify/run.sh

Preconditions:

- Fresh run (4 settlers in the Keep, no jobs).

- **Daytime.** `expect` `night` = false; `wait_until` `min.villagers_awake` = 4.
- **Nightfall.** `{"click_button": "4x"}`; `wait_until` `night` = true (timeout 60). `expect` message `Night falls` and text `Night`.
- **Everyone asleep.** `wait_until` `max.villagers_awake` = 0 (timeout 30). Screenshot shows the dark tint and an empty town.
- **Morning.** `wait_until` `night` = false; `expect` message `Day 2 begins` and text `Day 2`; `wait_until` `min.villagers_awake` = 4.
- **Proof.** `tools/verify/run.sh tools/verify/scenarios/day-night.json` exits 0 with `01-night-town-asleep.png` and `02-morning.png` (windowed; the tint isn't visible headless).

## Gotchas

- Workers finish their current action first, so `villagers_awake` reaches 0 a few seconds after nightfall, not instantly.
- Guards, scholars and service workers are already invisible (inside), so they don't count as awake either way.
- Raids still come at night. Sleeping villagers are indoors and safe.
