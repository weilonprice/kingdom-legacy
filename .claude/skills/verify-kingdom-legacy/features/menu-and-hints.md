# Menu and tutorial hints

The game opens on a title screen: map seed (blank = random), difficulty
(Easy/Normal/Hard) and a tutorial-hints checkbox, then New Game. In game, a
top-left panel shows one goal at a time (`Goal N/11: …`) and moves on when
it's done; ✕ hides it. The end screen's Main Menu returns to the title.

## Sub-features

- `menu` title, seed box, difficulty toggles, `Tutorial hints`, New Game, Quit.
- `settings-carry` seed, difficulty (first raid 10/7/5 min, raid size) and
  hints reach the game.
- `hints` goals tick off: road → House → Woodcutter → food → tower → Village
  → troops → Town → City → Kingdom → the Dragon.
- `back-to-menu` end screen `Main Menu` → title, unpaused.

## How to get to it (user POV)

- Launch the game (F5). Hints are on by default; untick to skip them.

## Driving it with tools/verify/run.sh

- **Menu.** The JSON driver loads `main.tscn` directly, so the title screen
  has its own check: `godot --headless --path . res://tools/verify/menu_check.tscn`
  prints `MENU CHECK PASS` (windowed runs also save
  `.verify-evidence/menu-title.png`).
- **Hints.** `tools/verify/run.sh tools/verify/scenarios/tutorial-hints.json`:
  `setup_hints` true; `expect` hint `Press R`; drag a road → hint `build a
  House`; House → `Woodcutter`; Woodcutter → `Fisher` and text `Goal 4/11`;
  click `✕` → `text_absent` `Goal 4/11`.

## Gotchas

- The driver starts every scenario with hints off (the panel covers
  top-left tiles); only `setup_hints` turns them on.
