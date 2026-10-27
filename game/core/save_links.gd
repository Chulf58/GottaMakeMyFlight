class_name SaveLinks
extends RefCounted
## The checks across parts of a whole-world save, run by SaveGame on the
## staged copies before anything is installed. Each part's own loader already
## checks the part alone; these check that an id saved in one part names
## something another part holds:
##
## - offers and flight contracts: an accepted offer has the contract of the
##   same id with the same terms, an offer not accepted has none, and every
##   other contract is the starter (FlightSim.DEFAULT_ID);
## - flight ids in the passengers part (each passenger's flight, the pending
##   spawns, the scheduled flights, the no-shows and flight results) and in
##   the rating's pending list: a live flight, or an occurrence of a saved
##   contract (FlightSim answers a pruned occurrence from its contract);
## - stations and seats in the passengers part: every queue's station and
##   every passenger's station is a usable station of the layout built from
##   the saved grid, and every gate seat a passenger holds is a seat there.
##   A save is taken only between ticks with no edit pending, and each tick
##   starts by bringing queues and seats in line with the layout, so a save
##   never holds one that is gone.
##
## Checked elsewhere already: staff stations and roles against the layout
## (StaffSnapshot.load), cafe visits and queues against the saved grid
## (CafeSnapshot.load), queue members against the saved passengers
## (PassengerSnapshot.load), and one tick for every part that keeps one
## (SaveGame).


## "" or the first broken link. `data` is the save; `staged` holds the staged
## copies SaveGame's stage steps kept.
static func problem(data: Dictionary, staged: Dictionary) -> String:
	var flights: Dictionary = staged["flights"]
	var found := _offer_problem(data["offers"]["offers"], staged["offers"], flights["contracts"])
	if found == "":
		found = _flight_id_problem(staged["passengers"], staged["rating"], flights)
	if found == "":
		found = _station_problem(staged["passengers"], staged["sim"])
	return found


static func _offer_problem(saved: Array, board: OfferBoard, contracts: Array) -> String:
	var by_id := {}
	for contract in contracts:
		by_id[contract["id"]] = contract
	var offer_ids := {}
	for entry in saved:
		var offer := board.offer_of(str(entry["id"]))
		var id: String = offer["id"]
		offer_ids[id] = true
		var contract: Dictionary = by_id.get(id, {})
		if offer["status"] != OfferBoard.ACCEPTED:
			if not contract.is_empty():
				return (
					"offers: offer %s is %s but flights hold its contract" % [id, offer["status"]]
				)
			continue
		if contract.is_empty():
			return "offers: offer %s is accepted but flights hold no contract %s" % [id, id]
		for key in FlightContract.TERM_KEYS:
			if not _same(contract[key], offer[key]):
				return "offers: contract %s has another %s than its offer" % [id, key]
	for id in by_id:
		if not offer_ids.has(id) and id != FlightSim.DEFAULT_ID:
			return "flights: contract %s is neither the starter nor an accepted offer" % id
	return ""


static func _flight_id_problem(
	passengers: Dictionary, rating: Dictionary, flights: Dictionary
) -> String:
	var live := {}
	for flight in flights["flights"]:
		live[flight["id"]] = true
	var contracts := {}
	for contract in flights["contracts"]:
		contracts[contract["id"]] = true
	var named: Array[String] = []
	for p in passengers["passengers"]:
		named.append((p as Passenger).flight_id)
	for entry in passengers["schedule"]:
		named.append(str(entry["flight"]))
	for key in ["scheduled", "no_shows", "flight_results"]:
		for id in (passengers[key] as Dictionary).keys():
			named.append(str(id))
	for entry in rating["pending"]:
		named.append(str(entry["flight"]))
	for id in named:
		if live.has(id):
			continue
		var occurrence := FlightTimetable.parse_occurrence(id)
		if occurrence.is_empty() or not contracts.has(occurrence["contract"]):
			return "flight %s is named but is neither a live flight nor a saved contract's" % id
	return ""


static func _station_problem(passengers: Dictionary, sim: PassengerSim) -> String:
	var layout := sim.layout
	for station in (passengers["queues"] as Dictionary).keys():
		if not layout.is_usable(int(station)):
			return "passengers: a queue is at %d, which is not a usable station" % station
	for p in passengers["passengers"]:
		var passenger := p as Passenger
		if passenger.station != 0 and not layout.is_usable(passenger.station):
			return (
				"passengers: passenger %d is at %d, which is not a usable station"
				% [passenger.id, passenger.station]
			)
		if passenger.seat_object != 0 and not _has_seat(layout, passenger):
			return "passengers: passenger %d holds a seat that is not there" % passenger.id
	return ""


static func _has_seat(layout: TerminalLayout, p: Passenger) -> bool:
	for seat in layout.seats:
		if seat["object_id"] == p.seat_object and seat["cell"] == p.seat_cell:
			return true
	return false


## Equal values, a whole float from JSON counting as the int it holds.
static func _same(a: Variant, b: Variant) -> bool:
	var numbers := [TYPE_INT, TYPE_FLOAT]
	if typeof(a) in numbers and typeof(b) in numbers:
		return float(a) == float(b)
	return a == b
