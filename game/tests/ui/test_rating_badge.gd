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


## The empty-star state as drawn: every fill 0.
func _assert_empty_stars() -> void:
	assert_array(_badge.star_row().fills).is_equal([0.0, 0.0, 0.0, 0.0, 0.0])


func test_it_says_no_flights_yet_and_shows_empty_stars_without_data() -> void:
	assert_bool(_rating.has_data()).is_false()
	assert_str(_badge.label().text).is_equal("No flights yet")
	_assert_empty_stars()
	assert_str(_badge.card().tooltip_text).contains("No flights yet")


func test_it_shows_the_rating_stars_and_their_number_once_there_is_data() -> void:
	_record(100, 3, 80, 1)
	assert_bool(_rating.has_data()).is_true()
	assert_array(_badge.star_row().fills).is_equal(RatingBadge.star_fills(_rating.stars()))
	(
		assert_float(
			_badge.star_row().fills.reduce(func(a: float, b: float) -> float: return a + b)
		)
		. is_equal(_rating.stars())
	)
	assert_str(_badge.label().text).is_equal("%.1f" % _rating.stars())


func test_the_tooltip_gives_the_made_share_the_mood_and_the_days() -> void:
	_record(100, 3, 80, 1)
	var tip := _badge.card().tooltip_text
	assert_str(tip).contains("Made it: 75%")
	assert_str(tip).contains("3 of 4 passengers")
	assert_str(tip).contains("Mood: 80 of 100")
	assert_str(tip).contains("Days counted: 1 of 3")


func test_the_card_carries_the_tooltip_and_the_shared_hud_theme() -> void:
	_record(100, 2, 50)
	assert_object(_badge.card().theme).is_same(BuildMenu.HUD_THEME)
	assert_str(_badge.card().tooltip_text).is_equal(_badge.tooltip_text())
	assert_int(_badge.card().mouse_filter).is_equal(Control.MOUSE_FILTER_STOP)


func test_the_drawn_stars_label_and_tooltip_follow_changed_without_a_refresh() -> void:
	_record(100, 2, 100)
	var fills_before := _badge.star_row().fills.duplicate()
	var text_before := _badge.label().text
	var tip_before := _badge.card().tooltip_text
	assert_str(text_before).is_equal("5.0")
	_record(100, 0, 0, 6)
	assert_array(_badge.star_row().fills).is_not_equal(fills_before)
	assert_array(_badge.star_row().fills).is_equal(RatingBadge.star_fills(_rating.stars()))
	assert_str(_badge.label().text).is_not_equal(text_before)
	assert_str(_badge.label().text).is_equal("%.1f" % _rating.stars())
	assert_str(_badge.card().tooltip_text).is_not_equal(tip_before)
	assert_str(_badge.card().tooltip_text).contains("Made it: 25%")


func test_the_drawn_state_goes_back_to_no_flights_yet_when_the_days_leave_the_window() -> void:
	_record(GameCalendar.tick_at(0, 600), 2, 60)
	assert_str(_badge.label().text).is_not_equal("No flights yet")
	_rating.on_tick(GameCalendar.tick_at(3, 0))
	assert_bool(_rating.has_data()).is_false()
	assert_str(_badge.label().text).is_equal("No flights yet")
	_assert_empty_stars()
	assert_str(_badge.card().tooltip_text).contains("No flights yet")


func test_the_star_colours_come_from_the_hud_theme() -> void:
	var star_row := _badge.star_row()
	for colour in [&"star_fill", &"star_empty", &"star_outline"]:
		assert_bool(BuildMenu.HUD_THEME.has_color(colour, &"RatingStars")).is_true()
		assert_object(star_row.get_theme_color(colour, &"RatingStars")).is_equal(
			BuildMenu.HUD_THEME.get_color(colour, &"RatingStars")
		)
	# A changed palette on the card reaches the stars.
	var palette: Theme = BuildMenu.HUD_THEME.duplicate()
	palette.set_color(&"star_fill", &"RatingStars", Color.RED)
	_badge.card().theme = palette
	assert_object(star_row.get_theme_color(&"star_fill", &"RatingStars")).is_equal(Color.RED)


func test_watching_the_same_rating_twice_connects_once() -> void:
	_badge.watch(_rating)
	assert_int(_rating.changed.get_connections().size()).is_equal(1)


func test_star_fills_follow_half_steps() -> void:
	assert_array(RatingBadge.star_fills(0.0)).is_equal([0.0, 0.0, 0.0, 0.0, 0.0])
	assert_array(RatingBadge.star_fills(2.5)).is_equal([1.0, 1.0, 0.5, 0.0, 0.0])
	assert_array(RatingBadge.star_fills(5.0)).is_equal([1.0, 1.0, 1.0, 1.0, 1.0])
	assert_array(RatingBadge.star_fills(1.0)).is_equal([1.0, 0.0, 0.0, 0.0, 0.0])
