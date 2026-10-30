class_name Settlement
extends Node
## Pays the airline fee (decision flights-and-economy-design-tick-derived-
## calendar-timetable-o, point 5). When PassengerSim.outcome says a passenger
## made their flight, the passenger's occurrence is resolved to its contract
## and the fee_per_passenger captured there is credited to the wallet, once.
## A missed passenger pays nothing, and neither does a one-off flight, which
## has no contract.
##
## A fee the wallet cannot hold (it would pass Wallet.MAX_BALANCE) is owed,
## not lost: it waits in the owed list and is paid on the first sim tick it
## fits, oldest first. The owed list is the one state a save holds
## (to_snapshot). PassengerSim emits outcome only when a passenger finishes
## (never when a snapshot is loaded), so a load cannot replay a fee; the
## settled ids below only refuse a repeated signal for a passenger the sim
## still holds.
##
## It also charges staff wages (ruling staff-wages-charged-daily-at-midnight-
## unpaid-wages-carried-as-owed). On the last tick of each game day (midnight,
## decision daily-wages-are-charged-on-the-last-tick-of-the-game-day-and) every
## member on the staff roster, one still finishing a service before leaving
## included, is charged the wage of their role (PriceTable.WAGES). The charge
## carries that tick, so the DayLedger books it to the day it was earned and the
## next day starts at 0 wages. The wallet
## pays what it holds; the rest is owed wages, kept apart from the wallet so
## the debt is whole even when it is larger than the wallet could ever hold.
## Owed wages are paid first, the moment money comes in: Settlement sets
## Wallet.credit_claim, so every credit (a fee, a cafe sale, a refund, a
## grant) goes to the debt before the balance sees it and nothing can spend
## it first. Each sim tick also pays any debt the balance already holds the
## money for, before the owed fees, so paying it frees the room a fee waits
## for in a full wallet.
##
## A passenger who makes the flight whose bag missed it (BaggageSim.bag_settled
## with loaded false) pays PriceTable.fee_after_missed_bag of the fee (Baggage B4,
## ruling baggage-rides-a-player-built-belt-from-check-in-to-a-bag-roo). A bag
## whose passenger missed the flight changes nothing: that passenger pays no
## fee. The bag and the passenger settle in either order. A missed bag seen
## first is kept (_bag_missed) until its passenger finishes; a made passenger
## whose bag is still on its way is kept with the fee it earned (_awaiting_bag)
## until the bag settles. Both are saved, so a load never pays a full fee for a
## bag that missed. A passenger with no bag in the BaggageSim (none checked in,
## or settled long ago) pays the full fee, as does any passenger when no
## BaggageSim is set.
##
## On the same tick, after the wages, every ready toilet room is charged its
## upkeep (decision toilet-design-queue-free-reservable-stalls-per-stall-daily-u,
## point 2): RoomRules.daily_upkeep, PriceTable.TOILET_STALL_UPKEEP per stall.
## Every screen stand on the grid, in a room or not, is charged with it
## (ScreenCoverage.daily_upkeep, PriceTable.SCREEN_UPKEEP a screen; decision
## boredom-and-shops-design-boredom-need-while-waiting-kiosk-sh, point 3), and
## so is every prize podium (PrizeCar.daily_upkeep, PriceTable.PRIZE_CAR_UPKEEP)
## and every info screen (PriceTable.INFO_SCREEN_UPKEEP; the info screen is its own
## piece, not a screen stand).
## The wallet pays the wages first and the upkeep from what is left; the rest of
## the upkeep is owed upkeep, kept apart from owed wages so the ledger books each
## under its own category. Repayment order, on every credit (credit_claim) and in
## each tick's sweep: owed wages, then owed upkeep, then owed fees. Owed upkeep is
## saved under its own optional key; a save without it owes none.
##
## The last day charged is saved with the owed wages, so a load neither charges
## a day twice nor skips one. A save taken mid-day D before the charge moved to
## the day's last tick holds D as charged (it was charged at D's start), so D's
## own end-of-day charge is skipped once after loading it.

