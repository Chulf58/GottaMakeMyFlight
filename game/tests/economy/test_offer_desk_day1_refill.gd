class_name TestOfferDeskDay1Refill
extends GdUnitTestSuite
## Day-1 post-opening offer fitting and mid-day offer refills (ruling d97c94bd,
## preserving 6799c86c and clock.rng determinism).

const SEEDS := [1, 7, 42, 2024]


class OpenGate:
	extends AirportGate
	var from_tick := 0

	func ready_to_open() -> bool:
		return not is_open() and flights.tick >= from_tick


func _world(seed_value: int, open_at := 0) -> Dictionary:
	var clock := auto_free(SimClock.new()) as SimClock
	clock.seed_rng(seed_value)
	clock.hold_calendar()
	var flights := auto_free(FlightSim.new()) as FlightSim
	flights.bind_clock(clock)
	var gate := auto_free(OpenGate.new()) as OpenGate
	gate.flights = flights
	gate.from_tick = open_at
	flights.gate = gate
	var desk := auto_free(OfferDesk.new()) as OfferDesk
	desk.runway = Runway.new(PlaneClasses.LARGE)
	desk.flights = flights
	desk.bind_clock(clock)
	return {"clock": clock, "flights": flights, "gate": gate, "desk": desk}


func _step_to_open(w: Dictionary, target_tick: int) -> void:
	var clock: SimClock = w["clock"]
	while clock.tick < target_tick:
		clock.advance(SimClock.STEP)


func _min_minute(clock: SimClock, day: int) -> int:
	var min_tick := clock.tick + FlightTimetable.issue_lead()
	var since_day := min_tick - GameCalendar.day_start(day, clock.epoch)
	return -GameCalendar.floor_div(-since_day, GameCalendar.TICKS_PER_MINUTE)


func _fitting_same_day_offers(desk: OfferDesk, flights: FlightSim, clock: SimClock) -> Array:
	var day := GameCalendar.day_of(clock.tick, clock.epoch)
	var min_minute := _min_minute(clock, day)
	var out: Array = []
	for offer in desk.board.open_offers():
		if offer["day"] == day and int(offer["departure_minute"]) >= min_minute:
			if FlightFit.fits(flights, OfferBoard.terms_of(offer)):
				out.append(offer)
	return out


func test_post_opening_day1_offers_fit_behind_starter_in_same_day_afternoon_evening() -> void:
	for seed_value in SEEDS:
		var w := _world(seed_value, 100)
		var clock: SimClock = w["clock"]
		var flights: FlightSim = w["flights"]
		var desk: OfferDesk = w["desk"]
		assert_int(flights.opened_tick).is_equal(-1)
		assert_array(desk.board.open_offers()).has_size(OfferBoard.OFFERS_PER_DAY)
		_step_to_open(w, 100)
		assert_int(flights.opened_tick).is_equal(100)
		assert_array(flights.contract_ids()).is_equal([FlightSim.DEFAULT_ID])
		var fitting := _fitting_same_day_offers(desk, flights, clock)
		(
			assert_int(fitting.size())
			. override_failure_message("seed %d" % seed_value)
			. is_greater_equal(1)
		)
		for offer in fitting:
			var id: String = offer["id"]
			assert_int(int(offer["departure_minute"])).is_greater_equal(_min_minute(clock, 0))
			assert_bool(desk.board.accept(id, flights)).is_true()
			assert_int(int(flights.contract_of(id)["first_day"])).is_equal(0)


func test_accepting_fitting_offers_triggers_mid_day_refill_without_mutating_clock_rng() -> void:
	var w := _world(42, 20)
	var clock: SimClock = w["clock"]
	var flights: FlightSim = w["flights"]
	var desk: OfferDesk = w["desk"]
	_step_to_open(w, 20)
	var rng_state_before := clock.rng.state
	var first_wave := _fitting_same_day_offers(desk, flights, clock)
	assert_int(first_wave.size()).is_equal(2)
	for offer in first_wave:
		assert_bool(desk.board.accept(offer["id"], flights)).is_true()
	# Still on Day 0, a refill wave arrived without touching clock.rng.
	assert_int(clock.rng.state).is_equal(rng_state_before)
	assert_int(desk.board.day_offer_count(0)).is_equal(2 * OfferBoard.OFFERS_PER_DAY)
	var second_wave := _fitting_same_day_offers(desk, flights, clock)
	assert_array(second_wave).is_not_empty()
	for offer in second_wave:
		assert_bool(desk.board.accept(offer["id"], flights)).is_true()
		assert_int(int(flights.contract_of(offer["id"])["first_day"])).is_equal(0)
	assert_int(clock.rng.state).is_equal(rng_state_before)


