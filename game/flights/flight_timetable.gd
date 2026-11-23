class_name FlightTimetable
extends RefCounted
## The timing of a contract's daily occurrences, as pure functions of the
## immutable contract and a day. The occurrence of day d departs (starts
## PUSHBACK) at the contract's departure minute on day d and is named
## "<contract>-d<d>". Its preparation window, and its gate reservation, is the
## half-open interval from its first state (SCHEDULED) to DEPARTED.
##
## The phase lengths are FlightSim.PHASE_TICKS with the contract's own taxi pair
## (FlightContract.TAXI_KEY, TaxiTimes; ruling taxi-time-follows-each-gate-s-
## route-length-far-side-gates-ta). The departure stays where it is, so a
## longer TAXI_IN only moves the first state earlier and a longer TAXI_OUT only
## moves DEPARTED later. The pair is the contract's current assignment: an
## occurrence already issued keeps the starts it was issued with, so it is
## pruned PRUNE_AFTER_TICKS after its own DEPARTED (prune_tick()), never after
## the contract's.
##
## Issuing is anchored to the departure, not the first state: an occurrence is
## issued issue_lead() before it departs, which is ISSUE_LEAD_TICKS before the
## first state of a flight at TaxiTimes.BASE. So which days are issued, and the
## day a closed airport's contract starts on, never depend on the pair, and a
## contract that moves to a gate with other taxi times issues its next day at
## the same tick (TaxiTimes.MAX_IN keeps that at or before its first state).
##
## Days and departure minutes are calendar ones, so every function that turns
## them into ticks takes the calendar epoch E (GameCalendar, SimClock.epoch).

## Issue an occurrence two game hours before the first state of a flight at
## TaxiTimes.BASE, so listeners can plan it before anything is due. Passenger
## arrivals are set against the departure (ArrivalTypes) and start at most
## ArrivalTypes.RELAXED_LEAD_TICKS before it, 1460 ticks after the issue.
const ISSUE_LEAD_TICKS := 2400
## Keep a departed occurrence listed for one game hour, then drop the record.
const PRUNE_AFTER_TICKS := 1200

## The shared runway and taxi lane are not timetable holds any more: GroundPlanner
## books them (decision runway-and-taxi-technical-design-movement-plan-analytic-
## bookings-planned-pauses, sections 5 and 6, which supersede the whole-lane
## holds), through FlightPlans. Only the gate itself is held here.

static var _occurrence_pattern := RegEx.create_from_string("^([A-Za-z0-9]+)-d(0|[1-9][0-9]{0,9})$")


## The taxi pair of a contract (FlightContract.TAXI_KEY).
static func taxi_of(contract: Dictionary) -> Array:
	return contract[FlightContract.TAXI_KEY]


## Boarding duration in ticks for `contract`: charters use the compact
## same-day turnaround, regular contracts use FlightSim.PHASE_TICKS[BOARDING].
static func boarding_ticks_of(contract: Dictionary) -> int:
	return (
		FlightSim.CHARTER_BOARDING_TICKS
		if FlightContract.is_charter(contract)
		else FlightSim.PHASE_TICKS[FlightSim.State.BOARDING]
	)


## Ticks from the first state to the scheduled departure (start of PUSHBACK)
## for a flight with taxi pair `taxi` (and optional `boarding_ticks` override).
static func departure_offset(taxi: Array = TaxiTimes.BASE, boarding_ticks: int = -1) -> int:
	var ticks := TaxiTimes.phase_ticks(taxi)
	if boarding_ticks >= 0:
		ticks[FlightSim.State.BOARDING] = boarding_ticks
	var offset := 0
	for state in FlightSim.State.PUSHBACK:
		offset += ticks[state]
	return offset


## Ticks from an occurrence's issue to its departure, the same for every pair.
static func issue_lead() -> int:
	return ISSUE_LEAD_TICKS + departure_offset(TaxiTimes.BASE)


static func occurrence_id(contract_id: String, day: int) -> String:
	return "%s-d%d" % [contract_id, day]


