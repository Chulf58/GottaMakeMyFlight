class_name FlightResult
extends RefCounted
## A finished flight's result: how many passengers made it, how many missed it
## and the reasons they missed, from what PassengerSim recorded when the doors
## closed on each of them (Passenger.missed_stage and missed_stuck), kept in
## PassengerSim.flight_results after the passengers are retired. A blocking
## status such as "no check-in desk" wins over the stage the passenger was in.

const NEVER_ARRIVED := "Never arrived: the terminal has no entrance"
const ARRIVED_LATE := "Did not arrive before the doors closed"
## PassengerSim.no_shows causes: scheduled passengers dropped at doors close.
const NO_SHOW_TEXT := {"no_entrance": NEVER_ARRIVED, "late": ARRIVED_LATE}

const STUCK_TEXT := {
	Passenger.Stuck.NO_CHECKIN: "No check-in desk to go to",
	Passenger.Stuck.NO_SECURITY: "No security scanner or lane to go to",
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
	Passenger.Stage.SECURITY: "Still at security",
	Passenger.Stage.TO_GATE: "Still walking to the gate",
	Passenger.Stage.SITTING_DOWN: "At the gate, but not boarded in time",
	Passenger.Stage.SEATED: "At the gate, but not boarded in time",
	Passenger.Stage.STANDING: "At the gate, but not boarded in time",
	Passenger.Stage.STANDING_UP: "At the gate, but not boarded in time",
	Passenger.Stage.TO_EXIT: "Left the gate too late for the plane",
	Passenger.Stage.APRON: "Left the gate too late for the plane",
}
## A passenger caught in a facility visit, whatever its stage there
## (StageKinds.facility()).
const FACILITY_TEXT := {
	StageKinds.Facility.CAFE: "Still at the cafe",
	StageKinds.Facility.TOILET: "Still at the toilet",
}
## The reason when nothing more is known.
const MISSED_TEXT := "Missed the flight"


## The reason text for a passenger who missed the plane at `stage`.
static func reason_text(stage: Passenger.Stage, stuck: Passenger.Stuck) -> String:
	if STUCK_TEXT.has(stuck):
		return STUCK_TEXT[stuck]
	if STAGE_TEXT.has(stage):
		return STAGE_TEXT[stage]
	return FACILITY_TEXT.get(StageKinds.facility(stage), MISSED_TEXT)


## {"flight", "made", "missed", "reasons"} for one flight. "reasons" is a list of
## {"text", "count"} sorted largest first (ties by text). Scheduled passengers
## dropped when the doors closed (PassengerSim.no_shows) never reached the
## terminal, so they are a reason but are not in "missed". Nothing here reads
## the live schedule, so the result does not change after the doors close.
static func summarize(sim: PassengerSim, flight_id: String) -> Dictionary:
	var result: Dictionary = sim.flight_results.get(flight_id, {})
	var made: int = result.get("made", 0)
	var missed: int = result.get("missed", 0)
	var counts := {}
	var causes: Dictionary = result.get("causes", {})
	for cause: Vector2i in causes:
		var text := reason_text(cause.x as Passenger.Stage, cause.y as Passenger.Stuck)
		counts[text] = int(counts.get(text, 0)) + causes[cause]
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