func test_mid_day_refills_stop_when_no_same_day_slot_remains_and_at_cap() -> void:
	var w := _world(7, 20)
	var clock: SimClock = w["clock"]
	var flights: FlightSim = w["flights"]
	var desk: OfferDesk = w["desk"]
	_step_to_open(w, 20)
	# Drain open waves until no same-day fitting offer remains (gate full or cap hit).
	var safety := 0
	while safety < 10:
		safety += 1
		var fitting := _fitting_same_day_offers(desk, flights, clock)
		if fitting.is_empty():
			if (
				not OfferBoard.has_fitting_slot(
					flights, 0, PlaneClasses.LARGE, _min_minute(clock, 0)
				)
				or desk.board.day_offer_count(0) >= OfferBoard.MAX_DAY_OFFERS
			):
				break
			var open := desk.board.open_offers()
			if open.is_empty():
				break
			desk.board.decline(open[0]["id"])
			continue
		for offer in fitting:
			if flights.accept_problem(OfferBoard.terms_of(offer)) == "":
				assert_bool(desk.board.accept(offer["id"], flights)).is_true()
	var count_after_fill := desk.board.day_offer_count(0)
	assert_int(count_after_fill).is_greater(OfferBoard.OFFERS_PER_DAY)
	assert_int(count_after_fill).is_less_equal(OfferBoard.MAX_DAY_OFFERS)
	# Declining any leftover push offer once no same-day slot remains does not spam refills.
	for offer in desk.board.open_offers():
		desk.board.decline(offer["id"])
	assert_int(desk.board.day_offer_count(0)).is_equal(count_after_fill)
	# Direct refill_day respects MAX_REFILLS_PER_DAY on a wide open multi-gate airport.
	var wide := auto_free(FlightSim.new()) as FlightSim
	wide.gate_source = func() -> Array[String]: return ["A", "B", "C", "D"] as Array[String]
	wide.open_airport()
	var board := OfferBoard.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	board.ensure_day(0, rng, 0, PlaneClasses.LARGE, wide)
	for wave in OfferBoard.MAX_REFILLS_PER_DAY:
		assert_array(board.refill_day(0, rng.seed, 0, PlaneClasses.LARGE, wide)).has_size(
			OfferBoard.OFFERS_PER_DAY
		)
	assert_array(board.refill_day(0, rng.seed, 0, PlaneClasses.LARGE, wide)).is_empty()
	assert_int(board.day_offer_count(0)).is_equal(OfferBoard.MAX_DAY_OFFERS)


func test_midnight_rollover_after_mid_day_refills_matches_uninterrupted_rng_draw() -> void:
	var with_refill := _world(42, 20)
	var without_refill := _world(42, 20)
	_step_to_open(with_refill, 20)
	_step_to_open(without_refill, 20)
	var desk_a: OfferDesk = with_refill["desk"]
	var flights_a: FlightSim = with_refill["flights"]
	var clock_a: SimClock = with_refill["clock"]
	for offer in _fitting_same_day_offers(desk_a, flights_a, clock_a):
		assert_bool(desk_a.board.accept(offer["id"], flights_a)).is_true()
	assert_int(desk_a.board.day_offer_count(0)).is_equal(2 * OfferBoard.OFFERS_PER_DAY)
	var midnight := GameCalendar.day_start(1, clock_a.epoch)
	clock_a.tick = midnight
	clock_a.ticked.emit(midnight)
	var clock_b: SimClock = without_refill["clock"]
	var desk_b: OfferDesk = without_refill["desk"]
	clock_b.tick = midnight
	clock_b.ticked.emit(midnight)
	assert_int(clock_a.rng.state).is_equal(clock_b.rng.state)
	assert_array(desk_a.board.open_offers()).has_size(OfferBoard.OFFERS_PER_DAY)
	for offer in desk_a.board.open_offers():
		assert_int(offer["day"]).is_equal(1)


