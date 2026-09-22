# Kingdom Legacy

A medieval city builder with monster raids, made in Godot 4.

Grow a hamlet into a kingdom: lay roads, build supply chains, and keep your
villagers fed, while goblins, orcs and trolls raid in escalating waves.

- **Engine:** Godot 4.7 (GDScript)
- **View:** top-down 2D, 32x32 pixel art
- **Design:** see [design.txt](design.txt)
- **Roadmap:** see [roadmap.txt](roadmap.txt)

## Running

1. Open the Godot Project Manager, click **Import**, and select `project.godot`.
2. Press **F5** to run.

## Controls

| Action | Input |
|---|---|
| Pan camera | WASD / arrow keys / middle-mouse drag |
| Zoom | Mouse wheel |
| Road / Demolish | R / X |
| Build categories | Tab, then 1-9 to pick a building |
| Inspect building | Left-click |
| Select squad | Click a troop / drag a box / Ctrl+1-9 |
| Order squad | Right-click ground (move) or a raider (attack) |
| Squad back to guarding | G |
| Cancel / deselect | Right-click / Esc |
| Pause / speed | Space / top-bar buttons |
| Tier progress | T |
| Call a raid now (testing) | F9 |

## Verification

`tools/verify/` drives the real game with injected mouse and keyboard input and
records screenshots, state snapshots and a pass/fail report:

```bash
tools/verify/doctor.sh
tools/verify/run.sh tools/verify/scenarios/build-and-inspect.json
tools/verify/cleanup.sh
```

See `tools/verify/README.md` for the scenario format and
`.claude/skills/verify-kingdom-legacy/` for the agent guide and feature map.
Pass `-- --seed=N` to Godot to replay a specific map.
