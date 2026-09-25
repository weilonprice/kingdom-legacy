# Goods

Homes want goods by level (NeedDefs.GOODS): ale from Cottages (Townhouses
need it), tools and cloth from Townhouses (Manors need them), wine and fine
clothes for Manors. A home has a good (`✔ Ale` in its panel) when the
kingdom has some in storage and a staffed Market covers it; homes use it up
per resident per minute (stats `used`). Producers: Brewery, Toolmaker, Sheep
Farm, Weaver (Village); Vineyard, Winery, Tailor (Town). Sheep Farm and
Vineyard need no input (`Produces 2 wool every 10s`). Cloth & wine
merchant (Town+) sells the luxuries.

## Driving it with tools/verify/run.sh

- `tools/verify/run.sh tools/verify/scenarios/goods.json`: village setup;
  Stockpile, Carter's Yard, Market, Brewery, Toolmaker, Weaver, Sheep Farm
  (`find_site` with `connect` lays their roads) → ale, tools, cloth in
  storage; `goods_met.ale` ≥ 2, `✔ Ale` on h1, `used.ale` ≥ 1; Town, h1 →
  Manor with granted wine/fine clothes/tools/cloth → `✔ Wine`,
  `used.wine` ≥ 1; Vineyard + Winery → wine rises.

## Gotchas

- Goods count only once hauled to storage: without free storage or haulers
  they sit in the workshop's pile. The scenario adds a Stockpile and a
  Carter's Yard.
