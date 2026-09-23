# Kingdom Legacy

**A medieval city builder where every villager is a real person hauling real goods, and goblins come to take them.**

Grow a hamlet into a kingdom. Lay roads, build farms, mills and bakeries, keep
your people fed, housed and happy, then train an army and raise towers before
the next raid hits. Made with Godot 4.

![A village by a lake: the castle Keep, thatched cottages, a barracks, villagers on the dirt road, and a selected squad marching south](docs/screenshots/village-overview.png)

> **Status: playable, start to finish.** Milestones M0–M8a are done: economy,
> raids, troops, tiers, research, needs, day/night, pixel art, walls, fire,
> the war economy, a main menu, tutorial hints, and the Dragon's final siege
> to win. Save/load and a balance pass (M8b) are next. See the [roadmap](roadmap.txt).

## Features

- **A living town.** Every villager is an agent with a home and a job. You can
  watch them chop trees, harvest wheat, carry flour from the mill to the bakery
  and haul goods to storage. When there's a bottleneck, you can see it.
- **Supply chains.** Woodcutters, quarries, fishers, and farms that till and
  harvest their own fields. Wheat goes to the mill, flour to the bakery, bread
  to the granary. Goods sit in specific buildings, and haulers from a Carter's
  Yard keep them moving.
- **Needs and happiness.** Homes need food, water, religion, a market and a
  tavern. Cover them with Wells, Chapels, Markets and Taverns, and cottages grow
  into townhouses and manors that hold more people and pay more tax. Set the tax
  rate on the Keep and trade gold for happiness.
- **Monster raids.** Goblins arrive every few minutes from a direction the game
  announces. Thieves loot the storehouse they reach and run, and brutes smash
  buildings. Later come orcs who set fires, shamans who heal them, wolf riders
  who hit outlying farms, and trolls that smash through walls. Villagers hide
  when raiders get close. Lose the Keep and the game is over.
- **A war economy.** Iron mines feed a smithy and an armory; spearmen and
  archers need weapons, knights need weapons and armor. Goblin lairs out in
  the wilds make every raid bigger until you march a squad out and burn them
  down. In a pinch, sound the Call to Arms and villagers fight with
  pitchforks.
- **Walls and fire.** Drag palisades and stone walls around the town and put
  gates where your roads cross them. Raiders have to break through. Fire
  spreads between wooden buildings unless a Well is close enough to put it
  out.
- **Hybrid combat.** Guard towers shoot on their own. Barracks train militia,
  spearmen and archers into squads that defend automatically. Select a squad
  whenever you want to send it somewhere, then let it go back to guarding.
- **Progression.** Grow from Hamlet to Village, Town, City and Kingdom. Each
  tier unlocks buildings, units and research, and upgrades the Keep into a
  Castle and then a Citadel. The raids grow with you.
- **Day and night.** At dusk the town goes quiet as villagers head home to
  sleep. Guards stay on watch.
- **Procedural maps.** Every game is a new 128×128 map. Pass a seed to replay
  one.

## Screenshots

| | |
|---|---|
| ![Home panel showing needs met and missing](docs/screenshots/needs-panel.png) | ![A goblin raid with manned guard towers and the raid banner](docs/screenshots/raid.png) |
| **Needs.** A Chapel turned this home into a Townhouse. A market and a tavern would make it a Manor. | **Raids.** Manned guard towers wait for 2 goblins; the red arrow points at them off-screen. |
| ![The service-coverage overlay: coverage circles and need dots on each home](docs/screenshots/services-overlay.png) | ![The town at night, everyone asleep](docs/screenshots/night.png) |
| **Overlays.** Press O to see which homes a well and a chapel cover. | **Night.** The villagers are asleep and the town is empty until morning. |

## Getting started

**Requirements:** [Godot 4.7](https://godotengine.org/download) (standard
build; no .NET needed).

```bash
git clone https://github.com/weilonprice/kingdom-legacy.git
```

1. Open the Godot Project Manager, click **Import**, and select
   `kingdom-legacy/project.godot`.
2. Press **F5** to play. The title screen takes an optional map seed, a
   difficulty and whether to show tutorial hints.

To skip the menu and replay a specific map, run the game scene from a
terminal with a seed:

```bash
godot --path kingdom-legacy res://scenes/main.tscn -- --seed=12345
```

### Your first few minutes

1. Four settlers live in the **Keep**. Press **1** (House) and place homes
   along the road, with their yellow entrance square on the road.
