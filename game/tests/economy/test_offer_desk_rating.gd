class_name TestOfferDeskRating
extends GdUnitTestSuite
## OfferDesk draws each day at the airline tier the airport rating has reached
## (RatingFormula.tier) when the day starts. Offers already drawn keep their
## terms for the rest of their day whatever the rating does (immutable offers,
## decision flights-and-economy-design-tick-derived-calendar-timetable-o).

var _clock: SimClock
var _rating: AirportRating
var _desk: OfferDesk


func before_test() -> void:
	_clock = auto_free(SimClock.new()) as SimClock
	_clock.seed_rng(2024)
	_rating = auto_free(AirportRating.new()) as AirportRating
	_desk = auto_free(OfferDesk.new()) as OfferDesk
	_desk.rating = _rating


## Records `made` passengers at `mood` and `missed` ones on day 0.
func _rate(made: int, missed: int, mood: int) -> void:
	for i in made:
		_rating.record_passenger(10, true, mood)
	for i in missed:
		_rating.record_passenger(10, false, 0)


## What the rating means for the board: stars 5 -> tier 2, 3.5 -> 1, 1 -> 0.
func _rate_for_tier(tier: int) -> void:
	match tier:
		2:
			_rate(10, 0, PassengerSim.MOOD_MAX)
		1:
			_rate(5, 5, PassengerSim.MOOD_MAX)
		_:
			_rate(0, 10, 0)
	assert_int(RatingFormula.tier(_rating.stars())).is_equal(tier)


## Moves both to `tick` the way the scene does: the rating, then the desk.
func _tick_to(tick: int) -> void:
	_clock.tick = tick
	_rating.on_tick(tick)
	_clock.ticked.emit(tick)


func _tiers_of_open_offers() -> Array:
	var tiers := []
	for offer in _desk.board.open_offers():
		tiers.append(OfferBoard.tier_of(offer["airline"]))
	return tiers


func _expected_board(day: int, tier: int) -> OfferBoard:
	var board := OfferBoard.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	board.ensure_day(day, rng, tier)
	return board


func test_a_new_game_draws_day_zero_at_the_tier_of_the_starting_rating() -> void:
	_desk.bind_clock(_clock)
	assert_float(_rating.stars()).is_equal(RatingFormula.STARTING_STARS)
	assert_array(_desk.board.open_offers()).is_equal(_expected_board(0, 0).open_offers())


func test_a_loaded_rating_decides_the_first_draw() -> void:
	_rate_for_tier(2)
	_desk.bind_clock(_clock)
	assert_array(_desk.board.open_offers()).is_equal(_expected_board(0, 2).open_offers())


func test_the_next_day_is_drawn_at_the_tier_the_rating_has_reached() -> void:
	_desk.bind_clock(_clock)
	assert_array(_tiers_of_open_offers()).is_equal([0, 0, 0])
	_rate_for_tier(1)
	_tick_to(GameCalendar.day_start(1))
	var drawn := _desk.board.open_offers()
	assert_int(drawn.size()).is_equal(OfferBoard.OFFERS_PER_DAY)
	for offer in drawn:
		assert_int(offer["day"]).is_equal(1)
		assert_int(OfferBoard.tier_of(offer["airline"])).is_less_equal(1)


func test_a_rating_that_rises_mid_day_changes_nothing_until_the_next_day() -> void:
	_desk.bind_clock(_clock)
	var before := _desk.board.open_offers()
	_rate_for_tier(2)
	_tick_to(GameCalendar.day_start(1) - 1)
	assert_array(_desk.board.open_offers()).is_equal(before)


func test_a_low_rating_keeps_the_board_at_the_starter_tier() -> void:
	_rate_for_tier(0)
	assert_bool(_rating.warning()).is_true()
	_desk.bind_clock(_clock)
	_tick_to(GameCalendar.day_start(1))
	for offer in _desk.board.open_offers():
		assert_int(OfferBoard.tier_of(offer["airline"])).is_equal(0)


func test_a_desk_without_a_rating_draws_the_starter_board() -> void:
	_desk.rating = null
	_desk.bind_clock(_clock)
	assert_array(_desk.board.open_offers()).is_equal(_expected_board(0, 0).open_offers())


func test_higher_tiers_show_up_across_days_once_the_rating_is_high() -> void:
	_rate_for_tier(2)
	_desk.bind_clock(_clock)
	var seen := {}
	for day in range(1, 30):
		_rate(10, 0, PassengerSim.MOOD_MAX)
		_tick_to(GameCalendar.day_start(day))
		for offer in _desk.board.open_offers():
			seen[OfferBoard.tier_of(offer["airline"])] = true
	assert_array(seen.keys()).contains([0, 1, 2])


func test_a_desk_in_a_scene_without_a_rating_says_so() -> void:
	var bare := auto_free(OfferDesk.new()) as OfferDesk
	bare.clock = _clock
	bare.flights = auto_free(FlightSim.new()) as FlightSim
	await (
		assert_error(func() -> void: add_child(bare))
		. is_push_error("OfferDesk: no rating set, so every day is drawn at the starter tier")
	)
	assert_int(bare.board.open_offers().size()).is_equal(OfferBoard.OFFERS_PER_DAY)


func test_a_desk_in_a_scene_without_flights_says_so() -> void:
	var bare := auto_free(OfferDesk.new()) as OfferDesk
	bare.clock = _clock
	bare.rating = _rating
	await (
		assert_error(func() -> void: add_child(bare))
		. is_push_error("OfferDesk: no flights set, so no contract will ever end")
	)
