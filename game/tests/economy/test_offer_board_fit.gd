class_name TestOfferBoardFit
extends GdUnitTestSuite
## Given the flights, ensure_day fits a new day's offers to the timetable
## (decision airline-offers-pick-1-of-3-side-by-side-spin-away-discard): all 3
## offers depart at distinct slots the gates have room for whenever free slots
## allow, falling back to another-gate push slots only when fewer than 3
## distinct fitting slots exist. The RNG advances as it does without fitting.
##
## Each fit costs a few hundred ms, so a case draws a handful of days.
const SEEDS := [1, 42, 2024, 7_654_321]
## One gate whose day is full for all plane sizes: 135 minutes apart from 07:00 to 20:30.
const FULL_DAY := [420, 555, 690, 825, 960, 1095, 1230]
## Seed -> the fitted N1, N2 and N3 departures on one gate busy at 10:00 and
## 16:40 (test_golden_fitted_departures_on_a_busy_gate). Updated for FIT_OFFERS=3
## (8e0c5b1b) where all 3 offers fit distinct free slots.
const GOLDEN_BUSY := {
	1: [795, 1215, 450],
	42: [1200, 450, 855],
	2024: [360, 1230, 855],
	7_654_321: [1200, 465, 735],
}


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


## With nothing booked every slot fits, so each of the 3 offers fits the
## empty gate and takes a distinct departure (moving off an earlier offer's
## gate hold if needed). Every other term matches the plain draw.
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
		var chosen: Array[Dictionary] = [_offer_terms(plain, 1)]
		for idx in range(1, OfferBoard.OFFERS_PER_DAY):
			var drawn_terms := _offer_terms(plain, idx + 1)
			var fitted_terms := _offer_terms(fitted, idx + 1)
			assert_bool(FlightFit.fits(sim, fitted_terms)).is_true()
			if FlightFit.fits(sim, drawn_terms, chosen) and not a.slice(0, idx).has(b[idx]):
				assert_int(a[idx]).is_equal(b[idx])
			else:
				moved += 1
				assert_bool(FlightFit.fits(sim, fitted_terms, chosen)).is_true()
			chosen.append(fitted_terms)
		for number in range(1, OfferBoard.OFFERS_PER_DAY + 1):
			var left := _offer_terms(fitted, number)
			var right := _offer_terms(plain, number)
			var left_min: int = left["departure_minute"]
			var right_min: int = right["departure_minute"]
			var expected_fee := OfferBoard.apply_peak_bonus(
				OfferBoard._base_fee_before_peak(int(right["fee_per_passenger"]), right_min),
				left_min
			)
			assert_int(int(left["fee_per_passenger"])).is_equal(expected_fee)
			left.erase("departure_minute")
			right.erase("departure_minute")
			left.erase("fee_per_passenger")
			right.erase("fee_per_passenger")
			assert_dict(left).is_equal(right)
	print("empty timetable: offers moved to distinct non-clashing slots %d times" % moved)


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


## One gate holding a 10:00 contract: all 3 daily offers fit distinct slots
## on the gate (true 3-way trade-off).
func test_one_gate_with_one_contract_fits_all_three_offers() -> void:
	var sim := _sim(["C"] as Array[String], [600])
	for seed_value in SEEDS:
		var board := OfferBoard.new()
		board.ensure_day(0, _rng(seed_value), 0, PlaneClasses.LARGE, sim)
		var minutes := _minutes(board)
		print("seed %d minutes %s" % [seed_value, minutes])
		var seen := {}
		for number in range(1, OfferBoard.OFFERS_PER_DAY + 1):
			var terms := _offer_terms(board, number)
			assert_bool(FlightFit.fits(sim, terms)).is_true()
			seen[terms["departure_minute"]] = true
		assert_int(seen.size()).is_equal(OfferBoard.OFFERS_PER_DAY)


