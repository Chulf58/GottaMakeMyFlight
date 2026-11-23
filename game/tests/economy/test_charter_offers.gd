class_name TestCharterOffers
extends GdUnitTestSuite
## Same-day one-off charter generation in OfferBoard/OfferDesk: quiet daytime
## gap detection, cutoff/midnight expiration, cooldown/cap, strict snapshot, and
## zero interference with daily offers or SimClock.rng.


func _world(seed_value := 42) -> Dictionary:
	var clock := auto_free(SimClock.new()) as SimClock
	clock.seed_rng(seed_value)
	var flights := auto_free(FlightSim.new()) as FlightSim
	flights.bind_clock(clock)
	flights.open_airport()
	var desk := auto_free(OfferDesk.new()) as OfferDesk
	desk.runway = Runway.new(PlaneClasses.LARGE)
	desk.flights = flights
	desk.bind_clock(clock)
	return {"clock": clock, "flights": flights, "desk": desk}


func _step_tick(clock: SimClock, tick: int) -> void:
	clock.tick = tick
	clock.ticked.emit(tick)


func test_charter_opens_during_quiet_gap_without_touching_offers_or_clock_rng() -> void:
	var w := _world(77)
	var clock: SimClock = w["clock"]
	var flights: FlightSim = w["flights"]
	var desk: OfferDesk = w["desk"]
	var offers_before := desk.board.open_offers()
	var rng_state_before := clock.rng.state

	# Airport opens at 06:00 (tick 0); first charter interval at tick 300 (06:15).
	_step_tick(clock, OfferDesk.CHARTER_CHECK_INTERVAL_TICKS)

	assert_int(clock.rng.state).is_equal(rng_state_before)
	assert_array(desk.board.open_offers()).is_equal(offers_before)
	var charters := desk.board.open_charters()
	assert_array(charters).has_size(1)
	var charter: Dictionary = charters[0]
	assert_str(charter["id"]).starts_with(OfferBoard.CHARTER_PREFIX)
	assert_str(charter["plane_size"]).is_equal(PlaneClasses.SMALL)
	assert_int(int(charter[FlightContract.ONE_OFF_DAY_KEY])).is_equal(0)
	assert_bool(FlightContract.is_charter(charter)).is_true()
	assert_bool(FlightFit.fits(flights, OfferBoard.terms_of(charter))).is_true()
	var min_dep := 15 + OfferBoard.CHARTER_MIN_LEAD_MINUTES + 6 * 60
	assert_int(int(charter["departure_minute"])).is_greater_equal(min_dep)

	# Second check while one is already open does not open a second charter.
	_step_tick(clock, 2 * OfferDesk.CHARTER_CHECK_INTERVAL_TICKS)
	assert_array(desk.board.open_charters()).has_size(1)
	assert_int(clock.rng.state).is_equal(rng_state_before)


func test_charter_does_not_open_when_closed_or_when_gate_has_no_quiet_gap() -> void:
	var clock := auto_free(SimClock.new()) as SimClock
	clock.seed_rng(12)
	var closed_flights := auto_free(FlightSim.new()) as FlightSim
	closed_flights.bind_clock(clock)
	var desk := auto_free(OfferDesk.new()) as OfferDesk
	desk.runway = Runway.new(PlaneClasses.LARGE)
	desk.flights = closed_flights
	desk.bind_clock(clock)
	_step_tick(clock, OfferDesk.CHARTER_CHECK_INTERVAL_TICKS)
	assert_array(desk.board.open_charters()).is_empty()

	# Pack single starter gate tightly all day so no slot has a quiet gap.
	var busy := auto_free(FlightSim.new()) as FlightSim
	busy.open_airport()
	for minute in [420, 555, 690, 825, 960, 1095, 1230]:
		var terms := TestFlightFit.terms("S%d" % minute, minute, PlaneClasses.SMALL)
		assert_bool(busy.accept_contract(terms)).is_true()
	var board := OfferBoard.new()
	var id := board.ensure_charter_for_gap(0, 300, 0, 12, PlaneClasses.LARGE, busy)
	assert_str(id).is_empty()
	assert_array(board.open_charters()).is_empty()


