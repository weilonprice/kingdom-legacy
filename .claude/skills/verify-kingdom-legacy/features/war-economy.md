# War economy

Iron Mines dig iron from rocks; the Smithy forges it into weapons and the
Armory into armor. Spearmen and archers need weapons, Knights (City) need
weapons and armor. Wall Towers join walls and shoot on their own. Two goblin
lairs sit in the wilds; each adds goblins to every raid until a squad
destroys it (its guards come out to fight). During a raid, Call to Arms makes
villagers fight nearby raiders with pitchforks instead of hiding.

## Sub-features

- `iron-chain` Iron Mine pile fills with iron; the Smithy's recipe
  `2 iron → 1 weapons`; weapons reach storage (top-bar materials tooltip).
- `wall-tower` `Defense` → `Wall Tower` is a single-click build; its panel
  says `Shoots raiders within 7 tiles…`; it kills a lone raider without a guard.
- `knights` Barracks panel `Knight` button (City); `A knight joined Squad N`.
- `lairs` `Scouts found 2 goblin lairs…` at game start (sent before the
  driver connects, so check `min.lairs` instead); dark ☠ arrows at the screen
  edge; right-click a lair with a squad selected; `The Goblin Lair is
  destroyed! +150 gold.`
- `call-to-arms` During a raid, `⚒ Call to Arms (C)` under the banner →
  message `To arms!`, button becomes `Stand down (C)`, villagers show a
  pitchfork and fight; it resets when the raid ends.

## How to get to it (user POV)

- Village: `Resources` → `Iron Mine`, `Industry` → `Smithy`. Town: `Armory`,
  `Defense` → `Wall Tower`. City: Barracks → `Knight`.
- Lairs are 30+ tiles from the Keep; follow the dark edge arrows.
- `F9` calls a raid; the Call to Arms button shows once raiders arrive.

## Driving it with tools/verify/run.sh

Preconditions: `include` `village-setup.json`, then (after Call to Arms)
`setup_tier` `City`, `setup_delay_raids` 3000 (no stray raids during the long
economy waits), a road
dragged `[[-9,-6],[9,-6]]` north of the Keep (the rows below the Keep are
rock on seed 12345), a Warehouse near `[5,-8]` so goods have room.

- **Call to Arms** (first, while still a Village so the raid is small):
  `F9`, `wait_until` `raid_phase` `ACTIVE`, `click_button` `Call to Arms`;
  `expect` `call_to_arms` true; `wait_until` `min.villagers_fighting` 1;
  after `CALM`, `expect` `call_to_arms` false.
- **Chain.** `find_site`/click `iron_mine` and `smithy`; at `4x`,
  `wait_until` `min.weapons` 1 (timeout 200).
- **Wall tower.** Click `Wall Tower`, `click_tile` `[4,-4]`; `setup_spawn`
  a `goblin_brute` at `[4,-9]`; `wait_until` `max.enemies` 0.
- **Knights.** `setup_grant` weapons 3 / armor 2 (armory shortcut); barracks →
  `Knight` ×2 + `Spearman`; `wait_until` `squad_troops_min` 3.
- **Lair.** `setup_research` tempered_steel (2 knights + a spearman alone
  lose to a 2500 HP lair about half the time); `setup_lair` `[0,-12]`; `CTRL+1`; `right_click_tile` `[0,-12]`;
  `expect` `squad_mode` `MANUAL`; `wait_until` message `Goblin Lair is destroyed`.
- **Proof.** `tools/verify/run.sh tools/verify/scenarios/war-economy.json`
  exits 0; windowed runs save `00-call-to-arms` … `04-lair-destroyed`.

## Gotchas

- Long run (~8 min headless); pass `--timeout 900`.
- `setup_grant`, `setup_tier`, `setup_spawn`, `setup_lair` are shortcuts.
- Over-full storage stalls the chain (`Storage full (holding iron)`).
- At City tier the F9 raids bring trolls and wolves; an undefended test town
  can fall (the game-over overlay then eats every click). Keep raids early.
- Lairs are drawn ~80px above their foot tile; clicks hit the sprite.
