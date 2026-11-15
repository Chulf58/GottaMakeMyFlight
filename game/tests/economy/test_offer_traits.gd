class_name TestOfferTraits
extends GdUnitTestSuite
## The offer trait table and its pure queries (decision airline-offer-traits-
## each-offer-pairs-an-upside-with-a-downs): the catalogue, the checks a saved
## traits term must pass, the fee, booking, missed-bag and pair rules, and the
## day draw from its own seeded stream.

const ALL_LIVE := {OfferTraits.NEEDS_BAGS: true, OfferTraits.NEEDS_SHOPS: true}
const DAYS := 200


static func paired(up: String, down: String, level: int) -> Dictionary:
	return {"up": up, "down": down, "level": level}


func test_every_trait_has_a_label_a_tip_and_a_value_per_level() -> void:
	for id in OfferTraits.UPS + OfferTraits.DOWNS:
		var row: Dictionary = OfferTraits.TABLE[id]
		for field in ["labels", "tips", "values"]:
			assert_array(row[field]).override_failure_message(id).has_size(2)
		(
			assert_bool(["", OfferTraits.NEEDS_BAGS, OfferTraits.NEEDS_SHOPS].has(row["needs"]))
			. is_true()
		)
	assert_int(OfferTraits.TABLE.size()).is_equal(11)


func test_plain_and_every_allowed_pair_are_valid_and_the_forbidden_pairs_are_not() -> void:
	assert_str(OfferTraits.problem({})).is_empty()
	var valid := 0
	for up in OfferTraits.UPS:
		for down in OfferTraits.DOWNS:
			for level in OfferTraits.LEVELS:
				var problem := OfferTraits.problem(paired(up, down, level))
				if OfferTraits.is_forbidden(up, down):
					assert_str(problem).contains("cancel out")
				else:
					assert_str(problem).is_empty()
					valid += 1
	assert_int(valid).is_equal(56)
	assert_bool(OfferTraits.is_forbidden(OfferTraits.SHOPPERS, OfferTraits.RUSH_CROWD)).is_true()
	assert_bool(OfferTraits.is_forbidden(OfferTraits.BAG_COVER, OfferTraits.HEAVY_BAGS)).is_true()


func test_a_json_level_loads_and_bad_traits_are_refused() -> void:
	var from_json: Variant = JSON.parse_string(
		JSON.stringify(paired(OfferTraits.TOP_FARE, OfferTraits.RUSH_CROWD, 2))
	)
	assert_str(OfferTraits.problem(from_json)).is_empty()
	assert_int(typeof(OfferTraits.frozen(from_json)["level"])).is_equal(TYPE_INT)
	var bad: Array = [
		"top_fare",
		{"up": OfferTraits.TOP_FARE},
		paired(OfferTraits.TOP_FARE, OfferTraits.RUSH_CROWD, 3),
		{"up": OfferTraits.TOP_FARE, "down": OfferTraits.RUSH_CROWD, "level": 1.5},
		paired(OfferTraits.RUSH_CROWD, OfferTraits.TOP_FARE, 1),
		paired("free_lunch", OfferTraits.RUSH_CROWD, 1),
		{"up": 1, "down": OfferTraits.RUSH_CROWD, "level": 1},
		{"up": OfferTraits.TOP_FARE, "down": OfferTraits.RUSH_CROWD, "level": 1, "x": 1},
	]
	for traits in bad:
		assert_str(OfferTraits.problem(traits)).override_failure_message(str(traits)).is_not_empty()


func test_frozen_traits_are_a_read_only_copy() -> void:
	var source := paired(OfferTraits.TOP_FARE, OfferTraits.RUSH_CROWD, 1)
	var frozen := OfferTraits.frozen(source)
	source["level"] = 2
	assert_bool(frozen.is_read_only()).is_true()
	assert_int(frozen["level"]).is_equal(1)
	assert_bool(OfferTraits.frozen({}).is_read_only()).is_true()


