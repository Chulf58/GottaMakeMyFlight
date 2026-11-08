class_name TestGroundPlannerOrder
extends GdUnitTestSuite
## GroundPlanner.plan_all() (decision runway-and-taxi-technical-design-
## movement-plan-analytic-bookings-planned-pauses, section 6): flights planned
## in order of first start tick, no pause first, then the shortest pause at the
## earliest hold line; TAXI_BUSY when nothing fits; issued flights' plans kept
## through accept, reassign, end and works; a restart each quiet night.

## Medium stands on one row, west to east.
const WEST := Vector2i(10, 60)
const MID := Vector2i(43, 60)
const EAST := Vector2i(80, 60)
## A departs MID at 10:00 on day 1.
const A_MINUTE := 600

var _kit: GroundPlannerKit
## [A, B, B's departure minute]: B, arriving at WEST later, needs a pause to
## pass A taxiing out from MID. Found once in before().
var _pair: Array = []


func before() -> void:
	_kit = GroundPlannerKit.new()
	_pair = _paused_pair()


func _req(id: String, cell: Vector2i, minute: int, day := 1) -> Dictionary:
	return _kit.request(id, PlaneClasses.MEDIUM, _kit.stand(cell), day, minute)


static func _paused(result: Dictionary) -> bool:
	for pause: Dictionary in result["pauses"].values():
		if not pause.is_empty():
			return true
	return false


## B's departure minute is searched from 115 to 175 minutes after A's, where
## B's arrival taxi meets A's departure taxi on the lane.
func _paused_pair() -> Array:
	var a := _req("A", MID, A_MINUTE)
	for minute in range(A_MINUTE + 115, A_MINUTE + 176):
		var b := _req("B", WEST, minute)
		var result := _kit.planner().plan_all([a, b])
		if result["B"]["ok"] and _paused(result["B"]):
			return [a, b, minute]
	return []


func test_the_pause_is_the_first_option_that_fits_and_no_pause_comes_first() -> void:
	assert_array(_pair).is_not_empty()
	var a: Dictionary = _pair[0]
	var b: Dictionary = _pair[1]
	var result := _kit.planner().plan_all([a, b])
	print(
		"B departs minute %d: A %s, B %s" % [_pair[2], result["A"]["pauses"], result["B"]["pauses"]]
	)
	# A comes first in time and flies with no pause.
	assert_bool(_paused(result["A"])).is_false()
	# Against A alone, each of B's phases takes its first option that fits;
	# the paused phase's no-pause option does not.
	var held := _kit.planner()
	held.plan_all([a])
	var skipped := 0
	for state in GroundPlanner.TAXI_STATES:
		var options := held.phase_options(b, state)
		var first_fit := -1
		for i in options.size():
			if held.fits(GroundPlanner.phase_bookings(b, state, options[i])):
				first_fit = i
				break
		assert_int(first_fit).is_greater_equal(0)
		assert_dict(result["B"]["pauses"][state]).is_equal(options[first_fit])
		skipped += first_fit
	assert_int(skipped).is_greater(0)
	# The plans never clash with each other.
	for one: Dictionary in result["A"]["bookings"]:
		for other: Dictionary in result["B"]["bookings"]:
			assert_bool(GroundPlanner.clash(one, other)).is_false()
	# Control: B with no pauses at all clashes with A.
	var flat: Array[Dictionary] = GroundPlanner.fixed_bookings(b)
	for state in GroundPlanner.TAXI_STATES:
		flat.append_array(GroundPlanner.phase_bookings(b, state, {}))
	assert_bool(held.fits(flat)).is_false()
	# The paused plan is covered at every half tick too.
	var sampled := GroundPlannerKit.sample(b, result["B"]["pauses"])
	print("B paused plan sampled: %s" % [sampled])
	assert_int(sampled["samples"]).is_greater(4000)
	assert_int(sampled["uncovered"]).is_equal(0)


func test_taxi_busy_when_nothing_fits() -> void:
	assert_str(GroundPlanner.TAXI_BUSY_TEXT).is_equal("taxi lane busy at that time")
	var planner := _kit.planner()
	# Same times at another gate: both on the runway at once.
	var other := planner.plan_all([_req("A", MID, A_MINUTE), _req("B", WEST, A_MINUTE)])
	assert_bool(other["A"]["ok"]).is_true()
	assert_bool(other["B"]["ok"]).is_false()
	assert_str(other["B"]["reason"]).is_equal(GroundPlanner.TAXI_BUSY)
	# A refused flight books nothing.
	assert_int(planner.bookings().size()).is_equal(other["A"]["bookings"].size())
	# At one gate two minutes later: the parked planes overlap.
	var same := planner.plan_all([_req("A", MID, A_MINUTE), _req("B", MID, A_MINUTE + 2)])
	assert_str(same["B"]["reason"]).is_equal(GroundPlanner.TAXI_BUSY)
	# Control: four hours later at the same gate it fits with no pause (three
	# hours later its approach would meet A's takeoff on the runway).
	var later := planner.plan_all([_req("A", MID, A_MINUTE), _req("B", MID, A_MINUTE + 240)])
	assert_bool(later["B"]["ok"]).is_true()
	assert_bool(_paused(later["B"])).is_false()


