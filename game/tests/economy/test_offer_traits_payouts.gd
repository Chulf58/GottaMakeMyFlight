class_name TestOfferTraitsPayouts
extends GdUnitTestSuite
## Slice 2 of the offer traits (decision airline-offer-traits-each-offer-pairs-
## an-upside-with-a-downs): Signing bonus and Loyal airline join the upsides and
## Miss fine the downsides, at the same two levels, with their money numbers
## and card labels in the table.

const ALL_LIVE := {OfferTraits.NEEDS_BAGS: true, OfferTraits.NEEDS_SHOPS: true}


func test_the_three_money_traits_are_in_the_table_at_both_levels() -> void:
	assert_bool(OfferTraits.UPS.has(OfferTraits.SIGNING_BONUS)).is_true()
	assert_bool(OfferTraits.UPS.has(OfferTraits.LOYAL_AIRLINE)).is_true()
	assert_bool(OfferTraits.DOWNS.has(OfferTraits.MISS_FINE)).is_true()
	assert_array(OfferTraits.TABLE[OfferTraits.SIGNING_BONUS]["values"]).is_equal([150, 300])
	assert_array(OfferTraits.TABLE[OfferTraits.MISS_FINE]["values"]).is_equal([10, 20])
	assert_array(OfferTraits.TABLE[OfferTraits.LOYAL_AIRLINE]["values"]).is_equal([10, 10])
	assert_array(Array(OfferTraits.card_labels(_paired("signing_bonus", "miss_fine", 2)))).is_equal(
		["Signing bonus $300", "Miss fine $20"]
	)
	assert_array(Array(OfferTraits.card_labels(_paired("loyal_airline", "miss_fine", 1)))).is_equal(
		["Loyal airline", "Miss fine $10"]
	)


func test_the_money_queries_read_the_level_or_zero_without_the_trait() -> void:
	assert_int(OfferTraits.miss_fine(_paired("top_fare", "miss_fine", 1))).is_equal(10)
	assert_int(OfferTraits.miss_fine(_paired("top_fare", "miss_fine", 2))).is_equal(20)
	assert_int(OfferTraits.miss_fine(_paired("top_fare", "rush_crowd", 2))).is_equal(0)
	assert_int(OfferTraits.miss_fine({})).is_equal(0)
	assert_int(OfferTraits.signing_bonus(_paired("signing_bonus", "heavy_bags", 1))).is_equal(150)
	assert_int(OfferTraits.signing_bonus(_paired("signing_bonus", "heavy_bags", 2))).is_equal(300)
	assert_int(OfferTraits.signing_bonus(_paired("top_fare", "heavy_bags", 2))).is_equal(0)
	assert_bool(OfferTraits.builds_loyalty(_paired("loyal_airline", "rush_crowd", 2))).is_true()
	assert_bool(OfferTraits.builds_loyalty(_paired("top_fare", "rush_crowd", 2))).is_false()
	assert_bool(OfferTraits.builds_loyalty({})).is_false()


func test_signing_bonus_and_loyal_airline_pair_with_every_downside() -> void:
	var pairs := OfferTraits.pairs(ALL_LIVE)
	for down in OfferTraits.DOWNS:
		assert_bool(pairs.has([OfferTraits.SIGNING_BONUS, down])).is_true()
		assert_bool(pairs.has([OfferTraits.LOYAL_AIRLINE, down])).is_true()
	for up in OfferTraits.UPS:
		var allowed := not OfferTraits.is_forbidden(up, OfferTraits.MISS_FINE)
		assert_bool(pairs.has([up, OfferTraits.MISS_FINE])).is_equal(allowed)
	# Miss fine and the money upsides need nothing, so they are drawn with no
	# bag room and no shop.
	var bare := OfferTraits.pairs({})
	assert_bool(bare.has([OfferTraits.SIGNING_BONUS, OfferTraits.MISS_FINE])).is_true()
	assert_bool(bare.has([OfferTraits.LOYAL_AIRLINE, OfferTraits.RUSH_CROWD])).is_true()


func test_a_loyal_fee_is_ten_percent_more_rounded_half_up_and_never_stacks() -> void:
	assert_int(OfferTraits.loyal_fee_of(20, true)).is_equal(22)
	assert_int(OfferTraits.loyal_fee_of(25, true)).is_equal(28)
	assert_int(OfferTraits.loyal_fee_of(15, true)).is_equal(17)
	assert_int(OfferTraits.loyal_fee_of(25, false)).is_equal(25)
	assert_str(OfferTraits.LOYAL_LABEL).is_equal("Loyal: +10%")


func test_every_new_pair_is_drawn_over_many_days() -> void:
	var seen := {}
	for day in 400:
		for traits in OfferTraits.draw_day(77, day, 3, 2, ALL_LIVE):
			if not traits.is_empty():
				seen[[traits["up"], traits["down"]]] = true
	assert_bool(seen.has([OfferTraits.SIGNING_BONUS, OfferTraits.MISS_FINE])).is_true()
	assert_bool(seen.has([OfferTraits.LOYAL_AIRLINE, OfferTraits.HEAVY_BAGS])).is_true()
	assert_int(seen.size()).is_equal(OfferTraits.pairs(ALL_LIVE).size())


static func _paired(up: String, down: String, level: int) -> Dictionary:
	return {"up": up, "down": down, "level": level}
