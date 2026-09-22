---
name: verify-kingdom-legacy
description: Drive the real Kingdom Legacy game (Godot 4.7 desktop city builder) with injected mouse/keyboard input and capture screenshots, state snapshots and a pass/fail report. Use to prove a gameplay or UI change works the way a player experiences it — building, roads, the building panel, raids, squads, tiers, research — instead of trusting headless unit-style checks.
---

# Verify Kingdom Legacy

The game is a single-player Godot desktop app. The harness in `tools/verify/`
loads the real `scenes/main.tscn` under a driver node that plays a JSON
scenario by feeding real `InputEvent`s through `Input.parse_input_event`, so
clicks and keys take the same path a player's do (GUI buttons, the build and
unit controllers' `_unhandled_input`). The driver only reads game state, except
the explicit `setup_grant` shortcut.

Feature recipes live in `features/` (start at `features/README.md`). Scenario
step reference: `tools/verify/README.md`.

## Launch

```bash
tools/verify/run.sh tools/verify/scenarios/build-and-inspect.json
```

- Each run starts its own game process: a 1600x900 window titled "Kingdom
  Legacy", map seed 12345 unless `--seed N`. Nothing is shared between runs.
- Ready signal: `VERIFY READY seed=… display=macOS` in `godot.log` (run.sh
  echoes it). Done: `VERIFY DONE PASS|FAIL failures=N out=…`.
- run.sh waits for the process, enforces `--timeout` (default 300s, then kills
  only its own PID), and exits 0 PASS / 1 FAIL / 124 timeout.
- Windowed runs pop the game window to the front and keep it always-on-top:
  macOS throttles covered windows (the game clock nearly stops, clicks are
  lost, screenshots fail with "the game window is not drawing"). If that
  still happens (full-screen apps on another Space, minimizing it), rerun
  with `--headless` to tell an environment failure from a real one.
- `--headless` runs without a window (screenshots are skipped, everything else
  works). Use it for logic-only proofs or when the window can't stay visible.
- Several runs may execute side by side (no ports or save files are shared).

## Doctor

```bash
tools/verify/doctor.sh
```

Checks the Godot binary is 4.7.x (`GODOT=…` overrides the path
`/Applications/Godot.app/Contents/MacOS/Godot`), prints branch and commit,
loads every script through a headless editor start and fails on any
`SCRIPT ERROR`/parse error, and lists verify instances still running. Run it
first, and whenever a run fails in a way that doesn't look like the feature.
It refreshes the `.godot/` import cache but changes nothing else.

## Drive

Write or reuse a scenario in `tools/verify/scenarios/`, then run it:

- Map coordinates are `[dx, dy]` tile offsets from the Keep's entrance (the
  tile under the Keep door). The camera starts centred there at zoom 1, so
  roughly ±24 x ±12 tiles are on screen. Don't click tiles outside that.
- Use `find_site` to pick building spots instead of hard-coding tiles; with
  `"entrance_on_road": true` the building works immediately.
- Click buttons by their visible label (`"click_button": "] House"` targets
  the build-menu item `[1] House`, not the `Stone House` button or the
  `Housing` tab). Category tabs: `Housing`, `Resources`, `Food`, `Storage`,
  `Defense`, `Civic`. Speed: `Pause`, `1x`, `2x`, `4x`.
- Hotkeys: `R` road, `X` demolish, `Escape` cancel/deselect, `Tab` next
  category, `1`-`9` item in category, `T` tier panel, `F9` call a raid,
  `CTRL+1`..`CTRL+9` select squad, `G` release squad to guard.
- Wait on state, not time: `{"wait_until": {"tier": "Village"}, "timeout": 90}`.
  Click `4x` first to shorten long waits.
- `village-setup.json` is a reusable prefix that reaches Village tier
  (~1 minute at 4x); include it for Village-locked features.

## Evidence

Each run writes `.verify-evidence/<timestamp>-<scenario>/` (git-ignored):
`report.json` (every step with its result, failures, all notifications,
`setup_shortcuts` used), `godot.log`, `NN-name.png` screenshots,
`name.state.json` snapshots, and `scenario.json`.

Proof standards:

- Exercise the player's path: menu buttons, hotkeys, map clicks. Never call
  game functions from the driver to perform the action under test.
- Capture the action and the result: a screenshot or `expect` before and after
  (e.g. `build_mode` BUILD after the menu click, the building count after the
  map click), not just the final screen.
- Verify side effects through a second view: after building, click the
  building and assert the panel text; after research, assert the completion
  message and `research_done`.
- `setup_grant` only removes waiting for gatherers. Say so in the proof; never
  use it for the resource flow you're verifying.
- A PASS from `--headless` proves logic only. UI layout claims need a windowed
  run and the screenshot.

## Cleanup

```bash
tools/verify/cleanup.sh
```

Stops any game instance that run.sh started and left behind (tracked by
`.verify-evidence/*/pid`; it double-checks the process command line contains
`tools/verify/driver.tscn`). Never kill Godot by name: the user's Godot editor
is also a `Godot` process. Evidence directories are kept; delete old ones by
hand only when the user asks.

## Helpers

| Script | Use |
|---|---|
| `tools/verify/run.sh <scenario.json> [--seed N] [--headless] [--timeout S]` | Run one scenario on a fresh instance |
| `tools/verify/doctor.sh` | Read-only readiness check |
| `tools/verify/cleanup.sh` | Stop leftover instances started by run.sh |
| `tools/verify/driver.gd` | The in-game driver (step implementations) |
