class_name FlightResult
extends RefCounted
## A finished flight's result: how many passengers made it, how many missed it
## and the reasons they missed, from what PassengerSim recorded when the doors
## closed on each of them (Passenger.missed_stage and missed_stuck), kept in
## PassengerSim.flight_results after the passengers are retired. A blocking
## status such as "no check-in desk" wins over the stage the passenger was in.

## The reason texts below are the English msgids. Tests compare with them; the
## player's text comes from the _*_texts() functions, which hold tr()-style
## TranslationServer.translate() of the same literals, because the POT extractor
## reads only literals.
const NEVER_ARRIVED := "Never arrived: the terminal has no entrance"
const ARRIVED_LATE := "Did not arrive before the doors closed"
## PassengerSim.no_shows causes: scheduled passengers dropped at doors close.
const NO_SHOW_TEXT := {"no_entrance": NEVER_ARRIVED, "late": ARRIVED_LATE}
## A booking still in its car or taxi when the doors closed
## (ArrivalBookings.missed_by_flight): a missed flight, never a no-show.
const WAITING_FOR_DROP_OFF := "Waiting for drop-off"
## Check-in congestion: a passenger waiting in the line outside the entrance
## (EntranceLine) when the doors closed, held back from it on the schedule, or
## kept in its car or taxi because that line was full.
const ENTRANCE_LINE_TEXT := "Waiting outside: check-in full"
## A passenger held up in a boarding line when the doors closed.
const CROWDED_TEXT := "Held up by crowds at the gate"