## Wages were charged for `day`, on its last tick: `paid` is what the wallet paid
## at once and `owed` the shortfall carried as owed wages (the debt in total is
## wages_owed()). Not emitted on a day with nobody on the roster.
signal wages_charged(day: int, paid: int, owed: int)
## Wages were paid: the midnight charge, or owed wages paid off later out of a
## credit or the balance. `amount` is what this payment took, `owed` the debt
## left after it. One emission per payment and never for 0; a UI shows
## "Wages paid: <amount>".
signal wages_paid(amount: int, owed: int)
## The owed wages changed (a charge, a payment, a load); the money card follows it.
signal wages_owed_changed(owed: int)
## The owed upkeep changed (a charge, a payment, a load).
signal upkeep_owed_changed(owed: int)

const SNAPSHOT_KEYS := ["owed"]
## Added with toilet upkeep. A save from before it has none and owes no upkeep.
const UPKEEP_SNAPSHOT_KEY := "upkeep_owed"
## Added with staff wages. A save from before them has none and loads with no
## debt and no day charged yet.
## The three keys come as a group: all present or all absent.
const OPTIONAL_SNAPSHOT_KEYS := ["wages_owed", "wages_day", "wages_paid_today"]
## Names how `wages_day` is read. A save with it holds the day whose wages were
## charged (on that day's last tick), a save without it (before the charge moved
## to the last tick) holds the day charged at its start, one day later. Only
## with the wage keys; from_snapshot turns the old reading into the new.
const WAGE_TIMING_KEY := "wages_timing"
## The only value: wages_day is the day earned, charged on its last tick.
const WAGE_TIMING_LAST_TICK := "1"
## Added with missed bags (Baggage B4). A save from before them has neither and
## loads with no bag state; the two come as a pair, like the wage keys.
const BAG_SNAPSHOT_KEYS := ["bag_missed", "bags_awaited"]
## Sorted, so a saved entry's keys can be compared with it.
const AWAITED_KEYS := ["fee", "passenger"]
## Far past any passenger id a game hands out.
const MAX_PASSENGER_ID := 1_000_000_000_000
## No day charged yet. Ticks are never negative, so no day is.
const NO_DAY := -1
## Far past any game a player can play; a saved day beyond it is refused.
const MAX_DAY := 1_000_000_000
## The most owed wages the state holds. The debt is not a balance, so it is not
## bound by Wallet.MAX_BALANCE; this keeps the sums far from the 64-bit limit. At
## a few hundred a day it is never reached, and a charge that would pass it is
## refused loudly, never cut short.
const MAX_WAGES := 1_000_000_000_000_000
## The most wages paid in a day: the old debt, then a charge paid from the
## wallet, so no more than both limits together.
const MAX_WAGES_PAID_TODAY := MAX_WAGES + Wallet.MAX_BALANCE
## The most owed upkeep the state holds, for the same reason as MAX_WAGES.
const MAX_UPKEEP := MAX_WAGES
## The build catalog id of the info screen, charged PriceTable.INFO_SCREEN_UPKEEP a day.
const INFO_SCREEN_ID := &"info_screen"

## In a scene these come from the wired nodes; tests call bind(). Without
## `staff` no wage is charged.
@export var passengers: PassengerSim
@export var finances: Finances
@export var staff: StaffSim
## Without it every passenger who makes the flight pays the whole fee.
@export var baggage: BaggageSim