## One gate busy at 10:00 and 16:40 still gives all 3 offers fitting slots,
## and accepting 1 immediately closes the other 2 (Pick-1-of-3).
func test_one_busy_gate_fits_three_offers_and_accepting_one_closes_others() -> void:
	for seed_value in SEEDS:
		var sim := _sim(["C"] as Array[String], [600, 1000])
		var board := OfferBoard.new()
		board.ensure_day(0, _rng(seed_value), 0, PlaneClasses.LARGE, sim)
		for number in range(1, OfferBoard.OFFERS_PER_DAY + 1):
			assert_bool(FlightFit.fits(sim, _offer_terms(board, number))).is_true()
		assert_bool(board.accept("O0N1", sim)).is_true()
		assert_array(board.open_offers()).is_empty()
		assert_str(board.offer_of("O0N2")["status"]).is_equal(OfferBoard.DECLINED)
		assert_str(board.offer_of("O0N3")["status"]).is_equal(OfferBoard.DECLINED)


## The fitted offers take distinct free slots rather than all piling onto one slot.
func test_the_two_fit_offers_do_not_take_the_same_free_time() -> void:
	var sim := _sim(["C"] as Array[String], [600, 1000])
	for seed_value in SEEDS:
		var board := OfferBoard.new()
		board.ensure_day(0, _rng(seed_value), 0, PlaneClasses.LARGE, sim)
		var minutes := _minutes(board)
		var first := _offer_terms(board, 1)
		var second := _offer_terms(board, 2)
		assert_bool(FlightFit.fits(sim, second, [first])).is_true()
		assert_int(absi(minutes[0] - minutes[1])).is_greater_equal(135)


## A full gate: still three offers, none fits, each card falls back to a push
## slot with "No gate free at this time: build another gate".
func test_full_gates_still_show_three_offers_each_with_a_reason() -> void:
	var sim := _sim(["C"] as Array[String], FULL_DAY)
	for seed_value in SEEDS:
		var board := OfferBoard.new()
		board.ensure_day(0, _rng(seed_value), 0, PlaneClasses.LARGE, sim)
		assert_array(board.open_offers()).has_size(OfferBoard.OFFERS_PER_DAY)
		var texts := []
		for number in range(1, OfferBoard.OFFERS_PER_DAY + 1):
			var offer := board.offer_of("O0N%d" % number)
			var assessment := FlightFit.assess(sim, OfferBoard.terms_of(offer))
			texts.append(FlightFit.text(assessment, offer["plane_size"]))
			assert_bool(assessment["fits"]).is_false()
		print("seed %d full gate: %s" % [seed_value, texts])
		for text: String in texts:
			assert_str(text).is_equal(FlightFit.ANOTHER_GATE_TEXT)


## When fewer than 3 distinct fitting slots exist on a nearly full gate (only
## 07:00 is free), N1 fits at 07:00 while N2/N3 fall back cleanly to push slots.
func test_fewer_than_three_distinct_fitting_slots_falls_back_cleanly() -> void:
	var nearly_full := FULL_DAY.slice(1)
	var sim := _sim(["C"] as Array[String], nearly_full)
	var board := OfferBoard.new()
	board.ensure_day(0, _rng(1), 0, PlaneClasses.LARGE, sim)
	var fit_count := 0
	var fallback_count := 0
	for number in range(1, OfferBoard.OFFERS_PER_DAY + 1):
		var assessment := FlightFit.assess(sim, _offer_terms(board, number))
		if assessment["fits"]:
			fit_count += 1
		else:
			fallback_count += 1
			assert_str(assessment["blocker"]).is_equal(FlightSim.BLOCKER_GATE)
			assert_bool(assessment["another_gate_helps"]).is_true()
	assert_int(fit_count).is_equal(1)
	assert_int(fallback_count).is_equal(2)


## A fitted day is saved with its fitted departures; loading it and starting
## the same day again draws and fits nothing, even after the timetable changed.
func test_a_fitted_day_is_saved_and_never_fitted_again_on_load() -> void:
	var sim := _sim(["C"] as Array[String], [600])
	var board := OfferBoard.new()
	board.ensure_day(0, _rng(42), 0, PlaneClasses.LARGE, sim)
	var saved: Dictionary = JSON.parse_string(JSON.stringify(board.to_snapshot()))
	assert_int(int(saved["save_version"])).is_equal(OfferBoard.SAVE_VERSION)
	var loaded := OfferBoard.new()
	assert_bool(loaded.from_snapshot(saved)).is_true()
	assert_bool(sim.accept_contract(TestFlightFit.terms("LATE", 1200))).is_true()
	var rng := _rng(5)
	var state := rng.state
	assert_array(loaded.ensure_day(0, rng, 0, PlaneClasses.LARGE, sim)).is_empty()
	assert_int(rng.state).is_equal(state)
	assert_array(_minutes(loaded)).is_equal(_minutes(board))
	assert_dict(loaded.to_snapshot()).is_equal(board.to_snapshot())


