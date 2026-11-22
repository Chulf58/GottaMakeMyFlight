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
## - flight ids in the passengers part and in the rating's pending list, in
##   two groups. Ids whose holders ask FlightSim about them as the game runs
##   (each passenger's flight, the pending spawns and the scheduled flights:
##   doors closed, boarding window, gate) must name a flight FlightSim knows
##   after the load, a live or landed one (_known()): FlightSim._find()
##   answers only those, so a passenger on an older occurrence would wait for
##   doors that never close. Ids that are only kept as records and dropped
##   once FlightSim stops listing the flight (the no-shows and flight
##   results, the rating's pending list) may also name any occurrence of a
##   saved contract on a day already issued (_issued());
## - stations and seats in the passengers part: every queue's station and
##   every passenger's station is a usable station of the layout built from
##   the saved grid, and every gate seat a passenger holds is a seat there.
##   A save is taken only between ticks with no edit pending, and each tick
##   starts by bringing queues and seats in line with the layout, so a save
##   never holds one that is gone;
## - the settlement's last charged wage day is the clock's day (or none yet),
##   and no wages are owed while the wallet holds money
##   (Settlement.wages_link_problem).
## - bags: every bag fits the route field built from the saved grid
##   (BaggageSnapshot.grid_problem), an unsettled bag's flight is live (its
##   cutoff comes before its doors close, and a flight stays listed until
##   after it departs), and every flight in the bag results is live or an
##   issued occurrence. A bag's passenger and desk are not looked up: a
##   settled passenger is retired and a desk can be demolished while its
##   bags remain. The reverse is looked up: a passenger whose fee the
##   settlement holds for a bag on its way has an unsettled bag.
## - the landside: every arrival booking's flight is one the passengers part
##   has scheduled, and every flight with transport misses is live or an
##   issued occurrence;
## - incidents: a VIP offer or accepted VIP's flight and an announced rush's
##   flights are asked about as the game runs (IncidentMajors._flight_lost,
##   FlightSim.state_of), so each must be live, landed (_known()) or not yet
##   issued (_unissued(): a day on or after its contract's next day, as a VIP
##   or rush can name a day ahead). A forgotten occurrence would never answer;
## - today's money: the DayLedger's day is the clock's day
##   (DayLedger.day_link_problem), and unless it counts since a load its
##   wages paid are the settlement's wages paid today
##   (DayLedger.wages_link_problem); a save without the ledger has none to check.
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
	if found == "" and staged.has("incidents"):
		found = _incident_problem(staged["incidents"], flights)
	if found == "":
		found = _landside_problem(staged["landside"], staged["passengers"], flights)
	if found == "":
		found = _station_problem(staged["passengers"], staged["sim"])
	if found == "":
		found = Settlement.wages_link_problem(data["settlement"], data["clock"], data["wallet"])
	if found == "":
		found = _bag_problem(staged["baggage"], staged["grid"], flights)
	if found == "":
		found = _awaited_problem(data["settlement"], staged["baggage"]["bags"])
	if found == "" and staged.has("staff"):
		found = _ramp_problem(staged["staff"], staged["baggage"], flights, staged["rating"])
	if found == "" and data.has("day_ledger"):
		found = DayLedger.day_link_problem(data["day_ledger"], data["clock"])
		if found == "":
			found = DayLedger.wages_link_problem(data["day_ledger"], data["settlement"])
	return found


## Every fee the settlement holds for a bag still on its way names a passenger
## with an unsettled bag. A bag settles before it is retired, and settling pays
## the fee, so a saved fee with no unsettled bag would never be paid.
static func _awaited_problem(settlement: Dictionary, bags: Array[Bag]) -> String:
	var unsettled := {}
	for bag in bags:
		if not bag.is_settled():
			unsettled[bag.passenger] = true
	for entry in settlement.get("bags_awaited", []):
		var passenger := str(entry["passenger"]).to_int()
		if not unsettled.has(passenger):
			return "baggage: passenger %d awaits a bag but has no unsettled bag" % passenger
	return ""


