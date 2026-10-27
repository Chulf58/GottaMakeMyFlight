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

const SNAPSHOT_KEYS := ["owed"]

## In a scene these come from the wired nodes; tests call bind().
@export var passengers: PassengerSim
@export var finances: Finances

var _sim: PassengerSim
var _wallet: Wallet
## Passengers already paid (or owed) that the sim still holds (it retires
## settled passengers after a while, and ids are never reused).
var _settled: Dictionary = {}
## Fees earned that did not fit the wallet yet, oldest first.
var _owed: Array[int] = []


func _ready() -> void:
	if passengers == null or finances == null:
		push_error("Settlement: passengers and finances must both be set, so no fee is paid")
		return
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


## JSON-safe state for a save: the owed fees as decimal strings, like the
## wallet's balance.
func to_snapshot() -> Dictionary:
	var out := []
	for fee in _owed:
		out.append(str(fee))
	return {"owed": out}


## Restores a to_snapshot() dictionary. Pushes an error and returns false,
## changing nothing, for a missing or unknown key or an owed fee that is not a
## decimal string from 1 to Wallet.MAX_BALANCE.
func from_snapshot(data: Dictionary) -> bool:
	for key in data.keys():
		if not SNAPSHOT_KEYS.has(key):
			push_error("Settlement.from_snapshot: unknown key '%s'" % key)
			return false
	if not data.has("owed") or typeof(data["owed"]) != TYPE_ARRAY:
		push_error("Settlement.from_snapshot: 'owed' must be a list")
		return false
	var loaded: Array[int] = []
	for text in data["owed"]:
		var fee := str(text).to_int()
		var bad := not SimClock.is_int64_string(text) or fee < 1 or fee > Wallet.MAX_BALANCE
		if bad:
			push_error(
				"Settlement.from_snapshot: owed fee %s is not 1 to %d" % [text, Wallet.MAX_BALANCE]
			)
			return false
		loaded.append(fee)
	_owed = loaded
	return true


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


func _on_tick(_tick: int) -> void:
	_pay_owed()


## Pays owed fees, oldest first, while the next one fits the wallet.
func _pay_owed() -> void:
	while not _owed.is_empty() and _owed[0] <= Wallet.MAX_BALANCE - _wallet.balance:
		if not _wallet.credit(_owed[0]):
			return
		_owed.pop_front()


func _forget_retired() -> void:
	for id in _settled.keys():
		if _sim.get_passenger(id) == null:
			_settled.erase(id)
