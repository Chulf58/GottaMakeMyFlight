class_name Settlement
extends Node
## Pays the airline fee (decision flights-and-economy-design-tick-derived-
## calendar-timetable-o, point 5). When PassengerSim.outcome says a passenger
## made their flight, the passenger's occurrence is resolved to its contract
## and the fee_per_passenger captured there is credited to the wallet, once.
## A missed passenger pays nothing, and neither does a one-off flight, which
## has no contract.
##
## Settlement keeps no state a save would hold. PassengerSim emits outcome
## only when a passenger finishes (never when a snapshot is loaded), so a load
## cannot replay a fee; the settled ids below only refuse a repeated signal
## for a passenger the sim still holds.

## In a scene these come from the wired nodes; tests call bind().
@export var passengers: PassengerSim
@export var finances: Finances

var _sim: PassengerSim
var _wallet: Wallet
## Passengers already paid that the sim still holds (it retires settled
## passengers after a while, and ids are never reused).
var _settled: Dictionary = {}


func _ready() -> void:
	if passengers == null or finances == null:
		push_error("Settlement: passengers and finances must both be set, so no fee is paid")
		return
	bind(passengers, finances.wallet)


## Follows `sim`'s outcomes and pays into `wallet`. Binding the sim already
## followed only changes the wallet; binding another lets go of the first.
func bind(sim: PassengerSim, wallet: Wallet) -> void:
	_wallet = wallet
	if sim == _sim:
		return
	if _sim != null:
		_sim.outcome.disconnect(_on_outcome)
	_sim = sim
	_settled.clear()
	_sim.outcome.connect(_on_outcome)


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
	if _wallet.credit(contract["fee_per_passenger"]):
		_settled[id] = true


func _forget_retired() -> void:
	for id in _settled.keys():
		if _sim.get_passenger(id) == null:
			_settled.erase(id)