var _sim: PassengerSim
var _wallet: Wallet
## Passengers already paid (or owed) that the sim still holds (it retires
## settled passengers after a while, and ids are never reused).
var _settled: Dictionary = {}
## Fees earned that did not fit the wallet yet, oldest first.
var _owed: Array[int] = []
## Wages charged but not paid yet, carried until money is there.
var _wages_owed := 0
## Room upkeep charged but not paid yet, paid after owed wages.
var _upkeep_owed := 0
## The last game day wages and upkeep were charged for, or NO_DAY.
var _wages_day := NO_DAY
## Wages paid on the current game day: the charge made on its last tick and any
## owed wages paid during it.
var _wages_paid_today := 0
## The game day _wages_paid_today counts, or NO_DAY before the session's first
## payment or tick. Not saved: a load takes the loaded clock's day.
var _paid_day := NO_DAY
## Passenger ids (set of true) whose bag missed while the passenger was still
## on their way; dropped when the passenger finishes.
var _bag_missed: Dictionary = {}
## Passenger id -> the fee of a passenger who made the flight while their bag
## was still on its way, held until the bag settles.
var _awaiting_bag: Dictionary = {}


func _ready() -> void:
	if passengers == null or finances == null:
		push_error("Settlement: passengers and finances must both be set, so no fee is paid")
		return
	if staff == null:
		push_error("Settlement: staff is not set, so no wage is charged")
	if baggage == null:
		push_error("Settlement: baggage is not set, so no fee is cut for a missed bag")
	bind(passengers, finances.wallet)


## Follows `sim`'s outcomes and pays into `wallet`, retrying owed fees on
## the sim's clock. Binding the sim already followed only changes the wallet;
## binding another lets go of the first.
func bind(sim: PassengerSim, wallet: Wallet) -> void:
	if _wallet != null and _wallet != wallet and _wallet.credit_claim == _claim_credit:
		_wallet.credit_claim = Callable()
	_wallet = wallet
	_wallet.credit_claim = _claim_credit
	if baggage != null and not baggage.bag_settled.is_connected(_on_bag_settled):
		baggage.bag_settled.connect(_on_bag_settled)
	if sim == _sim:
		return
	if _sim != null:
		_sim.outcome.disconnect(_on_outcome)
		_sim.clock.ticked.disconnect(_on_tick)
	_sim = sim
	_settled.clear()
	_sim.outcome.connect(_on_outcome)
	_sim.clock.ticked.connect(_on_tick)


## The fees owed, oldest first.
func owed() -> Array[int]:
	return _owed.duplicate()


## Wages still owed.
func wages_owed() -> int:
	return _wages_owed


## Wages paid on the current game day, owed wages caught up included.
func wages_paid_today() -> int:
	return _wages_paid_today


## Room upkeep still owed.
func upkeep_owed() -> int:
	return _upkeep_owed


## Everything credit_claim takes out of a credit before the balance sees it:
## owed wages and owed upkeep. A credit of this much more than a sum leaves that
## sum in the wallet (RescueGrant grosses its grant up by it).
func claimed_debt() -> int:
	return _wages_owed + _upkeep_owed


## JSON-safe state for a save: the owed fees as decimal strings, like the
## wallet's balance, the wage state (owed wages, last charged day and paid
## today) and the owed upkeep as decimal strings, and the bag state: the
## passengers whose bag missed ("bag_missed") and the fees held for a bag still
## on its way ("bags_awaited", each {"passenger", "fee"}), also as decimal
## strings.
func to_snapshot() -> Dictionary:
	var out := []
	for fee in _owed:
		out.append(str(fee))
	var missed := []
	for id in _bag_missed:
		missed.append(str(id))
	var awaited := []
	for id in _awaiting_bag:
		awaited.append({"passenger": str(id), "fee": str(_awaiting_bag[id])})
	return {
		"owed": out,
		"wages_owed": str(_wages_owed),
		"wages_day": str(_wages_day),
		"wages_paid_today": str(_wages_paid_today),
		WAGE_TIMING_KEY: WAGE_TIMING_LAST_TICK,
		UPKEEP_SNAPSHOT_KEY: str(_upkeep_owed),
		"bag_missed": missed,
		"bags_awaited": awaited,
	}


