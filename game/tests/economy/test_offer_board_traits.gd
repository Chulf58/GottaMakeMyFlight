class_name TestOfferBoardTraits
extends GdUnitTestSuite
## Offer traits on the board (technical design offer-traits-technical-design-
## offertraits-table-frozen-trait): drawn from their own stream so the base
## offers of a seed are unchanged, the fee and booking traits folded in at draw
## time, frozen on offers and contracts, and kept through a JSON save.

const SEED := 2026
const ALL_LIVE := {OfferTraits.NEEDS_BAGS: true, OfferTraits.NEEDS_SHOPS: true}

var _rng: RandomNumberGenerator


func before_test() -> void:
	_rng = RandomNumberGenerator.new()
	_rng.seed = SEED


## The tier 0 draw replayed by hand from `rng`, in _draw's order: airline,
## destination, slot, size, booked, fee. The slot is one draw: over the quarter
## hours from 07:00 to 21:00, or with Odd hours between 06:00 and 22:00.
static func _replay(rng: RandomNumberGenerator, traits: Dictionary) -> Dictionary:
	var airline: String = OfferBoard.AIRLINES[rng.randi_range(0, OfferBoard.AIRLINES.size() - 1)]
	var destination: String = OfferBoard.DESTINATIONS[rng.randi_range(
		0, OfferBoard.DESTINATIONS.size() - 1
	)]
	var span := FlightContract.window(traits)
	var minute: int
	if OfferTraits.window_widening(traits) > 0:
		minute = span[rng.randi_range(0, 1)]
	else:
		@warning_ignore("integer_division")
		var last_slot: int = (span[1] - span[0]) / OfferBoard.DEPARTURE_STEP
		minute = span[0] + rng.randi_range(0, last_slot) * OfferBoard.DEPARTURE_STEP
	var sizes: Array = OfferBoard.STARTER_SIZES.keys()
	var size: String = sizes[rng.randi_range(0, 1) % sizes.size()]
	var booked_range: Array = OfferBoard.STARTER_SIZES[size]
	var booked := rng.randi_range(booked_range[0], booked_range[1])
	var fees: Array = OfferBoard.fee_range_for(0, size)
	var fee := rng.randi_range(fees[0], fees[1])
	return {
		"airline": airline,
		"destination": destination,
		"departure_minute": minute,
		"plane_size": size,
		"booked": booked,
		"fee": fee,
		"range": booked_range,
	}


func test_the_base_offers_of_a_seed_are_unchanged_and_the_rng_advances_as_before() -> void:
	var board := OfferBoard.new()
	var replay := RandomNumberGenerator.new()
	replay.seed = SEED
	var traited := 0
	for day in 10:
		board.ensure_day(day, _rng, 0, PlaneClasses.LARGE, null, ALL_LIVE)
		for number in range(1, OfferBoard.OFFERS_PER_DAY + 1):
			var offer := board.offer_of("O%dN%d" % [day, number])
			var base := _replay(replay, offer["traits"])
			for key in ["airline", "destination", "departure_minute", "plane_size"]:
				assert_that(offer[key]).is_equal(base[key])
			var traits: Dictionary = offer["traits"]
			assert_int(offer["fee_per_passenger"]).is_equal(OfferTraits.fee_of(base["fee"], traits))
			var booked := OfferTraits.booked_of(base["booked"], base["range"][1], traits)
			assert_int(offer["booked_passengers"]).is_equal(booked)
			traited += int(not OfferTraits.is_plain(traits))
		assert_int(_rng.state).is_equal(replay.state)
	assert_int(traited).is_equal(20)


func test_each_day_has_two_paired_offers_and_one_plain_one_all_frozen() -> void:
	var board := OfferBoard.new()
	for day in 30:
		board.ensure_day(day, _rng, 2, PlaneClasses.LARGE, null, ALL_LIVE)
		var plain := 0
		for number in range(1, OfferBoard.OFFERS_PER_DAY + 1):
			var traits: Dictionary = board.offer_of("O%dN%d" % [day, number])["traits"]
			assert_bool(traits.is_read_only()).is_true()
			plain += int(OfferTraits.is_plain(traits))
		assert_int(plain).is_equal(1)


