# Peasants, burghers and nobles

A villager's class is their home's level: Cottage peasants, Townhouse
burghers, Manor nobles (castle residents are peasants). Jobs have a class
(ClassDefs): burghers for smithy, armory, tavern, market, trading post
(market/trading post also nobles); nobles for scholars, chapel and the
Barracks captain; everything else labour. Burghers take labour when no
skilled job is free. With nobody of the right class free, a lower-class
villager fills in as an apprentice (60% speed; the panel shows
`(peasant, apprentice: slower)`) and steps aside for a fitting worker.
Knights need a noble captain (`Knights need a noble captain…`). Homes are
drawn per level (house → townhouse → manor; stone house → stone townhouse →
stone manor). Taxes by level 1 / 2 / 3.5.

## Driving it with tools/verify/run.sh

- `tools/verify/run.sh tools/verify/scenarios/classes.json`: village setup
  (all peasants); Chapel, Smithy, Barracks → `apprentices` ≥ 2, smithy panel
  `(needs burghers)`; `setup_home_level` h1/h2 → 2 → `class.burgher` ≥ 4,
  `home_art` `townhouse`, apprentices drop, smithy shows `(burgher)`; City,
  Knight → `noble captain` refusal; h3 → 3 → a noble, `manor`, barracks
  `A noble captain commands`, Knight trains.

## Gotchas

- `setup_home_level` pins the level (meta `pinned_level`): Needs won't
  change a pinned home.
