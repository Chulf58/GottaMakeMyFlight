class_name TestRatingBadgeMain
extends GdUnitTestSuite
## The rating on the real main scene (Rating 2a): main.tscn holds an
## AirportRating whose clock, flights and passengers are the scene's own, and a
## RatingBadge that reads it. One boot of main.tscn for the file.

const MAIN := "res://main/main.tscn"

var _main: Node


func before() -> void:
	_main = load(MAIN).instantiate()
	add_child(_main)
	(_main.get_node("SimClock") as SimClock).set_paused(true)


func after() -> void:
	_main.free()


func test_the_rating_is_bound_to_the_scenes_own_clock_flights_and_passengers() -> void:
	var rating: AirportRating = _main.get_node("AirportRating")
	assert_object(rating.clock).is_same(_main.get_node("SimClock"))
	assert_object(rating.flights).is_same(_main.get_node("FlightSim"))
	assert_object(rating.passengers).is_same(_main.get_node("PassengerSim"))
	var clock: SimClock = _main.get_node("SimClock")
	assert_bool(clock.ticked.is_connected(rating.on_tick)).is_true()


func test_a_new_game_shows_no_flights_yet() -> void:
	var badge: RatingBadge = _main.get_node("RatingBadge")
	assert_object(badge.rating).is_same(_main.get_node("AirportRating"))
	assert_str(badge.summary_text()).is_equal("No flights yet")


func test_the_badge_sits_beside_the_money_slot_without_covering_it() -> void:
	var badge: RatingBadge = _main.get_node("RatingBadge")
	var money := (_main.get_node("BuildMenu").find_child("MoneySlot", true, false)) as Control
	assert_object(money).is_not_null()
	var money_rect := Rect2(money.position, money.custom_minimum_size)
	assert_float(badge.card().position.x).is_greater_equal(money_rect.end.x)
	assert_float(badge.card().position.y).is_equal(money.position.y)