## The pick floor(r * n / 57), table driven: r 0..56 spreads evenly over n
## candidates, both ends land on the first and last, and a remainder (r % n)
## would give other answers in most rows.
func test_the_drawn_slot_maps_onto_n_candidates_by_floor_r_n_over_57() -> void:
	# [drawn slot r, candidates n, expected index]
	var table := [
		[0, 1, 0],
		[56, 1, 0],
		[0, 57, 0],
		[56, 57, 56],
		[28, 2, 0],
		[29, 2, 1],
		[56, 2, 1],
		[5, 10, 0],
		[6, 10, 1],
		[56, 10, 9],
		[18, 3, 0],
		[19, 3, 1],
		[38, 3, 2],
		[40, 24, 16],
	]
	for row: Array in table:
		(
			assert_int(OfferBoard._pick([row[0], 57], row[1]))
			. override_failure_message("r %d over %d candidates" % [row[0], row[1]])
			. is_equal(row[2])
		)
	# Every r picks a valid index, and each of n candidates is picked by
	# floor(d / n) or one more of the d draws, for the plain window's 57 slots
	# and an Odd hours offer's 2 (06:00 and 22:00).
	for slots in [57, 2]:
		for n in [1, 2, 3, 7, 10, 24, 56, 57, 65]:
			if n > slots:
				continue
			var counts := {}
			for r in range(slots):
				var index := OfferBoard._pick([r, slots], n)
				assert_int(index).is_between(0, n - 1)
				counts[index] = counts.get(index, 0) + 1
			assert_int(counts.size()).is_equal(n)
			for index: int in counts:
				assert_int(counts[index]).is_between(
					floori(float(slots) / n), floori(float(slots) / n) + 1
				)


## Golden fitted departures for fixed seeds on one gate busy at 10:00 and
## 16:40 (13:15 and 20:00 to 21:00 are free): measured on 71f5059f, the build
## the review read, so a change to the candidate lists, the pick or the pair
## search shows here.
func test_golden_fitted_departures_on_a_busy_gate() -> void:
	var golden := GOLDEN_BUSY
	var sim := _sim(["C"] as Array[String], [600, 1000])
	var found := {}
	for seed_value in SEEDS:
		var board := OfferBoard.new()
		board.ensure_day(0, _rng(seed_value), 0, PlaneClasses.LARGE, sim)
		found[seed_value] = _minutes(board)
	print("busy gate fitted departures: %s" % [found])
	for seed_value in SEEDS:
		assert_array(found[seed_value]).is_equal(golden.get(seed_value, []))


## Cost of one day-boundary fit on a busy two-gate timetable, measured headless
## and printed for the report; machine speed varies, so no time is asserted.
func test_the_cost_of_a_day_boundary_fit_on_two_busy_gates() -> void:
	var sim := _sim(["C", "D"] as Array[String], [450, 600, 840, 1200])
	var board := OfferBoard.new()
	board.ensure_day(0, _rng(1), 0, PlaneClasses.LARGE, sim)
	var worst := 0.0
	var total := 0.0
	for seed_value in SEEDS:
		var day_board := OfferBoard.new()
		var started := Time.get_ticks_usec()
		var ids := day_board.ensure_day(0, _rng(seed_value), 1, PlaneClasses.LARGE, sim)
		var ms := (Time.get_ticks_usec() - started) / 1000.0
		worst = maxf(worst, ms)
		total += ms
		assert_array(ids).has_size(OfferBoard.OFFERS_PER_DAY)
	print(
		(
			"FIT_COST two busy gates: mean %.1f ms, worst %.1f ms over %d days"
			% [total / SEEDS.size(), worst, SEEDS.size()]
		)
	)