## Issued flights (A and the paused B) start before every unissued one, so
## accepting, reassigning, ending and placing works change none of their plans.
func test_issued_plans_are_unchanged_by_accept_reassign_end_and_works() -> void:
	assert_array(_pair).is_not_empty()
	var issued: Array = [_pair[0], _pair[1]]
	var waiting: Array = [_req("C", EAST, 940), _req("D", WEST, 1000), _req("E", MID, 1200)]
	var planner := _kit.planner()
	var base := planner.plan_all(issued + waiting)
	for id in ["A", "B", "C", "D", "E"]:
		assert_bool(base[id]["ok"]).override_failure_message(id).is_true()
	assert_bool(_paused(base["B"])).is_true()
	var cutoff := float(waiting[0]["starts"][0])
	var gap := planner.works_gap(cutoff, 1200.0)
	print("works gap from %.1f: %.1f" % [cutoff, gap])
	var works := GroundPlanner.works_booking(gap, 1200.0)
	var accepted := waiting + [_req("F", EAST, 1010), _req("G", MID, 1130)]
	var reassigned := waiting.duplicate()
	reassigned[1] = _req("D", EAST, 1000)
	var ended := waiting.slice(0, 2)
	var variants := {
		"accept": [issued + accepted, []],
		"reassign": [issued + reassigned, []],
		"end": [issued + ended, []],
		"works": [issued + waiting, [works]],
		"all":
		[issued + accepted.slice(0, 1) + reassigned.slice(1, 2) + [_req("F", EAST, 1010)], [works]],
	}
	for name: String in variants:
		var again := planner.plan_all(variants[name][0], variants[name][1])
		for flight: Dictionary in issued:
			(
				assert_dict(again[flight["id"]])
				. override_failure_message("%s changed %s" % [name, flight["id"]])
				. is_equal(base[flight["id"]])
			)
		for booking in planner.bookings():
			if booking["flight"] and not variants[name][1].is_empty():
				assert_bool(GroundPlanner.clash(booking, works)).is_false()
	# Control: a flight that comes before an issued one in time order (B's
	# twin, ordered first by its id) changes that one's plan.
	var twin := _req("AB", WEST, _pair[2])
	var broken := planner.plan_all(issued + [twin] + waiting)
	assert_bool(broken["AB"]["ok"]).is_true()
	assert_dict(broken["B"]).is_not_equal(base["B"])


func test_works_gap_is_the_first_clear_stretch_of_runway() -> void:
	var planner := _kit.planner()
	var flights := planner.plan_all([_req("A", MID, A_MINUTE), _req("B", MID, A_MINUTE + 240)])
	assert_bool(flights["B"]["ok"]).is_true()
	var after := float(flights["A"]["bookings"][0]["from"]) - 5000.0
	var ticks := 1200.0
	# Before every booking the runway is clear at once.
	assert_float(planner.works_gap(after, ticks)).is_equal(after)
	# From the first runway booking on, works start where some booking ends.
	var start := float(_req("A", MID, A_MINUTE)["starts"][FlightSim.State.APPROACH])
	var gap := planner.works_gap(start, ticks)
	print("works from %.1f: %.1f" % [start, gap])
	assert_float(gap).is_greater(start)
	var works := GroundPlanner.works_booking(gap, ticks)
	var ends_at_gap := false
	for booking in planner.bookings():
		assert_bool(GroundPlanner.clash(booking, works)).is_false()
		ends_at_gap = ends_at_gap or is_equal_approx(booking["to"], gap)
	assert_bool(ends_at_gap).is_true()


## Works belong to no flight: a flight whose id is the works' owner name still
## clashes with them (Sol review). Control: the same flight with another id.
func test_works_clash_with_a_flight_of_any_id() -> void:
	var works_from := float(_req("A", MID, A_MINUTE)["starts"][0])
	var works := GroundPlanner.works_booking(works_from, 6000.0)
	for id in [GroundPlanner.WORKS_OWNER, "A"]:
		var result := _kit.planner().plan_all([_req(id, MID, A_MINUTE)], [works])
		print("flight %s during works: %s" % [id, result[id]["reason"]])
		assert_bool(result[id]["ok"]).is_false()
		assert_str(result[id]["reason"]).is_equal(GroundPlanner.TAXI_BUSY)
	var after := _kit.planner().plan_all([_req(GroundPlanner.WORKS_OWNER, MID, 900)], [works])
	assert_bool(after[GroundPlanner.WORKS_OWNER]["ok"]).is_true()