## Restores a to_snapshot() dictionary. Pushes an error and returns false,
## changing nothing, for a missing or unknown key, an owed fee that is not a
## decimal string from 1 to Wallet.MAX_BALANCE, or a wage amount or day that is
## not a decimal string in range. The wage keys are optional as a group: a save
## without any loads with no owed wages and no day charged yet, and a partial
## set is refused. The owed upkeep is optional on its own: a save without it
## owes none, and one that is not a decimal string from 0 to MAX_UPKEEP is
## refused. The bag keys are optional as a pair in the same way, and
## refused for a passenger id or fee out of range, a passenger listed twice or in
## both lists. A successful load forgets which passengers were paid, since the
## loaded sim may replay them.
func from_snapshot(data: Dictionary) -> bool:
	var problem := _snapshot_problem(data)
	if problem != "":
		push_error("Settlement.from_snapshot: %s" % problem)
		return false
	var loaded: Array[int] = []
	for text in data["owed"]:
		loaded.append(str(text).to_int())
	_owed = loaded
	_set_wages_owed(str(data.get("wages_owed", "0")).to_int())
	_set_upkeep_owed(str(data.get(UPKEEP_SNAPSHOT_KEY, "0")).to_int())
	_wages_day = _earned_day(data)
	_wages_paid_today = str(data.get("wages_paid_today", "0")).to_int()
	_paid_day = GameCalendar.day_of(_sim.clock.tick) if _sim != null else NO_DAY
	_bag_missed.clear()
	for text in data.get("bag_missed", []):
		_bag_missed[str(text).to_int()] = true
	_awaiting_bag.clear()
	for entry in data.get("bags_awaited", []):
		_awaiting_bag[str(entry["passenger"]).to_int()] = str(entry["fee"]).to_int()
	# A load rewinds the session: the passengers it holds may finish again.
	_settled.clear()
	return true


## The saved last charged day as the day earned. A save without the timing key
## holds the day charged at its start, so days up to the one before it are paid.
func _earned_day(data: Dictionary) -> int:
	var saved := str(data.get("wages_day", str(NO_DAY))).to_int()
	if data.has(WAGE_TIMING_KEY) or saved == NO_DAY:
		return saved
	return saved - 1


func _snapshot_problem(data: Dictionary) -> String:
	for key in data.keys():
		if (
			not SNAPSHOT_KEYS.has(key)
			and key != WAGE_TIMING_KEY
			and key != UPKEEP_SNAPSHOT_KEY
			and not OPTIONAL_SNAPSHOT_KEYS.has(key)
			and not BAG_SNAPSHOT_KEYS.has(key)
		):
			return "unknown key '%s'" % key
	if not data.has("owed") or typeof(data["owed"]) != TYPE_ARRAY:
		return "'owed' must be a list"
	for text in data["owed"]:
		if not _in_range(text, 1, Wallet.MAX_BALANCE):
			return "owed fee %s is not 1 to %d" % [text, Wallet.MAX_BALANCE]
	var problem := _wage_problem(data)
	if problem == "":
		problem = _bag_problem(data)
	if (
		problem == ""
		and data.has(UPKEEP_SNAPSHOT_KEY)
		and not _in_range(data[UPKEEP_SNAPSHOT_KEY], 0, MAX_UPKEEP)
	):
		problem = "'%s' is not 0 to %d" % [UPKEEP_SNAPSHOT_KEY, MAX_UPKEEP]
	return problem


## Why the bag keys are refused, or "" (both absent is allowed).
func _bag_problem(data: Dictionary) -> String:
	if data.has("bag_missed") != data.has("bags_awaited"):
		return "the bag keys %s must be both present or both absent" % [BAG_SNAPSHOT_KEYS]
	if not data.has("bag_missed"):
		return ""
	if typeof(data["bag_missed"]) != TYPE_ARRAY or typeof(data["bags_awaited"]) != TYPE_ARRAY:
		return "'bag_missed' and 'bags_awaited' must be lists"
	var missed := {}
	for text in data["bag_missed"]:
		if not _in_range(text, 1, MAX_PASSENGER_ID) or missed.has(str(text)):
			return "bag_missed entry %s is not a new passenger id" % [text]
		missed[str(text)] = true
	var awaited := {}
	for entry in data["bags_awaited"]:
		var problem := _awaited_problem(entry, missed, awaited)
		if problem != "":
			return problem
		awaited[str(entry["passenger"])] = true
	return ""


