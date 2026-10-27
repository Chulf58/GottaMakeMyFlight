class_name TestOfferDesk
extends GdUnitTestSuite
## OfferDesk draws each game day's offers from SimClock.rng: today's on a new
## game, then one set as the clock enters each new day (GameCalendar.day_of),
## and never twice for one day.

var _clock: SimClock
var _desk: OfferDesk
var _changes := 0


func before_test() -> void:
	_changes = 0
	_clock = auto_free(SimClock.new()) as SimClock
	_clock.seed_rng(2024)
	_desk = auto_free(OfferDesk.new()) as OfferDesk
	_desk.board.changed.connect(func() -> void: _changes += 1)


## Moves the clock to `tick` and announces it, as SimClock.advance does.
func _tick_to(tick: int) -> void:
	_clock.tick = tick
	_clock.ticked.emit(tick)


## The offers a bare board draws for `days` in order from a clock seeded alike.
func _replay(days: Array) -> OfferBoard:
	var board := OfferBoard.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	for day in days:
		board.ensure_day(day, rng)
	return board


func test_a_new_game_draws_day_zeros_offers_from_the_clock_rng() -> void:
	_desk.bind_clock(_clock)
	assert_array(_desk.board.open_offers()).has_size(OfferBoard.OFFERS_PER_DAY)
	assert_array(_desk.board.open_offers()).is_equal(_replay([0]).open_offers())
	for offer in _desk.board.open_offers():
		assert_int(offer["day"]).is_equal(0)


func test_ticks_inside_the_day_draw_nothing_more() -> void:
	_desk.bind_clock(_clock)
	var state := _clock.rng.state
	for tick in [1, 1000, GameCalendar.day_start(1) - 1]:
		_tick_to(tick)
	assert_int(_changes).is_equal(1)
	assert_int(_clock.rng.state).is_equal(state)


func test_midnight_draws_the_new_days_offers_and_expires_the_old() -> void:
	_desk.bind_clock(_clock)
	var day0 := _desk.board.open_offers()
	_tick_to(GameCalendar.day_start(1) - 1)
	_tick_to(GameCalendar.day_start(1))
	assert_int(GameCalendar.day_of(_clock.tick)).is_equal(1)
	for offer in day0:
		assert_str(_desk.board.offer_of(offer["id"])["status"]).is_equal(OfferBoard.EXPIRED)
	assert_array(_desk.board.open_offers()).has_size(OfferBoard.OFFERS_PER_DAY)
	for offer in _desk.board.open_offers():
		assert_int(offer["day"]).is_equal(1)
	assert_array(_desk.board.open_offers()).is_equal(_replay([0, 1]).open_offers())


func test_each_day_draws_exactly_once() -> void:
	_desk.bind_clock(_clock)
	for day in [1, 2]:
		_tick_to(GameCalendar.day_start(day))
		_tick_to(GameCalendar.day_start(day) + 1)
		_tick_to(GameCalendar.day_start(day) + 5000)
	assert_int(_changes).is_equal(3)
	assert_array(_desk.board.open_offers()).is_equal(_replay([0, 1, 2]).open_offers())
	assert_int(_desk.board.to_snapshot()["offers"].size()).is_equal(3 * OfferBoard.OFFERS_PER_DAY)


func test_a_clock_already_past_day_zero_draws_its_own_day() -> void:
	_clock.tick = GameCalendar.day_start(3) + 100
	_desk.bind_clock(_clock)
	for offer in _desk.board.open_offers():
		assert_int(offer["day"]).is_equal(3)
	assert_array(_desk.board.open_offers()).is_equal(_replay([3]).open_offers())


func test_a_board_that_already_holds_today_is_not_redrawn_on_bind() -> void:
	var loaded := _replay([0])
	assert_bool(_desk.board.from_snapshot(loaded.to_snapshot())).is_true()
	_changes = 0
	var state := _clock.rng.state
	_desk.bind_clock(_clock)
	assert_int(_changes).is_equal(0)
	assert_int(_clock.rng.state).is_equal(state)


func test_an_unbound_desk_draws_nothing() -> void:
	assert_array(_desk.board.open_offers()).is_empty()
