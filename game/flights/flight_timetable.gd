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
## ArrivalTypes.RELAXED_LEAD_TICKS before departure (1640 ticks before the
## first state); this leaves 760 ticks between the issue and the earliest of
## them.
const ISSUE_LEAD_TICKS := 2400
## Keep a departed occurrence listed for one game hour, then drop the record.
const PRUNE_AFTER_TICKS := 1200

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


## True when two contracts at one gate would hold it at the same time on any
## day. Both repeat daily for ever and a reservation is shorter than a day, so
## comparing day-0 times with the other shifted a day either way covers all.
static func contracts_clash(a: Dictionary, b: Dictionary) -> bool:
	if a["gate"] != b["gate"]:
		return false
	var a_start := _first_start(a, 0)
	var b_start := _first_start(b, 0)
	var length := reserved_ticks()
	for shift in [-1, 0, 1]:
		var moved: int = b_start + shift * GameCalendar.TICKS_PER_DAY
		if a_start < moved + length and moved < a_start + length:
			return true
	return false


## True when a one-off flight holding the gate over [start, end) overlaps an
## occurrence of `contract` on any day from its first_day. The overlapping
## days form one contiguous range, found in closed form.
static func contract_overlaps(contract: Dictionary, start: int, end: int) -> bool:
	if start >= end:
		return false
	var first := _first_start(contract, 0)
	var day_size := GameCalendar.TICKS_PER_DAY
	var lowest := GameCalendar.floor_div(start - first - reserved_ticks(), day_size) + 1
	var highest := -GameCalendar.floor_div(first - end, day_size) - 1
	return maxi(lowest, int(contract["first_day"])) <= highest


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
