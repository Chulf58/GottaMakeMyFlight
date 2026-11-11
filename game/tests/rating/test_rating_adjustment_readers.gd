class_name TestRatingAdjustmentReaders
extends GdUnitTestSuite
## Every reader of AirportRating.stars() sees the adjusted stars: the badge
## tooltip (with an "Incident adjustment" line only while one is non-zero),
## the offer desk's airline tier and the build unlocks' star check.

var _rating: AirportRating


func before_test() -> void:
	_rating = auto_free(AirportRating.new()) as AirportRating


## Five made at `mood` and five missed on day 0.
func _half_made(mood: int) -> void:
	for i in 5:
		_rating.record_passenger(10, true, mood)
		_rating.record_passenger(10, false, 0)


func test_the_tooltip_shows_the_incident_adjustment_only_while_it_is_not_zero() -> void:
	var badge := auto_free(RatingBadge.new()) as RatingBadge
	badge.rating = _rating
	add_child(badge)
	_half_made(PassengerSim.MOOD_MAX)
	assert_str(badge.card().tooltip_text).not_contains("Incident adjustment")
	assert_bool(_rating.add_adjustment("vip", 10, 500, -2)).is_true()
	var tip := badge.card().tooltip_text
	print(tip)
	assert_str(tip).contains("Airport rating: 2.5 of 5")
	assert_str(tip).contains("Incident adjustment: -1.0 stars")
	assert_bool(_rating.add_adjustment("spill", 10, 400, -1)).is_true()
	assert_str(badge.card().tooltip_text).contains("Incident adjustment: -1.5 stars")
	_rating.on_tick(400)
	assert_str(badge.card().tooltip_text).contains("Incident adjustment: -1.0 stars")
	_rating.on_tick(500)
	assert_str(badge.card().tooltip_text).not_contains("Incident adjustment")


func _board_at(tier: int) -> Array:
	var board := OfferBoard.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	board.ensure_day(0, rng, tier)
	return board.open_offers()


## Base 3.0 is tier 1; a half-star loss drops the desk's draw to tier 0.
func test_the_offer_desk_draws_at_the_tier_of_the_adjusted_stars() -> void:
	assert_array(_board_at(0)).is_not_equal(_board_at(1))
	_half_made(50)
	assert_int(RatingFormula.tier(_rating.stars())).is_equal(1)
	assert_bool(_rating.add_adjustment("spill", 10, 500, -1)).is_true()
	assert_float(_rating.stars()).is_equal(2.5)
	var clock := auto_free(SimClock.new()) as SimClock
	clock.seed_rng(2024)
	var desk := auto_free(OfferDesk.new()) as OfferDesk
	desk.runway = Runway.new(PlaneClasses.LARGE)
	desk.rating = _rating
	desk.bind_clock(clock)
	assert_array(desk.board.open_offers()).is_equal(_board_at(0))


## Three made at mood 0 of ten is exactly tier 2's 2.0 stars; a half-star
## penalty keeps the tier shut until it expires.
func test_build_unlocks_check_the_adjusted_stars() -> void:
	var pax := auto_free(PassengerSim.new()) as PassengerSim
	var unlocks := auto_free(BuildUnlocks.new()) as BuildUnlocks
	unlocks.rating = _rating
	unlocks.passengers = pax
	unlocks.manual = true
	add_child(unlocks)
	for i in 3:
		_rating.record_passenger(0, true, 0)
	for i in 7:
		_rating.record_passenger(0, false, 0)
	for i in 50:
		pax.outcome.emit(i, true)
	assert_float(_rating.stars()).is_equal(2.0)
	assert_bool(_rating.add_adjustment("spill", 0, 500, -1)).is_true()
	assert_float(_rating.stars()).is_equal(1.5)
	unlocks.check()
	print("tier %d at %.1f stars" % [unlocks.tier(), _rating.stars()])
	assert_int(unlocks.tier()).is_equal(1)
	_rating.on_tick(500)
	unlocks.check()
	print("tier %d at %.1f stars" % [unlocks.tier(), _rating.stars()])
	assert_int(unlocks.tier()).is_equal(2)
