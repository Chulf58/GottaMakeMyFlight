class_name TestRatingAdjustments
extends GdUnitTestSuite
## Incident adjustments (decision daily-incidents-technical-design-
## incidentdirector-shared-clo): saved half-star shifts owned by AirportRating,
## added after RatingFormula.stars() and clamped to 1-5, active from their
## outcome tick until their expiry tick. stars(), parts(), warning() and the
## day-end low count all read the adjusted stars, so the badge and the contract
## penalties agree. The rating is built alone and fed record_passenger.

var _rating: AirportRating


func before_test() -> void:
	_rating = auto_free(AirportRating.new()) as AirportRating


## `made` passengers at `mood` and `missed` ones at `tick`.
func _record(tick: int, made: int, mood: int, missed: int) -> void:
	for i in made:
		_rating.record_passenger(tick, true, mood)
	for i in missed:
		_rating.record_passenger(tick, false, 0)


func _noon(day: int) -> int:
	return GameCalendar.tick_at(day, 12 * 60)


func test_an_adjustment_shifts_the_stars_by_half_steps() -> void:
	_record(_noon(0), 5, PassengerSim.MOOD_MAX, 5)
	var base := _rating.stars()
	print("base %.1f" % base)
	assert_float(base).is_equal(3.5)
	assert_bool(_rating.add_adjustment("vip-0", _noon(0), _noon(2), -2)).is_true()
	assert_float(_rating.stars()).is_equal(base - 1.0)
	assert_bool(_rating.add_adjustment("spill-0", _noon(0), _noon(2), -1)).is_true()
	assert_float(_rating.stars()).is_equal(base - 1.5)
	var parts := _rating.parts()
	assert_float(parts["stars"]).is_equal(_rating.stars())
	assert_float(parts["base_stars"]).is_equal(base)
	assert_float(parts["adjustment"]).is_equal(-1.5)
	assert_array(_rating.active_adjustments()).has_size(2)


func test_the_adjusted_stars_are_clamped_at_one() -> void:
	_record(_noon(0), 10, PassengerSim.MOOD_MAX, 0)
	assert_float(_rating.stars()).is_equal(RatingFormula.MAX_STARS)
	var most := RatingAdjustments.MAX_HALF_STAR_DELTA
	assert_bool(_rating.add_adjustment("down-a", _noon(0), _noon(1), -most)).is_true()
	assert_bool(_rating.add_adjustment("down-b", _noon(0), _noon(1), -most)).is_true()
	print("adjustment %.1f stars" % _rating.parts()["adjustment"])
	assert_float(_rating.parts()["adjustment"]).is_equal(-float(most))
	assert_float(_rating.stars()).is_equal(RatingFormula.MIN_STARS)


func test_an_adjustment_ends_at_its_expiry_tick() -> void:
	_record(_noon(0), 5, PassengerSim.MOOD_MAX, 5)
	var base := _rating.stars()
	var expiry := _noon(0) + 100
	assert_bool(_rating.add_adjustment("spill", _noon(0), expiry, -1)).is_true()
	var changes := [0]
	_rating.changed.connect(func() -> void: changes[0] += 1)
	_rating.on_tick(expiry - 1)
	assert_float(_rating.stars()).is_equal(base - 0.5)
	assert_int(changes[0]).is_equal(0)
	_rating.on_tick(expiry)
	print("at expiry: stars %.1f, changes %d" % [_rating.stars(), changes[0]])
	assert_float(_rating.stars()).is_equal(base)
	assert_array(_rating.active_adjustments()).is_empty()
	assert_int(changes[0]).is_equal(1)


func test_the_window_expiry_is_the_start_of_the_day_its_passengers_leave_the_window() -> void:
	var outcome := _noon(4)
	var expiry := RatingAdjustments.expiry_for(outcome)
	assert_int(expiry).is_equal(GameCalendar.day_start(4 + RatingFormula.WINDOW_DAYS))
	assert_int(GameCalendar.day_of(expiry - 1)).is_equal(4 + RatingFormula.WINDOW_DAYS - 1)


## Base 2.5 is clear of WARN_BELOW; a one-star adjustment alone makes it low,
## and the badge shows the same stars the warning reads.
func test_an_adjustment_alone_makes_the_rating_low_and_the_badge_agrees() -> void:
	_record(_noon(0), 5, 0, 5)
	assert_float(_rating.stars()).is_equal(2.5)
	assert_bool(_rating.warning()).is_false()
	var badge := auto_free(RatingBadge.new()) as RatingBadge
	badge.rating = _rating
	add_child(badge)
	(
		assert_bool(
			_rating.add_adjustment(
				"inspector", _noon(0), RatingAdjustments.expiry_for(_noon(0)), -2
			)
		)
		. is_true()
	)
	print("adjusted %.1f, badge %.1f" % [_rating.stars(), badge.shown_stars()])
	assert_float(_rating.stars()).is_less(RatingFormula.WARN_BELOW)
	assert_bool(_rating.warning()).is_true()
	assert_float(badge.shown_stars()).is_equal(_rating.stars())
	assert_str(badge.label().text).is_equal("%.1f" % _rating.stars())


