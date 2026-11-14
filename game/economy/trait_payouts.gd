class_name TraitPayouts
extends RefCounted
## The money two offer traits move once a contract flies (decision airline-
## offer-traits-each-offer-pairs-an-upside-with-a-downs). Settlement owns one and
## calls it from the signals it follows; the state is part of its save.
##
## Miss fine: each passenger of the contract's flight who missed it costs
## OfferTraits.miss_fine, charged when the miss is known (a terminal outcome or a
## road miss, the same misses the airport rating counts). Wallet.charge takes it
## down to a balance of 0 and announces the rest as unpaid; nothing is owed. A
## no-show who never came is not a miss and is never fined.
##
## Signing bonus: the contract's first flight to depart, made or not, pays
## OfferTraits.signing_bonus as Wallet.Category.SIGNING_BONUS, never on accept.
## The contracts already paid are saved, so a load never pays one twice.

## A contract id, as FlightContract.problem accepts one: letters and digits.
static var _id_pattern := RegEx.create_from_string("^[A-Za-z0-9]+$")

## Contract id -> true for each contract whose signing bonus was paid.
var _bonus_paid: Dictionary = {}


## Fines `wallet` for one passenger of flight `flight_id` in `flights` who missed
## it; returns what the wallet paid. A one-off flight or a contract without Miss
## fine charges nothing.
func fine_miss(flights: FlightSim, flight_id: String, wallet: Wallet) -> int:
	var contract := _contract_of(flights, flight_id)
	if contract.is_empty():
		return 0
	var fine := OfferTraits.miss_fine(contract[FlightContract.TRAITS_KEY])
	return wallet.charge(fine, Wallet.Category.FINES) if fine > 0 else 0


## Pays the signing bonus into `wallet` when departed flight `flight_id` is the
## first of its contract to depart and the contract has Signing bonus. True when
## it paid. A bonus the wallet cannot take (it would pass Wallet.MAX_BALANCE) is
## forfeited (conductor ruling): the contract is still marked paid, so it is
## never paid later.
func on_departed(flights: FlightSim, flight_id: String, wallet: Wallet) -> bool:
	var contract := _contract_of(flights, flight_id)
	if contract.is_empty() or _bonus_paid.has(contract["id"]):
		return false
	var bonus := OfferTraits.signing_bonus(contract[FlightContract.TRAITS_KEY])
	if bonus <= 0:
		return false
	_bonus_paid[contract["id"]] = true
	if not wallet.can_credit(bonus, Wallet.Category.SIGNING_BONUS):
		return false
	if not wallet.credit(bonus, Wallet.Category.SIGNING_BONUS):
		push_error("TraitPayouts: the wallet refused the signing bonus of %s" % contract["id"])
		return false
	return true


## The contracts whose bonus was paid, in the order paid, for a save.
func bonuses_paid() -> Array:
	return _bonus_paid.keys()


## "" when `saved` is a list of distinct contract ids; otherwise what is wrong.
static func bonuses_problem(saved: Variant) -> String:
	if saved == null:
		return "missing key 'bonuses_paid'"
	if typeof(saved) != TYPE_ARRAY:
		return "bonuses_paid must be a list"
	var seen := {}
	for id: Variant in saved:
		if typeof(id) != TYPE_STRING or _id_pattern.search(id) == null:
			return "bonuses_paid entry %s is not a contract id" % [id]
		if seen.has(id):
			return "bonuses_paid lists %s twice" % [id]
		seen[id] = true
	return ""


## Restores bonuses_paid() from a list bonuses_problem accepts.
func load_bonuses(saved: Array) -> void:
	_bonus_paid.clear()
	for id: String in saved:
		_bonus_paid[id] = true


## The contract of occurrence `flight_id`, or {} for a one-off or unknown flight.
static func _contract_of(flights: FlightSim, flight_id: String) -> Dictionary:
	var contract_id := flights.flight_contract_id(flight_id)
	if contract_id == "":
		return {}
	var contract := flights.contract_of(contract_id)
	if contract.is_empty():
		push_error("TraitPayouts: flight '%s' has no contract" % flight_id)
	return contract
