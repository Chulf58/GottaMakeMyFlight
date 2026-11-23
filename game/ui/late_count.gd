class_name LateCount
extends RefCounted
## How many passengers of each flight are running late, for the departures
## board's "N running late" pill and self-clearing alert card (decisions
## calm-cozy-default-view-quiet-world-detail-on-ask-soft-statio part 4,
## days-3-5-close-call-drama-ccbc48f5-last-second-save-counter, and
## departures-live-ops-drawer-and-actionable-on-time-hud-stat). A passenger
## counts while Passenger.late holds and its journey is not over, the same test
## the passenger card's "Running late" line makes (PassengerInspect.now_line).

const ALERT_KEY := &"late_runners"

static var _translator := RefCounted.new()


## Total running-late passengers across all flights in `counts` (by_flight()).
static func total_late(counts: Dictionary) -> int:
	var total := 0
	for count: int in counts.values():
		total += count
	return total


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


## Tightest active running-late passenger across all flights, or {} when none:
## {"id", "flight", "total"}.
static func tightest_overall(sim: PassengerSim) -> Dictionary:
	if sim == null:
		return {}
	var total := 0
	var best_id := 0
	var best_flight := ""
	var best_slack := 0
	for id in sim.passenger_ids():
		var p := sim.get_passenger(id)
		if p == null or p.is_done() or not p.late:
			continue
		total += 1
		var doors_close := sim.flights.doors_close_tick(p.flight_id) if sim.flights != null else -1
		var slack := _slack_of(sim, p, doors_close)
		if best_id == 0 or slack < best_slack or (slack == best_slack and p.id < best_id):
			best_id = p.id
			best_flight = p.flight_id
			best_slack = slack
	if total == 0:
		return {}
	return {"id": best_id, "flight": best_flight, "total": total}


## Self-clearing AlertBoard cause for running-late passengers when the
## Departures drawer is hidden; empty when nobody is late.
static func alert_cause(sim: PassengerSim, flights: FlightSim) -> Array[Dictionary]:
	var info := tightest_overall(sim)
	if info.is_empty():
		return []
	var pid: int = info["id"]
	var flight_id: String = info["flight"]
	var total: int = info["total"]
	var p := sim.get_passenger(pid)
	var targets: Array[Vector3] = []
	if p != null and sim.grid != null:
		var at := sim.world_position(p)
		targets.append(Vector3(at.x, 0.0, at.z))
	return [
		{
			"key": ALERT_KEY,
			"title": text_for(total),
			"detail": _late_detail(flights, flight_id),
			"targets": targets,
			"flight": flight_id,
			"show_after": 0,
			"clear_after": 0,
		}
	]


static func _late_detail(flights: FlightSim, flight_id: String) -> String:
	if flights != null:
		var parts := FlightLabel.parts(flights, true, flight_id)
		if not parts.is_empty():
			if parts[1] != "":
				return _translator.tr("{time} {destination} · Click to follow").format(
					{"time": parts[0], "destination": parts[1]}
				)
			return _translator.tr("{time} {flight} · Click to follow").format(
				{"time": parts[0], "flight": FlightResultPanel.flight_title(flight_id)}
			)
	return _translator.tr("{flight} · Click to follow").format(
		{"flight": FlightResultPanel.flight_title(flight_id)}
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