## The day-end low count reads the adjusted stars too: the adjustment lasts the
## three days its passengers count, so each of those day ends is low, and the
## first day end after it is not.
func test_the_day_end_low_count_uses_the_adjusted_stars() -> void:
	var control := auto_free(AirportRating.new()) as AirportRating
	for rating: AirportRating in [_rating, control]:
		for i in 5:
			rating.record_passenger(_noon(0), true, 0)
			rating.record_passenger(_noon(0), false, 0)
	var expiry := RatingAdjustments.expiry_for(_noon(0))
	assert_bool(_rating.add_adjustment("inspector", _noon(0), expiry, -2)).is_true()
	for day in range(1, RatingFormula.WINDOW_DAYS + 1):
		for rating: AirportRating in [_rating, control]:
			rating.on_tick(GameCalendar.day_start(day))
		print("day %d: low %d, control %d" % [day, _rating.low_days(), control.low_days()])
		assert_int(_rating.low_days()).is_equal(day)
		assert_int(control.low_days()).is_equal(0)
	_rating.on_tick(GameCalendar.day_start(RatingFormula.WINDOW_DAYS + 1))
	assert_int(_rating.low_days()).is_equal(0)


## The ruling applies adjustments after RatingFormula.stars(), so they move the
## STARTING_STARS of a window with no passengers too, and stars() (the tier
## readers' value) shows it. Without passengers there is still no warning and
## the badge still says "No flights yet", so the two still agree.
func test_with_no_passengers_the_adjustment_moves_the_starting_stars() -> void:
	var badge := auto_free(RatingBadge.new()) as RatingBadge
	badge.rating = _rating
	add_child(badge)
	assert_bool(_rating.add_adjustment("early", 0, 500, -2)).is_true()
	print("no passengers: stars %.1f" % _rating.stars())
	assert_float(_rating.stars()).is_equal(RatingFormula.STARTING_STARS - 1.0)
	assert_int(RatingFormula.tier(_rating.stars())).is_equal(0)
	assert_bool(_rating.warning()).is_false()
	assert_str(badge.label().text).is_equal(RatingBadge.NO_DATA_TEXT)
	_rating.record_passenger(10, true, PassengerSim.MOOD_MAX)
	assert_float(_rating.stars()).is_equal(RatingFormula.MAX_STARS - 1.0)


## An outcome on a day that has already closed would never be counted at that
## day's end, so the badge could go low while low_days stays 0: refused.
func test_an_outcome_before_the_ratings_tick_is_refused() -> void:
	_record(_noon(0), 5, 0, 5)
	_rating.on_tick(_noon(1))
	var before := JSON.stringify(_rating.to_snapshot())
	assert_bool(_rating.add_adjustment("late", _noon(0), _noon(2), -2)).is_false()
	assert_bool(_rating.add_adjustment("late", _noon(1) - 1, _noon(2), -2)).is_false()
	assert_str(JSON.stringify(_rating.to_snapshot())).is_equal(before)
	assert_float(_rating.stars()).is_equal(2.5)
	assert_bool(_rating.add_adjustment("now", _noon(1), _noon(2), -2)).is_true()


## Adjustments are penalties only (conductor ruling on the Sol review): a
## reward is paid as money (Wallet.Category.INCIDENT), so no adjustment can
## open a build tier for good.
func test_bad_adjustments_are_refused_and_change_nothing() -> void:
	_rating.on_tick(1000)
	assert_bool(_rating.add_adjustment("held", 1000, 2000, -1)).is_true()
	var before := JSON.stringify(_rating.to_snapshot())
	var most := RatingAdjustments.MAX_HALF_STAR_DELTA
	var cases := {
		"empty id": ["", 1000, 2000, -1],
		"id already held": ["held", 1000, 2000, -1],
		"zero delta": ["z", 1000, 2000, 0],
		"positive delta": ["up", 1000, 2000, 1],
		"largest positive delta": ["big", 1000, 2000, most],
		"delta below the least": ["small", 1000, 2000, -most - 1],
		"negative outcome": ["neg", -1, 2000, -1],
		"expiry at the outcome": ["same", 1000, 1000, -1],
		"outcome before the tick": ["past", 900, 2000, -1],
	}
	for name: String in cases:
		var args: Array = cases[name]
		var added := _rating.add_adjustment(args[0], args[1], args[2], args[3])
		assert_bool(added).override_failure_message(name).is_false()
		assert_str(JSON.stringify(_rating.to_snapshot())).override_failure_message(name).is_equal(
			before
		)


func test_a_full_list_refuses_one_more() -> void:
	for i in RatingAdjustments.MAX_COUNT:
		assert_bool(_rating.add_adjustment("a%d" % i, 0, 5000, -1)).is_true()
	assert_bool(_rating.add_adjustment("one-more", 0, 5000, -1)).is_false()
	assert_array(_rating.active_adjustments()).has_size(RatingAdjustments.MAX_COUNT)


func test_adding_one_rolls_the_rating_to_its_outcome_tick() -> void:
	assert_bool(_rating.add_adjustment("later", _noon(1), _noon(2), -1)).is_true()
	assert_int(_rating.current_day()).is_equal(1)
	var listed: Dictionary = _rating.active_adjustments()[0]
	assert_dict(listed).is_equal(
		{"id": "later", "outcome_tick": _noon(1), "expiry_tick": _noon(2), "half_star_delta": -1}
	)
