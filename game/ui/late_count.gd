class_name LateCount
extends RefCounted
## How many passengers of each flight are running late, for the departures
## board's soft "N running late" line (board 7f89cf1e, decision calm-cozy-
## default-view-quiet-world-detail-on-ask-soft-statio part 4). A passenger
## counts while Passenger.late holds and its journey is not over, the same test
## the passenger card's "Running late" line makes (PassengerInspect.now_line).


## {flight id: passengers running late}, flights with nobody late left out.
static func by_flight(sim: PassengerSim) -> Dictionary:
	var counts := {}
	for id in sim.passenger_ids():
		var p := sim.get_passenger(id)
		if p.late and not p.is_done():
			counts[p.flight_id] = int(counts.get(p.flight_id, 0)) + 1
	return counts


## "3 running late", or "" for none.
static func text_for(count: int) -> String:
	return "" if count <= 0 else "%d running late" % count