## {"contract": id, "day": d} for a canonical occurrence id, else {}.
static func parse_occurrence(id: String) -> Dictionary:
	var found := _occurrence_pattern.search(id)
	if found == null:
		return {}
	return {"contract": found.get_string(1), "day": found.get_string(2).to_int()}


static func starts_for(contract: Dictionary, day: int, epoch: int) -> Array[int]:
	return FlightSim.schedule_starts(
		_first_start(contract, day, epoch), taxi_of(contract), boarding_ticks_of(contract)
	)


## The first day >= 0 whose occurrence's first state is at or after `now`.
## Nothing of that occurrence is due before `now + 1`: its first transition
## comes PHASE_TICKS[0] later, and arrivals are planned after its first state.
static func first_day(contract: Dictionary, now: int, epoch: int) -> int:
	return _day_at_or_after(_first_start(contract, 0, epoch), now)


## The first day, from the contract's first_day on, that is issued at or after
## `opened` (the tick the airport opened): the start of a contract accepted
## while the airport was closed. The days before it are never flown.
static func opening_day(contract: Dictionary, opened: int, epoch: int) -> int:
	if FlightContract.is_charter(contract):
		return FlightContract.one_off_day(contract)
	var issued := _day_at_or_after(issue_tick(contract, 0, epoch), opened)
	return maxi(int(contract["first_day"]), issued)


static func issue_tick(contract: Dictionary, day: int, epoch: int) -> int:
	return GameCalendar.tick_at(day, int(contract["departure_minute"]), epoch) - issue_lead()


## The tick a flight with `starts` is pruned: PRUNE_AFTER_TICKS after it departs.
static func prune_tick(starts: Array) -> int:
	return int(starts[FlightSim.State.DEPARTED]) + PRUNE_AFTER_TICKS


## The first day not yet issued at `now`.
static func next_day(contract: Dictionary, now: int, epoch: int) -> int:
	if FlightContract.is_charter(contract):
		var target := FlightContract.one_off_day(contract)
		return target if now < issue_tick(contract, target, epoch) else target + 1
	var since_first := now - issue_tick(contract, 0, epoch)
	var day := GameCalendar.floor_div(since_first, GameCalendar.TICKS_PER_DAY) + 1
	return maxi(int(contract["first_day"]), day)


## True when two contracts would hold one gate at the same time on some day:
## they share a gate and their gate holds overlap. Repeating contracts repeat
## daily forever; one-off charters (one_off_day >= 0) hold only that single day.
static func contracts_share_gate(a: Dictionary, b: Dictionary) -> bool:
	if a["gate"] != b["gate"]:
		return false
	var a_size: String = a.get("plane_size", PlaneClasses.MEDIUM)
	var b_size: String = b.get("plane_size", PlaneClasses.MEDIUM)
	if FlightContract.is_charter(a) and FlightContract.is_charter(b):
		return shares_gate(
			a["gate"],
			starts_for(a, FlightContract.one_off_day(a), 0),
			b["gate"],
			starts_for(b, FlightContract.one_off_day(b), 0),
			a_size,
			b_size
		)
	if FlightContract.is_charter(a):
		return contract_meets(
			b, a["gate"], starts_for(a, FlightContract.one_off_day(a), 0), 0, a_size
		)
	if FlightContract.is_charter(b):
		return contract_meets(
			a, b["gate"], starts_for(b, FlightContract.one_off_day(b), 0), 0, b_size
		)
	var a_starts := starts_for(a, 0, 0)
	for shift in [-1, 0, 1]:
		if shares_gate(a["gate"], a_starts, b["gate"], starts_for(b, shift, 0), a_size, b_size):
			return true
	return false


