class_name FlightTimetable
extends RefCounted
## The timing of a contract's daily occurrences, as pure functions of the
## immutable contract and a day. The occurrence of day d departs (starts
## PUSHBACK) at the contract's departure minute on day d and is named
## "<contract>-d<d>". Its preparation window, and its gate reservation, is the
## half-open interval from its first state (SCHEDULED) to DEPARTED. It is
## issued ISSUE_LEAD_TICKS before that window opens and pruned
## PRUNE_AFTER_TICKS after it departs.

## Issue an occurrence two game hours before its first state, so listeners
## can plan it before anything is due. Passenger arrivals start up to
## ArrivalTypes.RELAXED_LEAD_TICKS before departure (1340 ticks before the
## first state); this leaves 1060 ticks between the issue and the earliest of
## them.
const ISSUE_LEAD_TICKS := 2400
## Keep a departed occurrence listed for one game hour, then drop the record.
const PRUNE_AFTER_TICKS := 1200

## The shared ground every gate's planes use (decision gates-technical-design-
## gate-desks-link-to-north-exits-one-st, point 4): the runway and the taxi
## lane with its links to the runway (StandPlacement.runway_zone(), lane_zone()).
## A flight holds each for every tick any part of the plane can be on it, at
## any legal stand: flight_holds(). Two flights at different gates clash when
## they hold one of them at once; at one gate the gate hold already covers it.
const RUNWAY := "runway"
const LANE := "lane"
## Holds at the gate itself, from the first state to DEPARTED. A clash_on()
## answer, beside RUNWAY and LANE.
const GATE := "gate"
## Cut points inside a phase, measured by test_shared_ground_holds.gd with
## PHASE_TICKS over stands across the whole site and the shortest taxi routes
## any stand can have, each with a margin of 10 or more ticks. The arriving
## plane is off the runway by TAXI_IN + 239 (it is still on it as it turns off
## the runway exit); the departing one is on it from TAXI_OUT + 343 and off the
## lane by TAKEOFF + 28 (its tail swings over the lane as it lines up).
const RUNWAY_VACATE_TICKS := 260
const RUNWAY_ENTER_TICKS := 320
const LANE_CLEAR_TICKS := 40

static var _occurrence_pattern := RegEx.create_from_string("^([A-Za-z0-9]+)-d(0|[1-9][0-9]{0,9})$")


## Ticks from the first state to the scheduled departure (start of PUSHBACK).
static func departure_offset() -> int:
	var offset := 0
	for state in FlightSim.State.PUSHBACK:
		offset += FlightSim.PHASE_TICKS[state]
	return offset


static func occurrence_id(contract_id: String, day: int) -> String:
	return "%s-d%d" % [contract_id, day]


## {"contract": id, "day": d} for a canonical occurrence id, else {}.
static func parse_occurrence(id: String) -> Dictionary:
	var found := _occurrence_pattern.search(id)
	if found == null:
		return {}
	return {"contract": found.get_string(1), "day": found.get_string(2).to_int()}


static func starts_for(contract: Dictionary, day: int) -> Array[int]:
	return FlightSim.schedule_starts(_first_start(contract, day))


## The first day >= 0 whose occurrence's first state is at or after `now`.
## Nothing of that occurrence is due before `now + 1`: its first transition
## comes PHASE_TICKS[0] later, and arrivals are planned after its first state.
static func first_day(contract: Dictionary, now: int) -> int:
	var behind := now - _first_start(contract, 0)
	return maxi(0, -GameCalendar.floor_div(-behind, GameCalendar.TICKS_PER_DAY))


## The first day, from the contract's first_day on, that is issued at or after
## `opened` (the tick the airport opened): the start of a contract accepted
## while the airport was closed. The days before it are never flown.
static func opening_day(contract: Dictionary, opened: int) -> int:
	return maxi(int(contract["first_day"]), first_day(contract, opened + ISSUE_LEAD_TICKS))


static func issue_tick(contract: Dictionary, day: int) -> int:
	return _first_start(contract, day) - ISSUE_LEAD_TICKS


static func prune_tick(contract: Dictionary, day: int) -> int:
	return _first_start(contract, day) + reserved_ticks() + PRUNE_AFTER_TICKS


## The first day not yet issued at `now`.
static func next_day(contract: Dictionary, now: int) -> int:
	var since_first := now - issue_tick(contract, 0)
	var day := GameCalendar.floor_div(since_first, GameCalendar.TICKS_PER_DAY) + 1
	return maxi(int(contract["first_day"]), day)


## True when two contracts would hold one gate, the runway or the lane at the
## same time on any day (contracts_clash_on).
static func contracts_clash(a: Dictionary, b: Dictionary) -> bool:
	return contracts_clash_on(a, b) != ""


## What two contracts would hold at the same time on some day: GATE when they
## share a gate and their gate holds overlap, else RUNWAY or LANE, else "".
## Both repeat daily for ever and every hold lies inside the gate hold, which
## is shorter than a day, so comparing day 0 of one with day -1, 0 and 1 of the
## other covers all.
static func contracts_clash_on(a: Dictionary, b: Dictionary) -> String:
	var a_starts := starts_for(a, 0)
	for shift in [-1, 0, 1]:
		var on := clash_on(a["gate"], a_starts, b["gate"], starts_for(b, shift))
		if on != "":
			return on
	return ""