const STUCK_TEXT := {
	Passenger.Stuck.NO_CHECKIN: "No check-in desk to go to",
	Passenger.Stuck.NO_SECURITY: "No security scanner or lane to go to",
	Passenger.Stuck.QUEUE_FULL: "Waiting outside a full queue",
	Passenger.Stuck.NO_ROUTE: "No walkable route",
	Passenger.Stuck.EXIT_BLOCKED: "The exit to the plane was blocked",
	# Held back in a boarding line when the doors closed: the terminal's
	# crowding cost the flight (decision a-late-passenger-held-up-by-people-
	# traffic-at-boarding-misse).
	Passenger.Stuck.CROWDED: CROWDED_TEXT,
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
## (StageKinds.facility()). A miss records its stage, not which shop (a kiosk
## or a store), so a shop visit reads the same for every shop type.
const FACILITY_TEXT := {
	StageKinds.Facility.CAFE: "Still at the cafe",
	StageKinds.Facility.TOILET: "Still at the toilet",
	StageKinds.Facility.SHOP: "Still at a shop",
}
## The reason when nothing more is known.
const MISSED_TEXT := "Missed the flight"


## The reason text for a passenger who missed the plane at `stage`.
static func reason_text(stage: Passenger.Stage, stuck: Passenger.Stuck) -> String:
	if stage == Passenger.Stage.SPAWNED and stuck == Passenger.Stuck.QUEUE_FULL:
		return TranslationServer.translate("Waiting outside: check-in full")
	var stuck_texts := _stuck_texts()
	if stuck_texts.has(stuck):
		return stuck_texts[stuck]
	var stage_texts := _stage_texts()
	if stage_texts.has(stage):
		return stage_texts[stage]
	return _facility_texts().get(
		StageKinds.facility(stage), TranslationServer.translate("Missed the flight")
	)


## The player's text per blocking status (STUCK_TEXT).
static func _stuck_texts() -> Dictionary:
	return {
		Passenger.Stuck.NO_CHECKIN: TranslationServer.translate("No check-in desk to go to"),
		Passenger.Stuck.NO_SECURITY:
		TranslationServer.translate("No security scanner or lane to go to"),
		Passenger.Stuck.QUEUE_FULL: TranslationServer.translate("Waiting outside a full queue"),
		Passenger.Stuck.NO_ROUTE: TranslationServer.translate("No walkable route"),
		Passenger.Stuck.EXIT_BLOCKED:
		TranslationServer.translate("The exit to the plane was blocked"),
		Passenger.Stuck.CROWDED: TranslationServer.translate("Held up by crowds at the gate"),
	}


## The player's text per stage the passenger was in (STAGE_TEXT).
static func _stage_texts() -> Dictionary:
	var at_gate := TranslationServer.translate("At the gate, but not boarded in time")
	var too_late := TranslationServer.translate("Left the gate too late for the plane")
	return {
		Passenger.Stage.SPAWNED: TranslationServer.translate("Arrived after the doors closed"),
		Passenger.Stage.TO_CHECKIN: TranslationServer.translate("Still walking to check-in"),
		Passenger.Stage.CHECKIN_QUEUE: TranslationServer.translate("Still queuing for check-in"),
		Passenger.Stage.CHECKIN: TranslationServer.translate("Still at the check-in desk"),
		Passenger.Stage.TO_SECURITY: TranslationServer.translate("Still walking to security"),
		Passenger.Stage.SECURITY_QUEUE: TranslationServer.translate("Still queuing for security"),
		Passenger.Stage.SECURITY: TranslationServer.translate("Still at security"),
		Passenger.Stage.TO_GATE: TranslationServer.translate("Still walking to the gate"),
		Passenger.Stage.SITTING_DOWN: at_gate,
		Passenger.Stage.SEATED: at_gate,
		Passenger.Stage.STANDING: at_gate,
		Passenger.Stage.STANDING_UP: at_gate,
		Passenger.Stage.TO_EXIT: too_late,
		Passenger.Stage.APRON: too_late,
	}


## The player's text per facility visit (FACILITY_TEXT).
static func _facility_texts() -> Dictionary:
	return {
		StageKinds.Facility.CAFE: TranslationServer.translate("Still at the cafe"),
		StageKinds.Facility.TOILET: TranslationServer.translate("Still at the toilet"),
		StageKinds.Facility.SHOP: TranslationServer.translate("Still at a shop"),
	}


## {"flight", "made", "missed", "close_calls", "reasons"} for one flight.
## "reasons" is a list of
## {"text", "count"} sorted largest first (ties by text). Scheduled passengers
## dropped when the doors closed (PassengerSim.no_shows) never reached the
## terminal, so they are a reason but are not in "missed". Passengers still on
## the road in a car or taxi then did miss it: they are in "missed", with the
## reason WAITING_FOR_DROP_OFF. Nothing here reads the live schedule, so the
## result does not change after the doors close.
static func summarize(sim: PassengerSim, flight_id: String) -> Dictionary:
	var result: Dictionary = sim.flight_results.get(flight_id, {})
	var made: int = int(result.get("made", 0))
	var close_calls: int = int(result.get("close_calls", 0))
	var on_road: int = sim.arrivals.missed_by_flight.get(flight_id, 0)
	var missed: int = int(result.get("missed", 0)) + on_road
	var counts := {}
	var held: int = mini(sim.entrance.held_missed.get(flight_id, 0), on_road)
	if on_road - held > 0:
		counts[TranslationServer.translate("Waiting for drop-off")] = on_road - held
	if held > 0:
		counts[TranslationServer.translate("Waiting outside: check-in full")] = held
	var causes: Dictionary = result.get("causes", {})
	for cause: Vector2i in causes:
		var text := reason_text(cause.x as Passenger.Stage, cause.y as Passenger.Stuck)
		counts[text] = int(counts.get(text, 0)) + causes[cause]
	var no_shows: Dictionary = sim.no_shows.get(flight_id, {})
	var no_show_texts := {
		"no_entrance": TranslationServer.translate("Never arrived: the terminal has no entrance"),
		"late": TranslationServer.translate("Did not arrive before the doors closed"),
	}
	for cause in no_show_texts:
		if no_shows.get(cause, 0) > 0:
			counts[no_show_texts[cause]] = no_shows[cause]
	var reasons := []
	for text in counts:
		reasons.append({"text": text, "count": counts[text]})
	reasons.sort_custom(_larger_first)
	return {
		"flight": flight_id,
		"made": made,
		"missed": missed,
		"close_calls": close_calls,
		"reasons": reasons,
	}


static func _larger_first(a: Dictionary, b: Dictionary) -> bool:
	if a["count"] != b["count"]:
		return a["count"] > b["count"]
	return a["text"] < b["text"]
