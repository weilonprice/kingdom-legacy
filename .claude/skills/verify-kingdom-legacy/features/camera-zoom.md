# Camera and zoom

Zoom with the mouse wheel or a trackpad pinch (toward the cursor), the
`+`/`-` keys, or the HUD's `+` / `−` / `⌂` buttons beside the minimap
(toward the screen centre). `Home` or `⌂` zooms out until the whole map fits.
Zoom eases smoothly; range is the whole-map fit (~0.21x on a Normal map) to
3x. Pan with WASD/arrows, middle-drag, two-finger trackpad scroll, or edge
scrolling (Settings). Zoomed far out, the map is centred and the minimap
frame stays inside the map.

## Sub-features

- `wheel` / `pinch` zoom at the cursor (the point under it stays put).
- `keys` `+` (EQUAL/PLUS/KP_ADD), `-` (MINUS/KP_SUBTRACT), `Home`.
- `buttons` `+`, `−`, `⌂` in the HUD beside the minimap.
- `pan` two-finger scroll moves the camera.
- `limits` never past the whole-map fit or 3x.

## How to get to it (user POV)

- Pinch on the trackpad, scroll the wheel, press +/-, or click the buttons
  left of the minimap.

## Driving it with tools/verify/run.sh

- `tools/verify/run.sh tools/verify/scenarios/camera-zoom.json`: `zoom` 1 at
  start; `EQUAL` → ≥1.35; `MINUS` ×2 → ~0.7; `+` button → ~1; `gesture`
  `magnify` 2 → ~2 with `camera_moved` 0 (pinch at the centre); `gesture`
  `pan` → `camera_moved` ≥ 30; `⌂` → `zoom` ≤ 0.26 (whole map); `MINUS` at
  the limit changes nothing; 9 × `+` → 3 (cap).

## Gotchas

- Godot delivers each trackpad gesture to `_unhandled_input` twice in the
  same frame (separate copies); the camera drops the repeat
  (`_is_repeat`). The driver injects gestures with `Input.parse_input_event`
  so this path is tested.
- Zoom eases, so wait ~1 s after a key or button before checking `zoom`.
- The pan-gesture scale (32 px per unit) assumes macOS's 0.03 scaling of
  scroll points; tune `PAN_GESTURE_SCALE` if real trackpads feel off.
