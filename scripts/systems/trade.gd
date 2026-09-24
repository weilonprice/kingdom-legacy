class_name Trade
extends Node
## Travelling merchants. While the town has a Trading Post, a caravan sets
## out every CARAVAN_INTERVAL calm seconds: a merchant walks in from the map
## edge, trades at the post for STAY_TIME seconds, then walks away. A merchant
## keeps trading through a raid warning but leaves when the raiders arrive;
## the next caravan then comes AFTER_RAID seconds after the raid.
## Buying and selling happen in lots (TradeDefs.LOT) through buy()/sell().

signal changed

const CARAVAN_INTERVAL := 150.0
const FIRST_CARAVAN := 45.0
const STAY_TIME := 90.0
const AFTER_RAID := 45.0

var world: WorldMap
var raids: RaidDirector
var progression: Progression

## The merchant at the post (or on the way): {} when none.
## {"id", "stock": {item: n}, "gold": int, "time_left": float, "arrived": bool}
var merchant := {}
var agent: MerchantAgent
var timer := FIRST_CARAVAN


func post() -> Building:
	for b in world.buildings:
		if b.def_id == "trading_post" and b.has_road:
			return b
	return null


func is_open() -> bool:
	return not merchant.is_empty() and merchant.arrived


func merchant_name() -> String:
	return TradeDefs.MERCHANTS[merchant.id].name if not merchant.is_empty() else ""


func _process(delta: float) -> void:
	var p := post()
	var raid_on := raids.phase == RaidDirector.Phase.ACTIVE
	if merchant.is_empty():
		if p == null or raids.phase != RaidDirector.Phase.CALM:
			return
		timer -= delta
		if timer <= 0.0:
			_send_caravan(p)
		return
	if raid_on or p == null:
		_leave("The %s packs up and hurries away from the raid." % merchant_name().to_lower())
		timer = AFTER_RAID
		return
	if merchant.arrived:
		merchant.time_left -= delta
		if merchant.time_left <= 0.0:
			_leave("The %s moves on." % merchant_name().to_lower())


func _send_caravan(p: Building) -> void:
	var ids: Array = TradeDefs.BY_TIER[progression.tier] if progression != null else TradeDefs.BY_TIER[0]
	var id: String = ids[randi() % ids.size()]
	var start := raids._pick_spawn_tile()
	arrive(id, start if start != WorldMap.INVALID_TILE else p.entrance())


## A merchant of type `id` sets out from `from` toward the Trading Post
## (tests pass the post's own entrance to have them arrive at once).
func arrive(id: String, from: Vector2i) -> void:
	var def: Dictionary = TradeDefs.MERCHANTS[id]
	var stock: Dictionary = def.sells.duplicate()
	for item: String in def.carries:
		stock[item] = stock.get(item, 0) + def.carries[item]
	merchant = {"id": id, "stock": stock, "gold": def.gold, "time_left": STAY_TIME, "arrived": false}
	agent = MerchantAgent.new()
	agent.setup(world, from, post().entrance())
	agent.reached.connect(_on_reached)
	world.unit_root.add_child(agent)
	if from == post().entrance():
		_on_reached()
	changed.emit()


func _on_reached() -> void:
	if merchant.is_empty() or merchant.arrived:
		return
	merchant.arrived = true
	GameState.notify("A %s has arrived at the Trading Post (click it to trade)." % merchant_name().to_lower())
	Sound.play("coins", post().center() if post() != null else null)
	changed.emit()


func _leave(text: String) -> void:
	if merchant.arrived:
		GameState.notify(text)
	merchant = {}
	timer = CARAVAN_INTERVAL
	if is_instance_valid(agent):
		agent.go_away(raids._pick_spawn_tile())
	agent = null
	changed.emit()


# --- Prices and deals -------------------------------------------------------------

## Gold for LOT units bought from the merchant (0 if it has none to sell).
func buy_price(item: String) -> int:
	if not is_open() or merchant.stock.get(item, 0) <= 0:
		return 0
	var def: Dictionary = TradeDefs.MERCHANTS[merchant.id]
	var k := TradeDefs.SELL_SPECIALTY if def.sells.has(item) else TradeDefs.SELL_OTHER
	return maxi(1, ceili(TradeDefs.PRICES[item] * k * TradeDefs.LOT))


## Gold the merchant pays for LOT units of yours.
func sell_price(item: String) -> int:
	if not is_open():
		return 0
	var def: Dictionary = TradeDefs.MERCHANTS[merchant.id]
	var k := TradeDefs.BUY_WANTED if item in def.wants else TradeDefs.BUY_OTHER
	return maxi(1, floori(TradeDefs.PRICES[item] * k * TradeDefs.LOT))


## Buys a lot; "" on success, else why not.
func buy(item: String) -> String:
	var lot := mini(TradeDefs.LOT, int(merchant.get("stock", {}).get(item, 0)))
	if not is_open() or lot <= 0:
		return "The merchant has no %s to sell." % item
	var cost := ceili(buy_price(item) * lot / float(TradeDefs.LOT))
	if GameState.space_for(item) < lot:
		return "No room to store %s." % item
	if not GameState.spend({"gold": cost}):
		return "Not enough gold (%d needed)." % cost
	GameState.add_resource(item, lot)
	merchant.stock[item] -= lot
	merchant.gold += cost
	GameState.tally("bought", item, lot)
	Sound.play("coins")
	changed.emit()
	return ""


## Sells a lot; "" on success, else why not.
func sell(item: String) -> String:
	if not is_open():
		return "No merchant is here."
	var price := sell_price(item)
	if GameState.count(item) < TradeDefs.LOT:
		return "You need %d %s to sell." % [TradeDefs.LOT, item]
	if merchant.gold < price:
		return "The %s can't afford more %s." % [merchant_name().to_lower(), item]
	GameState.remove_resource(item, TradeDefs.LOT)
	GameState.add_resource("gold", price)
	merchant.gold -= price
	merchant.stock[item] = merchant.stock.get(item, 0) + TradeDefs.LOT
	GameState.tally("sold", item, TradeDefs.LOT)
	Sound.play("coins")
	changed.emit()
	return ""
