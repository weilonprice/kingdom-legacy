# Beauty and desirability

Every tile has a desirability (WorldMap.desirability_at, BeautyDefs):
decorations and some civic buildings raise it nearby, industry, storage and
barracks lower it. Homes need ≥ -10 for Townhouse and ≥ 20 for Manor. The
Decor tab: `Plaza` (drag; paves road tiles, 3 stone each), `Flowerbed`,
`Planted Tree` (Hamlet), `Garden`, `Fountain` (Village), `Statue`, `Royal
Monument` (Town; shows the current ruler, titled `Monument to <ruler>`).
Decorations need no road. O cycles to `Overlay: Desirability` (heatmap +
each home's score). A home's panel shows `Desirability N` and what a Manor
needs.

## Driving it with tools/verify/run.sh

- `tools/verify/run.sh tools/verify/scenarios/beauty.json`: village setup;
  Plaza drag `[-5, 4]`→`[5, 4]` (the street) → `plazas` ≥ 8; fountain,
  garden, 2 flowerbeds, a planted tree → `home_beauty` up ≥ 5; Town →
  Royal Monument → `Monument to`; a home's panel shows `Desirability`;
  O ×4 → `Overlay: Desirability` (screenshot); a Smithy by the homes →
  `decreased.home_beauty` ≥ 1; F5/F8 keeps plazas and buildings.

## Gotchas

- The build bar is rebuilt on tier-up: click another tab and back before
  pressing a newly unlocked button.
- Desirability is recomputed lazily (next frame) after building changes.
