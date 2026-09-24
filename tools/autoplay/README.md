# Autoplayer

A bot that plays whole games for balance data. It uses the game's own rules —
costs, tier locks, placement and road access, real game time at 4x — with no
test shortcuts, and writes a timeline and summary per game.

```bash
tools/autoplay/run.sh --seeds 12345,7,99 --minutes 90      # Normal difficulty
tools/autoplay/run.sh --seeds 12345 --minutes 60 --difficulty 0
```

Reports: `.autoplay/<timestamp>/seed-<n>/summary.md` (tiers, counters, per-minute
table, events) and `report.json` (everything, including per-minute
production/spending rates, building counts, the bot's actions and why builds
failed). A 90-minute game takes about 10–40 seconds headless.

`probe.tscn` measures one workplace in a quiet game (no raids):

```bash
godot --headless --fixed-fps 30 --path . res://tools/autoplay/probe.tscn -- --building=quarry --minutes=5
```

It prints output per minute and how the workers spent their time.

## How the bot plays

Every 2 game seconds it takes the most urgent action it can afford:
1. War first: Call to Arms when raiders swamp the Keep; lair assault at City
   with 6+ troops; a guard tower before the first raid; barracks at Village.
2. Food when stocks are low (fishers by water, farms, then mills/bakeries).
3. Woodcutters when wood runs short, and firewood stock before winter.
4. Housing, only while food (2.5+ minutes of stock) and a firewood reserve
   allow.
5. Quarries, storage when 85% full, wells where homes lack water, services
   and tier buildings, research, and troops (once the town has 20 people).

Streets: horizontal avenues every 3 rows around the Keep, joined by a spine,
lengthened when there's no room; branch roads out to forests, rocks and water.

It is a sensible but plain player: no walls, no clever tower placement, no
micro. Treat its results as "what an average player may hit", not as limits.

## First findings (M12, Normal, seeds 12345 / 7 / 99, 90 minutes)

All three towns lost between minutes 26 and 39:
- Towns reach Village in 1-9 minutes, grow to 25-30 people by minutes 6-10,
  then stall; none reached Town (35 people, 2 raids, 4 level-2 homes).
- Food production (30-40 a minute) barely matched consumption at that size.
- Raids 3-5 (minutes 20-35, 14-25 raiders with orcs) burned the towns:
  25-57 fires and 21-66 buildings lost per game, 30-48 villagers killed.
- Storage: materials share one capacity, so wood surpluses (300+ idle) fill
  it and block stone; a probed woodcutter spent about half its time on
  "Storage full" and produced 14 wood/min instead of about 25-30.

## Round 1 of balance changes (M13) and what changed

Changes: Keep storage 200 → 300 (and more per tier), Stockpile 150 → 250;
fire burns 2%/s (was 3%) and spreads 2%/s (was 5%), and a building's own
people put fires out in 15 s without a Well; orcs from the 3rd raid with a
10% ignite chance (was 2nd raid, 25%). The re-run also exposed a bug:
between raids buildings repair 2%/s, which fully cancelled the new burn
rate, so fires outside raids never burned out. Burning buildings no longer
repair.

Same seeds, 90 minutes (the bot still loses every game):

| | before | after |
|---|---|---|
| survived until (min) | 26-39 | 41-53 |
| reached Town | 0 of 3 | 2 of 3 (min 16 and 33) |
| peak population | 25-30 | 36 / 150 / 114 |
| fires per game | 25-57 | 11-29 |
| villagers killed by raiders | 30-48 | 10-26 |
| left starving | 0-87 | 28-216 |

The killer now is food. Towns grow to 100-150 people, raids (which scale
with population, 40 raiders by minute 27) stop work for long stretches, and
the farm chain is choked: 14 farms grew 228 wheat/min but only ~20 flour/min
came out of 3-4 mills with a single carter.

## Round 2 (M14)

Game changes: producers (mills, bakeries, smithies) fetch a full load of whole
batches per trip, keeping the extra at the workplace, instead of one batch
per trip; mills have 2 millers and grind in 5 s (was 1 and 10 s); goblin
numbers grow with population half as fast (pop/16, was pop/8).
Bot changes: 1 mill per 3 farms, carters in proportion to workplaces,
standing down Call to Arms once raiders thin out, and growing only while
food income (bread + fish per minute) covers the population by 15%.

Same seeds, 90 minutes: the bot still loses, at minutes 35-49.

| | round 1 | round 2 |
|---|---|---|
| survived until (min) | 41-53 | 35-49 |
| peak population | 36 / 150 / 114 | 80 / 88 / 52 |
| left starving | 28-216 | 0-56 |
| villagers killed by raiders | 10-26 | 1-36 |
| buildings lost | 20-59 | 25-64 |

Starvation is much lower now that the bot grows on income. The main failure
is defense: seed 99 lost its Keep to raid 4 (~30 raiders) with almost no other
losses. The bot defends plainly (no walls, 5 towers, 6 troops), so the next
step is a competent defender before concluding raids are too strong.
Food storage is shared by wheat, flour, bread and fish, so unground wheat
can crowd out bread and fish.

## Round 3 (M15): teaching the bot to defend

Bot-only changes: a town wall (a rectangle round the street grid; palisade,
then stone walls; gates where roads cross; wall towers every 8 segments from
Town, replacing palisade), up to 8 guard towers, a second barracks at Town,
3-6 troops per barracks, earlier Fletching/Masonry/Tempered Steel, and saving
up for key buildings (barracks, towers, scholars' hall, smithy) once the town
has 20 people.

Same seeds, 90 minutes: still no win, and results swing a lot by seed
(19 / 78 / 52 minutes). What held it back:
- Saving for defense without enough income stalls growth; without saving,
  it never affords a barracks (2,800 failed tries in one game).
- Its army was militia only (no weapons yet): 104 trained, 104 lost.
- It never reached Town in this round, so stone walls, wall towers and
  archers never came into play.
- Raid 2 (9-10 raiders, 2 brutes, minutes 13-20) can end a 16-20 person
  village whose defense is 2-3 guard towers: likely worth softening.

Conclusion: the bot is now the bottleneck, not the game. A competent bot
needs real economic planning (income-aware budgets per goal), which is a
project of its own. A human playtest is the better next source of truth.

## M16-M17

Raid 2 became goblins only (brutes from the 3rd raid), and wheat/flour got
their own "grain" storage. Same seeds: seed 7 survived the full 90 minutes
for the first time (peak population 106); none of the three towns starved;
seeds 12345 and 99 still lost their Keep around minute 40 (the bot's
defense).
