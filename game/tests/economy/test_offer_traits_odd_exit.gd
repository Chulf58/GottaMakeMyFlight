class_name TestOfferTraitsOddExit
extends GdUnitTestSuite
## Offer traits slice 3 (decision odd-hours-and-exit-fee-offer-traits-odd-hours-
## widens-the-dep): Odd hours and Exit fee join the downsides. The catalog pairs
## 6 upsides with 5 downsides less the 2 forbidden pairs, 28 in all; neither new
## downside cancels an upside. Over many seeds only an Odd hours offer departs
## outside 07:00 to 21:00, and Odd hours offers reach 06:00 and 22:00. The fit
## cache keeps plain and Odd hours windows apart whichever comes first.

const LIVE := {OfferTraits.NEEDS_BAGS: true, OfferTraits.NEEDS_SHOPS: true}
const ODD := {"up": "top_fare", "down": "odd_hours", "level": 1}
const SEEDS := 300
const DAYS := 10


func test_the_catalog_has_28_pairs_and_no_new_forbidden_pair() -> void:
	var all := OfferTraits.pairs(LIVE)
	assert_int(OfferTraits.UPS.size()).is_equal(6)
	assert_int(OfferTraits.DOWNS.size()).is_equal(5)
	print(
		"pairs: %d with every need live, %d with none" % [all.size(), OfferTraits.pairs({}).size()]
	)
	assert_int(all.size()).is_equal(28)
	# Without a bag room or a shop, Shoppers, Bag cover and Heavy bags drop out.
	assert_int(OfferTraits.pairs({}).size()).is_equal(16)
	for down in [OfferTraits.ODD_HOURS, OfferTraits.EXIT_FEE]:
		var with_down := all.filter(func(pair: Array) -> bool: return pair[1] == down)
		assert_int(with_down.size()).is_equal(OfferTraits.UPS.size())
	assert_array(OfferTraits.FORBIDDEN).has_size(2)
	for pair: Array in OfferTraits.FORBIDDEN:
		assert_bool(all.has(pair)).is_false()
	assert_int(OfferTraits.SEED_VERSION).is_equal(3)


func test_exit_fee_is_60_small_and_120_big_and_odd_hours_widens_an_hour() -> void:
	var small := {"up": "top_fare", "down": "exit_fee", "level": 1}
	var big := {"up": "signing_bonus", "down": "exit_fee", "level": 2}
	assert_str(OfferTraits.problem(big)).is_empty()
	assert_int(OfferTraits.exit_fee(small)).is_equal(60)
	assert_int(OfferTraits.exit_fee(big)).is_equal(120)
	assert_int(OfferTraits.exit_fee(ODD)).is_equal(0)
	assert_int(OfferTraits.exit_fee({})).is_equal(0)
	assert_int(OfferTraits.EXIT_FEE_DAYS).is_equal(7)
	assert_int(OfferTraits.window_widening(ODD)).is_equal(60)
	assert_int(OfferTraits.window_widening(big)).is_equal(0)


## The card says each new downside up front: the fee in the label, the term in
## the tip; the hours in the Odd hours tip.
func test_the_card_line_names_the_fee_and_the_hours() -> void:
	var exit := {"up": "top_fare", "down": "exit_fee", "level": 2}
	assert_array(Array(OfferTraits.card_labels(exit))).is_equal(["Top fare +30%", "Exit fee $120"])
	assert_str(OfferTraits.card_tips(exit)[1]).contains("7 days").contains("$120")
	assert_array(Array(OfferTraits.card_labels(ODD))).is_equal(["Top fare +15%", "Odd hours"])
	assert_str(OfferTraits.card_tips(ODD)[1]).contains("06:00").contains("22:00")


func test_slots_are_57_plain_and_65_with_odd_hours() -> void:
	var plain := OfferBoard.slots_of({})
	var odd := OfferBoard.slots_of(ODD)
	assert_int(plain.size()).is_equal(57)
	assert_int(odd.size()).is_equal(65)
	assert_array([plain[0], plain[-1], odd[0], odd[-1]]).is_equal([420, 1260, 360, 1320])
	# The last drawn slot of either window reaches the last candidate.
	assert_int(OfferBoard._pick([64, 65], 65)).is_equal(64)
	assert_int(OfferBoard._pick([56, 57], 57)).is_equal(56)
	assert_int(OfferBoard._pick([64, 65], 2)).is_equal(1)
	assert_int(OfferBoard._pick([0, 65], 2)).is_equal(0)