## Whether a flight at `gate` with `starts` and `flight_size` would hold the gate
## at the same time as an occurrence of `contract` on a day from its first_day.
## Only the days whose gate hold overlaps the flight's are compared; they form
## one contiguous range, found in closed form from the contract's full
## schedule span (which always encloses gate_hold_span()).
static func contract_meets(
	contract: Dictionary,
	gate: String,
	starts: Array,
	epoch: int,
	flight_size: String = PlaneClasses.MEDIUM
) -> bool:
	var hold := gate_hold_span(starts, flight_size)
	if hold[0] >= hold[1] or contract["gate"] != gate:
		return false
	var c_size: String = contract.get("plane_size", PlaneClasses.MEDIUM)
	if FlightContract.is_charter(contract):
		var c_starts := starts_for(contract, FlightContract.one_off_day(contract), epoch)
		return shares_gate(gate, starts, contract["gate"], c_starts, flight_size, c_size)
	var first := _first_start(contract, 0, epoch)
	var day_size := GameCalendar.TICKS_PER_DAY
	var held := reserved_ticks(taxi_of(contract), c_size, boarding_ticks_of(contract))
	var lowest := GameCalendar.floor_div(hold[0] - first - held, day_size) + 1
	var highest := -GameCalendar.floor_div(first - hold[1], day_size) - 1
	for day in range(maxi(lowest, int(contract["first_day"])), highest + 1):
		if shares_gate(
			gate, starts, contract["gate"], starts_for(contract, day, epoch), flight_size, c_size
		):
			return true
	return false


## Half-open gate-hold interval [start, end) in ticks for a flight with `starts`
## and `plane_size`: small planes hold from AT_STAND (extended back when
## TAXI_IN exceeds TAXI_OUT so incoming/outgoing taxi on any stand clears
## GroundPlanner) to DEPARTED; medium and large planes keep SCHEDULED to DEPARTED.
static func gate_hold_span(starts: Array, plane_size: String = PlaneClasses.MEDIUM) -> Array[int]:
	if plane_size == PlaneClasses.SMALL:
		var taxi := TaxiTimes.of_starts(starts)
		var lead_in := maxi(0, taxi[0] - taxi[1])
		return [
			int(starts[FlightSim.State.AT_STAND]) - lead_in,
			int(starts[FlightSim.State.DEPARTED]),
		]
	return [int(starts[0]), int(starts[FlightSim.State.DEPARTED])]


## Whether two flights hold one gate at the same time, half-open.
static func shares_gate(
	a_gate: String,
	a_starts: Array,
	b_gate: String,
	b_starts: Array,
	a_size: String = PlaneClasses.MEDIUM,
	b_size: String = PlaneClasses.MEDIUM
) -> bool:
	if a_gate != b_gate:
		return false
	var a_hold := gate_hold_span(a_starts, a_size)
	var b_hold := gate_hold_span(b_starts, b_size)
	return holds_overlap(a_hold[0], a_hold[1], b_hold[0], b_hold[1])


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


static func _first_start(contract: Dictionary, day: int, epoch: int) -> int:
	var departure := GameCalendar.tick_at(day, int(contract["departure_minute"]), epoch)
	return departure - departure_offset(taxi_of(contract), boarding_ticks_of(contract))


## The first day >= 0 whose tick, `day0` on day 0 and a day later each day
## after, is at or after `now`.
static func _day_at_or_after(day0: int, now: int) -> int:
	var behind := now - day0
	return maxi(0, -GameCalendar.floor_div(-behind, GameCalendar.TICKS_PER_DAY))


## Ticks an occurrence with taxi pair `taxi` and `plane_size` holds its gate:
## matches gate_hold_span().
static func reserved_ticks(
	taxi: Array = TaxiTimes.BASE, plane_size: String = PlaneClasses.MEDIUM, boarding_ticks: int = -1
) -> int:
	var ticks := TaxiTimes.phase_ticks(taxi)
	if boarding_ticks >= 0:
		ticks[FlightSim.State.BOARDING] = boarding_ticks
	if plane_size == PlaneClasses.SMALL:
		var lead_in := maxi(0, int(taxi[0]) - int(taxi[1]))
		var small_total := lead_in
		for state in range(FlightSim.State.AT_STAND, FlightSim.State.DEPARTED):
			small_total += ticks[state]
		return small_total
	var total := 0
	for phase_ticks in ticks:
		total += phase_ticks
	return total
