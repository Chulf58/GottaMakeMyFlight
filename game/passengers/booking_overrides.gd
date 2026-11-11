class_name BookingOverrides
extends RefCounted
## Extra passengers saved against one flight occurrence, set before the
## occurrence is scheduled (decision daily-incidents-technical-design-
## incidentdirector-shared-clo): PassengerSim.schedule_flight() adds them to
## the booking once and forgets them. They are capped by the plane class
## booking maximum (PlaneClasses.passenger_range()), so an incident can crowd a
## flight but never past what its plane carries. Static helpers over a sim; the
## state is the sim's `_booking_overrides` (occurrence id -> extra).
##
## An occurrence is scheduled when it is issued, so an override is for an
## occurrence not issued yet: its id is "<contract>-d<day>"
## (FlightTimetable.occurrence_id()) and its contract is already accepted.

const SCHEDULED := "the flight's passengers are already scheduled"
const DEPARTED := "the flight's doors have closed"
const PAST := "the flight's day has passed or will not be flown"
const ISSUED := "the flight is already issued"
const ENDED := "the flight's contract has ended"
const NO_CONTRACT := "the flight is not a contract occurrence"
const TOO_FEW := "extra passengers must be 1 or more"
const OVER_MAX := "the booking would pass the plane class maximum"
const KEYS := ["flight", "extra"]


## The contract an occurrence id belongs to, or {} for a one-off flight or an
## unknown contract.
static func contract_of(sim: PassengerSim, flight_id: String) -> Dictionary:
	var parts := FlightTimetable.parse_occurrence(flight_id)
	return {} if parts.is_empty() else sim.flights.contract_of(parts["contract"])


## How many extra passengers the occurrence can still take: the plane class
## maximum less the contract's booked passengers; 0 with no contract.
static func headroom(sim: PassengerSim, flight_id: String) -> int:
	return _headroom_of(contract_of(sim, flight_id))


## Sets the occurrence's extra passengers to `extra` (replacing an earlier
## override). {"ok": whether it was set, "reason": why not or "", "headroom":
## the most extra passengers it can take}, so a caller refused for going over
## can offer exactly the headroom.
static func set_extra(sim: PassengerSim, flight_id: String, extra: int) -> Dictionary:
	var contract := contract_of(sim, flight_id)
	var room := _headroom_of(contract)
	var reason := ""
	if contract.is_empty():
		reason = NO_CONTRACT
	elif sim._scheduled.has(flight_id):
		reason = SCHEDULED
	elif sim.flights.is_doors_closed(flight_id):
		reason = DEPARTED
	else:
		reason = _open_problem(sim.flights, contract, flight_id, GameCalendar.day_of(sim.tick))
	if reason == "" and extra < 1:
		reason = TOO_FEW
	elif reason == "" and extra > room:
		reason = OVER_MAX
	if reason == "":
		sim._booking_overrides[flight_id] = extra
	return {"ok": reason == "", "reason": reason, "headroom": room}


## The extra passengers set for the occurrence; 0 when none.
static func extra_of(sim: PassengerSim, flight_id: String) -> int:
	return int(sim._booking_overrides.get(flight_id, 0))


## The occurrence's extra passengers, removed: called as it is scheduled.
static func take(sim: PassengerSim, flight_id: String) -> int:
	var extra := extra_of(sim, flight_id)
	sim._booking_overrides.erase(flight_id)
	return extra


## Drops the overrides of an ended contract: its days from the end day on are
## never issued, so they would stay saved for ever.
static func clear_contract(sim: PassengerSim, contract_id: String) -> void:
	for flight_id: String in sim._booking_overrides.keys():
		if FlightTimetable.parse_occurrence(flight_id).get("contract", "") == contract_id:
			sim._booking_overrides.erase(flight_id)


## Drops the overrides of occurrences whose doors have closed without them
## being scheduled.
static func clear_closed(sim: PassengerSim) -> void:
	for flight_id: String in sim._booking_overrides.keys():
		if sim.flights.is_doors_closed(flight_id):
			sim._booking_overrides.erase(flight_id)