static func _bag_problem(baggage: Dictionary, grid: BuildGrid, flights: Dictionary) -> String:
	var bags: Array[Bag] = baggage["bags"]
	var found := BaggageSnapshot.grid_problem(bags, BagRoutes.build(grid))
	if found != "":
		return "baggage: %s" % found
	var live := {}
	for flight in flights["flights"]:
		live[flight["id"]] = true
	for bag in bags:
		if not bag.is_settled() and not live.has(bag.flight):
			return "baggage: bag %d waits for flight %s, which is not live" % [bag.id, bag.flight]
	for id in (baggage["results"] as Dictionary).keys():
		if not live.has(id) and not _issued(id, flights):
			return "baggage: flight %s has results but is neither live nor issued" % id
	return ""


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
		var keys: Array = FlightContract.TERM_KEYS + [FlightContract.TRAITS_KEY]
		for key in keys:
			if not _same(contract.get(key), offer.get(key)):
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
	# Asked about at run time: FlightSim must still know them.
	var asked: Array[String] = []
	for p in passengers["passengers"]:
		asked.append((p as Passenger).flight_id)
	for entry in passengers["schedule"]:
		asked.append(str(entry["flight"]))
	for id in (passengers["scheduled"] as Dictionary).keys():
		asked.append(str(id))
	for id in asked:
		if not _known(id, flights):
			return "flight %s is named but is neither live nor landed" % id
	# Kept as records only: an issued occurrence FlightSim forgot is fine.
	var recorded: Array[String] = []
	for key in ["no_shows", "flight_results"]:
		for id in (passengers[key] as Dictionary).keys():
			recorded.append(str(id))
	for entry in rating["pending"]:
		recorded.append(str(entry["flight"]))
	for id in recorded:
		if not live.has(id) and not _issued(id, flights):
			return "flight %s is named but is neither live nor an issued occurrence" % id
	return ""


## Whether FlightSim, loaded from `flights`, knows flight `id`: a live flight
## or a landed occurrence (today's or yesterday's, FlightSim._find()).
static func _known(id: String, flights: Dictionary) -> bool:
	for list: String in ["flights", "landed"]:
		for flight: Dictionary in flights[list]:
			if flight["id"] == id:
				return true
	return false


## "" or the first incident whose plan names a flight FlightSim cannot answer
## and that is not still to come: a VIP offered or accepted (its flight) or a
## rush announced (its flights). Done and declined incidents are not asked
## about any more, so their plans may name flights long gone.
static func _incident_problem(incidents: Dictionary, flights: Dictionary) -> String:
	for incident: Dictionary in incidents["incidents"]:
		var plan: Dictionary = incident["plan"]
		var asked: Array[String] = []
		match incident["kind"]:
			IncidentCatalogue.VIP:
				if incident["state"] in [IncidentCatalogue.OFFERED, IncidentCatalogue.ACCEPTED]:
					asked.append(plan["flight"])
			IncidentCatalogue.RUSH:
				if incident["state"] == IncidentCatalogue.ANNOUNCED:
					for entry: Dictionary in plan["flights"]:
						asked.append(entry["flight"])
		for id in asked:
			if not _known(id, flights) and not _unissued(id, flights):
				return (
					"incidents: incident %d names flight %s, neither live, landed nor to come"
					% [incident["id"], id]
				)
	return ""


## Every arrival booking is for a flight the passengers part has scheduled
## and whose doors have not closed (doors close settles a flight's bookings
## and unschedules it on the same tick), and every flight with transport
## misses is live or an issued occurrence.
static func _landside_problem(
	landside: Dictionary, passengers: Dictionary, flights: Dictionary
) -> String:
	var scheduled: Dictionary = passengers["scheduled"]
	for b: ArrivalBooking in landside["bookings"]:
		if not scheduled.has(b.flight_id):
			return (
				"landside: booking %d is for flight %s, which is not scheduled"
				% [b.id, b.flight_id]
			)
	var live := {}
	for flight in flights["flights"]:
		live[flight["id"]] = true
	for id in (landside["missed"] as Dictionary).keys():
		if not live.has(id) and not _issued(id, flights):
			return "landside: flight %s has misses but is neither live nor issued" % id
	return ""


