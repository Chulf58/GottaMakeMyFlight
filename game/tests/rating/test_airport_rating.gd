class_name TestAirportRating
extends GdUnitTestSuite
## The rolling three-day window, day roll-over, and the low-rating warning and
## contract-end state, on a rating fed directly (no scene).

var _changes := 0


func before_test() -> void:
	_changes = 0


func _rating() -> AirportRating:
	return auto_free(AirportRating.new()) as AirportRating


func _noon(day: int) -> int:
	return GameCalendar.tick_at(day, 12 * 60)


func _midnight(day: int) -> int:
	return GameCalendar.day_start(day)


## Records `made` passengers at `mood` and `missed` misses on `tick`.
func _feed(rating: AirportRating, tick: int, made: int, missed: int, mood := 100) -> void:
	for i in made:
		rating.record_passenger(tick, true, mood)
	for i in missed:
		rating.record_passenger(tick, false, 0)


func _on_changed() -> void:
	_changes += 1


func test_a_new_rating_has_no_data_and_the_starting_stars() -> void:
	var rating := _rating()
	assert_bool(rating.has_data()).is_false()
	assert_float(rating.stars()).is_equal(RatingFormula.STARTING_STARS)
	assert_bool(rating.warning()).is_false()
	assert_int(rating.low_days()).is_equal(0)
	assert_bool(rating.contract_ends()).is_false()


func test_parts_report_the_share_and_average_mood_for_the_tooltip() -> void:
	var rating := _rating()
	_feed(rating, _noon(0), 3, 1, 80)
	var parts := rating.parts()
	assert_int(parts["made"]).is_equal(3)
	assert_int(parts["missed"]).is_equal(1)
	assert_int(parts["passengers"]).is_equal(4)
	assert_float(parts["made_share"]).is_equal(0.75)
	assert_float(parts["mood_avg"]).is_equal(80.0)
	assert_int(parts["days"]).is_equal(1)


func test_the_window_pools_the_last_three_days_and_drops_older_ones() -> void:
	var rating := _rating()
	_feed(rating, _noon(0), 0, 10)
	rating.on_tick(_noon(1))
	_feed(rating, _noon(1), 10, 0)
	# Days 0 and 1 together: half made at full mood, 0.65, 3.5 stars.
	assert_float(rating.stars()).is_equal(3.5)
	rating.on_tick(_noon(2))
	assert_float(rating.stars()).is_equal(3.5)
	# Day 3 pushes day 0 out of the window.
	rating.on_tick(_noon(3))
	assert_float(rating.stars()).is_equal(5.0)
	assert_int(rating.parts()["passengers"]).is_equal(10)
	assert_array(rating.days_held()).is_equal([1])


func test_a_quiet_day_does_not_weigh_as_much_as_a_busy_one() -> void:
	var rating := _rating()
	_feed(rating, _noon(0), 0, 1)
	rating.on_tick(_noon(1))
	_feed(rating, _noon(1), 99, 0)
	# Pooled, one miss in 100 passengers: 0.7 * 0.99 + 0.3 = 0.993 -> 5.0.
	assert_float(rating.stars()).is_equal(5.0)


func test_day_rolls_over_at_midnight() -> void:
	var rating := _rating()
	var last := _midnight(1) - 1
	rating.on_tick(last)
	_feed(rating, last, 1, 0)
	rating.on_tick(_midnight(1))
	_feed(rating, _midnight(1), 0, 1)
	assert_int(rating.current_day()).is_equal(1)
	assert_int(rating.day_totals(0)["made"]).is_equal(1)
	assert_int(rating.day_totals(0)["missed"]).is_equal(0)
	assert_int(rating.day_totals(1)["missed"]).is_equal(1)
	assert_int(rating.day_totals(1)["made"]).is_equal(0)


func test_a_record_after_midnight_rolls_the_day_without_a_tick() -> void:
	var rating := _rating()
	_feed(rating, _noon(0), 1, 0)
	_feed(rating, _noon(1), 2, 0)
	assert_int(rating.current_day()).is_equal(1)
	assert_int(rating.day_totals(1)["made"]).is_equal(2)


func test_jumping_more_than_the_window_clears_everything() -> void:
	var rating := _rating()
	_feed(rating, _noon(0), 0, 10)
	rating.on_tick(_noon(0) + 1)
	rating.on_tick(_noon(5))
	assert_bool(rating.has_data()).is_false()
	assert_int(rating.low_days()).is_equal(0)
	assert_array(rating.days_held()).is_empty()
	assert_float(rating.stars()).is_equal(RatingFormula.STARTING_STARS)


func test_below_two_stars_warns_at_once() -> void:
	var rating := _rating()
	_feed(rating, _noon(0), 1, 9, 0)
	assert_float(rating.stars()).is_less(RatingFormula.WARN_BELOW)
	assert_bool(rating.warning()).is_true()
	assert_bool(rating.contract_ends()).is_false()


func test_two_stars_exactly_does_not_warn() -> void:
	var rating := _rating()
	# 3 made of 8, mood 0: 0.7 * 0.375 = 0.2625, 1 + 4 * 0.2625 = 2.05 -> 2.0.
	_feed(rating, _noon(0), 3, 5, 0)
	assert_float(rating.stars()).is_equal(2.0)
	assert_bool(rating.warning()).is_false()


func test_contract_ends_after_the_warning_day_and_two_more_low_days() -> void:
	var rating := _rating()
	_feed(rating, _noon(0), 0, 10)
	rating.on_tick(_midnight(1))
	assert_int(rating.low_days()).is_equal(1)
	assert_bool(rating.contract_ends()).is_false()
	rating.on_tick(_midnight(2))
	assert_int(rating.low_days()).is_equal(2)
	assert_bool(rating.contract_ends()).is_false()
	rating.on_tick(_midnight(3))
	assert_int(rating.low_days()).is_equal(RatingFormula.LOW_DAYS_TO_END)
	assert_bool(rating.contract_ends()).is_true()


func test_a_recovery_resets_the_count_at_the_next_day_end() -> void:
	var rating := _rating()
	_feed(rating, _noon(0), 0, 10)
	rating.on_tick(_midnight(1))
	assert_int(rating.low_days()).is_equal(1)
	_feed(rating, _noon(1), 90, 0)
	assert_float(rating.stars()).is_greater_equal(RatingFormula.WARN_BELOW)
	rating.on_tick(_midnight(2))
	assert_int(rating.low_days()).is_equal(0)
	assert_bool(rating.warning()).is_false()


func test_an_empty_window_ends_the_low_streak() -> void:
	var rating := _rating()
	_feed(rating, _noon(0), 0, 10)
	rating.on_tick(_midnight(1))
	rating.on_tick(_midnight(2))
	assert_int(rating.low_days()).is_equal(2)
	# Skipping to day 4 evaluates day 3 with day 0 gone: no data, no low day.
	rating.on_tick(_midnight(4))
	assert_int(rating.low_days()).is_equal(0)


func test_changed_is_emitted_when_the_numbers_move() -> void:
	var rating := _rating()
	rating.changed.connect(_on_changed)
	_feed(rating, _noon(0), 1, 0)
	assert_int(_changes).is_equal(1)
	rating.on_tick(_midnight(1))
	assert_int(_changes).is_equal(2)
	# A tick inside the same day changes nothing.
	rating.on_tick(_midnight(1) + 5)
	assert_int(_changes).is_equal(2)
