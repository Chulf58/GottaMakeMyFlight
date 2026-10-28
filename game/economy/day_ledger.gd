class_name DayLedger
extends Node
## Today's money, per wallet category (decision money-hover-design-categorised-
## wallet-transactions-feed-a-sa). It adds up every Wallet.transaction of the
## current game day: the gross amount under its category, and the wages a
## credit paid off under WAGES, so the totals sum to the change in the balance.
## Before recording a transaction it rolls to the day of the transaction's
## tick, and it rolls on every clock tick, so the wage charge at the first tick
## of a day lands on the new day whichever listener hears the tick first
## (SimClock counts the tick before it emits it).
##
## The totals are a SaveGame part. A save from before the part has none, and
## the load marks the ledger as counting since the load (start_since_load), so
## the money card says so rather than showing a partial day as the whole one.
## The next new day clears the mark.
##
## OPENING (the starting budget) is recorded but is not earnings: it is in
## neither the operating result nor the cash change. The rescue grant is
## counted apart from the operating result.

## The totals changed: a transaction, a new day, a load.
signal changed

## Snapshot key per category; each total is a signed decimal string.
const CATEGORY_KEYS := {
	Wallet.Category.FEES: "fees",
	Wallet.Category.SHOP: "shop",
	Wallet.Category.GRANT: "grant",
	Wallet.Category.OPENING: "opening",
	Wallet.Category.BUILD: "build",
	Wallet.Category.WAGES: "wages",
}
const SNAPSHOT_KEYS := ["day", "since_load"]
## Categories whose total is never above 0 (money out) or never below 0
## (money in); BUILD nets purchases against refunds and may be either.
const OUT_KEYS := ["wages"]
const IN_KEYS := ["fees", "shop", "grant", "opening"]
## Far beyond a day's money; a saved total past it is refused.
const MAX_TOTAL := 1_000_000_000_000_000_000
const NO_DAY := -1

## In a scene these come from the wired nodes; tests call bind().
@export var clock: SimClock
@export var finances: Finances

var _wallet: Wallet
var _clock: SimClock
var _day := NO_DAY
var _since_load := false
## Wallet.Category -> signed total for the day.
var _totals: Dictionary = {}


func _init() -> void:
	_clear()


func _ready() -> void:
	if clock == null or finances == null:
		push_error("DayLedger: clock and finances must both be set, so no money is counted")
		return
	bind(finances.wallet, clock)


## Follows `wallet`'s transactions and `with_clock`'s ticks. A ledger with no
## day yet starts on the clock's day.
func bind(wallet: Wallet, with_clock: SimClock) -> void:
	if _wallet != null and _wallet.transaction.is_connected(record):
		_wallet.transaction.disconnect(record)
	if _clock != null and _clock.ticked.is_connected(on_tick):
		_clock.ticked.disconnect(on_tick)
	_wallet = wallet
	_clock = with_clock
	_wallet.transaction.connect(record)
	_clock.ticked.connect(on_tick)
	if _day == NO_DAY:
		_day = GameCalendar.day_of(_clock.tick)


## The game day the totals are for.
func day() -> int:
	return _day


## True while the totals run from a load of a save that held no ledger.
func is_since_load() -> bool:
	return _since_load


## The signed total for `category` today: money in is positive, money out
## negative.
func amount(category: Wallet.Category) -> int:
	return _totals[category]


## Wages paid today, as a positive amount.
func wages_paid() -> int:
	return -amount(Wallet.Category.WAGES)


## Airline fees and shop sales less wages paid.
func operating_result() -> int:
	return amount(Wallet.Category.FEES) + amount(Wallet.Category.SHOP) - wages_paid()


## The day's change in the balance, the starting budget left out.
func cash_change() -> int:
	return operating_result() + amount(Wallet.Category.BUILD) + amount(Wallet.Category.GRANT)


