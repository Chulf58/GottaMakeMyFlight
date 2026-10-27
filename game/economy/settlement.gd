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
## unpaid-wages-carried-as-owed). On the first tick of each game day every
## member on the staff roster, one still finishing a service before leaving
## included, is charged the wage of their role (PriceTable.WAGES). The wallet
## pays what it holds; the rest is owed wages. Owed wages are paid first
## whenever money is there, on every sim tick and whenever a fee is settled,
## and before the owed fees, so paying them frees the room a fee waits for.
## Money that other code puts into the wallet is swept on the next tick, not
## the instant it arrives.
##
## The last day charged is saved with the owed wages, so a load neither charges
## a day twice nor skips one. The first tick seen after a new game, or after a
## load of a save from before wages, only records the day: nothing is charged
## for the day the session starts in.

## Wages were charged for `day`: `paid` is what the wallet paid at once and
## `owed` the shortfall carried as owed wages (the debt in total is
## wages_owed()). Not emitted on a day with nobody on the roster.
signal wages_charged(day: int, paid: int, owed: int)

const SNAPSHOT_KEYS := ["owed"]
## Added with staff wages. A save from before them has none and loads with no
## debt and no day charged yet.
const OPTIONAL_SNAPSHOT_KEYS := ["wages_owed", "wages_day", "wages_paid_today"]
## No day charged yet. Ticks are never negative, so no day is.
const NO_DAY := -1
## Far past any game a player can play; a saved day beyond it is refused.
const MAX_DAY := 1_000_000_000

## In a scene these come from the wired nodes; tests call bind(). Without
## `staff` no wage is charged.
@export var passengers: PassengerSim
@export var finances: Finances
@export var staff: StaffSim

var _sim: PassengerSim
var _wallet: Wallet
## Passengers already paid (or owed) that the sim still holds (it retires
## settled passengers after a while, and ids are never reused).
var _settled: Dictionary = {}
## Fees earned that did not fit the wallet yet, oldest first.
var _owed: Array[int] = []
## Wages charged but not paid yet, carried until money is there.
var _wages_owed := 0
## The last game day wages were charged for, or NO_DAY.
var _wages_day := NO_DAY
## Wages paid since the last midnight charge, catching up on owed wages included.
var _wages_paid_today := 0


func _ready() -> void:
	if passengers == null or finances == null:
		push_error("Settlement: passengers and finances must both be set, so no fee is paid")
		return
	if staff == null:
		push_error("Settlement: staff is not set, so no wage is charged")
	bind(passengers, finances.wallet)


## Follows `sim`'s outcomes and pays into `wallet`, retrying owed fees on
## the sim's clock. Binding the sim already followed only changes the wallet;
## binding another lets go of the first.
func bind(sim: PassengerSim, wallet: Wallet) -> void:
	_wallet = wallet
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


## Wages paid since the last midnight charge, owed wages caught up included.
func wages_paid_today() -> int:
	return _wages_paid_today


## JSON-safe state for a save: the owed fees as decimal strings, like the
## wallet's balance, and the wage state (owed wages, last charged day and paid
## today) as decimal strings.
func to_snapshot() -> Dictionary:
	var out := []
	for fee in _owed:
		out.append(str(fee))
	return {
		"owed": out,
		"wages_owed": str(_wages_owed),
		"wages_day": str(_wages_day),
		"wages_paid_today": str(_wages_paid_today),
	}


