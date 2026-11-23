class_name TestPeakHourWaves
extends GdUnitTestSuite
## Stage 2 S2-B: Peak-Hour Rush Waves (Morning 07:00-10:00 and Evening 17:00-20:00)
## with +15% Peak Demand bonus on Day 2+, wave-aware _fit() / refill_day(),
## Day-1 gentle pacing, and Odd hours exclusion.


func test_peak_wave_and_bonus_boundaries() -> void:
	var cases := [
		[360, "", false, 50],
		[405, "", false, 50],
		[420, OfferBoard.PEAK_WAVE_MORNING, true, 58],
		[510, OfferBoard.PEAK_WAVE_MORNING, true, 58],
		[600, OfferBoard.PEAK_WAVE_MORNING, true, 58],
		[615, "", false, 50],
		[1005, "", false, 50],
		[1020, OfferBoard.PEAK_WAVE_EVENING, true, 58],
		[1110, OfferBoard.PEAK_WAVE_EVENING, true, 58],
		[1200, OfferBoard.PEAK_WAVE_EVENING, true, 58],
		[1215, "", false, 50],
		[1320, "", false, 50],
	]
	for case: Array in cases:
		var minute: int = case[0]
		assert_str(OfferBoard.peak_wave(minute)).is_equal(case[1])
		assert_bool(OfferBoard.is_peak_minute(minute)).is_equal(case[2])
		assert_int(OfferBoard.apply_peak_bonus(50, minute)).is_equal(case[3])


func test_day2_plus_draws_banked_peak_waves_near_65_percent_and_keeps_odd_hours_unbonused() -> void:
	var board := OfferBoard.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261123
	var total_regular := 0
	var peak_count := 0
	var morning_count := 0
	var evening_count := 0
	var odd_hours_count := 0
	for day in range(1, 51):
		board.ensure_day(day, rng, 1, PlaneClasses.LARGE)
		for number in range(1, OfferBoard.OFFERS_PER_DAY + 1):
			var offer := board.offer_of("O%dN%d" % [day, number])
			var traits: Dictionary = offer["traits"]
			var minute: int = offer["departure_minute"]
			if OfferTraits.window_widening(traits) > 0:
				odd_hours_count += 1
				assert_array([360, 1320]).contains([minute])
				assert_bool(OfferBoard.is_peak_minute(minute)).is_false()
				var own: int = OfferBoard.tier_of(offer["airline"])
				var fees: Array = OfferBoard.fee_range_for(own, offer["plane_size"])
				assert_int(offer["fee_per_passenger"]).is_between(
					OfferTraits.fee_of(fees[0], traits), OfferTraits.fee_of(fees[1], traits)
				)
				continue
			total_regular += 1
			var wave := OfferBoard.peak_wave(minute)
			if wave != "":
				peak_count += 1
				if wave == OfferBoard.PEAK_WAVE_MORNING:
					morning_count += 1
				else:
					evening_count += 1
			var own_tier: int = OfferBoard.tier_of(offer["airline"])
			var fee_range: Array = OfferBoard.fee_range_for(own_tier, offer["plane_size"])
			var min_fee := OfferBoard.apply_peak_bonus(
				OfferTraits.fee_of(fee_range[0], traits), minute
			)
			var max_fee := OfferBoard.apply_peak_bonus(
				OfferTraits.fee_of(fee_range[1], traits), minute
			)
			assert_int(offer["fee_per_passenger"]).is_between(min_fee, max_fee)
	var share := float(peak_count) / float(total_regular)
	print(
		(
			"Day 2+ peak stats: %d/%d (%.1f%%), morning=%d, evening=%d, odd=%d"
			% [
				peak_count,
				total_regular,
				share * 100.0,
				morning_count,
				evening_count,
				odd_hours_count
			]
		)
	)
	assert_int(total_regular).is_greater_equal(100)
	assert_float(share).is_between(0.52, 0.78)
	assert_int(morning_count).is_greater(10)
	assert_int(evening_count).is_greater(10)
	assert_int(odd_hours_count).is_greater(0)

	# Same seed reproduces the exact same Day 2+ offers.
	var replay := OfferBoard.new()
	var replay_rng := RandomNumberGenerator.new()
	replay_rng.seed = 20261123
	for day in range(1, 51):
		replay.ensure_day(day, replay_rng, 1, PlaneClasses.LARGE)
	assert_dict(replay.to_snapshot()).is_equal(board.to_snapshot())


