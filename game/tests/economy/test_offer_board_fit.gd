class_name TestOfferBoardFit
extends GdUnitTestSuite
## Given the flights, ensure_day fits a new day's offers to the timetable
## (decision airline-offers-2-a-day-fit-the-free-gate-slots-1-needs-more): N1
## and N2 depart where the gates have room, as a pair that also fits together,
## and N3 where only another gate is missing. The RNG advances exactly as it
## does without fitting, a fitted day is saved as drawn and never fitted again,
## and when nothing fits the day still has its three offers, each with a reason.

## Each fit costs a few hundred ms (test_the_cost_of_a_day_boundary_fit_on_two_
## busy_gates), so a case draws a handful of days.
const SEEDS := [1, 42, 2024, 7_654_321]
## One gate whose day is full: 195 minutes apart from 07:00 to 20:00.
const FULL_DAY := [420, 615, 810, 1005, 1200]


func _sim(gates: Array[String], minutes: Array) -> FlightSim:
	var sim := auto_free(FlightSim.new()) as FlightSim
	sim.gate_source = func() -> Array[String]: return gates
	sim.open_airport()
	for minute: int in minutes:
		assert_bool(sim.accept_contract(TestFlightFit.terms("K%d" % minute, minute))).is_true()
	return sim


func _rng(seed_value: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	return rng


func _offer_terms(board: OfferBoard, number: int, day := 0) -> Dictionary:
	return OfferBoard.terms_of(board.offer_of("O%dN%d" % [day, number]))


func _minutes(board: OfferBoard, day := 0) -> Array:
	var out := []
	for number in range(1, OfferBoard.OFFERS_PER_DAY + 1):
		out.append(board.offer_of("O%dN%d" % [day, number])["departure_minute"])
	return out


## With nothing booked every slot fits, so each of the 57 picks maps onto
## itself: N1 and N3 (no slot needs another gate) depart as drawn. N2 does too
## unless it would share the one gate with N1, and then it moves to a time it
## fits beside N1. Every other term is as drawn.
func test_an_empty_timetable_keeps_the_drawn_departures() -> void:
	var sim := _sim(["C"] as Array[String], [])
	var moved := 0
	for seed_value in SEEDS:
		var fitted := OfferBoard.new()
		var plain := OfferBoard.new()
		fitted.ensure_day(0, _rng(seed_value), 0, PlaneClasses.LARGE, sim)
		plain.ensure_day(0, _rng(seed_value), 0, PlaneClasses.LARGE)
		var a := _minutes(fitted)
		var b := _minutes(plain)
		assert_int(a[0]).is_equal(b[0])
		assert_int(a[2]).is_equal(b[2])
		var drawn_second := _offer_terms(plain, 2)
		if FlightFit.fits(sim, drawn_second, [_offer_terms(plain, 1)]):
			assert_int(a[1]).is_equal(b[1])
		else:
			moved += 1
			var fitted_second := _offer_terms(fitted, 2)
			assert_bool(FlightFit.fits(sim, fitted_second, [_offer_terms(fitted, 1)])).is_true()
		for number in range(1, OfferBoard.OFFERS_PER_DAY + 1):
			var left := _offer_terms(fitted, number)
			var right := _offer_terms(plain, number)
			left.erase("departure_minute")
			right.erase("departure_minute")
			assert_dict(left).is_equal(right)
	print("empty timetable: N2 moved off N1's gate time on %d of %d seeds" % [moved, SEEDS.size()])


## The RNG state after ensure_day is the same with and without fitting, over
## several days on a busy timetable. Control: fitting did move departures.
func test_fitting_leaves_the_rng_exactly_where_drawing_alone_does() -> void:
	var sim := _sim(["C", "D"] as Array[String], [450, 600, 840, 1200])
	var moved := 0
	for seed_value in SEEDS.slice(0, 3):
		var with_fit := _rng(seed_value)
		var without := _rng(seed_value)
		var fitted := OfferBoard.new()
		var plain := OfferBoard.new()
		for day in 2:
			fitted.ensure_day(day, with_fit, 0, PlaneClasses.LARGE, sim)
			plain.ensure_day(day, without, 0, PlaneClasses.LARGE)
			assert_int(with_fit.state).is_equal(without.state)
			var a := _minutes(fitted, day)
			var b := _minutes(plain, day)
			for i in a.size():
				moved += 1 if a[i] != b[i] else 0
	print("departures moved by fitting: %d of %d" % [moved, 3 * 2 * 3])
	assert_int(moved).is_greater(0)


## One gate holding a 10:00 contract: N1 and N2 fit, together too, whichever
## is accepted first, and N3 clashes only for want of another gate.
func test_one_gate_with_one_contract_gives_two_fits_and_one_push() -> void:
	var sim := _sim(["C"] as Array[String], [600])
	for seed_value in SEEDS:
		var board := OfferBoard.new()
		board.ensure_day(0, _rng(seed_value), 0, PlaneClasses.LARGE, sim)
		var first := _offer_terms(board, 1)
		var second := _offer_terms(board, 2)
		var push := FlightFit.assess(sim, _offer_terms(board, 3))
		print("seed %d minutes %s push %s" % [seed_value, _minutes(board), push])
		assert_bool(FlightFit.fits(sim, first)).is_true()
		assert_bool(FlightFit.fits(sim, second)).is_true()
		assert_bool(FlightFit.fits(sim, second, [first])).is_true()
		assert_bool(FlightFit.fits(sim, first, [second])).is_true()
		assert_str(push["blocker"]).is_equal(FlightSim.BLOCKER_GATE)
		assert_bool(push["another_gate_helps"]).is_true()


## One gate busy at 10:00 and 16:40 leaves 13:15 and 20:00 to 21:00: a joint
## pair still exists, and accepting both on the board works in draw order.
func test_one_busy_gate_still_gets_a_pair_that_fits_together() -> void:
	for seed_value in SEEDS:
		var sim := _sim(["C"] as Array[String], [600, 1000])
		var board := OfferBoard.new()
		board.ensure_day(0, _rng(seed_value), 0, PlaneClasses.LARGE, sim)
		var first := _offer_terms(board, 1)
		var second := _offer_terms(board, 2)
		print("seed %d busy gate minutes %s" % [seed_value, _minutes(board)])
		assert_bool(FlightFit.fits(sim, second, [first])).is_true()
		assert_bool(FlightFit.fits(sim, first, [second])).is_true()
		assert_bool(board.accept("O0N1", sim)).is_true()
		assert_bool(board.accept("O0N2", sim)).is_true()


## The pair is a pair, not two fits that each take the last free slot: on one
## gate with one slot pair left, N1 and N2 never depart at the same time.
func test_the_two_fit_offers_do_not_take_the_same_free_time() -> void:
	var sim := _sim(["C"] as Array[String], [600, 1000])
	for seed_value in SEEDS:
		var board := OfferBoard.new()
		board.ensure_day(0, _rng(seed_value), 0, PlaneClasses.LARGE, sim)
		var minutes := _minutes(board)
		assert_int(absi(minutes[0] - minutes[1])).is_greater_equal(195)


## A full gate: still three offers, none fits, each card has its reason, and the
## two fit offers keep the slots they were drawn with.
func test_full_gates_still_show_three_offers_each_with_a_reason() -> void:
	var sim := _sim(["C"] as Array[String], FULL_DAY)
	for seed_value in SEEDS:
		var board := OfferBoard.new()
		var plain := OfferBoard.new()
		board.ensure_day(0, _rng(seed_value), 0, PlaneClasses.LARGE, sim)
		plain.ensure_day(0, _rng(seed_value), 0, PlaneClasses.LARGE)
		assert_array(board.open_offers()).has_size(OfferBoard.OFFERS_PER_DAY)
		var texts := []
		for number in range(1, OfferBoard.OFFERS_PER_DAY + 1):
			var offer := board.offer_of("O0N%d" % number)
			var assessment := FlightFit.assess(sim, OfferBoard.terms_of(offer))
			texts.append(FlightFit.text(assessment, offer["plane_size"]))
			assert_bool(assessment["fits"]).is_false()
		print("seed %d full gate: %s" % [seed_value, texts])
		for text: String in texts:
			assert_str(text).is_not_empty()
			assert_str(text).is_not_equal(FlightFit.FITS_TEXT)
		# The push offer found a slot where only a gate is missing.
		assert_str(texts[2]).is_equal(FlightFit.ANOTHER_GATE_TEXT)
		assert_array(_minutes(board).slice(0, 2)).is_equal(_minutes(plain).slice(0, 2))


## A fitted day is saved with its fitted departures; loading it and starting
## the same day again draws and fits nothing, even after the timetable changed.
func test_a_fitted_day_is_saved_and_never_fitted_again_on_load() -> void:
	var sim := _sim(["C"] as Array[String], [600])
	var board := OfferBoard.new()
	board.ensure_day(0, _rng(42), 0, PlaneClasses.LARGE, sim)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(board.to_snapshot()))
	assert_int(int(saved["save_version"])).is_equal(3)
	var loaded := OfferBoard.new()
	assert_bool(loaded.from_snapshot(saved)).is_true()
	assert_bool(sim.accept_contract(TestFlightFit.terms("LATE", 1200))).is_true()
	var rng := _rng(5)
	var state := rng.state
	assert_array(loaded.ensure_day(0, rng, 0, PlaneClasses.LARGE, sim)).is_empty()
	assert_int(rng.state).is_equal(state)
	assert_array(_minutes(loaded)).is_equal(_minutes(board))
	assert_dict(loaded.to_snapshot()).is_equal(board.to_snapshot())


## Cost of one day-boundary fit on a busy two-gate timetable, measured headless.
func test_the_cost_of_a_day_boundary_fit_on_two_busy_gates() -> void:
	var sim := _sim(["C", "D"] as Array[String], [450, 600, 840, 1200])
	var board := OfferBoard.new()
	board.ensure_day(0, _rng(1), 0, PlaneClasses.LARGE, sim)
	var worst := 0.0
	var total := 0.0
	for seed_value in SEEDS:
		var day_board := OfferBoard.new()
		var started := Time.get_ticks_usec()
		day_board.ensure_day(0, _rng(seed_value), 1, PlaneClasses.LARGE, sim)
		var ms := (Time.get_ticks_usec() - started) / 1000.0
		worst = maxf(worst, ms)
		total += ms
	print(
		(
			"FIT_COST two busy gates: mean %.1f ms, worst %.1f ms over %d days"
			% [total / SEEDS.size(), worst, SEEDS.size()]
		)
	)
	assert_float(total).is_greater(0.0)