## What a flight at `gate` with `starts` would hold at the same time as an
## occurrence of `contract` on a day from its first_day: GATE, RUNWAY, LANE or
## "". Only the days whose gate hold overlaps the flight's are compared; they
## form one contiguous range, found in closed form.
static func contract_meets(contract: Dictionary, gate: String, starts: Array) -> String:
	var start: int = starts[0]
	var end: int = starts[FlightSim.State.DEPARTED]
	if start >= end:
		return ""
	var first := _first_start(contract, 0)
	var day_size := GameCalendar.TICKS_PER_DAY
	var lowest := GameCalendar.floor_div(start - first - reserved_ticks(), day_size) + 1
	var highest := -GameCalendar.floor_div(first - end, day_size) - 1
	for day in range(maxi(lowest, int(contract["first_day"])), highest + 1):
		var on := clash_on(gate, starts, contract["gate"], starts_for(contract, day))
		if on != "":
			return on
	return ""


## What two flights would hold at the same time: GATE when they are at one gate
## and their gate holds overlap, else the RUNWAY or LANE they would both hold,
## else "".
static func clash_on(a_gate: String, a_starts: Array, b_gate: String, b_starts: Array) -> String:
	var last := FlightSim.State.DEPARTED
	if a_gate == b_gate:
		if holds_overlap(a_starts[0], a_starts[last], b_starts[0], b_starts[last]):
			return GATE
		return ""
	for a_hold in flight_holds(a_starts):
		for b_hold in flight_holds(b_starts):
			if a_hold[0] == b_hold[0] and holds_overlap(a_hold[1], a_hold[2], b_hold[1], b_hold[2]):
				return a_hold[0]
	return ""


## The flight's holds on the shared ground, [zone, from, to) with zone RUNWAY or
## LANE: the arrival holds the runway from APPROACH until it is off it in
## TAXI_IN and the lane for all of TAXI_IN; the departure holds the lane from
## PUSHBACK until it is lined up in TAKEOFF and the runway from late in
## TAXI_OUT to DEPARTED. The cut points are measured for PHASE_TICKS; a flight
## whose taxi or takeoff phases last otherwise (a one-off, tests and debug
## only) holds those phases whole instead.
static func flight_holds(starts: Array) -> Array:
	var s := starts
	var vacate: int = s[FlightSim.State.AT_STAND]
	var enter: int = s[FlightSim.State.TAXI_OUT]
	var lane_clear: int = s[FlightSim.State.DEPARTED]
	if _phases_standard(starts):
		vacate = s[FlightSim.State.TAXI_IN] + RUNWAY_VACATE_TICKS
		enter += RUNWAY_ENTER_TICKS
		lane_clear = s[FlightSim.State.TAKEOFF] + LANE_CLEAR_TICKS
	return [
		[RUNWAY, s[FlightSim.State.APPROACH], vacate],
		[LANE, s[FlightSim.State.TAXI_IN], s[FlightSim.State.AT_STAND]],
		[LANE, s[FlightSim.State.PUSHBACK], lane_clear],
		[RUNWAY, enter, s[FlightSim.State.DEPARTED]],
	]


## Whether TAXI_IN, TAXI_OUT and TAKEOFF last as PHASE_TICKS says.
static func _phases_standard(starts: Array) -> bool:
	for state in [FlightSim.State.TAXI_IN, FlightSim.State.TAXI_OUT, FlightSim.State.TAKEOFF]:
		if starts[state + 1] - starts[state] != FlightSim.PHASE_TICKS[state]:
			return false
	return true


## True when the half-open gate holds [a_start, a_end) and [b_start, b_end) overlap.
static func holds_overlap(a_start: int, a_end: int, b_start: int, b_end: int) -> bool:
	return a_start < b_end and b_start < a_end


## Timetable order of live flights: first start tick, then id.
static func flight_before(a: Dictionary, b: Dictionary) -> bool:
	if a["starts"][0] != b["starts"][0]:
		return a["starts"][0] < b["starts"][0]
	return a["id"] < b["id"]


## The state a flight is in at `now`: the last whose start tick has passed.
static func state_at(starts: Array[int], now: int) -> int:
	var state := FlightSim.State.SCHEDULED
	while state < FlightSim.State.DEPARTED and now >= starts[state + 1]:
		state += 1
	return state


static func starts_valid(starts: Array[int]) -> bool:
	if starts.size() != FlightSim.STATE_COUNT or starts[0] < 0:
		return false
	for i in range(1, FlightSim.STATE_COUNT):
		if starts[i] < starts[i - 1]:
			return false
	return true


static func _first_start(contract: Dictionary, day: int) -> int:
	var departure := GameCalendar.tick_at(day, int(contract["departure_minute"]))
	return departure - departure_offset()


## Ticks an occurrence holds its gate: from its first state to DEPARTED.
static func reserved_ticks() -> int:
	var total := 0
	for ticks in FlightSim.PHASE_TICKS:
		total += ticks
	return total
