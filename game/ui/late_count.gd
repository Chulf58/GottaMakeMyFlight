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
	if count <= 0:
		return ""
	return (
		TranslationServer
		. translate_plural("{count} running late", "{count} running late", count)
		. format({"count": count})
	)


## Id of the tightest active running-late passenger on `flight_id`, or 0 for
## none: lowest remaining forecast slack (doors_close - arrival), ties broken by
## lowest passenger id.
static func tightest_passenger(sim: PassengerSim, flight_id: String) -> int:
	if sim == null or flight_id == "":
		return 0
	var doors_close := sim.flights.doors_close_tick(flight_id) if sim.flights != null else -1
	var best_id := 0
	var best_slack := 0
	for id in sim.passenger_ids():
		var p := sim.get_passenger(id)
		if p == null or p.is_done() or not p.late or p.flight_id != flight_id:
			continue
		var slack := _slack_of(sim, p, doors_close)
		if best_id == 0 or slack < best_slack or (slack == best_slack and p.id < best_id):
			best_id = p.id
			best_slack = slack
	return best_id


static func _slack_of(sim: PassengerSim, p: Passenger, doors_close: int) -> int:
	if doors_close < 0 or StageKinds.leg(p.stage) == StageKinds.Leg.VISIT:
		return -JourneyForecast.NEVER
	var arrival := JourneyForecast.arrival_tick(sim, p)
	if arrival >= JourneyForecast.NEVER:
		return -JourneyForecast.NEVER
	return doors_close - arrival
