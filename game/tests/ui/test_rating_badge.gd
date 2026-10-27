class_name TestRatingBadge
extends GdUnitTestSuite
## The rating badge (Rating 2a): stars and a tooltip that follow AirportRating
## on its changed signal, and "No flights yet" while the rating has no data.
## The rating is built alone and fed record_passenger directly, so no world is
## needed.

var _rating: AirportRating
var _badge: RatingBadge


func before_test() -> void:
	_rating = auto_free(AirportRating.new()) as AirportRating
	_badge = auto_free(RatingBadge.new()) as RatingBadge
	_badge.rating = _rating
	add_child(_badge)


## `made` passengers who made it at `mood`, then `missed` who did not, at `tick`.
func _record(tick: int, made: int, mood: int, missed := 0) -> void:
	for i in made:
		_rating.record_passenger(tick, true, mood)
	for i in missed:
		_rating.record_passenger(tick, false, 0)


func test_it_says_no_flights_yet_and_shows_empty_stars_without_data() -> void:
	assert_bool(_rating.has_data()).is_false()
	assert_str(_badge.summary_text()).is_equal("No flights yet")
	assert_float(_badge.shown_stars()).is_equal(0.0)
	assert_str(_badge.tooltip_text()).contains("No flights yet")


func test_it_shows_the_rating_stars_and_their_number_once_there_is_data() -> void:
	_record(100, 3, 80, 1)
	assert_bool(_rating.has_data()).is_true()
	assert_float(_badge.shown_stars()).is_equal(_rating.stars())
	assert_str(_badge.summary_text()).is_equal("%.1f" % _rating.stars())


func test_the_tooltip_gives_the_made_share_the_mood_and_the_days() -> void:
	_record(100, 3, 80, 1)
	var tip := _badge.tooltip_text()
	assert_str(tip).contains("Made it: 75%")
	assert_str(tip).contains("3 of 4 passengers")
	assert_str(tip).contains("Mood: 80 of 100")
	assert_str(tip).contains("Days counted: 1 of 3")


func test_the_card_carries_the_tooltip_and_the_shared_hud_theme() -> void:
	_record(100, 2, 50)
	assert_object(_badge.card().theme).is_same(BuildMenu.HUD_THEME)
	assert_str(_badge.card().tooltip_text).is_equal(_badge.tooltip_text())
	assert_int(_badge.card().mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)


func test_it_follows_changed_without_being_refreshed() -> void:
	_record(100, 2, 100)
	var first := _badge.summary_text()
	_record(100, 0, 0, 6)
	assert_str(_badge.summary_text()).is_not_equal(first)
	assert_str(_badge.summary_text()).is_equal("%.1f" % _rating.stars())
	assert_str(_badge.tooltip_text()).contains("Made it: 25%")


func test_it_goes_back_to_no_flights_yet_when_the_days_leave_the_window() -> void:
	_record(GameCalendar.tick_at(0, 600), 2, 60)
	assert_str(_badge.summary_text()).is_not_equal("No flights yet")
	_rating.on_tick(GameCalendar.tick_at(3, 0))
	assert_bool(_rating.has_data()).is_false()
	assert_str(_badge.summary_text()).is_equal("No flights yet")
	assert_float(_badge.shown_stars()).is_equal(0.0)


func test_watching_the_same_rating_twice_connects_once() -> void:
	_badge.watch(_rating)
	assert_int(_rating.changed.get_connections().size()).is_equal(1)


func test_star_fills_follow_half_steps() -> void:
	assert_array(RatingBadge.star_fills(0.0)).is_equal([0.0, 0.0, 0.0, 0.0, 0.0])
	assert_array(RatingBadge.star_fills(2.5)).is_equal([1.0, 1.0, 0.5, 0.0, 0.0])
	assert_array(RatingBadge.star_fills(5.0)).is_equal([1.0, 1.0, 1.0, 1.0, 1.0])
	assert_array(RatingBadge.star_fills(1.0)).is_equal([1.0, 0.0, 0.0, 0.0, 0.0])