## SEEDS runs of DAYS days at every tier: no offer without Odd hours leaves
## outside 07:00 to 21:00, every Odd hours offer leaves inside 06:00 to 22:00,
## and some leave at 06:00 and some at 22:00. The same seed draws the same days.
func test_many_seeds_keep_plain_offers_in_07_to_21_and_odd_hours_reach_06_and_22() -> void:
	var counts := {"plain": 0, "odd": 0, "plain_outside": 0, "odd_outside": 0, 360: 0, 1320: 0}
	for seed_value in range(1, SEEDS + 1):
		var board := _drawn(seed_value)
		for day in DAYS:
			for number in range(1, OfferBoard.OFFERS_PER_DAY + 1):
				_count(board.offer_of("O%dN%d" % [day, number]), counts)
	print("offers over %d seeds: %s" % [SEEDS, counts])
	assert_int(counts["plain"]).is_greater(1000)
	assert_int(counts["odd"]).is_greater(100)
	assert_int(counts["plain_outside"]).is_equal(0)
	assert_int(counts["odd_outside"]).is_equal(0)
	assert_int(counts[360]).is_greater(0)
	assert_int(counts[1320]).is_greater(0)
	var again := _drawn(7)
	assert_str(JSON.stringify(again.to_snapshot())).is_equal(
		JSON.stringify(_drawn(7).to_snapshot())
	)
	assert_str(JSON.stringify(again.to_snapshot())).is_not_equal(
		JSON.stringify(_drawn(8).to_snapshot())
	)


## Fit candidates for a plain and an Odd hours offer of one plane size: the Odd
## hours list holds 06:00 and 22:00 and the plain one neither, and asking in
## either order with one shared cache gives the same lists.
func test_the_fit_cache_keeps_the_two_windows_apart_in_either_order() -> void:
	var sim := auto_free(FlightSim.new()) as FlightSim
	sim.gate_source = func() -> Array[String]: return ["C"] as Array[String]
	sim.open_airport()
	var plain := _offer("O0N1", {})
	var odd := _offer("O0N2", ODD)
	var cache := {}
	var plain_first := OfferBoard._slots_where(sim, plain, cache, true)
	var odd_second := OfferBoard._slots_where(sim, odd, cache, true)
	var other := {}
	var odd_first := OfferBoard._slots_where(sim, odd, other, true)
	var plain_second := OfferBoard._slots_where(sim, plain, other, true)
	print("fitting slots: plain %d, odd hours %d" % [plain_first.size(), odd_first.size()])
	assert_array(odd_first).is_equal(odd_second)
	assert_array(plain_first).is_equal(plain_second)
	assert_array(odd_first).contains([360, 1320])
	assert_array(plain_first).not_contains([360, 1320])
	assert_int(plain_first.size()).is_equal(57)
	assert_int(odd_first.size()).is_equal(65)


## An Odd hours offer fitted to the flights is accepted at its fitted slot, and
## the sim saved with it loads: fit, accept and load agree.
func test_a_fitted_odd_hours_offer_is_accepted_and_loads() -> void:
	var found := 0
	for seed_value in range(1, 40):
		var sim := auto_free(FlightSim.new()) as FlightSim
		sim.gate_source = func() -> Array[String]: return ["C", "D"] as Array[String]
		sim.open_airport()
		var board := OfferBoard.new()
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_value
		board.ensure_day(0, rng, 0, PlaneClasses.LARGE, sim, LIVE)
		for number in range(1, OfferBoard.FIT_OFFERS + 1):
			var offer := board.offer_of("O0N%d" % number)
			if OfferTraits.window_widening(offer["traits"]) == 0:
				continue
			found += 1
			print(
				(
					"seed %d: Odd hours %s fitted at %d"
					% [seed_value, offer["id"], offer["departure_minute"]]
				)
			)
			assert_bool(board.accept(offer["id"], sim)).is_true()
			var data: Dictionary = JSON.parse_string(JSON.stringify(sim.to_snapshot()))
			var loaded := auto_free(FlightSim.new()) as FlightSim
			loaded.gate_source = sim.gate_source
			assert_bool(loaded.from_snapshot(data)).is_true()
			assert_dict(loaded.contract_of(offer["id"])).is_equal(sim.contract_of(offer["id"]))
		if found >= 3:
			break
	assert_int(found).is_greater_equal(3)


func _drawn(seed_value: int) -> OfferBoard:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var board := OfferBoard.new()
	for day in DAYS:
		board.ensure_day(
			day, rng, seed_value % (OfferBoard.MAX_TIER + 1), PlaneClasses.LARGE, null, LIVE
		)
	return board


func _count(offer: Dictionary, counts: Dictionary) -> void:
	var minute: int = offer["departure_minute"]
	if OfferTraits.window_widening(offer["traits"]) > 0:
		counts["odd"] += 1
		counts["odd_outside"] += 1 if minute < 360 or minute > 1320 else 0
		if counts.has(minute):
			counts[minute] += 1
	else:
		counts["plain"] += 1
		counts["plain_outside"] += 1 if minute < 420 or minute > 1260 else 0


func _offer(id: String, traits: Dictionary) -> Dictionary:
	var offer := TestFlightContracts.terms(id, 600)
	offer["traits"] = traits
	return offer
