# Roads

Roads tab: `Cobblestone Road` (Village; 1 stone a tile; 2.0x) and `Paved
Street` (Town; 2 stone + 1 gold; 2.4x); dirt 1.6x. Drag over road to
upgrade or over open ground to lay new. Tiles show as `Cobblestone road` /
`Paved street` (+ `— crowded`). More than 2 walkers on a road tile slow it
(to 45% at worst). O → `Overlay: Traffic` (recent use, crowded tiles
ringed). Homes need a paved street at the door for Manor (panel: `A Manor
needs a paved street at the door.`). Paving adds desirability nearby.

## Driving it with tools/verify/run.sh

- `tools/verify/run.sh tools/verify/scenarios/roads.json`: village setup;
  h1 shows the paved-street hint; Cobblestone over `[-5, 4]`→`[5, 4]` →
  `cobble_roads` ≥ 8, `home_beauty` up; Paved Street refused before Town;
  Town → paved over the same street → `paved_roads` ≥ 8, hint gone; 4x →
  `busy_roads` ≥ 3; O ×5 → `Overlay: Traffic`; F5/F8 keeps tiers.
