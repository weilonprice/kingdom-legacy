# Verification harness

Drives the real game with injected mouse/keyboard events and records evidence.
The agent-facing guide is `.claude/skills/verify-kingdom-legacy/SKILL.md`.

```bash
tools/verify/doctor.sh                                   # is this checkout drivable?
tools/verify/run.sh tools/verify/scenarios/<name>.json   # one fresh game per run
tools/verify/cleanup.sh                                  # stop leftover instances
```

A run fails if `godot.log` has any `SCRIPT ERROR`, even when every step passed.

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
| `{"find_crossing": {"as": a, "as_end": b, "near": [dx, dy], "min": 1, "max": 5}}` | Finds a straight water crossing of min..max tiles; names the two banks and the first water tile (`<as>_water`). Read-only |
| `{"click_minimap": [fx, fy]}` | Clicks the minimap at that fraction of its width/height |
| `{"pan_to": [dx, dy]}` / `"alias"` | TEST-ONLY: centres the camera on a tile (for off-screen places). Logged |
| `{"wait": s}` / `{"wait_game": s}` | Wait real / game seconds |
| `{"wait_until": {...expect...}, "timeout": s}` | Poll until the condition holds |
| `{"expect": {...}}` | Assert on observable state (below); failure marks the run FAIL |
| `{"screenshot": "name"}` | Save `name.png` (windowed runs only) |
| `{"state": "name"}` | Save `name.state.json` (resources, buildings, tier, raid, squads, visible text, messages) |
| `{"drag_tile": [[dx, dy], [dx, dy]], "shot": "name"}` | Drag between two tiles; with `shot`, screenshot while still holding (drag previews) |
| `{"include": "file.json"}` | Run another scenario's steps inline |
| `{"expect_same_as": {"state": "before", "keys": [...], "close": {"wood": 5}}}` | Snapshot fields equal an earlier `state` snapshot; `close` resources may differ by that much |
| `{"setup_grant": {"wood": 100}}` | TEST-ONLY shortcut: adds resources. Logged in `report.setup_shortcuts` |
| `{"setup_tier": "Town"}` | TEST-ONLY: jumps straight to a tier. Logged |
| `{"setup_ignite": [dx, dy]}` | TEST-ONLY: sets the building on that tile alight. Logged |
| `{"setup_spawn": {"enemy": "troll", "count": 1, "at": [dx, dy]}}` | TEST-ONLY: spawns raiders there outside a raid. Logged |
| `{"setup_lair": [dx, dy]}` | TEST-ONLY: puts a goblin lair there. Logged |
| `{"setup_research": ["masonry"]}` | TEST-ONLY: completes research instantly. Logged |
| `{"setup_season": "winter"}` | TEST-ONLY: jumps to a season (`autumn`/`winter`/`spring`/`summer`, or `none` for the original art). Logged |
| `{"setup_merchant": "timber"}` | TEST-ONLY: a merchant (`timber`/`grain`/`iron`/`peddler`) arrives at the Trading Post now. Logged |
| `{"move_mouse": [x, y]}` | Moves the mouse to that viewport position (e.g. the window edge for edge scrolling); focuses the window first |
| `{"gesture": {"magnify": 2.0, "at": [x, y]}}` / `{"gesture": {"pan": [dx, dy]}}` | Trackpad pinch (total factor, sent as 4 events) or two-finger scroll, through `Input.parse_input_event` like real input |
| `{"reload_settings": true}` | Re-reads the settings file, as the next launch would. Tests use `user://verify-settings.cfg`, fresh each run |
| `{"setup_cut_forest": [dx, dy]}` | TEST-ONLY: fells the forest tile nearest that spot (with forest beside it, nothing built nearby) as a woodcutter would; alias `cut`. Logged |
| `{"setup_forest_time": s}` | TEST-ONLY: runs sapling growth and regrowth forward `s` game seconds. Logged |
| `{"setup_royal": {"ruler_age": 90, "no_heir": true, "traits": ["just"], "crisis_left": 1}}` | TEST-ONLY: changes the royal family (any of those keys). Logged |
| `{"setup_keep_hp": 0.4}` | TEST-ONLY: sets the castle's HP to that share of its maximum (a breach needs a raid on). Logged |
| `{"click_royal": "ruler"}` | Clicks that family member (`ruler`/`spouse`/`heir`) where they stand |
| `{"setup_home_level": {"home": alias, "level": 3}}` | TEST-ONLY: sets a home's level and pins it there (its residents' class follows). Logged |
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
`villagers_fighting`, `boss_hp` (dragon HP %, -1 if none), `season` (exact), `bridges` (count, in
`min`/`max`), `bridges_walkable` (bool), `minimap_visible` (bool), `merchant` (name of the
merchant in town, "" if none), `camera_near`
(`[x, y, max_tiles]` absolute tile), `sounds_min` (`{"horn": 1}`: plays so far), `call_to_arms`
(bool), `game_over` (bool), `hint` (current tutorial hint contains the text),
`squad_troops_min`, `squad_mode` (`AUTO`/`MANUAL`),
`settings` (`{"game/pan_speed": 1.6}`: values in Settings), `speed` (0 = paused, 1-3),
`ui_scale` (the window's content scale), `camera_moved` (`{"since": "<state>", "min": n}` or
`"max"`: tiles the camera moved since that snapshot),
`class.peasant` / `class.burgher` / `class.noble` / `apprentices` (in `min`/`max`), `home_art` (a home is
drawn with that sprite, e.g. `townhouse`), `plazas` / `home_beauty` (average home desirability) (in `min`/`max`), `decreased` (like `increased`,
for a drop), `life.children` / `life.shoppers` / `life.dogs` / `life.chickens` / `life.grazers` / `life.birds` /
`life.smoke` / `life.glows` / `life.chatting` / `life.folk_visible` (in `min`/`max`: the living-kingdom
counts), `royal_ruler` / `royal_spouse` / `royal_heir` (title contains the text; `""` = nobody), `royal_crisis`,
`royal_breached` (bools), `royals_on_map` / `happiness_mod` / `tax_mod` (in `min`/`max`),
`anims_seen` (list: every villager animation named must have been seen since the run
started, e.g. `["chop", "carry"]`), `castle` (stage title, exact), `castle_building` (bool), `castle_size` / `castle_progress` (0..1) /
`builders` / `keep_hp` (in `min`/`max`), `zoom` / `min_zoom` / `fps` (in `min`/`max`), `saplings` / `cleared` / `forest` (counts, in `min`/`max`), `increased` (`{"since": "<state>", "forest": 2}`:
a metric grew by at least that much), `sapling_at` (alias or offset has a sapling),
`research_done` (research id), `button_on_screen` (a visible button whose
label contains the text lies fully inside the window).