2. Open the **Resources** tab and build a **Woodcutter** next to the forest
   and a **Quarry** next to the rocks. Unemployed villagers take the jobs.
3. Open the **Food** tab. A **Fisher's Hut** by the water feeds people quickly;
   **Farm → Mill → Bakery** feeds more of them in the long run.
4. Build a **Well** and a **Granary** to reach **Village**. Press **T** to see
   what the next tier needs.
5. The first raid comes at about 7 minutes. Put a couple of **Guard Towers**
   near your storage, and later a **Barracks**.
6. To win, grow to **Kingdom**. That wakes the **Dragon**, whose siege
   comes three minutes later. Only towers and archers can hit it in the air;
   it lands every so often, and that's when your knights can strike.

## Controls

| Action | Input |
|---|---|
| Pan / zoom | WASD or arrow keys, middle-mouse drag / mouse wheel |
| Build | Category tabs at the bottom (**Tab** cycles), **1–9** picks a building |
| Road / Demolish | **R** (drag to lay) / **X** |
| Inspect a building | Left-click |
| Cancel / deselect | Right-click / **Esc** |
| Select a squad | Click a troop, drag a box, or **Ctrl+1–9** |
| Order a squad | Right-click the ground (move) or a raider (attack) |
| Squad back to guarding | **G** |
| Tier progress | **T** |
| Map overlays (happiness, services, roads) | **O** |
| Tax rate | Click the Keep |
| Pause / speed | **Space** / top-bar buttons |
| Call to Arms during a raid | **C** or the button under the raid banner |
| Call a raid now (testing) | **F9** |

## Project layout

```
scenes/main.tscn          Entry scene
scripts/
  data/                   Data tables: buildings, items, units, enemies, tiers, research, needs
  world/                  Map generation, terrain, buildings, pathfinding
  agents/                 Villagers, raiders, troops
  systems/                Citizens, raids, military, needs, research, tiers, storage, day/night
  controllers/            Camera, build tools, unit control
  ui/                     HUD, panels, overlays
assets/                   PixelLab art: buildings, terrain tilesets, characters, UI
  scripts/art/            Art loader (falls back to placeholder shapes if a file is missing)
tools/verify/             Real-input verification harness
design.txt                Game design outline
roadmap.txt               Milestones M0–M8
```

Most content is data-driven. A new building is mostly a new entry in
`scripts/data/building_defs.gd`.

## Development

### Verifying changes

`tools/verify/` plays the real game with injected mouse and keyboard input and
records screenshots, state snapshots and a pass/fail report:

```bash
tools/verify/doctor.sh                                   # is the checkout healthy?
tools/verify/run.sh tools/verify/scenarios/squads.json   # plays a scenario
tools/verify/cleanup.sh                                  # stops leftover instances
```

There are scenarios for building, raids, squads, tiers and research, needs,
hauling, day/night, walls/fire/sieges, the war economy, the final siege and
tutorial hints, plus a title-screen check
(`godot --headless --path . res://tools/verify/menu_check.tscn`). Add `--headless` to run without a window. Evidence goes
to `.verify-evidence/`. The scenario format is in
[`tools/verify/README.md`](tools/verify/README.md), and the agent guide and
feature map are in `.claude/skills/verify-kingdom-legacy/`.

### Workflow

Each milestone is developed on its own branch and merged through a pull request
after its scenarios pass.

## Roadmap

| Milestone | |
|---|---|
| M0–M1 | Map, roads, villagers, gathering, food chain ✅ |
| M2–M3 | Goblin raids, towers, troops and squads ✅ |
| M4–M5b | Tiers, research, needs, happiness, taxes, storage, haulers, day/night ✅ |
| M6 | Pixel-art pass: terrain, buildings, animated characters, HUD theme ✅ |
| M7a | Walls, gates, fire, orcs, wolf riders and trolls ✅ |
| M7b | Iron, smithy and armory, knights, goblin lairs, wall towers, Call to Arms ✅ |
| M8a | Main menu, tutorial hints, the Dragon's final siege, victory ✅ |
| M8b | Save/load, balance pass, performance, export builds |

Details are in [roadmap.txt](roadmap.txt) and [design.txt](design.txt).

## Credits

- Built with [Godot Engine](https://godotengine.org).
- Pixel art, the pixel font and the UI panels were generated with
  [PixelLab](https://pixellab.ai). See [the art style test](docs/style_test.png).