## The saved list, in occurrence id order.
static func to_list(sim: PassengerSim) -> Array:
	var ids: Array = sim._booking_overrides.keys()
	ids.sort()
	var list := []
	for flight_id: String in ids:
		list.append({"flight": flight_id, "extra": sim._booking_overrides[flight_id]})
	return list


## The saved "booking_overrides" in `data` checked: {"overrides": {id:
## extra}} or {"error": why}. Each names a canonical occurrence id once, that
## is not among the saved scheduled flights, with 1 or more extra passengers
## and no more than the largest plane class maximum. With `flights` (the saved
## flights, staged or restored) each must also be one set() could have made:
## its contract on record and running, its day not past and not issued, and
## within the contract's class maximum. A save of the current version must
## carry the list; an older migrated one has none. Changes no sim state:
## from_snapshot() installs the result.
static func checked(data: Dictionary, flights: FlightSim) -> Dictionary:
	var overrides := {}
	if not data.has("booking_overrides"):
		if int(data["save_version"]) >= PassengerSim.SAVE_VERSION:
			return {"error": "missing key 'booking_overrides'"}
		return {"overrides": overrides}
	var list: Variant = data["booking_overrides"]
	if typeof(list) != TYPE_ARRAY:
		return {"error": "booking_overrides must be a list"}
	var scheduled: Array = data.get("scheduled", [])
	var today := GameCalendar.day_of(str(data.get("tick", "0")).to_int())
	for entry: Variant in list:
		var problem := _entry_problem(entry, overrides, scheduled, flights, today)
		if problem != "":
			return {"error": problem}
		overrides[entry["flight"]] = int(entry["extra"])
	return {"overrides": overrides}


static func _entry_problem(
	entry: Variant, seen: Dictionary, scheduled: Array, flights: FlightSim, today: int
) -> String:
	if typeof(entry) != TYPE_DICTIONARY or (entry as Dictionary).keys().size() != KEYS.size():
		return "booking override %s is malformed" % str(entry).left(80)
	for key: String in KEYS:
		if not (entry as Dictionary).has(key):
			return "booking override %s is malformed" % str(entry).left(80)
	var id: Variant = entry["flight"]
	if typeof(id) != TYPE_STRING or FlightTimetable.parse_occurrence(id).is_empty():
		return "booking override flight %s is not an occurrence" % str(id).left(40)
	if seen.has(id) or scheduled.has(id):
		return "booking override for %s is repeated or already scheduled" % id
	if not WholeNumber.is_whole(entry["extra"]) or int(entry["extra"]) < 1:
		return "booking override extra for %s must be a whole number, 1 or more" % id
	var extra := int(entry["extra"])
	var room := _largest_headroom()
	if flights != null:
		var contract := flights.contract_of(FlightTimetable.parse_occurrence(id)["contract"])
		if contract.is_empty():
			return "booking override for %s names no contract on record" % id
		var why := _open_problem(flights, contract, id, today)
		if why != "":
			return "booking override for %s: %s" % [id, why]
		room = _headroom_of(contract)
	if extra > room:
		return "booking override extra for %s passes the plane class maximum" % id
	return ""


## Why an override cannot be set for occurrence `flight_id` of `contract` with
## `flights` as they are and `today` the calendar day: its contract ended, it
## is already issued, or its day has passed or comes before the contract's
## first day (so it is never issued). "" when it can.
static func _open_problem(
	flights: FlightSim, contract: Dictionary, flight_id: String, today: int
) -> String:
	var day: int = FlightTimetable.parse_occurrence(flight_id)["day"]
	if flights.contract_end_day(contract["id"]) >= 0:
		return ENDED
	if flights.state_of(flight_id) >= 0:
		return ISSUED
	if day < today or day < int(contract["first_day"]):
		return PAST
	return ""


static func _headroom_of(contract: Dictionary) -> int:
	if contract.is_empty():
		return 0
	var limits := PlaneClasses.passenger_range(contract["plane_size"])
	return maxi(0, int(limits[1]) - int(contract["booked_passengers"]))


## The most any occurrence could take: the largest class maximum less the
## smallest class minimum.
static func _largest_headroom() -> int:
	var most := 0
	for plane_class: String in PlaneClasses.ORDER:
		var limits := PlaneClasses.passenger_range(plane_class)
		most = maxi(most, int(limits[1]) - int(limits[0]))
	return most
