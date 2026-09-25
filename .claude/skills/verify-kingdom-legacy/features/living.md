# A living kingdom

Ambient life that doesn't touch the economy. TownLife keeps, from the
number of lived-in homes, people and farms: children (1/3 homes, ≤24),
townsfolk with baskets (1/10 people, ≤20) visiting the market, well,
tavern, chapel and trading post and chatting (speech bubble) when they meet,
dogs (1/15 people, ≤10) following villagers, 3 chickens per farm plus a cow
or two sheep, and bird flocks by day. TownEffects: chimney smoke on
lived-in homes and working bakery/smithy/armory/tavern (faster in winter),
window glow on homes and the castle at night (own canvas layer, additive),
and Carter's Yard haulers push handcarts while carrying. Townsfolk hide at
night and during raids.

## Sub-features

- `folk` Townsfolk (child/shopper/dog) with art child, townswoman, dog.
- `animals` Animal (chicken/sheep/cow) art in assets/sprites/animals.
- `birds` Birds node (code-drawn), launched near the camera every 20-45 s.
- `effects` TownEffects puffs and glows.

## Driving it with tools/verify/run.sh

- `tools/verify/run.sh tools/verify/scenarios/living.json`: village setup,
  a Farm and a Market; `wait_until` `life.children`/`shoppers`/`dogs`/
  `chickens`/`grazers`/`smoke`, then `life.birds`, then `life.chatting`;
  zoomed screenshots at the market and farm; night → `life.glows` ≥5 and
  `life.folk_visible` 0; morning → folk back; F9 raid → folk hidden.

## Gotchas

- Screenshots need the game window visible: a full-screen app in another
  macOS Space stops it drawing ("the game window is not drawing").
- Counts refresh every 3 s (TownLife.CHECK).
