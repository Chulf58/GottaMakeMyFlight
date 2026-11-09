class_name TestRunwayWorksPlan
extends GdUnitTestSuite
## Where runway works go in the timetable and what they do to it (Runway R9;
## ruling runway-upgrade-works-wait-for-a-timetable-gap-passengers-per-plane-
## class, design section 7): the first gap long enough is verified against the
## day's bookings, then protected as a fixed booking, so an offer that would
## use the runway during the works is refused and no plane already planned
## changes. While the airport is closed nothing flies, so the works apply at
## once.

## Departs 08:30 on day 0: its arrival uses the runway at about 06:20.
const EARLY_MINUTE := 8 * 60 + 30

var _sim: FlightSim


func before_test() -> void:
	_sim = _open_sim()


## A small-runway sim with two gates, so two flights arriving close together
## do not clash at the gate: any refusal in these cases is the runway's.
func _open_sim() -> FlightSim:
	var sim := auto_free(FlightSim.new()) as FlightSim
	sim.runway.size = PlaneClasses.SMALL
	sim.gate_source = func() -> Array[String]: return ["C", "D"]
	sim.open_airport()
	return sim


func _terms(id: String, minute: int) -> Dictionary:
	var terms := TestFlightContracts.terms(id, minute)
	terms["plane_size"] = PlaneClasses.SMALL
	terms["booked_passengers"] = PlaneClasses.passenger_range(PlaneClasses.SMALL)[0]
	return terms


## The runway-block bookings of day `day`'s plan, from the sim's own planner.
func _runway_bookings(day: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var block := GroundPlanner.runway_rect(PlaneClasses.LARGE)
	var plans: Dictionary = _sim._day_plan(day)
	for id: String in plans:
		for booking: Dictionary in plans[id]["bookings"]:
			if (booking["rect"] as Rect2).intersects(block):
				out.append(booking)
	return out


func test_with_nothing_booked_the_works_start_at_once() -> void:
	assert_int(_sim.works_start(PlaneClasses.MEDIUM)).is_equal(_sim.tick)


## The runway is busy with the morning arrival, so the works start where its
## runway booking ends, and the whole stretch is clear of every booking.
func test_the_gap_is_verified_long_enough() -> void:
	assert_bool(_sim.accept_contract(_terms("A", EARLY_MINUTE))).is_true()
	var busy := _runway_bookings(0)
	assert_array(busy).is_not_empty()
	var busy_from := float(busy[0]["from"])
	for booking in busy:
		busy_from = minf(busy_from, booking["from"])
	assert_bool(busy_from < 1200.0).override_failure_message("arrival at %f" % busy_from).is_true()
	var start := _sim.works_start(PlaneClasses.MEDIUM)
	print("works start %d, first runway booking from %.1f" % [start, busy_from])
	assert_int(start).is_greater(0)
	var works := GroundPlanner.works_booking(start, 1200.0)
	for booking in busy:
		assert_bool(GroundPlanner.clash(booking, works)).is_false()
	# Control: starting one tick earlier would meet a booking.
	var early := GroundPlanner.works_booking(start - 1.0, 1200.0)
	var meets := false
	for booking in busy:
		meets = meets or GroundPlanner.clash(booking, early)
	assert_bool(meets).is_true()
	# A large upgrade needs twice the stretch.
	var large := _sim.works_start(PlaneClasses.LARGE)
	var large_works := GroundPlanner.works_booking(large, 2400.0)
	for booking in busy:
		assert_bool(GroundPlanner.clash(booking, large_works)).is_false()


## Protected: an offer whose arrival lands in the booked works is refused with
## the taxi-busy text, where the same offer is taken without them.
func test_clashing_offers_are_refused_during_the_works() -> void:
	assert_bool(_sim.accept_contract(_terms("A", EARLY_MINUTE))).is_true()
	assert_bool(_sim.start_works(PlaneClasses.MEDIUM)).is_true()
	var works := _sim.runway.works
	var middle := (works.start + works.finish) / 2
	var minute := GameCalendar.minute_of_day(middle + FlightTimetable.departure_offset())
	var clash := _terms("B", minute)
	var problem := _sim.accept_problem(clash)
	print("offer arriving mid-works (%d): '%s'" % [middle, problem])
	assert_str(problem).is_equal(FlightSim.TAXI_BUSY_TEXT)
	assert_array(_sim.contract_ids()).is_equal(["A"])
	# Control: without the works the same offer is taken.
	var other := _open_sim()
	assert_bool(other.accept_contract(_terms("A", EARLY_MINUTE))).is_true()
	assert_str(other.accept_problem(clash)).is_empty()


func test_booking_the_works_changes_no_plane_already_planned() -> void:
	assert_bool(_sim.accept_contract(_terms("A", EARLY_MINUTE))).is_true()
	assert_bool(_sim.accept_contract(_terms("C", EARLY_MINUTE + 240))).is_true()
	var before := {}
	for id in _sim.flight_ids():
		before[id] = _sim.taxi_plan(id)
	assert_bool(_sim.start_works(PlaneClasses.MEDIUM)).is_true()
	assert_array(before.keys()).is_not_empty()
	for id: String in before:
		assert_dict(_sim.taxi_plan(id)).is_equal(before[id])


func test_the_size_switches_when_the_works_end_and_not_before() -> void:
	assert_bool(_sim.start_works(PlaneClasses.MEDIUM)).is_true()
	var finish := _sim.runway.works.finish
	var medium := _terms("M", 12 * 60)
	medium["plane_size"] = PlaneClasses.MEDIUM
	medium["booked_passengers"] = PlaneClasses.passenger_range(PlaneClasses.MEDIUM)[0]
	_sim.on_tick(finish - 1)
	assert_str(_sim.runway.size).is_equal(PlaneClasses.SMALL)
	assert_str(_sim.accept_problem(medium)).is_equal("the runway is too short for a medium plane")
	_sim.on_tick(finish)
	assert_str(_sim.runway.size).is_equal(PlaneClasses.MEDIUM)
	assert_str(_sim.accept_problem(medium)).is_empty()
	assert_bool(_sim.runway.works.scheduled()).is_false()


## Nothing flies while the airport is closed, so the works apply at once: the
## size changes on the spot and no works are booked.
func test_the_works_apply_at_once_while_the_airport_is_closed() -> void:
	var closed := auto_free(FlightSim.new()) as FlightSim
	closed.runway.size = PlaneClasses.SMALL
	assert_int(closed.opened_tick).is_equal(-1)
	assert_int(closed.works_start(PlaneClasses.MEDIUM)).is_equal(closed.tick)
	assert_bool(closed.start_works(PlaneClasses.MEDIUM)).is_true()
	assert_str(closed.runway.size).is_equal(PlaneClasses.MEDIUM)
	assert_bool(closed.runway.works.scheduled()).is_false()
	assert_int(closed.runway.works.fixed_bookings().size()).is_equal(0)


func test_works_that_do_not_grow_the_runway_are_refused() -> void:
	var refuse := func() -> void: assert_bool(_sim.start_works(PlaneClasses.SMALL)).is_false()
	assert_error(refuse).is_push_error(
		"FlightSim.start_works: the runway is small and the works build small"
	)
	assert_bool(_sim.runway.works.scheduled()).is_false()
