# Sound and minimap

All audio is synthesized at startup (no files). Effects play on game events
and fade with distance from the camera; ambience plays birds by day, crickets
at night, wind in winter. Volume, Effects and Ambience sliders sit on the
title screen and in the ☰ menu and are saved. The minimap (bottom-right)
shows terrain in the season's colours, roads, bridges, buildings, walls,
lairs, raiders, troops and the camera's view; clicking or dragging on it moves
the camera; M hides it.

## Sub-features

- `sfx` build, road, demolish, crash, click, chop, pick, horn, arrow, hit,
  fire, death, roar, breath, coins, chime, tier, victory, defeat.
- `ambience` amb_bird_*, amb_cricket, amb_wind.
- `volume` sliders labelled `Volume`, `Effects`, `Ambience`.
- `minimap` click to move the camera; `M` toggles.

## How to get to it (user POV)

- Play; open ☰ for the sliders; click the corner map.

## Driving it with tools/verify/run.sh

- `tools/verify/run.sh tools/verify/scenarios/sound-minimap.json`:
  `minimap_visible` true; `click_minimap` `[0.25, 0.25]` → `camera_near`
  `[32, 32, 3]`; `M` hides/shows; building a House and a road → `sounds_min`
  build/road/click; a Woodcutter at 4x → `chop`; `F9` → `horn`; ☰ shows
  `Effects`.
- Sound can't be heard in tests: `Sound.played` counts plays (snapshot
  `sounds`). Listen yourself in the editor.

## Gotchas

- `Sound.enabled` is off while a game is generated or a save applied.
- Headless uses Godot's dummy audio driver; plays still count.