## Why one "bags_awaited" entry is refused, or "".
func _awaited_problem(entry: Variant, missed: Dictionary, awaited: Dictionary) -> String:
	if typeof(entry) != TYPE_DICTIONARY:
		return "bags_awaited entries must be dictionaries"
	var keys: Array = (entry as Dictionary).keys()
	keys.sort()
	if keys != AWAITED_KEYS:
		return "bags_awaited entries hold exactly %s, not %s" % [AWAITED_KEYS, keys]
	if not _in_range(entry["passenger"], 1, MAX_PASSENGER_ID):
		return "bags_awaited passenger %s is not a passenger id" % [entry["passenger"]]
	if missed.has(str(entry["passenger"])) or awaited.has(str(entry["passenger"])):
		return "passenger %s is listed twice for a bag" % [entry["passenger"]]
	if not _in_range(entry["fee"], 1, Wallet.MAX_BALANCE):
		return "bags_awaited fee %s is not 1 to %d" % [entry["fee"], Wallet.MAX_BALANCE]
	return ""


## Why the wage keys are refused, or "" (all absent is allowed).
func _wage_problem(data: Dictionary) -> String:
	var wage_keys := 0
	for key in OPTIONAL_SNAPSHOT_KEYS:
		wage_keys += int(data.has(key))
	if wage_keys != 0 and wage_keys != OPTIONAL_SNAPSHOT_KEYS.size():
		return "the wage keys %s must be all present or all absent" % [OPTIONAL_SNAPSHOT_KEYS]
	for key in ["wages_owed", "wages_paid_today"]:
		var limit := MAX_WAGES if key == "wages_owed" else MAX_WAGES_PAID_TODAY
		if data.has(key) and not _in_range(data[key], 0, limit):
			return "'%s' is not 0 to %d" % [key, limit]
	if data.has("wages_day") and not _in_range(data["wages_day"], NO_DAY, MAX_DAY):
		return "'wages_day' is not a day"
	if data.has(WAGE_TIMING_KEY):
		if wage_keys == 0:
			return "'%s' needs the wage keys" % WAGE_TIMING_KEY
		if data[WAGE_TIMING_KEY] != WAGE_TIMING_LAST_TICK:
			return "'%s' must be \"%s\"" % [WAGE_TIMING_KEY, WAGE_TIMING_LAST_TICK]
	return ""


## "" or why the saved settlement disagrees with the other saved parts it
## depends on. Run on the save's parts by SaveLinks, since no part sees another.
## A save from before wages holds no wage state and always agrees. It also
## checks the owed upkeep against the wallet (upkeep_debt_problem).
static func wages_link_problem(
	settlement: Dictionary, clock: Dictionary, wallet: Dictionary
) -> String:
	var found := wages_day_problem(settlement, clock)
	if found == "":
		found = wages_debt_problem(settlement, wallet)
	if found == "":
		found = upkeep_debt_problem(settlement, wallet)
	return found