## Whether `id` is an occurrence that was issued: a saved contract's, on a
## day from its start day up to, not including, its first day not yet
## issued. FlightSim no longer answers it once it is pruned and dropped from
## landed, so only ids kept as records may rely on this (_known() is the
## check for ids that are asked about).
static func _issued(id: String, flights: Dictionary) -> bool:
	var occurrence := FlightTimetable.parse_occurrence(id)
	if occurrence.is_empty():
		return false
	var contract: String = occurrence["contract"]
	var start_day: Dictionary = flights["start_day"]
	var next_day: Dictionary = flights["next_day"]
	if not start_day.has(contract) or not next_day.has(contract):
		return false
	var day: int = occurrence["day"]
	return day >= int(start_day[contract]) and day < int(next_day[contract])


## Whether `id` is an occurrence of a saved contract on a day on or after its
## next day, one FlightSim will still issue (an incident can name a day ahead).
static func _unissued(id: String, flights: Dictionary) -> bool:
	var occurrence := FlightTimetable.parse_occurrence(id)
	if occurrence.is_empty():
		return false
	var contract: String = occurrence["contract"]
	var next_day: Dictionary = flights["next_day"]
	return next_day.has(contract) and int(occurrence["day"]) >= int(next_day[contract])


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
		# One getting up from a moved row keeps its old seat cell (GateRelocation).
		var holds := passenger.seat_object != 0 and not passenger.seat_exiting
		if holds and not _has_seat(layout, passenger):
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
	if typeof(a) == TYPE_DICTIONARY and typeof(b) == TYPE_DICTIONARY:
		return _same_dictionary(a, b)
	return a == b


