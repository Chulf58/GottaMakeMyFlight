class_name TestRatingFormula
extends GdUnitTestSuite
## The star formula: 70% share who made their flight, 30% average mood of the
## ones who made it, mapped onto 1 to 5 stars in half steps.


func test_every_passenger_made_it_in_a_good_mood_is_five_stars() -> void:
	assert_float(RatingFormula.stars(10, 0, 1000)).is_equal(5.0)


func test_everyone_missed_is_one_star() -> void:
	assert_float(RatingFormula.stars(0, 10, 0)).is_equal(1.0)


func test_made_share_alone_gives_70_percent_of_the_range() -> void:
	# All made at mood 0: score 0.7, 1 + 4 * 0.7 = 3.8, nearest half step 4.0.
	assert_float(RatingFormula.stars(10, 0, 0)).is_equal(4.0)


func test_half_made_at_full_mood_is_three_and_a_half() -> void:
	# Score 0.7 * 0.5 + 0.3 = 0.65, 1 + 4 * 0.65 = 3.6, nearest half step 3.5.
	assert_float(RatingFormula.stars(5, 5, 500)).is_equal(3.5)


func test_mood_only_counts_the_passengers_who_made_it() -> void:
	# Missed passengers carry mood 0 in the sim; they must not drag the mood part.
	# 0.7 * 10/11 + 0.3 * 1.0 = 0.936: 4.74 rounds to 4.5. Had the mood part
	# averaged over all 11, it would be 0.7 * 10/11 + 0.3 * 0.909 = 0.909: 4.64,
	# also 4.5, so the second case pins the difference.
	assert_float(RatingFormula.stars(10, 1, 1000)).is_equal(4.5)
	# 3 made, 3 missed, mood 100: 0.35 + 0.3 = 0.65 -> 3.5. Averaged over all
	# six the mood part would be 0.15 and the score 0.5 -> 3.0.
	assert_float(RatingFormula.stars(3, 3, 300)).is_equal(3.5)


func test_a_tie_between_two_half_steps_rounds_up() -> void:
	# Two made, mood sum 75 (average 37.5): score 0.8125, exactly 4.25.
	assert_float(RatingFormula.stars(2, 0, 75)).is_equal(4.5)
	# One point less is 4.244, which rounds down.
	assert_float(RatingFormula.stars(2, 0, 74)).is_equal(4.0)


func test_no_passengers_gives_the_starting_rating() -> void:
	assert_float(RatingFormula.stars(0, 0, 0)).is_equal(RatingFormula.STARTING_STARS)
	assert_float(RatingFormula.STARTING_STARS).is_greater_equal(RatingFormula.WARN_BELOW)
	assert_float(RatingFormula.STARTING_STARS).is_less(RatingFormula.TIER_STARS[0])


func test_stars_stay_between_one_and_five_in_half_steps() -> void:
	for made in [0, 1, 3, 10]:
		for missed in [0, 1, 4]:
			for mood in [0, 40, 100]:
				if made + missed == 0:
					continue
				var stars := RatingFormula.stars(made, missed, made * mood)
				assert_float(stars).is_between(1.0, 5.0)
				assert_float(fposmod(stars * 2.0, 1.0)).is_equal(0.0)


func test_tier_counts_the_thresholds_met() -> void:
	assert_array(RatingFormula.TIER_STARS).is_equal([3.0, 4.0])
	assert_int(RatingFormula.tier(1.0)).is_equal(0)
	assert_int(RatingFormula.tier(2.5)).is_equal(0)
	assert_int(RatingFormula.tier(3.0)).is_equal(1)
	assert_int(RatingFormula.tier(3.5)).is_equal(1)
	assert_int(RatingFormula.tier(4.0)).is_equal(2)
	assert_int(RatingFormula.tier(5.0)).is_equal(2)


func test_the_decision_values_are_the_ones_used() -> void:
	assert_int(RatingFormula.WINDOW_DAYS).is_equal(3)
	assert_float(RatingFormula.WARN_BELOW).is_equal(2.0)
	assert_int(RatingFormula.LOW_DAYS_TO_END).is_equal(3)
	assert_float(RatingFormula.WEIGHT_MADE + RatingFormula.WEIGHT_MOOD).is_equal(1.0)
	assert_float(RatingFormula.WEIGHT_MADE).is_greater(RatingFormula.WEIGHT_MOOD)
