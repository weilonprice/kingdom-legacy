# Tiers and research

The settlement advances from Hamlet to Village and beyond once it meets the
next tier's requirements, unlocking locked buildings, units and research. At
the Scholar's Hall the player pays for research topics that complete while
scholars study inside.

## Sub-features

- `locked` locked build items show `🔒` and refuse with `Unlocks at <tier>`.
- `tier-panel` `T` shows current tier, next tier requirements (✔/✘) and unlocks.
- `tier-up` reaching requirements announces `grown into a Village` and upgrades the Keep.
- `research-start` a research button in the Scholar's Hall panel pays and starts research.
- `research-complete` announces `Research complete: <name>` and applies its effect.

## How to get to it (user POV)

- The `⚑ Hamlet` button in the top bar or `T` opens the tier panel.
- `Civic` → `Scholar's Hall` (Village), click the hall, click a topic button.

## Driving it with tools/verify/run.sh

Preconditions:

- Fresh run at Hamlet.

- **Tier panel.** `{"key": "T"}`. `expect` text `Next: Village`. `{"key": "T"}` closes it.
- **Locked item.** `{"click_button": "Defense"}`, `{"click_button": "Barracks"}`. `expect` `build_mode` = `NONE` and message `Barracks: Unlocks at Village`.
- **Tier up.** `{"include": "village-setup.json"}` ends with `tier` = `Village` and message `grown into a Village`.
- **Research.** Place a `scholars_hall` (`Civic` tab), click it; `expect` text `Research: idle`. `{"click_button": "Crop Rotation"}`; `expect` text `Researching Crop Rotation`.
- **Complete.** At `4x`, `wait_until` `research_done` = `crop_rotation` (timeout 90); `expect` message `Research complete: Crop Rotation`.
- **Proof.** `tools/verify/run.sh tools/verify/scenarios/tiers-research.json` exits 0 with `01-tier-panel-hamlet`, `02-research-started`, `03-research-done` screenshots.

## Gotchas

- Research makes no progress until a scholar arrives inside the hall
  (`No scholars at work — research is paused`); it needs unemployed villagers.
- Tier checks run every 2 game seconds; assert with `wait_until`.
- At Village the top bar is wider than 1600 px and pushes the `2x` and `4x`
  speed buttons off-screen (known bug). A `click_button "4x"` then aims
  outside the window, so don't count on 4x speed after Village: give
  `wait_until` timeouts that also work at 1x.
