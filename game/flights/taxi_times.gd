class_name TaxiTimes
extends RefCounted
## A contract's taxi pair [TAXI_IN, TAXI_OUT] in ticks, from the length of its
## gate's routes (ruling taxi-time-follows-each-gate-s-route-length-far-side-
## gates-ta; design airside-all-around-technical-design-one-route-source-per-
## con, slice S2). Each phase gets the budget a plane needs to stay at or under
## MovementPlan.MAX_PEAK_SPEED (16 m/s) with the longest pause MovementPlan
## allows: a smoothstep leg peaks at 1.5 times its mean speed, so a route of D
## metres needs 1.5 * D / 0.8 + 160 = 1.875 * D + 160 ticks, rounded up to a
## whole STEP_TICKS. A phase never gets less than BASE, today's times, so every
## stand of the first site keeps exactly 1000 and 920. Pure and static.
##
## The pair is frozen on the contract when its gate is set (FlightContract.
## assigned()), so a flight's schedule never changes under it; FlightTimetable
## reads it from there.
##
## The pair must keep two things that fixed phases kept for free (VALID_IN and
## VALID_OUT): an occurrence is issued at or before its first state (issuing is
## anchored to the departure, FlightTimetable.issue_tick, so a TAXI_IN longer
## than BASE by more than ISSUE_LEAD_TICKS would issue it late), and the quiet
## night stays empty: a 22:00 departure (the latest, Odd hours) has DEPARTED by
## midnight. The first bound also keeps a 06:00 departure's first state after
## midnight, which needs only TAXI_IN <= 5540. No route the north lane can give
## comes near either (test_taxi_times.gd measures the longest).

## Today's times: FlightSim.PHASE_TICKS at TAXI_IN and TAXI_OUT, which a test
## pins. The fewest ticks any taxi phase gets.
const BASE: Array[int] = [1000, 920]
## Budgets are whole multiples of this, as pauses are (MovementPlan).
const STEP_TICKS := 20
## Ticks per metre at the speed cap: 1.5 / MovementPlan.MAX_PEAK_SPEED.
const TICKS_PER_M := 1.875
## The largest TAXI_IN: BASE's plus FlightTimetable.ISSUE_LEAD_TICKS, so issuing
## comes at or before the first state.
const MAX_IN := 3400
## The largest TAXI_OUT: a 22:00 departure's PUSHBACK (120), TAXI_OUT and
## TAKEOFF (200) end by midnight, 2400 ticks later.
const MAX_OUT := 2080


## The pair for routes of `in_m` and `out_m` metres.
static func for_lengths(in_m: float, out_m: float) -> Array[int]:
	var pair: Array[int] = [_budget(in_m, BASE[0]), _budget(out_m, BASE[1])]
	return pair


## The pair for a plane at StandPlacement stand `stand`, from its taxi routes
## (FlightGround.routes(), the same for every plane class), which only the
## stand decides: its sill, its side and a side stand's spur (lane_x, run on
## along the lane from the stub; TaxiRoutes). Routes longer than
## MAX_IN or MAX_OUT allow give a pair problem() refuses: a gate with such a
## stand takes no contract (FlightContract.assignment_problem()), and a save
## whose flight or contract would need it is refused.
static func for_stand(stand: Dictionary) -> Array[int]:
	var routes := FlightGround.routes(stand, PlaneClasses.ORDER[0])
	return for_lengths(
		MovementPlan.path_length(routes[FlightSim.State.TAXI_IN]),
		MovementPlan.path_length(routes[FlightSim.State.TAXI_OUT])
	)


## "" when `value` is a pair of whole ticks, each a whole STEP_TICKS from BASE
## to MAX_IN or MAX_OUT; otherwise what is wrong. JSON whole floats count.
static func problem(value: Variant) -> String:
	if typeof(value) != TYPE_ARRAY or (value as Array).size() != 2:
		return "taxi must be a pair of ticks [in, out]"
	var highest := [MAX_IN, MAX_OUT]
	for i in 2:
		var ticks: Variant = value[i]
		if not WholeNumber.is_whole(ticks) or ticks < BASE[i] or ticks > highest[i]:
			return "taxi ticks must be whole numbers from %s to %s" % [BASE, highest]
		if int(ticks) % STEP_TICKS != 0:
			return "taxi ticks must be whole multiples of %d" % STEP_TICKS
	return ""


## A read-only copy of a valid pair, as ints.
static func frozen(pair: Array) -> Array[int]:
	var out: Array[int] = [int(pair[0]), int(pair[1])]
	out.make_read_only()
	return out


## FlightSim.PHASE_TICKS with `pair`'s TAXI_IN and TAXI_OUT.
static func phase_ticks(pair: Array) -> Array[int]:
	var ticks: Array[int] = FlightSim.PHASE_TICKS.duplicate()
	ticks[FlightSim.State.TAXI_IN] = int(pair[0])
	ticks[FlightSim.State.TAXI_OUT] = int(pair[1])
	return ticks


## The pair a flight with `starts` (FlightSim.STATE_COUNT ticks) flies.
static func of_starts(starts: Array) -> Array[int]:
	var pair: Array[int] = [
		int(starts[FlightSim.State.AT_STAND]) - int(starts[FlightSim.State.TAXI_IN]),
		int(starts[FlightSim.State.TAKEOFF]) - int(starts[FlightSim.State.TAXI_OUT]),
	]
	return pair


## Whether pair `a` gives each phase at least the ticks of pair `b`.
static func covers(a: Array, b: Array) -> bool:
	return int(a[0]) >= int(b[0]) and int(a[1]) >= int(b[1])


## The ticks a phase over `metres` needs, never fewer than `least`.
static func _budget(metres: float, least: int) -> int:
	var ticks := TICKS_PER_M * metres + float(MovementPlan.MAX_PAUSE_TICKS)
	var steps := ceili(ticks / STEP_TICKS)
	return maxi(least, steps * STEP_TICKS)
