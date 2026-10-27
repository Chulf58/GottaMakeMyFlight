class_name FlightResult
extends RefCounted
## A finished flight's result: how many passengers made it, how many missed it
## and the reasons they missed, from what PassengerSim recorded when the doors
## closed on each of them (Passenger.missed_stage and missed_stuck). A blocking
## status such as "no check-in desk" wins over the stage the passenger was in.

const NEVER_ARRIVED := "Never arrived: the terminal has no entrance"
const ARRIVED_LATE := "Did not arrive before the doors closed"
## PassengerSim.no_shows causes: scheduled passengers dropped at doors close.
const NO_SHOW_TEXT := {"no_entrance": NEVER_ARRIVED, "late": ARRIVED_LATE}

const STUCK_TEXT := {
	Passenger.Stuck.NO_CHECKIN: "No check-in desk to go to",
	Passenger.Stuck.NO_SECURITY: "No security scanner to go to",
	Passenger.Stuck.QUEUE_FULL: "Waiting outside a full queue",
	Passenger.Stuck.NO_ROUTE: "No walkable route",
	Passenger.Stuck.EXIT_BLOCKED: "The exit to the plane was blocked",
}

const STAGE_TEXT := {
	Passenger.Stage.SPAWNED: "Arrived after the doors closed",
	Passenger.Stage.TO_CHECKIN: "Still walking to check-in",
	Passenger.Stage.CHECKIN_QUEUE: "Still queuing for check-in",
	Passenger.Stage.CHECKIN: "Still at the check-in desk",
	Passenger.Stage.TO_SECURITY: "Still walking to security",
	Passenger.Stage.SECURITY_QUEUE: "Still queuing for security",
	Passenger.Stage.SECURITY: "Still at the security scanner",
	Passenger.Stage.TO_GATE: "Still walking to the gate",
	Passenger.Stage.SITTING_DOWN: "At the gate, but not boarded in time",
	Passenger.Stage.SEATED: "At the gate, but not boarded in time",
	Passenger.Stage.STANDING: "At the gate, but not boarded in time",
	Passenger.Stage.STANDING_UP: "At the gate, but not boarded in time",
	Passenger.Stage.TO_EXIT: "Left the gate too late for the plane",
	Passenger.Stage.APRON: "Left the gate too late for the plane",
	Passenger.Stage.CAFE_WALK: "Still at the cafe",
	Passenger.Stage.CAFE_QUEUE: "Still at the cafe",
	Passenger.Stage.CAFE_ORDER: "Still at the cafe",
	Passenger.Stage.CAFE_TO_SEAT: "Still at the cafe",
	Passenger.Stage.CAFE_SITTING_DOWN: "Still at the cafe",
	Passenger.Stage.CAFE_SEATED: "Still at the cafe",
	Passenger.Stage.CAFE_STANDING_UP: "Still at the cafe",
}


## The reason text for a passenger who missed the plane at `stage`.
static func reason_text(stage: Passenger.Stage, stuck: Passenger.Stuck) -> String:
	if STUCK_TEXT.has(stuck):
		return STUCK_TEXT[stuck]
	return STAGE_TEXT.get(stage, "Missed the flight")


## {"flight", "made", "missed", "reasons"} for one flight. "reasons" is a list of
## {"text", "count"} sorted largest first (ties by text). Scheduled passengers
## dropped when the doors closed (PassengerSim.no_shows) never reached the
## terminal, so they are a reason but are not in "missed". Nothing here reads
## the live schedule, so the result does not change after the doors close.
static func summarize(sim: PassengerSim, flight_id: String) -> Dictionary:
	var made := 0
	var missed := 0
	var counts := {}
	for id in sim.passenger_ids():
		var p := sim.get_passenger(id)
		if p.flight_id != flight_id:
			continue
		if p.stage == Passenger.Stage.MADE:
			made += 1
		elif p.stage == Passenger.Stage.MISSED:
			missed += 1
			var text := reason_text(p.missed_stage, p.missed_stuck)
			counts[text] = int(counts.get(text, 0)) + 1
	var no_shows: Dictionary = sim.no_shows.get(flight_id, {})
	for cause in NO_SHOW_TEXT:
		if no_shows.get(cause, 0) > 0:
			counts[NO_SHOW_TEXT[cause]] = no_shows[cause]
	var reasons := []
	for text in counts:
		reasons.append({"text": text, "count": counts[text]})
	reasons.sort_custom(_larger_first)
	return {"flight": flight_id, "made": made, "missed": missed, "reasons": reasons}


static func _larger_first(a: Dictionary, b: Dictionary) -> bool:
	if a["count"] != b["count"]:
		return a["count"] > b["count"]
	return a["text"] < b["text"]