func test_day1_draw_preserves_gentle_uniform_distribution_without_forcing_morning_rush() -> void:
	var morning_draws := 0
	var total_regular := 0
	for seed_value in range(1, 61):
		var board := OfferBoard.new()
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		board.ensure_day(0, rng)
		for offer in board.open_offers():
			if OfferTraits.window_widening(offer["traits"]) > 0:
				continue
			total_regular += 1
			if OfferBoard.peak_wave(int(offer["departure_minute"])) == OfferBoard.PEAK_WAVE_MORNING:
				morning_draws += 1
	var morning_share := float(morning_draws) / float(total_regular)
	print(
		(
			"Day 1 morning share: %d/%d (%.1f%%)"
			% [morning_draws, total_regular, morning_share * 100.0]
		)
	)
	# Uniform 13/57 = 22.8% (whereas Day 2+ morning is ~32.5%).
	assert_float(morning_share).is_between(0.12, 0.32)


func test_wave_aware_fit_keeps_same_wave_and_updates_bonus_when_forced_across_boundary() -> void:
	# Pack all morning peak slots (07:00-10:00) on gate C, leaving evening peak
	# (17:00-20:00) and midday off-peak free.
	var morning_full := auto_free(FlightSim.new()) as FlightSim
	morning_full.gate_source = func() -> Array[String]: return ["C"] as Array[String]
	morning_full.open_airport()
	for minute in [420, 555]:
		(
			assert_bool(morning_full.accept_contract(TestFlightFit.terms("M%d" % minute, minute)))
			. is_true()
		)

	# A morning offer drawn on Day 2 (day=1) moves to Evening Peak first when
	# Morning Peak is full, preserving its +15% Peak Demand bonus.
	var offer_m := TestOfferBoard.record("O1N1", 1, 480)
	offer_m["fee_per_passenger"] = OfferBoard.apply_peak_bonus(50, 480)
	var batch_m: Array[Dictionary] = [offer_m]
	OfferBoard._fit(batch_m, morning_full)
	assert_str(OfferBoard.peak_wave(int(offer_m["departure_minute"]))).is_equal(
		OfferBoard.PEAK_WAVE_EVENING
	)
	assert_int(int(offer_m["fee_per_passenger"])).is_equal(58)

	# Now also pack Evening Peak (17:00-20:00), forcing a peak offer into Midday
	# off-peak: the +15% peak bonus must be stripped cleanly back to 50.
	var peaks_full := auto_free(FlightSim.new()) as FlightSim
	peaks_full.gate_source = func() -> Array[String]: return ["C"] as Array[String]
	peaks_full.open_airport()
	for minute in [420, 555, 1020, 1155]:
		(
			assert_bool(peaks_full.accept_contract(TestFlightFit.terms("P%d" % minute, minute)))
			. is_true()
		)

	var forced_off := TestOfferBoard.record("O1N2", 1, 540)
	forced_off["fee_per_passenger"] = OfferBoard.apply_peak_bonus(50, 540)
	var batch_off: Array[Dictionary] = [forced_off]
	OfferBoard._fit(batch_off, peaks_full)
	assert_bool(OfferBoard.is_peak_minute(int(forced_off["departure_minute"]))).is_false()
	assert_int(int(forced_off["fee_per_passenger"])).is_equal(50)

	# Conversely, pack midday off-peak so an off-peak offer is forced into a
	# peak slot: the +15% peak bonus must be added cleanly (50 -> 58).
	var offpeak_full := auto_free(FlightSim.new()) as FlightSim
	offpeak_full.gate_source = func() -> Array[String]: return ["C"] as Array[String]
	offpeak_full.open_airport()
	for minute in [615, 750, 885, 1215]:
		(
			assert_bool(offpeak_full.accept_contract(TestFlightFit.terms("D%d" % minute, minute)))
			. is_true()
		)

	var forced_peak := TestOfferBoard.record("O1N3", 1, 780)
	forced_peak["fee_per_passenger"] = 50
	var batch_peak: Array[Dictionary] = [forced_peak]
	OfferBoard._fit(batch_peak, offpeak_full)
	assert_bool(OfferBoard.is_peak_minute(int(forced_peak["departure_minute"]))).is_true()
	assert_int(int(forced_peak["fee_per_passenger"])).is_equal(58)


