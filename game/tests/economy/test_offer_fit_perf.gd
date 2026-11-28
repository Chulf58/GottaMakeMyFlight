class_name TestOfferFitPerf
extends GdUnitTestSuite
## Regression suite for build-mode speed-change / QuietNight midnight rollover
## freeze and OfferBoard._fit / OfferDesk._try_refill quadratic trial cost.


class CountingFlightSim:
	extends FlightSim
	var trial_calls := 0

	func trial_assignment(
		terms: Dictionary, before: Array = [], ignore_gate_overlap := false, only_gate := ""
	) -> Dictionary:
		trial_calls += 1
		return super.trial_assignment(terms, before, ignore_gate_overlap, only_gate)

	func trial_pair_fits(
		first_terms: Dictionary, first_gate: String, second_terms: Dictionary, second_gate: String
	) -> bool:
		trial_calls += 2
		return super.trial_pair_fits(first_terms, first_gate, second_terms, second_gate)


func _terms(id: String, minute: int, size := PlaneClasses.SMALL) -> Dictionary:
	return {
		"id": id,
		"airline": "SunHop",
		"destination": "Paris",
		"departure_minute": minute,
		"plane_size": size,
		"booked_passengers": 6 if size == PlaneClasses.SMALL else 40,
		"fee_per_passenger": 20,
		FlightContract.TRAITS_KEY: {},
	}


func test_offer_board_tight_gap_bounds_trial_assignment_calls() -> void:
	var sim := auto_free(CountingFlightSim.new()) as CountingFlightSim
	sim.gate_source = func() -> Array[String]: return ["C"] as Array[String]
	sim.open_airport()
	for minute in [675, 810, 945, 1080, 1215]:
		assert_bool(sim.accept_contract(_terms("C%d" % minute, minute))).is_true()

	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var board := OfferBoard.new()
	sim.trial_calls = 0
	var t0 := Time.get_ticks_usec()
	board.ensure_day(0, rng, 2, PlaneClasses.LARGE, sim)
	var ensure_ms := (Time.get_ticks_usec() - t0) / 1000.0
	var ensure_calls := sim.trial_calls

	sim.trial_calls = 0
	var t1 := Time.get_ticks_usec()
	board.refill_day(0, 1, 2, PlaneClasses.LARGE, sim, {}, 420)
	var refill_ms := (Time.get_ticks_usec() - t1) / 1000.0
	var refill_calls := sim.trial_calls

	print(
		(
			"PERF tight-gap ensure_day: %d calls (%.1f ms), refill_day: %d calls (%.1f ms)"
			% [ensure_calls, ensure_ms, refill_calls, refill_ms]
		)
	)
	# Three distinct offered classes at Tier 2 on a Large runway (small, medium,
	# large) need up to 3 * 57 base assessments plus another_gate_helps checks
	# (~219 calls total), still bounded linearly and far below quadratic pairing.
	assert_int(ensure_calls).is_less_equal(240)
	assert_int(refill_calls).is_less_equal(240)


func test_offer_board_refill_day_bounds_trial_calls() -> void:
	var clock := auto_free(SimClock.new()) as SimClock
	clock.seed_rng(42)
	var sim := auto_free(CountingFlightSim.new()) as CountingFlightSim
	sim.gate_source = func() -> Array[String]: return ["C"] as Array[String]
	sim.open_airport()
	for minute in [420, 555, 690, 825, 960, 1095]:
		assert_bool(sim.accept_contract(_terms("S%d" % minute, minute))).is_true()
	var desk := auto_free(OfferDesk.new()) as OfferDesk
	desk.runway = Runway.new(PlaneClasses.LARGE)
	desk.flights = sim
	desk.bind_clock(clock)
	sim.trial_calls = 0
	var t0 := Time.get_ticks_usec()
	desk.board.refill_day(0, clock.rng.seed, 0, PlaneClasses.LARGE, sim, {}, 420)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	print("PERF refill_day: %d calls (%.1f ms)" % [sim.trial_calls, ms])
	assert_int(desk.board.day_offer_count(0)).is_equal(2 * OfferBoard.OFFERS_PER_DAY)
	# With FIT_OFFERS := 3, the 3rd offer also checks distinct co-fit (~175 calls).
	assert_int(sim.trial_calls).is_less_equal(200)


func test_speed_change_in_build_mode_across_quiet_night_rollover_stays_under_budget() -> void:
	var clock := auto_free(SimClock.new()) as SimClock
	clock.seed_rng(1)
	var flights := auto_free(FlightSim.new()) as FlightSim
	flights.gate_source = func() -> Array[String]: return ["C", "D"] as Array[String]
	flights.bind_clock(clock)
	flights.open_airport()
	for idx in 6:
		var m: int = [450, 480, 750, 780, 1050, 1080][idx]
		assert_bool(flights.accept_contract(_terms("K%d" % idx, m, PlaneClasses.MEDIUM))).is_true()

	var passengers := auto_free(PassengerSim.new()) as PassengerSim
	var quiet := auto_free(QuietNight.new()) as QuietNight
	quiet.bind(clock, flights, passengers)

	var desk := auto_free(OfferDesk.new()) as OfferDesk
	desk.runway = Runway.new(PlaneClasses.LARGE)
	desk.flights = flights
	desk.bind_clock(clock)

	var session := auto_free(BuildSession.new()) as BuildSession
	session.clock = clock
	add_child(session)
	session.set_building(true)
	assert_bool(clock.paused).is_true()

	var midnight := GameCalendar.day_start(1, clock.epoch)
	clock.tick = midnight - 80
	flights.tick = clock.tick
	clock.set_speed(3)
	session.sync()
	assert_bool(clock.paused).is_false()
	assert_bool(session.active).is_true()
	assert_bool(quiet.is_quiet()).is_true()

	var max_frame_ms := 0.0
	for _frame in 10:
		var t0 := Time.get_ticks_usec()
		clock.advance(1.0 / 60.0)
		max_frame_ms = maxf(max_frame_ms, (Time.get_ticks_usec() - t0) / 1000.0)
		if GameCalendar.day_of(clock.tick, clock.epoch) >= 1:
			break

	print("PERF QuietNight build-mode speed-change rollover max_frame_ms=%.1f ms" % max_frame_ms)
	assert_int(GameCalendar.day_of(clock.tick, clock.epoch)).is_greater_equal(1)
	assert_array(desk.board.open_offers()).has_size(OfferBoard.OFFERS_PER_DAY)
	assert_float(max_frame_ms).is_less(700.0)
