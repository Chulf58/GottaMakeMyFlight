class_name TestArrivalsFlightSim
extends GdUnitTestSuite
## Arrivals Slice A1: FlightSim DEBOARDING timing, PUSHBACK departure anchor
## invariance across small/medium/large/charter contracts, deterministic
## arriving_passengers manifest, and deboarding_started signal.


func test_deboarding_phase_lengths_and_at_stand_shortening() -> void:
	assert_int(FlightSim.PHASE_TICKS[FlightSim.State.AT_STAND]).is_equal(20)
	assert_int(FlightSim.PHASE_TICKS[FlightSim.State.DEBOARDING]).is_equal(100)
	assert_int(FlightSim.LARGE_DEBOARDING_TICKS).is_equal(160)
	assert_int(FlightSim.CHARTER_DEBOARDING_TICKS).is_equal(60)
	assert_int(FlightSim.PHASE_TICKS[FlightSim.State.BOARDING]).is_equal(1200)
	assert_int(FlightSim.CHARTER_BOARDING_TICKS).is_equal(380)

	var starts := FlightSim.schedule_starts(0)
	assert_int(starts.size()).is_equal(FlightSim.STATE_COUNT)
	assert_int(starts[FlightSim.State.DEBOARDING] - starts[FlightSim.State.AT_STAND]).is_equal(20)
	assert_int(starts[FlightSim.State.BOARDING] - starts[FlightSim.State.DEBOARDING]).is_equal(100)
	assert_int(starts[FlightSim.State.PUSHBACK]).is_equal(2740)


func test_pushback_departure_stays_anchored_for_every_contract_class() -> void:
	var minute := 720
	var expected_pushback := GameCalendar.tick_at(0, minute, 0)
	var sizes := [PlaneClasses.SMALL, PlaneClasses.MEDIUM, PlaneClasses.LARGE]
	for size: String in sizes:
		var contract := TestFlightContracts.terms("C_%s" % size, minute)
		contract["plane_size"] = size
		contract["first_day"] = 0
		contract[FlightContract.TAXI_KEY] = TaxiTimes.BASE
		var starts := FlightTimetable.starts_for(contract, 0, 0)
		assert_int(starts[FlightSim.State.PUSHBACK]).is_equal(expected_pushback)
		var expected_deboard := 160 if size == PlaneClasses.LARGE else 100
		assert_int(starts[FlightSim.State.BOARDING] - starts[FlightSim.State.DEBOARDING]).is_equal(
			expected_deboard
		)
		(
			assert_int(starts[FlightSim.State.DOORS_CLOSED] - starts[FlightSim.State.BOARDING])
			. is_equal(1200)
		)

	var charter := TestFlightContracts.terms("CH", minute)
	charter["plane_size"] = PlaneClasses.SMALL
	charter["booked_passengers"] = 8
	charter["first_day"] = 0
	charter[FlightContract.TAXI_KEY] = TaxiTimes.BASE
	charter[FlightContract.ONE_OFF_DAY_KEY] = 0
	var c_starts := FlightTimetable.starts_for(charter, 0, 0)
	assert_int(c_starts[FlightSim.State.PUSHBACK]).is_equal(expected_pushback)
	assert_int(c_starts[FlightSim.State.BOARDING] - c_starts[FlightSim.State.DEBOARDING]).is_equal(
		60
	)
	(
		assert_int(c_starts[FlightSim.State.DOORS_CLOSED] - c_starts[FlightSim.State.BOARDING])
		. is_equal(380)
	)


func test_arriving_passengers_are_deterministic_and_starter_shows_six_to_ten() -> void:
	var starter := FlightSim.STARTER_TERMS.duplicate()
	starter["departure_minute"] = 600
	var starter_d0 := FlightTimetable.arriving_passengers_for(starter, 0, "GMF101-d0")
	assert_int(starter_d0).is_between(6, 10)
	assert_int(FlightTimetable.arriving_passengers_for(starter, 0, "GMF101-d0")).is_equal(
		starter_d0
	)

	for i in 12:
		var contract := TestFlightContracts.terms("DET%d" % i, 600)
		contract["booked_passengers"] = 20 + i * 3
		var occ := FlightTimetable.occurrence_id("DET%d" % i, i % 4)
		var count_a := FlightTimetable.arriving_passengers_for(contract, i % 4, occ)
		var count_b := FlightTimetable.arriving_passengers_for(contract, i % 4, occ)
		assert_int(count_a).is_equal(count_b)
		var min_expected := roundi(float(contract["booked_passengers"]) * 0.6)
		var max_expected := roundi(float(contract["booked_passengers"]) * 0.9)
		assert_int(count_a).is_between(min_expected, max_expected)


func test_deboarding_started_signal_emits_with_flight_id_and_manifest_count() -> void:
	var clock := auto_free(SimClock.new()) as SimClock
	var flights := auto_free(FlightSim.new()) as FlightSim
	flights.bind_clock(clock)
	flights.open_airport()
	var seen := []
	flights.deboarding_started.connect(
		func(flight_id: String, count: int) -> void: seen.append({"id": flight_id, "count": count})
	)
	var terms := TestFlightContracts.terms("ARR1", 600)
	terms["booked_passengers"] = 30
	assert_bool(flights.accept_contract(terms)).is_true()
	var occ_id := FlightTimetable.occurrence_id("ARR1", 0)
	var deboard_tick := flights.state_start(occ_id, FlightSim.State.DEBOARDING)
	var expected := FlightTimetable.arriving_passengers_for(flights.contract_of("ARR1"), 0, occ_id)
	assert_int(flights.arriving_passengers_of(occ_id)).is_equal(expected)

	for t in range(1, deboard_tick + 1):
		clock.advance(SimClock.STEP)
	assert_int(flights.state_of(occ_id)).is_equal(FlightSim.State.DEBOARDING)
	assert_int(seen.size()).is_equal(1)
	assert_str(seen[0]["id"]).is_equal(occ_id)
	assert_int(int(seen[0]["count"])).is_equal(expected)