func test_fees_follow_top_fare_and_plain_terms() -> void:
	assert_int(OfferTraits.fee_of(20, {})).is_equal(18)
	assert_int(OfferTraits.fee_of(35, {})).is_equal(32)
	var top_1 := paired(OfferTraits.TOP_FARE, OfferTraits.RUSH_CROWD, 1)
	var top_2 := paired(OfferTraits.TOP_FARE, OfferTraits.RUSH_CROWD, 2)
	assert_int(OfferTraits.fee_of(20, top_1)).is_equal(23)
	assert_int(OfferTraits.fee_of(20, top_2)).is_equal(26)
	var other := paired(OfferTraits.FULL_FLIGHT, OfferTraits.RUSH_CROWD, 2)
	assert_int(OfferTraits.fee_of(20, other)).is_equal(20)


func test_full_flight_books_from_the_top_of_the_range() -> void:
	var half := paired(OfferTraits.FULL_FLIGHT, OfferTraits.RUSH_CROWD, 1)
	var quarter := paired(OfferTraits.FULL_FLIGHT, OfferTraits.RUSH_CROWD, 2)
	# Medium: 24 to 48 booked.
	assert_int(OfferTraits.booked_of(24, 48, half)).is_equal(36)
	assert_int(OfferTraits.booked_of(48, 48, half)).is_equal(48)
	assert_int(OfferTraits.booked_of(24, 48, quarter)).is_equal(42)
	assert_int(OfferTraits.fewest_booked(24, 48, quarter)).is_equal(42)
	assert_int(OfferTraits.booked_of(30, 48, {})).is_equal(30)
	var top := paired(OfferTraits.TOP_FARE, OfferTraits.RUSH_CROWD, 2)
	assert_int(OfferTraits.booked_of(30, 48, top)).is_equal(30)


func test_a_missed_bag_costs_what_the_bag_traits_say() -> void:
	var cases := [
		[{}, PriceTable.MISSED_BAG_FEE_PERCENT],
		[paired(OfferTraits.BAG_COVER, OfferTraits.RUSH_CROWD, 1), 75],
		[paired(OfferTraits.BAG_COVER, OfferTraits.RUSH_CROWD, 2), 100],
		[paired(OfferTraits.TOP_FARE, OfferTraits.HEAVY_BAGS, 1), 25],
		[paired(OfferTraits.TOP_FARE, OfferTraits.HEAVY_BAGS, 2), 0],
		[paired(OfferTraits.TOP_FARE, OfferTraits.RUSH_CROWD, 2), 50],
	]
	for case in cases:
		var paid := OfferTraits.missed_bag_paid_percent(case[0])
		assert_int(paid).override_failure_message(str(case)).is_equal(case[1])


func test_pairs_leave_out_forbidden_pairs_and_traits_whose_need_is_not_met() -> void:
	assert_array(OfferTraits.pairs(ALL_LIVE)).has_size(28)
	for pair in OfferTraits.pairs(ALL_LIVE):
		assert_bool(OfferTraits.is_forbidden(pair[0], pair[1])).is_false()
	var none := OfferTraits.pairs({})
	(
		assert_array(none)
		. contains_exactly(
			[
				[OfferTraits.TOP_FARE, OfferTraits.RUSH_CROWD],
				[OfferTraits.TOP_FARE, OfferTraits.MISS_FINE],
				[OfferTraits.TOP_FARE, OfferTraits.ODD_HOURS],
				[OfferTraits.TOP_FARE, OfferTraits.EXIT_FEE],
				[OfferTraits.FULL_FLIGHT, OfferTraits.RUSH_CROWD],
				[OfferTraits.FULL_FLIGHT, OfferTraits.MISS_FINE],
				[OfferTraits.FULL_FLIGHT, OfferTraits.ODD_HOURS],
				[OfferTraits.FULL_FLIGHT, OfferTraits.EXIT_FEE],
				[OfferTraits.SIGNING_BONUS, OfferTraits.RUSH_CROWD],
				[OfferTraits.SIGNING_BONUS, OfferTraits.MISS_FINE],
				[OfferTraits.SIGNING_BONUS, OfferTraits.ODD_HOURS],
				[OfferTraits.SIGNING_BONUS, OfferTraits.EXIT_FEE],
				[OfferTraits.LOYAL_AIRLINE, OfferTraits.RUSH_CROWD],
				[OfferTraits.LOYAL_AIRLINE, OfferTraits.MISS_FINE],
				[OfferTraits.LOYAL_AIRLINE, OfferTraits.ODD_HOURS],
				[OfferTraits.LOYAL_AIRLINE, OfferTraits.EXIT_FEE],
			]
		)
	)
	var shops_only := OfferTraits.pairs({OfferTraits.NEEDS_SHOPS: true})
	assert_array(shops_only).has_size(19)
	var bags_only := OfferTraits.pairs({OfferTraits.NEEDS_BAGS: true})
	assert_array(bags_only).has_size(24)