## "" or why a saved last charged day and the saved clock disagree. Saves are
## taken between ticks and a day is charged on its last tick, so the last
## charged day is the day before the clock's, or the clock's own only when the
## saved tick is that day's last. A day after the clock's would skip days; one
## more than a day before it would never charge the days between. Only NO_DAY
## (no day charged yet) is exempt. A save without WAGE_TIMING_KEY holds the day
## charged at its start, which is the clock's own day (from_snapshot migrates it to
## the day before). Such a save taken on that day's last tick is refused: the migrated
## day D - 1 leaves D to its own last tick, which the save has already passed, so D's
## wages would never be charged. Charging on load is not possible here (no part sees the
## wallet or the clock being loaded), so the state is refused loudly instead.
static func wages_day_problem(settlement: Dictionary, clock: Dictionary) -> String:
	if not settlement.has("wages_day") or not clock.has("tick"):
		return ""
	if not SimClock.is_int64_string(settlement["wages_day"]):
		return ""
	if not SimClock.is_int64_string(clock["tick"]):
		return ""
	var saved_day := str(settlement["wages_day"]).to_int()
	var clock_tick := str(clock["tick"]).to_int()
	var clock_day := GameCalendar.day_of(clock_tick)
	var allowed := [clock_day]
	if settlement.has(WAGE_TIMING_KEY):
		allowed = [clock_day - 1]
		if GameCalendar.is_last_tick_of_day(clock_tick):
			allowed.append(clock_day)
	if saved_day != NO_DAY and not allowed.has(saved_day):
		return (
			"settlement: wages were last charged for day %d, but the clock is on day %d"
			% [saved_day, clock_day]
		)
	if (
		not settlement.has(WAGE_TIMING_KEY)
		and saved_day == clock_day
		and GameCalendar.is_last_tick_of_day(clock_tick)
	):
		return (
			"settlement: an old-format save taken on day %d's last tick would never charge that day"
			% clock_day
		)
	return ""


## "" or why saved owed wages and a saved balance disagree: every credit pays
## the debt first, so wages are never owed while the wallet holds money.
static func wages_debt_problem(settlement: Dictionary, wallet: Dictionary) -> String:
	if not settlement.has("wages_owed") or not wallet.has("balance"):
		return ""
	if not SimClock.is_int64_string(settlement["wages_owed"]):
		return ""
	if not SimClock.is_int64_string(wallet["balance"]):
		return ""
	if str(settlement["wages_owed"]).to_int() > 0 and str(wallet["balance"]).to_int() > 0:
		return "settlement: wages are owed while the wallet holds money"
	return ""


## "" or why saved owed upkeep and a saved balance disagree: like owed wages,
## owed upkeep takes every credit before the balance, so the two never both
## stand.
static func upkeep_debt_problem(settlement: Dictionary, wallet: Dictionary) -> String:
	if not settlement.has(UPKEEP_SNAPSHOT_KEY) or not wallet.has("balance"):
		return ""
	if not SimClock.is_int64_string(settlement[UPKEEP_SNAPSHOT_KEY]):
		return ""
	if not SimClock.is_int64_string(wallet["balance"]):
		return ""
	if str(settlement[UPKEEP_SNAPSHOT_KEY]).to_int() > 0 and str(wallet["balance"]).to_int() > 0:
		return "settlement: upkeep is owed while the wallet holds money"
	return ""


## Whether `text` is a decimal string of a whole number from `low` to `high`.
func _in_range(text: Variant, low: int, high: int) -> bool:
	if not SimClock.is_int64_string(text):
		return false
	var value := str(text).to_int()
	return value >= low and value <= high


func _on_outcome(id: int, made: bool) -> void:
	var bag_missed := _bag_missed.has(id)
	_bag_missed.erase(id)
	if not made:
		return
	var p := _sim.get_passenger(id)
	if p == null or p.stage != Passenger.Stage.MADE:
		push_error("Settlement: passenger %d made the flight but is not a made passenger" % id)
		return
	_forget_retired()
	if _settled.has(id):
		return
	var contract_id := _sim.flights.flight_contract_id(p.flight_id)
	if contract_id == "":
		return
	var contract := _sim.flights.contract_of(contract_id)
	if contract.is_empty():
		push_error("Settlement: flight '%s' has no contract to pay from" % p.flight_id)
		return
	_settled[id] = true
	var fee: int = contract["fee_per_passenger"]
	if fee > 0 and bag_missed:
		fee = PriceTable.fee_after_missed_bag(fee)
	elif fee > 0 and _bag_on_its_way(id):
		_awaiting_bag[id] = fee
		return
	if fee > 0:
		_owed.append(fee)
	_pay_owed()


