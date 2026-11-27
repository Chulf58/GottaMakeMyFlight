class_name TestOfferBoardTiers
extends GdUnitTestSuite
## Airline tiers on the offer board (decision airport-rating-1-5-stars-over-a-
## rolling-3-days-mostly-made-o): the tier a day is drawn at decides which
## airlines, plane sizes and fees its offers hold. Tier 0 is the starter board
## and must draw exactly what it drew before tiers existed.

const DAYS := 40

var _rng: RandomNumberGenerator


func before_test() -> void:
	_rng = RandomNumberGenerator.new()
	_rng.seed = 777


## Every offer of `days` consecutive days drawn at `tier`, one board.
func _draw_days(tier: int) -> Array[Dictionary]:
	var board := OfferBoard.new()
	for day in DAYS:
		board.ensure_day(day, _rng, tier)
	var offers: Array[Dictionary] = []
	for day in DAYS:
		for number in range(1, OfferBoard.OFFERS_PER_DAY + 1):
			offers.append(board.offer_of("O%dN%d" % [day, number]))
	return offers


func _large_offers(offers: Array[Dictionary]) -> Array:
	return offers.filter(func(offer: Dictionary) -> bool: return offer["plane_size"] == "large")


func _airlines_up_to(tier: int) -> Array:
	var airlines := []
	for t in range(tier + 1):
		airlines.append_array(OfferBoard.TIER_AIRLINES[t])
	return airlines


func test_tier_zero_is_the_starter_board_and_the_default() -> void:
	var plain := OfferBoard.new()
	var starter := OfferBoard.new()
	var other := RandomNumberGenerator.new()
	other.seed = 777
	for day in 5:
		plain.ensure_day(day, _rng)
		starter.ensure_day(day, other, 0)
	assert_dict(starter.to_snapshot()).is_equal(plain.to_snapshot())
	assert_int(other.state).is_equal(_rng.state)
	assert_array(OfferBoard.TIER_AIRLINES[0]).is_equal(OfferBoard.AIRLINES)


func test_a_tier_zero_day_holds_only_starter_airlines_and_planes() -> void:
	for offer in _draw_days(0):
		assert_bool(OfferBoard.AIRLINES.has(offer["airline"])).is_true()
		assert_bool(OfferBoard.STARTER_SIZES.has(offer["plane_size"])).is_true()


func test_each_tier_adds_its_airlines_and_never_a_higher_one() -> void:
	for tier in OfferBoard.MAX_TIER + 1:
		var seen_top := false
		for offer in _draw_days(tier):
			var airline: String = offer["airline"]
			(
				assert_bool(_airlines_up_to(tier).has(airline))
				. override_failure_message("tier %d drew %s" % [tier, airline])
				. is_true()
			)
			seen_top = seen_top or OfferBoard.tier_of(airline) == tier
		(
			assert_bool(seen_top)
			. override_failure_message("tier %d never drew its own" % tier)
			. is_true()
		)


func test_every_offer_follows_the_plane_sizes_and_fees_of_its_airlines_tier() -> void:
	for tier in OfferBoard.MAX_TIER + 1:
		for offer in _draw_days(tier):
			var own: int = OfferBoard.tier_of(offer["airline"])
			var sizes: Dictionary = OfferBoard.TIER_SIZES[own]
			assert_bool(sizes.has(offer["plane_size"])).is_true()
			var traits: Dictionary = offer["traits"]
			var booked: Array = sizes[offer["plane_size"]]
			assert_int(offer["booked_passengers"]).is_between(
				OfferTraits.fewest_booked(booked[0], booked[1], traits), booked[1]
			)
			var fees: Array = OfferBoard.fee_range_for(own, offer["plane_size"])
			var minute: int = offer["departure_minute"]
			assert_int(offer["fee_per_passenger"]).is_between(
				OfferBoard.apply_peak_bonus(OfferTraits.fee_of(fees[0], traits), minute),
				OfferBoard.apply_peak_bonus(OfferTraits.fee_of(fees[1], traits), minute)
			)
			var terms := OfferBoard.terms_of(offer)
			assert_str(FlightContract.problem(terms, FlightContract.TERM_KEYS)).is_empty()