func test_a_day_has_one_plain_offer_and_paired_offers_at_one_level() -> void:
	for day in DAYS:
		var traits := OfferTraits.draw_day(77, day, 3, 1, ALL_LIVE)
		var plain := 0
		for each in traits:
			assert_str(OfferTraits.problem(each)).is_empty()
			assert_bool(each.is_read_only()).is_true()
			plain += int(OfferTraits.is_plain(each))
		assert_int(plain).is_equal(1)


func test_the_draw_is_a_function_of_seed_and_day() -> void:
	assert_array(OfferTraits.draw_day(5, 9, 3, 2, ALL_LIVE)).is_equal(
		OfferTraits.draw_day(5, 9, 3, 2, ALL_LIVE)
	)
	var differs := false
	for day in 20:
		var mine := OfferTraits.draw_day(5, day, 3, 2, ALL_LIVE)
		differs = differs or mine != OfferTraits.draw_day(6, day, 3, 2, ALL_LIVE)
	assert_bool(differs).is_true()
	assert_int(OfferTraits.seed_for(5, 9)).is_not_equal(OfferTraits.seed_for(5, 10))


func test_levels_follow_the_tier_and_unmet_needs_are_never_drawn() -> void:
	var level_2 := [0, 0, 0]
	var drawn := {}
	for tier in 3:
		for day in DAYS:
			for each in OfferTraits.draw_day(31, day, 3, tier, {}):
				if not OfferTraits.is_plain(each):
					level_2[tier] += int(each["level"] == 2)
					drawn[each["up"]] = true
					drawn[each["down"]] = true
	assert_int(level_2[0]).is_equal(0)
	# 2 paired offers a day: tier 1 about half level 2, tier 2 about three in four.
	assert_int(level_2[1]).is_between(DAYS * 2 * 35 / 100, DAYS * 2 * 65 / 100)
	assert_int(level_2[2]).is_greater(DAYS * 2 * 65 / 100)
	(
		assert_array(drawn.keys())
		. contains_exactly_in_any_order(
			[
				OfferTraits.TOP_FARE,
				OfferTraits.FULL_FLIGHT,
				OfferTraits.SIGNING_BONUS,
				OfferTraits.LOYAL_AIRLINE,
				OfferTraits.RUSH_CROWD,
				OfferTraits.MISS_FINE,
				OfferTraits.ODD_HOURS,
				OfferTraits.EXIT_FEE,
			]
		)
	)


func test_every_live_pair_is_drawn_and_no_forbidden_pair_ever_is() -> void:
	var seen := {}
	for day in DAYS:
		for each in OfferTraits.draw_day(4242, day, 3, 1, ALL_LIVE):
			if not OfferTraits.is_plain(each):
				assert_bool(OfferTraits.is_forbidden(each["up"], each["down"])).is_false()
				seen[[each["up"], each["down"]]] = true
	assert_int(seen.size()).is_equal(28)


func test_card_labels_name_both_sides_or_plain_terms() -> void:
	var traits := paired(OfferTraits.TOP_FARE, OfferTraits.RUSH_CROWD, 2)
	assert_array(Array(OfferTraits.card_labels(traits))).is_equal(
		["Top fare +30%", "Big rush crowd"]
	)
	assert_array(Array(OfferTraits.card_labels({}))).is_equal([OfferTraits.PLAIN_LABEL, ""])
	assert_str(OfferTraits.card_tips(traits)[1]).contains("45%")