## True while passenger `id` has a bag in the BaggageSim that is not settled.
func _bag_on_its_way(id: int) -> bool:
	if baggage == null:
		return false
	var bag := baggage.bag_of_passenger(id)
	return bag != null and not bag.is_settled()


## A bag settled. A made passenger waiting for it is paid now, the fee cut if the
## bag missed. Otherwise a missed bag is kept until its passenger finishes, if
## the passenger is still on their way.
func _on_bag_settled(_bag_id: int, passenger_id: int, _flight_id: String, loaded: bool) -> void:
	if _awaiting_bag.has(passenger_id):
		var fee: int = _awaiting_bag[passenger_id]
		_awaiting_bag.erase(passenger_id)
		if not loaded:
			fee = PriceTable.fee_after_missed_bag(fee)
		if fee > 0:
			_owed.append(fee)
		_pay_owed()
		return
	if loaded or _sim == null:
		return
	var p := _sim.get_passenger(passenger_id)
	if p != null and not p.is_done():
		_bag_missed[passenger_id] = true


func _on_tick(tick: int) -> void:
	_roll_paid_day(tick)
	if GameCalendar.is_last_tick_of_day(tick):
		_charge_day(GameCalendar.day_of(tick))
	_pay_owed()


## Starts the day's wages paid over at 0 when the clock's day is not the one
## they count. Called before every payment, so the count is right whichever
## listener hears the first tick of a day first.
func _roll_paid_day(tick: int) -> void:
	var day := GameCalendar.day_of(tick)
	if _paid_day != NO_DAY and day != _paid_day:
		_wages_paid_today = 0
	_paid_day = day


## Counts a wage payment toward today, in the day of the clock's tick.
func _note_wages_paid(paid: int) -> void:
	if _sim != null:
		_roll_paid_day(_sim.clock.tick)
	_wages_paid_today += paid


## Charges the roster's wages and then the ready rooms' upkeep for `day`, on its
## last tick; a day at or before the last charged one is never charged again.
## The wages are paid from the balance first, the upkeep from what is left.
func _charge_day(day: int) -> void:
	if day <= _wages_day:
		return
	var due := _wages_due()
	var paid := mini(due, _wallet.balance)
	var upkeep := _upkeep_due()
	var upkeep_paid := mini(upkeep, _wallet.balance - paid)
	if _wages_owed + due - paid > MAX_WAGES:
		push_error(
			"Settlement: owed wages would pass %d, so day %d is not charged" % [MAX_WAGES, day]
		)
		return
	if _upkeep_owed + upkeep - upkeep_paid > MAX_UPKEEP:
		push_error(
			"Settlement: owed upkeep would pass %d, so day %d is not charged" % [MAX_UPKEEP, day]
		)
		return
	_wages_day = day
	if due > 0:
		_charge_wages(day, due, paid)
	if upkeep > 0:
		_charge_upkeep(upkeep, upkeep_paid)


## Takes the day's wages of `due`, `paid` of it from the wallet, the rest owed.
func _charge_wages(day: int, due: int, paid: int) -> void:
	if not _wallet.spend(paid, Wallet.Category.WAGES):
		push_error("Settlement: wallet refused a wage of %d it holds" % paid)
		return
	_note_wages_paid(paid)
	_set_wages_owed(_wages_owed + due - paid)
	wages_charged.emit(day, paid, due - paid)
	_announce_wages_paid(paid)


## Takes the day's upkeep of `due`, `paid` of it from the wallet, the rest owed.
func _charge_upkeep(due: int, paid: int) -> void:
	if not _wallet.spend(paid, Wallet.Category.UPKEEP):
		push_error("Settlement: wallet refused an upkeep of %d it holds" % paid)
		return
	_set_upkeep_owed(_upkeep_owed + due - paid)