func test_peak_bonus_round_trips_through_snapshot_and_pays_out_in_settlement() -> void:
	# Snapshot accepts valid peak-bonused fees (including top_fare + loyal + peak)
	# and rejects impossible un-bonused fees below peak minimum.
	var records := TestOfferBoard.day_records(1, [480, 720, 1080])
	records[0]["traits"] = {"up": "top_fare", "down": "rush_crowd", "level": 2}
	records[0]["fee_per_passenger"] = OfferBoard.apply_peak_bonus(
		OfferTraits.fee_of(OfferBoard.SMALL_FEE_MAX, records[0]["traits"]), 480
	)
	records[2]["fee_per_passenger"] = OfferBoard.apply_peak_bonus(OfferBoard.SMALL_FEE_MIN, 1080)
	var board := OfferBoard.new()
	assert_bool(board.from_snapshot(TestOfferBoard.save_of(records))).is_true()

	var bad := TestOfferBoard.day_records(1, [480, 720, 1080])
	bad[0]["fee_per_passenger"] = OfferBoard.SMALL_FEE_MIN
	assert_bool(OfferBoard.new().from_snapshot(TestOfferBoard.save_of(bad))).is_false()

	# Accepting a peak offer carries the +15% bonused fee into FlightSim and Settlement.
	var grid := BuildGrid.new()
	ReferenceTerminal.build(grid)
	var world := PassengerTestWorld.make(
		grid, FlightSim.schedule_starts(GameCalendar.tick_at(2, 9 * 60, 0))
	)
	world.flights.open_airport()
	var settlement := auto_free(Settlement.new()) as Settlement
	settlement.bind(world.sim, world.sim.wallet)
	assert_bool(board.accept("O1N3", world.flights)).is_true()
	var contract := world.flights.contract_of("O1N3")
	var expected_fee := OfferBoard.apply_peak_bonus(OfferBoard.SMALL_FEE_MIN, 1080)
	assert_int(int(contract["fee_per_passenger"])).is_equal(expected_fee)

	world.run_to(GameCalendar.tick_at(0, 19 * 60, 0))
	var made := world.sim.made_count()
	print(
		(
			"Settlement peak test: made=%d balance=%d expected_each=%d"
			% [made, world.sim.wallet.balance, expected_fee]
		)
	)
	assert_int(made).is_greater(0)
	assert_int(world.sim.wallet.balance).is_equal(made * expected_fee)
	world.free_all()


func test_refill_day_on_day2_plus_is_wave_aware() -> void:
	var sim := auto_free(FlightSim.new()) as FlightSim
	sim.gate_source = func() -> Array[String]: return ["C"] as Array[String]
	sim.open_airport()
	for minute in [420, 555]:
		assert_bool(sim.accept_contract(TestFlightFit.terms("R%d" % minute, minute))).is_true()
	var board := OfferBoard.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 909
	board.ensure_day(1, rng, 0, PlaneClasses.LARGE, sim)
	var ids := board.refill_day(1, rng.seed, 0, PlaneClasses.LARGE, sim)
	assert_array(ids).has_size(OfferBoard.OFFERS_PER_DAY)
	for id: String in ids:
		var offer := board.offer_of(id)
		var minute := int(offer["departure_minute"])
		var fees: Array = OfferBoard.fee_range_for(
			OfferBoard.tier_of(offer["airline"]), offer["plane_size"]
		)
		var traits: Dictionary = offer["traits"]
		assert_int(int(offer["fee_per_passenger"])).is_between(
			OfferBoard.apply_peak_bonus(OfferTraits.fee_of(fees[0], traits), minute),
			OfferBoard.apply_peak_bonus(OfferTraits.fee_of(fees[1], traits), minute)
		)