func test_save_and_load_preserves_refilled_offers_without_refitting() -> void:
	var w := _world(42, 20)
	var clock: SimClock = w["clock"]
	var flights: FlightSim = w["flights"]
	var desk: OfferDesk = w["desk"]
	_step_to_open(w, 20)
	for offer in _fitting_same_day_offers(desk, flights, clock):
		assert_bool(desk.board.accept(offer["id"], flights)).is_true()
	assert_int(desk.board.day_offer_count(0)).is_equal(2 * OfferBoard.OFFERS_PER_DAY)
	var saved_board: Dictionary = JSON.parse_string(JSON.stringify(desk.board.to_snapshot()))
	var saved_flights: Dictionary = JSON.parse_string(JSON.stringify(flights.to_snapshot()))
	var saved_clock: Dictionary = JSON.parse_string(JSON.stringify(clock.to_snapshot()))
	# Load into a fresh desk/clock/flights (as SaveGame.load_world does).
	var loaded_clock := auto_free(SimClock.new()) as SimClock
	var loaded_flights := auto_free(FlightSim.new()) as FlightSim
	loaded_flights.bind_clock(loaded_clock)
	var loaded_desk := auto_free(OfferDesk.new()) as OfferDesk
	loaded_desk.runway = Runway.new(PlaneClasses.LARGE)
	loaded_desk.flights = loaded_flights
	loaded_desk.bind_clock(loaded_clock)
	assert_bool(loaded_clock.from_snapshot(saved_clock)).is_true()
	assert_bool(loaded_flights.from_snapshot(saved_flights)).is_true()
	assert_bool(loaded_desk.board.from_snapshot(saved_board)).is_true()
	assert_dict(loaded_desk.board.to_snapshot()).is_equal(desk.board.to_snapshot())
	# Stepping one tick after load does not refit or mutate the active offer list.
	loaded_clock.advance(SimClock.STEP)
	assert_dict(loaded_desk.board.to_snapshot()).is_equal(desk.board.to_snapshot())


func test_same_day_loyal_refill_loads_through_snapshot() -> void:
	var flights := auto_free(FlightSim.new()) as FlightSim
	flights.open_airport()
	var board := OfferBoard.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 123
	board.ensure_day(4, rng, 0, PlaneClasses.LARGE, flights)
	for day in [2, 3, 4]:
		assert_bool(board.note_flown("Gotta Air", day)).is_true()
	var ids := board.refill_day(4, rng.seed, 0, PlaneClasses.LARGE, flights)
	assert_array(ids).has_size(OfferBoard.OFFERS_PER_DAY)
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(board.to_snapshot()))
	var loaded := OfferBoard.new()
	assert_bool(loaded.from_snapshot(parsed)).is_true()
	assert_dict(loaded.to_snapshot()).is_equal(board.to_snapshot())


func test_refill_snapshot_validation_accepts_superseded_expired_and_refuses_bad_batches() -> void:
	var flights := auto_free(FlightSim.new()) as FlightSim
	flights.open_airport()
	var board := OfferBoard.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 55
	board.ensure_day(0, rng, 0, PlaneClasses.LARGE, flights)
	var fitting := []
	for offer in board.open_offers():
		if flights.accept_problem(OfferBoard.terms_of(offer)) == "":
			fitting.append(offer["id"])
			if fitting.size() == 2:
				break
	for id: String in fitting:
		assert_bool(board.accept(id, flights)).is_true()
	# O0N3 (leftover from batch 1) was expired when batch 2 arrived.
	var batch2 := board.refill_day(0, rng.seed, 0, PlaneClasses.LARGE, flights)
	assert_array(batch2).has_size(OfferBoard.OFFERS_PER_DAY)
	var valid_snap := board.to_snapshot()
	assert_bool(OfferBoard.new().from_snapshot(valid_snap)).is_true()
	# Earlier batch left OPEN on latest day is refused.
	var open_early: Dictionary = valid_snap.duplicate(true)
	open_early["offers"][2]["status"] = OfferBoard.OPEN
	assert_bool(OfferBoard.new().from_snapshot(open_early)).is_false()
	# Latest batch marked EXPIRED with no later day is refused.
	var expired_late: Dictionary = valid_snap.duplicate(true)
	expired_late["offers"][3]["status"] = OfferBoard.EXPIRED
	assert_bool(OfferBoard.new().from_snapshot(expired_late)).is_false()
	# Non-contiguous offer ids on a day are refused.
	var gap := TestOfferBoard.day_records(0, [600, 720, 840])
	gap[2]["id"] = "O0N6"
	assert_bool(OfferBoard.new().from_snapshot(TestOfferBoard.save_of(gap))).is_false()