## The day's upkeep of every ready room on the sim's grid (RoomRules.daily_upkeep)
## and of every screen stand, prize podium and info screen on it; none without a
## grid.
func _upkeep_due() -> int:
	if _sim == null or _sim.grid == null:
		return 0
	var due := ScreenCoverage.daily_upkeep(_sim.grid) + PrizeCar.daily_upkeep(_sim.grid)
	due += _info_screen_upkeep(_sim.grid)
	for room_id in _sim.grid.room_ids():
		due += RoomRules.daily_upkeep(_sim.grid, room_id)
	return due


## What `grid`'s info screens cost to run for one game day.
func _info_screen_upkeep(grid: BuildGrid) -> int:
	var count := 0
	for id in grid.object_ids():
		if grid.get_object(id)["def"] == INFO_SCREEN_ID:
			count += 1
	return count * PriceTable.INFO_SCREEN_UPKEEP


## The wages of everyone on the roster for one day; none without a staff pool.
func _wages_due() -> int:
	if staff == null:
		return 0
	var due := 0
	for role in StaffMember.Role.values():
		var wage := PriceTable.wage_of(role)
		if wage > 0:
			due += staff.count(role) * wage
	return due


## Pays owed wages, then owed upkeep, then owed fees. The debts go first: paying
## them frees room in a full wallet for a fee to fit.
func _pay_owed() -> void:
	_pay_wages()
	_pay_upkeep()
	_pay_fees()


## Pays the owed wages the balance already holds the money for. Credits never
## leave debt and balance both standing (see _claim_credit), so this only acts
## on a state loaded or set up that way.
func _pay_wages() -> void:
	var paid := mini(_wages_owed, _wallet.balance)
	if paid <= 0 or not _wallet.spend(paid, Wallet.Category.WAGES):
		return
	_note_wages_paid(paid)
	_set_wages_owed(_wages_owed - paid)
	_announce_wages_paid(paid)


## Pays the owed upkeep the balance holds the money for, after _pay_wages.
func _pay_upkeep() -> void:
	var paid := mini(_upkeep_owed, _wallet.balance)
	if paid <= 0 or not _wallet.spend(paid, Wallet.Category.UPKEEP):
		return
	_set_upkeep_owed(_upkeep_owed - paid)


## Wallet.credit_claim: what is owed out of an incoming credit, owed wages
## first and owed upkeep from what is left, as {Category: share} with only the
## shares above 0. With `commit` false it only says what it would take; with
## true it takes it and pays those debts, so the balance gets only the rest.
func _claim_credit(amount: int, commit: bool) -> Dictionary:
	var wages := mini(_wages_owed, amount)
	var upkeep := mini(_upkeep_owed, amount - wages)
	if commit and wages > 0:
		_note_wages_paid(wages)
		_set_wages_owed(_wages_owed - wages)
		_announce_wages_paid(wages)
	if commit and upkeep > 0:
		_set_upkeep_owed(_upkeep_owed - upkeep)
	var claims := {}
	if wages > 0:
		claims[Wallet.Category.WAGES] = wages
	if upkeep > 0:
		claims[Wallet.Category.UPKEEP] = upkeep
	return claims


func _announce_wages_paid(paid: int) -> void:
	if paid > 0:
		wages_paid.emit(paid, _wages_owed)


func _set_wages_owed(value: int) -> void:
	if value == _wages_owed:
		return
	_wages_owed = value
	wages_owed_changed.emit(_wages_owed)


func _set_upkeep_owed(value: int) -> void:
	if value == _upkeep_owed:
		return
	_upkeep_owed = value
	upkeep_owed_changed.emit(_upkeep_owed)


## Pays owed fees, oldest first, while the next one fits the wallet.
func _pay_fees() -> void:
	while not _owed.is_empty() and _owed[0] <= Wallet.MAX_BALANCE - _wallet.balance:
		if not _wallet.credit(_owed[0], Wallet.Category.FEES):
			return
		_owed.pop_front()


func _forget_retired() -> void:
	for id in _settled.keys():
		if _sim.get_passenger(id) == null:
			_settled.erase(id)