## Large planes are offered at Tier 1+ on a large runway (PlaneClasses.max_offer_class() == LARGE),
## while Tier 0 stays small and medium only.
func test_no_tier_draws_a_large_offer_and_small_and_medium_still_draw() -> void:
	assert_str(PlaneClasses.max_offer_class()).is_equal(PlaneClasses.LARGE)
	var starter_seen := {}
	for stars in [1.0, 2.5]:
		var tier := RatingFormula.tier(stars)
		var offers := _draw_days(tier)
		print("%.1f stars -> tier %d: %d offers" % [stars, tier, offers.size()])
		assert_array(_large_offers(offers)).override_failure_message("%s stars" % stars).is_empty()
		for offer in offers:
			starter_seen[offer["plane_size"]] = true
	assert_array(starter_seen.keys()).contains_exactly_in_any_order(["small", "medium"])
	var high_seen := {}
	for stars in [3.0, 3.5, 4.0, 5.0]:
		var tier := RatingFormula.tier(stars)
		var offers := _draw_days(tier)
		print("%.1f stars -> tier %d: %d offers" % [stars, tier, offers.size()])
		(
			assert_array(_large_offers(offers))
			. override_failure_message("%s stars" % stars)
			. is_not_empty()
		)
		for offer in offers:
			high_seen[offer["plane_size"]] = true
	assert_array(high_seen.keys()).contains_exactly_in_any_order(["small", "medium", "large"])


func test_the_offer_gate_leaves_every_tier_with_medium_and_tier_zero_untouched() -> void:
	assert_dict(OfferBoard.offered_sizes(0)).is_equal(OfferBoard.STARTER_SIZES)
	assert_bool(OfferBoard.offered_sizes(0).has("large")).is_false()
	for tier in range(1, OfferBoard.MAX_TIER + 1):
		var offered := OfferBoard.offered_sizes(tier)
		assert_bool(offered.has("medium")).is_true()
		assert_bool(offered.has("large")).is_true()
		assert_array(OfferBoard.TIER_AIRLINES[tier]).is_not_empty()


func test_a_saved_large_offer_still_loads_and_is_accepted_as_a_contract() -> void:
	var board := OfferBoard.new()
	assert_bool(board.from_snapshot(_day_with_first(_tier_one_record()))).is_true()
	assert_str(board.offer_of("O0N1")["plane_size"]).is_equal("large")
	var sim := auto_free(FlightSim.new()) as FlightSim
	sim.open_airport()
	assert_bool(board.accept("O0N1", sim)).is_true()


func test_the_rng_advances_the_same_whatever_the_tier() -> void:
	var states := []
	for tier in OfferBoard.MAX_TIER + 1:
		var rng := RandomNumberGenerator.new()
		rng.seed = 55
		OfferBoard.new().ensure_day(3, rng, tier)
		states.append(rng.state)
	assert_array(states).contains_exactly([states[0], states[0], states[0]])


func test_a_tier_outside_the_table_is_refused_and_changes_nothing() -> void:
	var board := OfferBoard.new()
	var state := _rng.state
	for tier in [-1, OfferBoard.MAX_TIER + 1]:
		await (
			assert_error(func() -> void: board.ensure_day(0, _rng, tier))
			. is_push_error("OfferBoard: tier %d is outside 0..%d" % [tier, OfferBoard.MAX_TIER])
		)
	assert_array(board.open_offers()).is_empty()
	assert_int(_rng.state).is_equal(state)


func test_tiered_offers_survive_a_save_and_load() -> void:
	var board := OfferBoard.new()
	board.ensure_day(0, _rng, OfferBoard.MAX_TIER)
	board.ensure_day(1, _rng, 1)
	var through_json: Dictionary = JSON.parse_string(JSON.stringify(board.to_snapshot()))
	var loaded := OfferBoard.new()
	assert_bool(loaded.from_snapshot(through_json)).is_true()
	assert_dict(loaded.to_snapshot()).is_equal(board.to_snapshot())


## A saved tier-1 offer with terms in the tier's ranges.
func _tier_one_record() -> Dictionary:
	var record := TestOfferBoard.record("O0N1", 0, 660)
	record["airline"] = OfferBoard.TIER_AIRLINES[1][0]
	record["plane_size"] = "large"
	record["booked_passengers"] = OfferBoard.TIER_SIZES[1]["large"][0]
	record["fee_per_passenger"] = OfferBoard.TIER_FEES[1][0]
	return record


func _day_with_first(first: Dictionary) -> Dictionary:
	var offers := TestOfferBoard.day_records(0, [660, 720, 840])
	offers[0] = first
	return TestOfferBoard.save_of(offers)


