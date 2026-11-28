class_name TestOfferDeskDay1Refill
extends GdUnitTestSuite
## Day-1 post-opening offer fitting and Pick-1-of-3 no-mid-day-refill behavior
## (decision airline-offers-pick-1-of-3-side-by-side-spin-away-discard,
## superseding d97c94bd mid-day refills while keeping Day-1 post-opening fit
## and SimClock.rng determinism).

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
		assert_int(fitting.size()).override_failure_message("seed %d" % seed_value).is_equal(
			OfferBoard.OFFERS_PER_DAY
		)
		var chosen: Dictionary = fitting[0]
		var id: String = chosen["id"]
		assert_int(int(chosen["departure_minute"])).is_greater_equal(_min_minute(clock, 0))
		assert_bool(desk.board.accept(id, flights)).is_true()
		assert_int(int(flights.contract_of(id)["first_day"])).is_equal(0)
		assert_array(desk.board.open_offers()).is_empty()


func test_accepting_or_passing_does_not_trigger_mid_day_refill() -> void:
	var w := _world(42, 20)
	var clock: SimClock = w["clock"]
	var flights: FlightSim = w["flights"]
	var desk: OfferDesk = w["desk"]
	_step_to_open(w, 20)
	var rng_state_before := clock.rng.state
	var first_wave := _fitting_same_day_offers(desk, flights, clock)
	assert_int(first_wave.size()).is_equal(OfferBoard.OFFERS_PER_DAY)
	assert_bool(desk.board.accept(first_wave[0]["id"], flights)).is_true()
	# No mid-day refill batch spawns after the day's 1 pick; clock.rng stays untouched.
	assert_int(clock.rng.state).is_equal(rng_state_before)
	assert_int(desk.board.day_offer_count(0)).is_equal(OfferBoard.OFFERS_PER_DAY)
	assert_array(desk.board.open_offers()).is_empty()

	# Stepping through the rest of Day 1 never spawns another daily offer batch.
	clock.tick = GameCalendar.day_start(1, clock.epoch) - 10
	clock.ticked.emit(clock.tick)
	assert_int(desk.board.day_offer_count(0)).is_equal(OfferBoard.OFFERS_PER_DAY)
	assert_array(desk.board.open_offers()).is_empty()

	# Passing all 3 open offers on Day 2 also never triggers a mid-day refill.
	var midnight := GameCalendar.day_start(1, clock.epoch)
	clock.tick = midnight
	clock.ticked.emit(midnight)
	assert_array(desk.board.open_offers()).has_size(OfferBoard.OFFERS_PER_DAY)
	assert_bool(desk.board.pass_open_offers()).is_true()
	assert_array(desk.board.open_offers()).is_empty()
	assert_int(desk.board.day_offer_count(1)).is_equal(OfferBoard.OFFERS_PER_DAY)


func test_midnight_rollover_after_pick_draws_next_day_without_rng_drift() -> void:
	var with_pick := _world(42, 20)
	var without_pick := _world(42, 20)
	_step_to_open(with_pick, 20)
	_step_to_open(without_pick, 20)
	var desk_a: OfferDesk = with_pick["desk"]
	var flights_a: FlightSim = with_pick["flights"]
	var clock_a: SimClock = with_pick["clock"]
	var first: Dictionary = _fitting_same_day_offers(desk_a, flights_a, clock_a)[0]
	assert_bool(desk_a.board.accept(first["id"], flights_a)).is_true()
	assert_int(desk_a.board.day_offer_count(0)).is_equal(OfferBoard.OFFERS_PER_DAY)
	var midnight := GameCalendar.day_start(1, clock_a.epoch)
	clock_a.tick = midnight
	clock_a.ticked.emit(midnight)
	var clock_b: SimClock = without_pick["clock"]
	clock_b.tick = midnight
	clock_b.ticked.emit(midnight)
	assert_int(clock_a.rng.state).is_equal(clock_b.rng.state)
	assert_array(desk_a.board.open_offers()).has_size(OfferBoard.OFFERS_PER_DAY)
	for offer in desk_a.board.open_offers():
		assert_int(offer["day"]).is_equal(1)


func test_save_and_load_preserves_picked_day_without_refitting_or_refilling() -> void:
	var w := _world(42, 20)
	var clock: SimClock = w["clock"]
	var flights: FlightSim = w["flights"]
	var desk: OfferDesk = w["desk"]
	_step_to_open(w, 20)
	var first: Dictionary = _fitting_same_day_offers(desk, flights, clock)[0]
	assert_bool(desk.board.accept(first["id"], flights)).is_true()
	assert_int(desk.board.day_offer_count(0)).is_equal(OfferBoard.OFFERS_PER_DAY)
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
	var first := board.open_offers()[0]
	assert_bool(board.accept(first["id"], flights)).is_true()
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
