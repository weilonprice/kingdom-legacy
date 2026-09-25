# Public services

Civic tab: `Bathhouse`, `Physician`, `Fire Station` (Village) and `Town
Watch`, `School` (Town). Sickness (30+ people) shows a green cross on the
home: `Sickness has broken out at a Cottage. A Physician can cure it.`; the
physician walks there → `The physician cured the sick at a …`. Fires within
16 tiles of a Fire Station: `Firefighters put out the fire at the …`.
Unhappy homes (40+ people) send thieves: `Thieves stole N <item> from the
…! A Town Watch would stop them.`; storehouses in a watch house's range are
safe. Home panels list `✔ Bathhouse` / `✔ Town Watch` / `✔ School`
(School only from Townhouse up; Manors need it). Educated homes speed
research. Services overlay colours the new needs.

## Driving it with tools/verify/run.sh

- `tools/verify/run.sh tools/verify/scenarios/services.json`: village
  setup at Town; builds physician, fire station, bathhouse, school (each
  connected by road); `setup_sick` h1 → `sick_homes` 1 → cured
  (`sick_homes` 0, message); `setup_ignite` the school → `burning` 0 with
  `Firefighters put out`; h1 at level 2 → `educated_homes` ≥ 1 and
  `✔ School`; `setup_theft` h1 → `thefts` +1; Town Watch near the keep →
  `keep_guarded` true.