func test_a_tier_one_offer_loads_and_is_checked_against_its_own_tier() -> void:
	assert_bool(OfferBoard.new().from_snapshot(_day_with_first(_tier_one_record()))).is_true()
	var cases: Array = [
		["plane_size", "small"],
		["booked_passengers", OfferBoard.TIER_SIZES[1]["large"][1] + 1],
		["booked_passengers", OfferBoard.TIER_SIZES[1]["large"][0] - 1],
		["fee_per_passenger", OfferBoard.TIER_FEES[1][1] + 1],
		["fee_per_passenger", OfferBoard.TIER_FEES[1][0] - 1],
	]
	for case in cases:
		var bad := _tier_one_record()
		bad[case[0]] = case[1]
		var board := OfferBoard.new()
		(
			assert_bool(board.from_snapshot(_day_with_first(bad)))
			. override_failure_message(str(case))
			. is_false()
		)
		assert_array(board.open_offers()).is_empty()


func test_a_starter_airline_cannot_carry_a_higher_tiers_terms() -> void:
	var bad := TestOfferBoard.record("O0N1", 0, 660)
	bad["plane_size"] = "large"
	bad["booked_passengers"] = OfferBoard.TIER_SIZES[1]["large"][0]
	assert_bool(OfferBoard.new().from_snapshot(_day_with_first(bad))).is_false()
	var dear := TestOfferBoard.record("O0N1", 0, 660)
	dear["plane_size"] = "medium"
	dear["booked_passengers"] = OfferBoard.STARTER_SIZES["medium"][0]
	dear["fee_per_passenger"] = OfferBoard.TIER_FEES[1][1]
	assert_bool(OfferBoard.new().from_snapshot(_day_with_first(dear))).is_false()
	var over_small := TestOfferBoard.record("O0N1", 0, 660)
	over_small["fee_per_passenger"] = OfferBoard.SMALL_FEE_MAX + 1
	assert_bool(OfferBoard.new().from_snapshot(_day_with_first(over_small))).is_false()


## Version 5 added the Loyal airline count and each offer's loyal mark, version 6
## Odd hours and Exit fee, version 7 small-class 4-8 passengers and 30-70 base
## fees, version 8 dedicated same-day charters, version 9 peak-hour rush wave
## fee validation, version 10 multi-tier loyalty & Gold Hub contracts, and
## version 11 required day1_intro_shown bool, so versions 4 through 10 are
## refused.
func test_the_offer_save_version_is_11_and_versions_4_to_10_are_refused() -> void:
	assert_int(OfferBoard.SAVE_VERSION).is_equal(11)
	var board := OfferBoard.new()
	board.ensure_day(0, _rng, OfferBoard.MAX_TIER)
	var data := board.to_snapshot()
	assert_int(int(data["save_version"])).is_equal(OfferBoard.SAVE_VERSION)
	for old_version in [4, 5, 6, 7, 8, 9, 10]:
		data["save_version"] = old_version
		assert_bool(OfferBoard.new().from_snapshot(data)).is_false()
	# The control: the same save at the current version loads.
	data["save_version"] = OfferBoard.SAVE_VERSION
	assert_bool(OfferBoard.new().from_snapshot(data)).is_true()


func test_small_class_revenue_matches_starter_and_medium_stays_untouched() -> void:
	var starter := FlightSim.STARTER_TERMS
	assert_str(starter["plane_size"]).is_equal(PlaneClasses.SMALL)
	assert_int(starter["booked_passengers"]).is_equal(6)
	assert_int(starter["fee_per_passenger"]).is_equal(50)
	assert_int(int(starter["booked_passengers"]) * int(starter["fee_per_passenger"])).is_equal(300)
	var small_pax: Array = OfferBoard.STARTER_SIZES[PlaneClasses.SMALL]
	assert_array(small_pax).is_equal([4, 8])
	var small_fees: Array = OfferBoard.fee_range_for(0, PlaneClasses.SMALL)
	assert_array(small_fees).is_equal([30, 70])
	assert_int(int(small_pax[0]) * int(small_fees[0])).is_equal(120)
	assert_int(int(small_pax[1]) * int(small_fees[1])).is_equal(560)
	@warning_ignore("integer_division")
	var mid_rev := (
		((int(small_pax[0]) + int(small_pax[1])) / 2)
		* ((int(small_fees[0]) + int(small_fees[1])) / 2)
	)
	assert_int(mid_rev).is_equal(300)
	assert_array(OfferBoard.STARTER_SIZES[PlaneClasses.MEDIUM]).is_equal([24, 48])
	assert_array(OfferBoard.fee_range_for(0, PlaneClasses.MEDIUM)).is_equal([15, 35])
	assert_array(OfferBoard.TIER_FEES).is_equal([[15, 35], [25, 45], [40, 60]])