## Wallet.transaction: adds a movement to the day of its tick.
func record(gross: int, category: int, wages_claimed: int, tick: int) -> void:
	if tick == Wallet.NO_TICK:
		push_error(
			"DayLedger: a %d transaction has no tick; it is counted on day %d" % [gross, _day]
		)
	else:
		_roll_to(GameCalendar.day_of(tick))
	_totals[category] += gross
	_totals[Wallet.Category.WAGES] -= wages_claimed
	changed.emit()


## SimClock.ticked: starts a new day at its first tick.
func on_tick(tick: int) -> void:
	_roll_to(GameCalendar.day_of(tick))


## A load of a save with no ledger: nothing counted yet today, on the clock's
## day, marked as counting since the load.
func start_since_load() -> void:
	_clear()
	if _clock != null:
		_day = GameCalendar.day_of(_clock.tick)
	_since_load = true
	changed.emit()


## JSON-safe state for a save: the day, the since-load mark and each
## category's total as decimal strings.
func to_snapshot() -> Dictionary:
	var data := {"day": str(_day), "since_load": _since_load}
	for category in CATEGORY_KEYS:
		data[CATEGORY_KEYS[category]] = str(_totals[category])
	return data


## Restores a to_snapshot() dictionary. Pushes an error and returns false,
## changing nothing, for a missing or unknown key, a day that is not a decimal
## string from 0, a since_load that is not a boolean, or a total out of range
## or of the wrong sign for its category.
func from_snapshot(data: Dictionary) -> bool:
	var problem := _snapshot_problem(data)
	if problem != "":
		push_error("DayLedger.from_snapshot: %s" % problem)
		return false
	_day = str(data["day"]).to_int()
	_since_load = data["since_load"]
	for category in CATEGORY_KEYS:
		_totals[category] = str(data[CATEGORY_KEYS[category]]).to_int()
	changed.emit()
	return true


## "" or why a saved ledger and the saved clock disagree. The ledger rolls on
## every tick and saves are taken between ticks, so its day is the clock's.
## Run by SaveLinks on the save's parts.
static func day_link_problem(ledger: Dictionary, clock_data: Dictionary) -> String:
	if not SimClock.is_int64_string(ledger.get("day")):
		return ""
	if not SimClock.is_int64_string(clock_data.get("tick")):
		return ""
	var saved_day := str(ledger["day"]).to_int()
	var clock_day := GameCalendar.day_of(str(clock_data["tick"]).to_int())
	if saved_day != clock_day:
		return (
			"day_ledger: today's money was counted for day %d, but the clock is on day %d"
			% [saved_day, clock_day]
		)
	return ""


func _roll_to(new_day: int) -> void:
	if new_day == _day:
		return
	if new_day < _day:
		push_error("DayLedger: day %d is before the ledger's day %d" % [new_day, _day])
		return
	_clear()
	_day = new_day
	_since_load = false
	changed.emit()


func _clear() -> void:
	for category in CATEGORY_KEYS:
		_totals[category] = 0


func _snapshot_problem(data: Dictionary) -> String:
	var keys: Array = SNAPSHOT_KEYS + CATEGORY_KEYS.values()
	for key in data.keys():
		if not keys.has(key):
			return "unknown key '%s'" % key
	for key in keys:
		if not data.has(key):
			return "missing key '%s'" % key
	if not _whole_in(data["day"], 0, Settlement.MAX_DAY):
		return "'day' is not a day"
	if typeof(data["since_load"]) != TYPE_BOOL:
		return "'since_load' must be true or false"
	for key in CATEGORY_KEYS.values():
		var low := 0 if IN_KEYS.has(key) else -MAX_TOTAL
		var high := 0 if OUT_KEYS.has(key) else MAX_TOTAL
		if not _whole_in(data[key], low, high):
			return "'%s' is not a decimal string from %d to %d" % [key, low, high]
	return ""


## Whether `text` is a decimal string of a whole number from `low` to `high`.
static func _whole_in(text: Variant, low: int, high: int) -> bool:
	if not SimClock.is_int64_string(text):
		return false
	var value := str(text).to_int()
	return value >= low and value <= high
