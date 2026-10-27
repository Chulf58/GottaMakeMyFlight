class_name TestRatingFormulaBags
extends GdUnitTestSuite
## Missed bags (Baggage B4) are a smaller part than mood: they take at most
## WEIGHT_BAGS off the score, in proportion to the share of bags missed.


func test_bags_weigh_less_than_the_mood_and_the_made_share() -> void:
	assert_float(RatingFormula.WEIGHT_BAGS).is_greater(0.0)
	assert_float(RatingFormula.WEIGHT_BAGS).is_less(RatingFormula.WEIGHT_MOOD)
	assert_float(RatingFormula.WEIGHT_MOOD).is_less(RatingFormula.WEIGHT_MADE)


func test_no_bags_or_loaded_bags_leave_the_stars_unchanged() -> void:
	assert_float(RatingFormula.stars(10, 0, 1000, 0, 0)).is_equal(5.0)
	assert_float(RatingFormula.stars(10, 0, 1000, 10, 0)).is_equal(5.0)
	assert_float(RatingFormula.stars(5, 5, 500, 8, 0)).is_equal(3.5)


func test_every_bag_missed_takes_the_whole_bag_weight_off() -> void:
	# Score 1.0 - 0.2 = 0.8, 1 + 4 * 0.8 = 4.2, nearest half step 4.0.
	assert_float(RatingFormula.stars(10, 0, 1000, 10, 10)).is_equal(4.0)


func test_half_the_bags_missed_takes_half_the_bag_weight_off() -> void:
	# Score 1.0 - 0.1 = 0.9, 1 + 4 * 0.9 = 4.6, nearest half step 4.5.
	assert_float(RatingFormula.stars(10, 0, 1000, 10, 5)).is_equal(4.5)


func test_the_bag_penalty_never_takes_the_rating_below_one_star() -> void:
	assert_float(RatingFormula.stars(0, 10, 0, 10, 10)).is_equal(1.0)


func test_bags_alone_do_not_move_a_rating_with_no_passengers() -> void:
	assert_float(RatingFormula.stars(0, 0, 0, 5, 5)).is_equal(RatingFormula.STARTING_STARS)
