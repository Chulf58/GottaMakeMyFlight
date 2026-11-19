class_name DayLedger
extends Node
## Today's money, per wallet category (decision money-hover-design-categorised-
## wallet-transactions-feed-a-sa). It adds up every Wallet.transaction of the
## current game day: the gross amount under its category, and each debt a
## credit paid off under that debt's category (owed wages under WAGES, owed
## upkeep under UPKEEP), so the totals sum to the change in the balance.
## Before recording a transaction it rolls to the day of the transaction's
## tick, and it rolls on every clock tick (SimClock counts the tick before it
## emits it). Settlement charges the day's wages and toilet upkeep on the day's
## last tick (decision daily-wages-are-charged-on-the-last-tick-of-the-game-day-
## and), so they land on the day they were earned, whichever listener hears the
## tick first, and the next day starts at 0. Owed wages or upkeep paid later
## land on the day paid.
##
## The totals are a SaveGame part. A save from before the part has none, and
## the load marks the ledger as counting since the load (start_since_load), so
## the money card says so rather than showing a partial day as the whole one.
## The next new day clears the mark. A saved ledger from before upkeep has no
## "upkeep" total and loads with 0 upkeep paid.
##
## OPENING (the starting budget) is recorded but is not earnings: it is in
## neither the operating result nor the cash change. The rescue grant is
## counted apart from the operating result. Wages and upkeep are both costs in
## the operating result; parking fees are earnings in it. Incident bonuses and
## costs (INCIDENT) are in the cash change but not the operating result, like
## the rescue grant: they are one-off, not the airport's running business.
## Airline fines (FINES: a Miss fine contract's charge per missed passenger, and
## an Exit fee contract's fee when the player ends it within its term) are
## a running cost in the operating result; a signing bonus (SIGNING_BONUS) is
## one-off and in the cash change only. A fine the wallet could not pay in full
## (Wallet.unpaid) is added up as the day's unpaid fines, beside the totals: it
## moved no money, so it is in neither result.

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
	Wallet.Category.UPKEEP: "upkeep",
	Wallet.Category.PARKING: "parking",
	Wallet.Category.INCIDENT: "incident",
	Wallet.Category.FINES: "fines",
	Wallet.Category.SIGNING_BONUS: "signing_bonus",
}
## The day's unpaid fines, a decimal string from 0.
const FINES_UNPAID_KEY := "fines_unpaid"
## Cumulative positive revenue across all days, a decimal string from 0.
const TOTAL_EARNED_KEY := "total_earned"
const EARNED_CATEGORIES := [
	Wallet.Category.FEES,
	Wallet.Category.SHOP,
	Wallet.Category.PARKING,
	Wallet.Category.SIGNING_BONUS,
	Wallet.Category.INCIDENT,
]
## Totals added after the ledger was first saved: a saved ledger without one
## loads it as 0.
const OPTIONAL_CATEGORY_KEYS := ["upkeep"]
const SNAPSHOT_KEYS := ["day", "since_load", FINES_UNPAID_KEY, TOTAL_EARNED_KEY]
## Far beyond a day's money; a saved total past it is refused. Any total may
## be either sign, since the Wallet takes any category in either direction.
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
## Fines charged today that the wallet could not pay, as a positive amount.
var _fines_unpaid := 0
## Cumulative positive revenue across all days of the run (survives day rollover).
var _total_earned := 0


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
		_wallet.unpaid.disconnect(record_unpaid)
	if _clock != null and _clock.ticked.is_connected(on_tick):
		_clock.ticked.disconnect(on_tick)
	_wallet = wallet
	_clock = with_clock
	_wallet.transaction.connect(record)
	_wallet.unpaid.connect(record_unpaid)
	_clock.ticked.connect(on_tick)
	if _day == NO_DAY:
		_day = GameCalendar.day_of(_clock.tick, _clock.epoch)


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


## Room upkeep paid today, as a positive amount.
func upkeep_paid() -> int:
	return -amount(Wallet.Category.UPKEEP)


## Fines that could not be paid today, as a positive amount.
func fines_unpaid() -> int:
	return _fines_unpaid


## Cumulative positive revenue across all days of the run (EARNED_CATEGORIES).
func total_earned() -> int:
	return _total_earned


## Airline fees, shop sales and parking fees less wages, upkeep and airline
## fines paid.
func operating_result() -> int:
	return (
		amount(Wallet.Category.FEES)
		+ amount(Wallet.Category.SHOP)
		+ amount(Wallet.Category.PARKING)
		+ amount(Wallet.Category.FINES)
		- wages_paid()
		- upkeep_paid()
	)


## The day's change in the balance, the starting budget left out.
func cash_change() -> int:
	return (
		operating_result()
		+ amount(Wallet.Category.BUILD)
		+ amount(Wallet.Category.GRANT)
		+ amount(Wallet.Category.INCIDENT)
		+ amount(Wallet.Category.SIGNING_BONUS)
	)


## Wallet.transaction: adds a movement to the day of its tick.
func record(gross: int, category: int, claimed: Dictionary, tick: int) -> void:
	if tick == Wallet.NO_TICK:
		push_error(
			"DayLedger: a %d transaction has no tick; it is counted on day %d" % [gross, _day]
		)
	else:
		_roll_to(GameCalendar.day_of(tick, _clock.epoch))
	_totals[category] += gross
	for debt in claimed:
		_totals[debt] -= claimed[debt]
	if gross > 0 and EARNED_CATEGORIES.has(category):
		_total_earned = mini(_total_earned + gross, MAX_TOTAL)
	changed.emit()


