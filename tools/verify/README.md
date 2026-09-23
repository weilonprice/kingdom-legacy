# Verification harness

Drives the real game with injected mouse/keyboard events and records evidence.
The agent-facing guide is `.claude/skills/verify-kingdom-legacy/SKILL.md`.

```bash
tools/verify/doctor.sh                                   # is this checkout drivable?
tools/verify/run.sh tools/verify/scenarios/<name>.json   # one fresh game per run
tools/verify/cleanup.sh                                  # stop leftover instances
```

`run.sh` options: `--seed N` (default 12345), `--headless` (no window, no
screenshots), `--timeout S` (default 300). Evidence goes to
`.verify-evidence/<timestamp>-<scenario>/`: `report.json`, `godot.log`,
`*.png`, `*.state.json`, and a copy of the scenario.

## Scenario steps

A scenario is a JSON array of steps, run in order. Tiles are `[dx, dy]` offsets
from the Keep's entrance (the tile below the Keep's door), or an alias from
`find_site`. The starting road runs 3 tiles down from there, then along
`dy = 3` from `dx = -5` to `dx = 5`.

| Step | Effect |
|---|---|
| `{"click_button": "text"}` | Clicks the first visible button whose label contains `text` |
| `{"key": "R"}`, `{"key": "CTRL+1"}` | Presses and releases a key (Godot key names: `Escape`, `F9`, `Space`) |
| `{"click_tile": [dx, dy]}` / `"alias"` | Left-click on a map tile |
| `{"right_click_tile": [dx, dy]}` | Right-click on a map tile |
| `{"drag_tile": [[dx, dy], [dx, dy]]}` | Left-drag between two tiles (roads, walls) |
| `{"find_site": {"building": id, "as": alias, "entrance_on_road": true, "near": [dx, dy]}}` | Finds a valid spot and names the tile to click. Read-only |
| `{"wait": s}` / `{"wait_game": s}` | Wait real / game seconds |
| `{"wait_until": {...expect...}, "timeout": s}` | Poll until the condition holds |
| `{"expect": {...}}` | Assert on observable state (below); failure marks the run FAIL |
| `{"screenshot": "name"}` | Save `name.png` (windowed runs only) |
| `{"state": "name"}` | Save `name.state.json` (resources, buildings, tier, raid, squads, visible text, messages) |
| `{"include": "file.json"}` | Run another scenario's steps inline |
| `{"setup_grant": {"wood": 100}}` | TEST-ONLY shortcut: adds resources. Logged in `report.setup_shortcuts` |
| `{"setup_tier": "Town"}` | TEST-ONLY: jumps straight to a tier. Logged |
| `{"setup_ignite": [dx, dy]}` | TEST-ONLY: sets the building on that tile alight. Logged |
| `{"setup_spawn": {"enemy": "troll", "count": 1, "at": [dx, dy]}}` | TEST-ONLY: spawns raiders there outside a raid. Logged |
| `{"setup_lair": [dx, dy]}` | TEST-ONLY: puts a goblin lair there. Logged |
| `{"setup_research": ["masonry"]}` | TEST-ONLY: completes research instantly. Logged |
| `{"setup_hints": true}` | Turns tutorial hints on (the driver starts with them off so they don't cover tiles) |
| `{"setup_delay_raids": s}` | TEST-ONLY: no natural raid for `s` game seconds. Logged |

`expect` keys: `buildings` (exact counts), `tier`, `raid_phase`
(`CALM`/`WARNING`/`ACTIVE`), `build_mode` (`NONE`/`BUILD`/`ROAD`/`WALL`/`DEMOLISH`),
`buildings_min` / `buildings_max` (counts per building id),
`selected_building` (title), `text` (any visible HUD label/button contains it),
`text_absent` (no visible HUD label/button contains it),
`message` (any notification so far contains it), `min` / `max` (`population`,
`roads`, `happiness`, or any resource), `tax_rate` (`None`..`Harsh`),
`house_level_min` (`{"level": 2, "count": 1}`), `night` (bool),
`stored_min` / `pile_min` (`{"stockpile": {"wood": 1}}`: goods stored in /
waiting at buildings of that type), `min`/`max` also take `villagers_awake`, `enemies`, `burning`, `lairs`,
`villagers_fighting`, `boss_hp` (dragon HP %, -1 if none), `call_to_arms`
(bool), `game_over` (bool), `hint` (current tutorial hint contains the text),
`squad_troops_min`, `squad_mode` (`AUTO`/`MANUAL`),
`research_done` (research id), `button_on_screen` (a visible button whose
label contains the text lies fully inside the window).