## Two dictionaries with the same keys whose values are _same (a traits term).
static func _same_dictionary(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for key in a:
		if not b.has(key) or not _same(a[key], b[key]):
			return false
	return true


static func _ramp_problem(
	staff: Dictionary, baggage: Dictionary, flights: Dictionary, rating: Dictionary
) -> String:
	var live_flights := {}
	for flight: Dictionary in flights["flights"]:
		live_flights[flight["id"]] = flight
	var contracts := {}
	for contract: Dictionary in flights["contracts"]:
		contracts[contract["id"]] = contract
	var shuttles_by_id := {}
	for shuttle: BaggageShuttle in baggage["shuttles"]:
		shuttles_by_id[shuttle.id] = shuttle
	var ramp_by_id := {}
	var claimed_shuttles := {}
	var claimed_pushbacks := {}
	var claimed_marshals := {}
	for m: StaffMember in staff["members"]:
		if m.role != StaffMember.Role.RAMP:
			if (
				m.ramp_job != StaffMember.RampJob.NONE
				or m.ramp_shuttle_id != 0
				or m.ramp_flight_id != ""
			):
				return "staff: non-ramp member %d holds a ramp job" % m.id
			continue
		ramp_by_id[m.id] = m
		if (
			m.leaving
			and m.ramp_job != StaffMember.RampJob.SHUTTLE
			and m.ramp_job != StaffMember.RampJob.PUSHBACK
		):
			return "staff: leaving ramp agent %d holds no shuttle or pushback" % m.id
		var problem := _ramp_member_problem(
			m,
			shuttles_by_id,
			live_flights,
			contracts,
			claimed_shuttles,
			claimed_pushbacks,
			claimed_marshals
		)
		if problem != "":
			return problem
	for shuttle: BaggageShuttle in baggage["shuttles"]:
		var worker: StaffMember = ramp_by_id.get(shuttle.driver_staff_id)
		if (
			shuttle.driver_staff_id <= 0
			or worker == null
			or worker.ramp_job != StaffMember.RampJob.SHUTTLE
			or worker.ramp_shuttle_id != shuttle.id
		):
			return (
				"baggage: shuttle %d driver %d is not a matching ramp agent"
				% [shuttle.id, shuttle.driver_staff_id]
			)
	return _emergency_pushback_problem(live_flights, contracts, claimed_pushbacks, rating)


static func _emergency_pushback_problem(
	live_flights: Dictionary,
	contracts: Dictionary,
	claimed_pushbacks: Dictionary,
	rating: Dictionary,
) -> String:
	var emergency_flights := {}
	for adj: Dictionary in rating.get("adjustments", []):
		var parsed := RampDispatch.parse_emergency_id(String(adj.get("id", "")))
		if parsed.is_empty():
			continue
		var fid: String = parsed["flight"]
		if int(adj.get("half_star_delta", 0)) != RampDispatch.EMERGENCY_RATING_HALF_STARS:
			return "rating: emergency pushback %s has invalid half_star_delta" % fid
		if emergency_flights.has(fid):
			return "rating: flight %s has duplicate emergency pushback adjustments" % fid
		emergency_flights[fid] = adj
	for fid: String in claimed_pushbacks:
		if emergency_flights.has(fid):
			return (
				"staff: flight %s pushback has both ramp agent and emergency pushback adjustment"
				% fid
			)
	for fid: String in live_flights:
		var flight: Dictionary = live_flights[fid]
		if int(flight["state"]) != FlightSim.State.PUSHBACK:
			continue
		if _flight_self_taxis(flight, contracts):
			continue
		if not claimed_pushbacks.has(fid) and not emergency_flights.has(fid):
			return (
				"staff: flight %s in pushback lacks a ramp agent or emergency pushback adjustment"
				% fid
			)
	return ""


static func _ramp_member_problem(
	m: StaffMember,
	shuttles_by_id: Dictionary,
	live_flights: Dictionary,
	contracts: Dictionary,
	claimed_shuttles: Dictionary,
	claimed_pushbacks: Dictionary,
	claimed_marshals: Dictionary,
) -> String:
	match m.ramp_job:
		StaffMember.RampJob.SHUTTLE:
			if claimed_shuttles.has(m.ramp_shuttle_id):
				return "staff: shuttle %d is claimed by two ramp agents" % m.ramp_shuttle_id
			claimed_shuttles[m.ramp_shuttle_id] = m.id
			var shuttle: BaggageShuttle = shuttles_by_id.get(m.ramp_shuttle_id)
			if shuttle == null:
				return "staff: ramp agent %d names missing shuttle %d" % [m.id, m.ramp_shuttle_id]
			if shuttle.driver_staff_id != m.id:
				return (
					"staff: ramp agent %d and shuttle %d driver disagree"
					% [m.id, m.ramp_shuttle_id]
				)
		StaffMember.RampJob.PUSHBACK:
			if claimed_pushbacks.has(m.ramp_flight_id):
				return "staff: flight %s pushback has two ramp agents" % m.ramp_flight_id
			claimed_pushbacks[m.ramp_flight_id] = m.id
			var flight: Dictionary = live_flights.get(m.ramp_flight_id, {})
			if flight.is_empty():
				return (
					"staff: ramp agent %d pushback flight %s is not live" % [m.id, m.ramp_flight_id]
				)
			if _flight_self_taxis(flight, contracts):
				return (
					"staff: ramp agent %d pushback flight %s self-taxis" % [m.id, m.ramp_flight_id]
				)
			var state := int(flight["state"])
			if state != FlightSim.State.DOORS_CLOSED and state != FlightSim.State.PUSHBACK:
				return (
					"staff: ramp agent %d pushback flight %s is in invalid phase"
					% [m.id, m.ramp_flight_id]
				)
		StaffMember.RampJob.MARSHAL:
			if claimed_marshals.has(m.ramp_flight_id):
				return "staff: flight %s marshal has two ramp agents" % m.ramp_flight_id
			claimed_marshals[m.ramp_flight_id] = m.id
			var flight: Dictionary = live_flights.get(m.ramp_flight_id, {})
			if flight.is_empty():
				return (
					"staff: ramp agent %d marshal flight %s is not live" % [m.id, m.ramp_flight_id]
				)
			if _flight_self_taxis(flight, contracts):
				return (
					"staff: ramp agent %d marshal flight %s self-taxis" % [m.id, m.ramp_flight_id]
				)
			if int(flight["state"]) != FlightSim.State.TAXI_IN:
				return (
					"staff: ramp agent %d marshal flight %s is not in TAXI_IN"
					% [m.id, m.ramp_flight_id]
				)
	return ""


static func _flight_self_taxis(flight: Dictionary, contracts: Dictionary) -> bool:
	var contract_id: String = flight.get("contract", "")
	var contract: Dictionary = contracts.get(contract_id, {})
	if contract.is_empty():
		contract = FlightSim.STARTER_TERMS
	var model := PlaneClasses.model_for(String(contract["airline"]), String(contract["plane_size"]))
	return model == "" or PlaneClasses.self_taxis(model)
