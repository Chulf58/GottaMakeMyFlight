class_name TestRatingContractEnd
extends GdUnitTestSuite
## AirportRating.note_contract_ended (decision low-rating-ends-one-airline-
## contract-per-low-day): once the low days have run out and a contract has
## ended, the low-day count starts again from RatingFormula.LOW_DAYS_AFTER_END.

var _rating: AirportRating
var _changes := 0


func before_test() -> void:
	_changes = 0
	_rating = auto_free(AirportRating.new()) as AirportRating
	_rating.changed.connect(func() -> void: _changes += 1)


## Misses on each of the first `days` days, then rolls to the day after.
func _low_days(days: int) -> void:
	for day in days:
		_rating.record_passenger(GameCalendar.day_start(day), false, 0)
	_rating.on_tick(GameCalendar.day_start(days))


func test_the_count_starts_again_after_an_end() -> void:
	_low_days(RatingFormula.LOW_DAYS_TO_END)
	assert_bool(_rating.contract_ends()).is_true()
	_changes = 0
	assert_bool(_rating.note_contract_ended()).is_true()
	assert_int(_rating.low_days()).is_equal(RatingFormula.LOW_DAYS_AFTER_END)
	assert_bool(_rating.contract_ends()).is_false()
	assert_int(_changes).is_equal(1)


func test_an_end_with_no_ended_due_is_refused_and_changes_nothing() -> void:
	_low_days(1)
	_changes = 0
	await (
		assert_error(func() -> void: _rating.note_contract_ended())
		. is_push_error("AirportRating.note_contract_ended: no contract is due to end")
	)
	assert_int(_rating.low_days()).is_equal(1)
	assert_int(_changes).is_equal(0)


func test_the_reset_count_is_saved_and_restored() -> void:
	_low_days(RatingFormula.LOW_DAYS_TO_END)
	_rating.note_contract_ended()
	var data: Dictionary = JSON.parse_string(JSON.stringify(_rating.to_snapshot()))
	var loaded := auto_free(AirportRating.new()) as AirportRating
	assert_bool(loaded.from_snapshot(data)).is_true()
	assert_int(loaded.low_days()).is_equal(RatingFormula.LOW_DAYS_AFTER_END)
	assert_dict(loaded.to_snapshot()).is_equal(_rating.to_snapshot())


func test_the_next_low_days_count_up_to_the_next_end() -> void:
	_low_days(RatingFormula.LOW_DAYS_TO_END)
	_rating.note_contract_ended()
	var needed := RatingFormula.LOW_DAYS_TO_END - RatingFormula.LOW_DAYS_AFTER_END
	var day := RatingFormula.LOW_DAYS_TO_END
	for i in needed:
		assert_bool(_rating.contract_ends()).is_false()
		_rating.record_passenger(GameCalendar.day_start(day), false, 0)
		day += 1
		_rating.on_tick(GameCalendar.day_start(day))
	assert_bool(_rating.contract_ends()).is_true()