func test_charter_expires_at_cutoff_and_at_midnight_and_respects_gap_cooldown() -> void:
	var w := _world(99)
	var clock: SimClock = w["clock"]
	var desk: OfferDesk = w["desk"]
	_step_tick(clock, OfferDesk.CHARTER_CHECK_INTERVAL_TICKS)
	var charter: Dictionary = desk.board.open_charters()[0]
	var id: String = charter["id"]
	var cutoff := int(charter["cutoff_tick"])

	# At cutoff it stays open; one tick past cutoff it expires.
	_step_tick(clock, cutoff)
	assert_str(desk.board.charter_of(id)["status"]).is_equal(OfferBoard.OPEN)
	_step_tick(clock, cutoff + 1)
	assert_str(desk.board.charter_of(id)["status"]).is_equal(OfferBoard.EXPIRED)
	assert_array(desk.board.open_charters()).is_empty()

	# Midnight rollover also expires any open charter from the previous day.
	var w2 := _world(101)
	var clock2: SimClock = w2["clock"]
	var desk2: OfferDesk = w2["desk"]
	var late_tick := GameCalendar.tick_at(0, 18 * 60, 0) + 1
	_step_tick(clock2, late_tick)
	# Force an evening charter on day 0 and advance directly to day 1 midnight.
	var board2: OfferBoard = desk2.board
	var late_id := board2.ensure_charter_for_gap(
		0, late_tick, 0, 101, PlaneClasses.LARGE, w2["flights"]
	)
	assert_str(late_id).is_not_empty()
	_step_tick(clock2, GameCalendar.day_start(1, 0))
	assert_str(board2.charter_of(late_id)["status"]).is_equal(OfferBoard.EXPIRED)

	# Declined charter cooldown prevents immediate re-generation in the same gap.
	var w3 := _world(55)
	var clock3: SimClock = w3["clock"]
	var desk3: OfferDesk = w3["desk"]
	_step_tick(clock3, OfferDesk.CHARTER_CHECK_INTERVAL_TICKS)
	var first: Dictionary = desk3.board.open_charters()[0]
	var first_min := int(first["departure_minute"])
	assert_bool(desk3.board.decline(first["id"])).is_true()
	_step_tick(clock3, 2 * OfferDesk.CHARTER_CHECK_INTERVAL_TICKS)
	for c in desk3.board.open_charters():
		assert_int(absi(int(c["departure_minute"]) - first_min)).is_greater_equal(
			OfferBoard.CHARTER_COOLDOWN_MINUTES
		)


func test_charter_snapshot_round_trip_and_strict_validation() -> void:
	var w := _world(31)
	_step_tick(w["clock"], OfferDesk.CHARTER_CHECK_INTERVAL_TICKS)
	var board: OfferBoard = w["desk"].board
	var saved := JSON.parse_string(JSON.stringify(board.to_snapshot())) as Dictionary
	var loaded := OfferBoard.new()
	assert_bool(loaded.from_snapshot(saved)).is_true()
	assert_dict(loaded.to_snapshot()).is_equal(board.to_snapshot())
	assert_array(loaded.open_charters()).is_equal(board.open_charters())

	# Reject non-small plane, bad one_off_day, or >1 open charter.
	var bad_size := saved.duplicate(true)
	bad_size["charters"][0]["plane_size"] = PlaneClasses.MEDIUM
	assert_bool(OfferBoard.new().from_snapshot(bad_size)).is_false()

	var bad_day := saved.duplicate(true)
	bad_day["charters"][0][FlightContract.ONE_OFF_DAY_KEY] = 2
	assert_bool(OfferBoard.new().from_snapshot(bad_day)).is_false()

	var two_open := saved.duplicate(true)
	var copy_c: Dictionary = two_open["charters"][0].duplicate(true)
	copy_c["id"] = "CH0N2"
	two_open["charters"].append(copy_c)
	assert_bool(OfferBoard.new().from_snapshot(two_open)).is_false()


func test_overnight_ticks_do_not_open_or_burn_daily_charter_cap() -> void:
	var w := _world(17)
	var clock: SimClock = w["clock"]
	var desk: OfferDesk = w["desk"]
	var flights: FlightSim = w["flights"]
	# Midnight to 05:45 on Day 1 must never open charters or spend MAX_CHARTERS_PER_DAY.
	for minute in [0, 180, 345]:
		var tick := GameCalendar.tick_at(1, minute, clock.epoch)
		assert_int(tick % OfferDesk.CHARTER_CHECK_INTERVAL_TICKS).is_equal(0)
		_step_tick(clock, tick)
		assert_array(desk.board.open_charters()).is_empty()
		assert_int(desk.board.day_charter_count(1)).is_equal(0)
		(
			assert_str(
				desk.board.ensure_charter_for_gap(
					1, tick, clock.epoch, clock.rng.seed, PlaneClasses.LARGE, flights
				)
			)
			. is_empty()
		)
		assert_int(desk.board.day_charter_count(1)).is_equal(0)

	# Morning active hours (06:15 on Day 1) open the first Day 1 charter cleanly.
	_step_tick(clock, GameCalendar.tick_at(1, 375, clock.epoch))
	assert_array(desk.board.open_charters()).has_size(1)
	assert_int(desk.board.day_charter_count(1)).is_equal(1)


func test_two_gates_opens_charter_when_first_gate_is_not_quiet_and_second_is() -> void:
	var sim := auto_free(FlightSim.new()) as FlightSim
	sim.open_airport()
	# Fill Gate C with flights spaced ~135 min apart (never a 300-tick quiet gap margin),
	# then add an empty Gate D and verify charters still open via Gate D.
	for minute in [450, 585, 720, 855, 990, 1125]:
		(
			assert_bool(
				sim.accept_contract(TestFlightFit.terms("C%d" % minute, minute, PlaneClasses.SMALL))
			)
			. is_true()
		)
	var board := OfferBoard.new()
	assert_str(board.ensure_charter_for_gap(0, 300, 0, 77, PlaneClasses.LARGE, sim)).is_empty()
	sim.gate_source = func() -> Array[String]: return ["C", "D"] as Array[String]
	var id := board.ensure_charter_for_gap(0, 300, 0, 77, PlaneClasses.LARGE, sim)
	assert_str(id).is_not_empty()
	var charter := board.charter_of(id)
	assert_bool(FlightFit.fits(sim, OfferBoard.terms_of(charter))).is_true()