func test_without_a_bag_room_or_a_shop_no_bag_or_shopper_trait_is_drawn() -> void:
	var board := OfferBoard.new()
	for day in 60:
		board.ensure_day(day, _rng, 1)
	var gated := [OfferTraits.SHOPPERS, OfferTraits.BAG_COVER, OfferTraits.HEAVY_BAGS]
	for offer in board.to_snapshot()["offers"]:
		var traits: Dictionary = offer["traits"]
		if not traits.is_empty():
			assert_bool(gated.has(traits["up"]) or gated.has(traits["down"])).is_false()


func test_traits_survive_a_json_save_frozen_and_with_whole_levels() -> void:
	var board := OfferBoard.new()
	for day in 3:
		board.ensure_day(day, _rng, 2, PlaneClasses.LARGE, null, ALL_LIVE)
	var saved := board.to_snapshot()
	var loaded := OfferBoard.new()
	assert_bool(loaded.from_snapshot(JSON.parse_string(JSON.stringify(saved)))).is_true()
	assert_str(JSON.stringify(loaded.to_snapshot())).is_equal(JSON.stringify(saved))
	for offer in loaded.open_offers():
		var traits: Dictionary = offer["traits"]
		assert_bool(traits.is_read_only()).is_true()
		if not traits.is_empty():
			assert_int(typeof(traits["level"])).is_equal(TYPE_INT)


func test_a_saved_offer_with_impossible_traits_or_fee_is_refused() -> void:
	var cases: Array = [
		["traits", {"up": OfferTraits.SHOPPERS, "down": OfferTraits.RUSH_CROWD, "level": 1}],
		["traits", {"up": "free_lunch", "down": OfferTraits.RUSH_CROWD, "level": 1}],
		["traits", "plain"],
		# A plain offer pays at most 90% of SMALL_FEE_MAX, rounded.
		["fee_per_passenger", OfferBoard.SMALL_FEE_MAX, {}],
		# Top fare +30% pays at least 130% of SMALL_FEE_MIN, rounded.
		[
			"fee_per_passenger",
			OfferBoard.SMALL_FEE_MIN,
			{"up": "top_fare", "down": "rush_crowd", "level": 2}
		],
		# Full flight books from the top half of the small range (6..8) only.
		["booked_passengers", 5, {"up": "full_flight", "down": "rush_crowd", "level": 1}],
	]
	for case in cases:
		var offers := TestOfferBoard.day_records(0, [600, 720, 840])
		offers[0][case[0]] = case[1]
		if case.size() > 2:
			offers[0]["traits"] = case[2]
		var board := OfferBoard.new()
		(
			assert_bool(board.from_snapshot(TestOfferBoard.save_of(offers)))
			. override_failure_message(str(case))
			. is_false()
		)
	var good := TestOfferBoard.day_records(0, [600, 720, 840])
	good[0]["traits"] = {"up": "top_fare", "down": "rush_crowd", "level": 2}
	good[0]["fee_per_passenger"] = OfferTraits.fee_of(OfferBoard.SMALL_FEE_MAX, good[0]["traits"])
	assert_bool(OfferBoard.new().from_snapshot(TestOfferBoard.save_of(good))).is_true()


func test_an_accepted_offer_makes_a_contract_with_its_frozen_traits() -> void:
	var sim: FlightSim = auto_free(FlightSim.new())
	var offers := TestOfferBoard.day_records(0, [600, 720, 840])
	offers[0]["traits"] = {"up": "top_fare", "down": "rush_crowd", "level": 1}
	offers[0]["fee_per_passenger"] = 58
	var board := OfferBoard.new()
	assert_bool(board.from_snapshot(TestOfferBoard.save_of(offers))).is_true()
	assert_bool(board.accept("O0N1", sim)).is_true()
	var contract := sim.contract_of("O0N1")
	assert_dict(contract["traits"]).is_equal(offers[0]["traits"])
	assert_bool((contract["traits"] as Dictionary).is_read_only()).is_true()
	assert_int(contract["fee_per_passenger"]).is_equal(58)
