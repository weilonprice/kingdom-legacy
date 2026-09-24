# Settings

The Settings window opens from the title screen (`Settings` beside New Game)
and from the in-game menu (Esc or ☰ → `Settings`). Pages: `Audio` (Volume,
Effects, Ambience, Music sliders), `Display` (`Windowed`/`Fullscreen`,
`VSync`, `Interface scale` 75%–200%), `Game` (`Tutorial hints`, `Autosave`
Off/2/5/10 min, `Camera speed` Slow/Normal/Fast, `Edge scrolling`,
`Pause when raiders are sighted`) and `Controls` (hotkey list). Changes
apply at once and are saved to user://settings.cfg; `Back` or Esc closes.

## Sub-features

- `menu` Esc opens the game menu when no tool, building or squad is
  selected (otherwise Esc cancels that first); Esc again closes it.
- `persist` every setting is saved immediately and read on launch.
- `scale` interface scale sets the window's content scale.
- `edge` edge scrolling pans when the mouse is against the window edge
  (ignored when the window isn't focused or the mouse has left it).
- `raid-pause` a raid warning pauses the game with
  `Paused: raiders sighted`.
- `autosave` interval or Off (Off also skips the after-raid autosave).
- `F11` toggles fullscreen.

## How to get to it (user POV)

- Title screen → Settings, or in game press Esc → Settings.

## Driving it with tools/verify/run.sh

- `tools/verify/run.sh tools/verify/scenarios/settings.json`: Esc → `Paused`,
  `speed` 0; `Settings` → `Effects`; `Display` → `125%` → `ui_scale` 1.25,
  back to `100%`; `Game` → pause-on-raid, `2 min`, `Fast`, edge scrolling →
  `settings` values; `Controls` → `Call to Arms`; Esc back to the menu,
  `Resume`; `reload_settings` keeps the values; `move_mouse` to the right
  edge → `camera_moved` ≥ 8 tiles, centre → stops; `R` then Esc cancels the
  tool without opening the menu; `F9` → `speed` 0, message `raiders sighted`;
  Space resumes.
- The title-screen button is covered by `menu_check.tscn`.

## Gotchas

- Tests and tools call `Settings.use_file(...)`: the driver and menu check
  use a fresh `user://verify-settings.cfg`, the autoplayer its own. Never
  let a tool write the player's settings.
- Clicks are converted from viewport to window pixels (`_to_window`), so
  they still land with the interface scaled.
- Fullscreen and VSync aren't applied headless.