## A taxi route with a segment off the axes is refused loudly, never booked
## (Sol review: the slices would sit on the segment's start).
func test_a_route_off_the_axes_is_refused() -> void:
	var req := _req("D", MID, A_MINUTE)
	var route: PackedVector3Array = req["routes"][FlightSim.State.TAXI_IN]
	assert_bool(GroundPlanner.axis_aligned(route)).is_true()
	route[1] += Vector3(5.0, 0.0, 0.0)
	req["routes"][FlightSim.State.TAXI_IN] = route
	assert_bool(GroundPlanner.axis_aligned(route)).is_false()
	var planner := _kit.planner()
	var out := [{}]
	(
		assert_error(func() -> void: out[0] = planner.plan_all([req]))
		. is_push_error("GroundPlanner: D's state 3 route has a segment off the axes")
	)
	assert_str(out[0]["D"]["reason"]).is_equal(GroundPlanner.BAD_ROUTE)
	assert_array(planner.bookings()).is_empty()
	var booked := [[1]]
	(
		assert_error(
			func() -> void: booked[0] = GroundPlanner.phase_bookings(req, FlightSim.State.TAXI_IN)
		)
		. is_push_error("GroundPlanner.phase_bookings: a route off the axes cannot be booked")
	)
	assert_array(booked[0]).is_empty()


## How long planning takes under a week's load: 2 gates with a departure every
## 2 hours from 07:00 to 21:00 (8 a day each), 7 days, then the same plus one
## new offer, as R7 re-plans per offer. Printed, with a loose bound so a
## return to quadratic work shows.
func test_planning_time_for_a_week_of_two_gates() -> void:
	var flights: Array = []
	for day in range(1, 8):
		for slot in 8:
			flights.append(_req("W%d_%d" % [day, slot], WEST, 420 + 120 * slot, day))
			flights.append(_req("E%d_%d" % [day, slot], EAST, 480 + 120 * slot, day))
	var planner := _kit.planner()
	var began := Time.get_ticks_usec()
	var week := planner.plan_all(flights)
	var first_ms := (Time.get_ticks_usec() - began) / 1000.0
	var planned := 0
	for id: String in week:
		planned += 1 if week[id]["ok"] else 0
	began = Time.get_ticks_usec()
	var offered := planner.plan_all(flights + [_req("NEW", MID, 750, 4)])
	var offer_ms := (Time.get_ticks_usec() - began) / 1000.0
	print(
		(
			"week: %d flights, %d planned, %d bookings, %.0f ms; with one offer: %.0f ms (%s)"
			% [
				flights.size(),
				planned,
				planner.bookings().size(),
				first_ms,
				offer_ms,
				offered["NEW"]["reason"] if not offered["NEW"]["ok"] else "fits"
			]
		)
	)
	assert_int(planned).is_greater(0)
	assert_float(offer_ms).is_less(20000.0)


## Departures 07:00 to 21:00 leave every night from 22:02 to 04:52 free, so the
## planner restarts there (and wherever else nothing is held) and a day planned
## alone is planned as with the day before it. A departure outside the day is
## refused.
func test_the_planner_restarts_each_quiet_night() -> void:
	assert_int(GroundPlanner.FIRST_DEPARTURE_MINUTE).is_equal(OfferBoard.DEPARTURE_FIRST_MINUTE)
	assert_int(GroundPlanner.LAST_DEPARTURE_MINUTE).is_equal(OfferBoard.DEPARTURE_LAST_MINUTE)
	var days := {}
	for day in [1, 2]:
		days[day] = [
			_req("M%d" % day, MID, 420, day),
			_req("W%d" % day, WEST, 720, day),
			_req("E%d" % day, EAST, 1260, day),
		]
	var planner := _kit.planner()
	var both := planner.plan_all(days[1] + days[2])
	# A restart at every stretch with nothing held: two inside each day (the
	# flights are hours apart) and the night between.
	assert_int(planner.restarts).is_equal(5)
	var spans := {}
	for day: int in days:
		var low := INF
		var high := -INF
		for flight: Dictionary in days[day]:
			var result: Dictionary = both[flight["id"]]
			assert_bool(result["ok"]).is_true()
			for booking: Dictionary in result["bookings"]:
				low = minf(low, booking["from"])
				high = maxf(high, booking["to"])
		spans[day] = Vector2(low, high)
		var first_allowed := GameCalendar.tick_at(day, 420) - 2560
		var last_allowed := GameCalendar.tick_at(day, 1260) + 1240
		assert_float(low).is_greater_equal(first_allowed)
		assert_float(high).is_less_equal(last_allowed)
	var quiet: float = spans[2].x - spans[1].y
	print("day spans %s; quiet stretch %.0f ticks (%.0f minutes)" % [spans, quiet, quiet / 20.0])
	assert_float(quiet).is_equal(410.0 * GameCalendar.TICKS_PER_MINUTE)
	var alone := _kit.planner().plan_all(days[2])
	for flight: Dictionary in days[2]:
		assert_dict(alone[flight["id"]]).is_equal(both[flight["id"]])
	# A departure outside 07:00 to 21:00 is refused and books nothing.
	var outside := _kit.planner()
	var refused := outside.plan_all([_req("N", MID, 405), _req("L", WEST, 1275)])
	for id in ["N", "L"]:
		assert_bool(refused[id]["ok"]).is_false()
		assert_str(refused[id]["reason"]).is_equal(GroundPlanner.QUIET_NIGHT)
	assert_array(outside.bookings()).is_empty()
