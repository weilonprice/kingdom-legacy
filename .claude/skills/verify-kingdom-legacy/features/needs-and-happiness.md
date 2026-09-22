# Needs and happiness

Each home tracks five needs (food, water, religion, market, tavern), a
happiness score and a level. Service buildings meet needs for homes inside
their coverage circle; homes upgrade from Cottage to Townhouse to Manor, hold
more people and pay more tax. The tax rate set on the Keep trades gold for
happiness, and overlays show happiness, coverage and road access on the map.

## Sub-features

- `home-needs` the house panel lists each need with ✔/✘ and the home's happiness.
- `service-coverage` a staffed Chapel/Market/Tavern (or a Well) meets its need for homes in range.
- `house-level` homes meeting the next level's needs upgrade after ~10 s (`A home grew into a Townhouse`).
- `tax-rate` the Keep panel's `None`/`Low`/`Normal`/`High`/`Harsh` buttons change tax and happiness.
- `overlay` `O` cycles Happiness → Services → Road access → Off.
- `hud-happiness` the top bar shows average happiness as `☺N` and net gold per minute.

## How to get to it (user POV)

- Click a House to see `Cottage — happiness N/100` and the needs checklist.
- `Civic` tab → `Chapel` / `Market` (Village) or `Tavern` (Town); click the map.
- Click the Keep for the tax-rate buttons.
- Press `O` to cycle overlays.

## Driving it with tools/verify/run.sh

Preconditions:

- `{"include": "village-setup.json"}`: Village tier, 3 houses, a well and a granary, all on the starting road.

- **Home panel.** `{"click_tile": "h1"}`. `expect` `selected_building` = `House` and text `Cottage`.
- **Build a chapel.** `{"click_button": "Civic"}`, `find_site` `chapel` with `entrance_on_road`, `{"click_button": "Chapel"}`, `{"click_tile": "chapel"}`. `expect` `buildings.chapel` = 1.
- **Upgrade.** `wait_until` `house_level_min` = `{"level": 2, "count": 1}` (timeout 90). `expect` message `grew into a Townhouse`; the house panel shows `Townhouse`.
- **Overlays.** `{"key": "O"}` → message `Overlay: Happiness`; again → `Overlay: Services`. Press twice more to turn it off.
- **Tax.** `{"click_tile": [0, -2]}` (the Keep). `expect` text `Tax rate: Normal`. `{"click_button": "Harsh"}` → `tax_rate` = `Harsh`; `wait_until` `max.happiness` = 55. `{"click_button": "None"}` → `wait_until` `min.happiness` = 70.
- **Proof.** `tools/verify/run.sh tools/verify/scenarios/needs-happiness.json` exits 0; `state` snapshots show `house_levels` going from all 1s to including 2s and `happiness` moving with the tax rate.

## Gotchas

- Services with a job do nothing until their worker is inside (`Waiting for a worker`); they need an unemployed villager.
- Coverage is a circle from the building's center, not a road distance. The placement preview draws it.
- Levels change only after needs hold for ~10 game seconds, and happiness updates every 2 s; always `wait_until`.
- Setting `Harsh` on a small Hamlet can push homes under 25 happiness, and they start losing residents after ~45 s.
- `click_tile [0, -2]` hits the Keep only while the camera hasn't moved; the Keep is 3x3 directly above its entrance.
