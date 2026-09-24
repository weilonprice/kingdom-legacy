# Royal family and treasury

A ruling house lives in the castle: ruler, spouse and heir (Lord/Lady →
Duke/Duchess → King/Queen by tier; the heir is Heir or Prince/Princess).
By day they stroll the castle grounds (king, queen, heir art); at night and
during raids they're inside. `K`, the crown (♛) button or clicking a royal
opens `The Royal Court — House <name>` with portraits, ages and the ruler's
traits. Traits apply to the realm while that ruler reigns. Royals age a
year every 100 s; the ruler dies of old age (58-72) → `Long live <heir>!`;
with no heir → `succession crisis` (no taxes, -15 happiness, 25% gold lost)
for 3 minutes → `<new ruler> of House <x> claims the throne`. Raiders who
bring the castle below half HP during a raid → `Raiders have broken into
the <castle>!` (30% gold stolen, 20% of castle-stored goods burned, 35% a
royal is slain); repaired above half → `the breach is sealed`.

## Sub-features

- `court` panel via K, crown button, castle panel `Royal Court`, clicking.
- `map` RoyalAgent strollers; hidden at night/raids.
- `traits` GameState.royal_mods (Royals._after_change); keys happiness,
  tax, castle_work, troop_damage, research_speed, troop_upkeep.
- `succession` heir inherits, marriage after 2 years, child after 2 more.
- `crisis` no heir; new dynasty after CRISIS_TIME.
- `breach` once per breach, sealed by repair.
- `save` family, timers, crisis, breach and RNG state (save version 3).

## How to get to it (user POV)

- Press K, or click the crowned figures near the castle.

## Driving it with tools/verify/run.sh

- `tools/verify/run.sh tools/verify/scenarios/royals.json`: ruler and heir
  present, ≥2 royals on the map; K shows the court; `click_royal` `ruler`
  opens it; `setup_royal` traits just → `happiness_mod` 6, greedy →
  `tax_mod` 1.3 / -6; ruler age 99 → `Long live`, heir empty; again →
  `succession crisis`, `tax_mod` 0, panel `The throne is empty`;
  `crisis_left` 0.5 → `claims the throne`; F5/F8 keeps the court; F9 raid →
  royals off the map; `setup_keep_hp` 0.4 → `broken into`; 0.9 → `sealed`.

## Gotchas

- The founding family depends on the map seed; a claimant may be a Lady,
  so match titles loosely (`" "` = anyone).
- Royal art is on a 68 px canvas; RoyalAgent scales it (0.72, heir 0.55).
