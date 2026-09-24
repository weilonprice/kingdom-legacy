# Merchants and trade

A Trading Post (Storage tab, Village) brings travelling merchants: every 150
calm seconds a caravan walks in from the map edge and trades for 90 s. The
Trading Post panel shows `<Merchant> in town for m:ss — has N gold to spend`
and a row per good with `Buy for Ng` / `Sell for Ng` (lots of 10). Merchants
leave when raiders arrive (`packs up and hurries away`) and move on after
their stay (`moves on`).

## Sub-features

- `post` Trading Post placement; panel shows `Next caravan in m:ss` with no
  merchant.
- `arrive` message `A <merchant> has arrived at the Trading Post`.
- `buy` gold down, goods up; `No room to store <item>` when storage is full;
  `Not enough gold`.
- `sell` goods down, gold up; `The <merchant> can't afford more <item>`.
- `leave` on raid arrival; next caravan 45 s after the raid.
- `save` saves keep the merchant (stock, purse, time left) and the timer.

## How to get to it (user POV)

- Reach Village, build a Trading Post on a road, wait for a caravan (about
  45 s for the first), click the post.

## Driving it with tools/verify/run.sh

- `tools/verify/run.sh tools/verify/scenarios/trade.json`: village setup;
  build the post; `setup_merchant` `timber`; `button_on_screen` checks;
  `Buy for 9g` wood → `No room to store wood` (the test Keep is over-full);
  `Sell for 30g` bread → gold up; `Buy for 35g` bread → `min.bread` 140;
  `F5`/`F8` keeps `merchant` `Timber merchant`; `F9` → at `ACTIVE`, message
  `packs up and hurries away`.

## Gotchas

- The panel refreshes on every trade (Trade.changed), and the driver re-aims
  before pressing, so buttons that shift as text changes are still hit.
- Windowed runs can lose all input if the window isn't in front ("cursor over
  nothing"); rerun.