## Restores a to_snapshot() dictionary. Pushes an error and returns false,
## changing nothing, for a missing or unknown key, an owed fee that is not a
## decimal string from 1 to Wallet.MAX_BALANCE, or a wage amount or day that is
## not a decimal string in range. The wage keys are optional: a save without
## them loads with no owed wages and no day charged yet. A successful load
## forgets which passengers were paid, since the loaded sim may replay them.
func from_snapshot(data: Dictionary) -> bool:
	var problem := _snapshot_problem(data)
	if problem != "":
		push_error("Settlement.from_snapshot: %s" % problem)
		return false
	var loaded: Array[int] = []
	for text in data["owed"]:
		loaded.append(str(text).to_int())
	_owed = loaded
	_wages_owed = str(data.get("wages_owed", "0")).to_int()
	_wages_day = str(data.get("wages_day", str(NO_DAY))).to_int()
	_wages_paid_today = str(data.get("wages_paid_today", "0")).to_int()
	# A load rewinds the session: the passengers it holds may finish again.
	_settled.clear()
	return true


func _snapshot_problem(data: Dictionary) -> String:
	for key in data.keys():
		if not SNAPSHOT_KEYS.has(key) and not OPTIONAL_SNAPSHOT_KEYS.has(key):
			return "unknown key '%s'" % key
	if not data.has("owed") or typeof(data["owed"]) != TYPE_ARRAY:
		return "'owed' must be a list"
	for text in data["owed"]:
		if not _in_range(text, 1, Wallet.MAX_BALANCE):
			return "owed fee %s is not 1 to %d" % [text, Wallet.MAX_BALANCE]
	for key in ["wages_owed", "wages_paid_today"]:
		if data.has(key) and not _in_range(data[key], 0, Wallet.MAX_BALANCE):
			return "'%s' is not 0 to %d" % [key, Wallet.MAX_BALANCE]
	if data.has("wages_day") and not _in_range(data["wages_day"], NO_DAY, MAX_DAY):
		return "'wages_day' is not a day"
	return ""


## Whether `text` is a decimal string of a whole number from `low` to `high`.
func _in_range(text: Variant, low: int, high: int) -> bool:
	if not SimClock.is_int64_string(text):
		return false
	var value := str(text).to_int()
	return value >= low and value <= high


func _on_outcome(id: int, made: bool) -> void:
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
	if fee > 0:
		_owed.append(fee)
	_pay_owed()


func _on_tick(tick: int) -> void:
	_charge_wages(GameCalendar.day_of(tick))
	_pay_owed()


## Charges the roster once for each new game day: the first tick seen only
## records the day, and a day at or before the last charged one is never
## charged again.
func _charge_wages(day: int) -> void:
	if _wages_day == NO_DAY:
		_wages_day = day
		return
	if day <= _wages_day:
		return
	_wages_day = day
	_wages_paid_today = 0
	if staff == null:
		return
	var due := 0
	for role in StaffMember.Role.values():
		var wage := PriceTable.wage_of(role)
		if wage > 0:
			due += staff.count(role) * wage
	if due == 0:
		return
	var paid := mini(due, _wallet.balance)
	if not _wallet.spend(paid):
		push_error("Settlement: wallet refused a wage of %d it holds" % paid)
		return
	_wages_paid_today = paid
	_wages_owed = mini(_wages_owed + due - paid, Wallet.MAX_BALANCE)
	wages_charged.emit(day, paid, due - paid)


## Pays owed wages, then owed fees, then wages again from the fees just paid.
## Wages go first: paying them frees room in a full wallet for a fee to fit.
func _pay_owed() -> void:
	_pay_wages()
	_pay_fees()
	_pay_wages()


## Pays the owed wages the wallet holds the money for.
func _pay_wages() -> void:
	var paid := mini(_wages_owed, _wallet.balance)
	if paid <= 0 or not _wallet.spend(paid):
		return
	_wages_owed -= paid
	_wages_paid_today += paid


## Pays owed fees, oldest first, while the next one fits the wallet.
func _pay_fees() -> void:
	while not _owed.is_empty() and _owed[0] <= Wallet.MAX_BALANCE - _wallet.balance:
		if not _wallet.credit(_owed[0]):
			return
		_owed.pop_front()


func _forget_retired() -> void:
	for id in _settled.keys():
		if _sim.get_passenger(id) == null:
			_settled.erase(id)