## Wallet.unpaid: adds the unpaid part of a fine to the day of its tick. Only
## fines are charged with Wallet.charge; another category pushes an error and is
## not counted.
func record_unpaid(unpaid: int, category: int, tick: int) -> void:
	if category != Wallet.Category.FINES:
		push_error("DayLedger: an unpaid %d in category %d is not a fine" % [unpaid, category])
		return
	if tick != Wallet.NO_TICK:
		_roll_to(GameCalendar.day_of(tick, _clock.epoch))
	_fines_unpaid += unpaid
	changed.emit()


## SimClock.ticked: starts a new day at its first tick.
func on_tick(tick: int) -> void:
	_roll_to(GameCalendar.day_of(tick, _clock.epoch))


## A load of a save with no ledger: nothing counted yet today, on the clock's
## day, marked as counting since the load.
func start_since_load() -> void:
	_clear()
	_total_earned = 0
	if _clock != null:
		_day = GameCalendar.day_of(_clock.tick, _clock.epoch)
	_since_load = true
	changed.emit()


## JSON-safe state for a save: the day, the since-load mark and each
## category's total as decimal strings.
func to_snapshot() -> Dictionary:
	var data := {
		"day": str(_day),
		"since_load": _since_load,
		FINES_UNPAID_KEY: str(_fines_unpaid),
		TOTAL_EARNED_KEY: str(_total_earned),
	}
	for category in CATEGORY_KEYS:
		data[CATEGORY_KEYS[category]] = str(_totals[category])
	return data


## Restores a to_snapshot() dictionary. Pushes an error and returns false,
## changing nothing, for a missing or unknown key, a day that is not a decimal
## string from 0, a since_load that is not a boolean, or a total outside
## -MAX_TOTAL to MAX_TOTAL (either sign is allowed in every category).
func from_snapshot(data: Dictionary) -> bool:
	var problem := _snapshot_problem(data)
	if problem != "":
		push_error("DayLedger.from_snapshot: %s" % problem)
		return false
	_day = str(data["day"]).to_int()
	_since_load = data["since_load"]
	_fines_unpaid = str(data[FINES_UNPAID_KEY]).to_int()
	_total_earned = str(data[TOTAL_EARNED_KEY]).to_int()
	for category in CATEGORY_KEYS:
		_totals[category] = str(data.get(CATEGORY_KEYS[category], "0")).to_int()
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
	if not SimClock.is_int64_string(clock_data.get("epoch")):
		return ""
	var clock_day := GameCalendar.day_of(
		str(clock_data["tick"]).to_int(), SimClock.saved_epoch(clock_data)
	)
	if saved_day != clock_day:
		return (
			"day_ledger: today's money was counted for day %d, but the clock is on day %d"
			% [saved_day, clock_day]
		)
	return ""


## "" or why a saved ledger and the saved settlement disagree on today's
## wages. Settlement.wages_paid_today counts the day's wage charge (made on its
## last tick), owed wages paid from the balance and wages claimed from credits
## during the day, and the ledger counts the same three under WAGES from the
## same tick, so a ledger not marked since_load holds exactly minus that. A ledger
## with a settlement that has no wage state is refused: every save that has
## the ledger also has the wage keys.
static func wages_link_problem(ledger: Dictionary, settlement: Dictionary) -> String:
	if not settlement.has("wages_paid_today"):
		return "day_ledger: the settlement holds no wages paid today to check it against"
	if ledger.get("since_load") == true:
		return ""
	if not SimClock.is_int64_string(ledger.get("wages")):
		return ""
	if not SimClock.is_int64_string(settlement["wages_paid_today"]):
		return ""
	var counted := -str(ledger["wages"]).to_int()
	var paid := str(settlement["wages_paid_today"]).to_int()
	if counted != paid:
		return (
			"day_ledger: today's wages paid are %d, but the settlement paid %d today"
			% [counted, paid]
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
	_fines_unpaid = 0
	for category in CATEGORY_KEYS:
		_totals[category] = 0


func _snapshot_problem(data: Dictionary) -> String:
	var keys: Array = SNAPSHOT_KEYS + CATEGORY_KEYS.values()
	for key in data.keys():
		if not keys.has(key):
			return "unknown key '%s'" % key
	for key in keys:
		if not data.has(key) and not OPTIONAL_CATEGORY_KEYS.has(key):
			return "missing key '%s'" % key
	if not _whole_in(data["day"], 0, Settlement.MAX_DAY):
		return "'day' is not a day"
	if typeof(data["since_load"]) != TYPE_BOOL:
		return "'since_load' must be true or false"
	return _totals_problem(data)


## Why the saved unpaid fines, total earned or a saved category total is refused, or "".
func _totals_problem(data: Dictionary) -> String:
	if not _whole_in(data[FINES_UNPAID_KEY], 0, MAX_TOTAL):
		return "'%s' is not a decimal string from 0 to %d" % [FINES_UNPAID_KEY, MAX_TOTAL]
	if not _whole_in(data[TOTAL_EARNED_KEY], 0, MAX_TOTAL):
		return "'%s' is not a decimal string from 0 to %d" % [TOTAL_EARNED_KEY, MAX_TOTAL]
	for key in CATEGORY_KEYS.values():
		if data.has(key) and not _whole_in(data[key], -MAX_TOTAL, MAX_TOTAL):
			return "'%s' is not a decimal string from %d to %d" % [key, -MAX_TOTAL, MAX_TOTAL]
	return ""


## Whether `text` is a decimal string of a whole number from `low` to `high`.
static func _whole_in(text: Variant, low: int, high: int) -> bool:
	if not SimClock.is_int64_string(text):
		return false
	var value := str(text).to_int()
	return value >= low and value <= high
