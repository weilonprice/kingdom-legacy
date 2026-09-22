# Storage and hauling

Goods live in specific buildings. Workplaces keep a pile of finished goods
(`Ready for pickup`); storage buildings (Keep, Stockpile, Granary, Warehouse)
hold their own inventory up to their capacity; gold is the Keep's treasury.
Haulers from a Carter's Yard empty piles into storage and bring producers
their ingredients; without haulers, workers carry a load themselves when
their pile fills up.

## Sub-features

- `workplace-pile` gatherers, farms and producers drop output at their own building.
- `storage-inventory` each storage panel lists `Stored here: …` and `Holds <category>: n/cap`.
- `haulers` Carter's Yard workers move piles of 4+ into the nearest storage with room, 8 at a time.
- `supply` haulers (or the producer itself) bring inputs from storage or another workplace's pile.
- `self-haul` a worker whose pile is full carries a load to storage (`Pile is full: hauling a load to storage`).
- `theft` goblins steal from the specific storage they reach (`stole … from the <building>`).

## How to get to it (user POV)

- Click a workplace for `Ready for pickup: …`, a storage building for `Stored here: …`.
- `Storage` tab → `Carter's Yard` (Hamlet).

## Driving it with tools/verify/run.sh

Preconditions:

- Fresh run; `setup_grant` 200 wood / 50 stone.

- **Road to the woods.** `{"key": "R"}`, `{"drag_tile": [[6, 3], [14, 3]]}`.
- **Woodcutter + stockpile.** `Resources` → `Woodcutter` at `find_site` near `[10, 2]` with `entrance_on_road`; `Storage` → `Stockpile` at a road site.
- **Pile builds up.** At `4x`, `wait_until` `pile_min` = `{"woodcutter": {"wood": 4}}`; the woodcutter panel shows `Ready for pickup: wood`.
- **Haulers deliver.** `Storage` → `Carter's Yard` at a road site; `wait_until` `stored_min` = `{"stockpile": {"wood": 4}}` (timeout 90). The stockpile panel shows `Stored here: wood`.
- **Proof.** `tools/verify/run.sh tools/verify/scenarios/hauling.json` exits 0 with `01-woodcutter-pile.png` and `02-stockpile-filled.png`.

## Gotchas

- Wood can also reach storage by self-hauling when the woodcutter's pile tops 12. The haulers take it at 4, and in 8-unit loads, so a stockpile holding 8 soon after the yard is built points to haulers.
- Haulers go to the nearest storage with room, which may be the Keep rather than the new stockpile. The scenario builds the stockpile nearer the woodcutter than the Keep.
- Kingdom totals in the top bar count storage only, not workplace piles.
- Destroying a storage building loses what's inside; demolishing it moves the goods elsewhere.
