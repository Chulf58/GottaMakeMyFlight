class_name TestOfferDeskMain
extends GdUnitTestSuite
## The rating's effect on offers on the real main scene (Rating 2b): the
## OfferDesk follows the scene's AirportRating and FlightSim, so a low rating
## ends contracts there. One boot of main.tscn for the file.

const MAIN := "res://main/main.tscn"

var _main: Node
var _desk: OfferDesk
var _rating: AirportRating
var _flights: FlightSim


func before() -> void:
	_main = load(MAIN).instantiate()
	add_child(_main)
	(_main.get_node("SimClock") as SimClock).set_paused(true)
	_desk = _main.get_node("OfferDesk")
	_rating = _main.get_node("AirportRating")
	_flights = _main.get_node("FlightSim")


func after() -> void:
	_main.free()


func test_the_desk_follows_the_scenes_own_rating_and_flights() -> void:
	assert_object(_desk.rating).is_same(_rating)
	assert_object(_desk.flights).is_same(_flights)
	assert_object((_main.get_node("OfferPanel") as OfferPanel).desk).is_same(_desk)


func test_three_low_day_ends_end_the_oldest_contract_of_the_scene() -> void:
	assert_bool(_flights.open_airport()).is_true()
	assert_bool(_flights.accept_contract(TestFlightContracts.terms("AM", 480))).is_true()
	assert_bool(_flights.accept_contract(TestFlightContracts.terms("PM", 840))).is_true()
	var ended: Array[String] = []
	_desk.contract_ended.connect(func(contract: Dictionary) -> void: ended.append(contract["id"]))
	for day in range(1, RatingFormula.LOW_DAYS_TO_END + 1):
		_rating.record_passenger(GameCalendar.day_start(day - 1), false, 0)
		_rating.on_tick(GameCalendar.day_start(day))
		_desk.on_tick(GameCalendar.day_start(day))
	assert_array(ended).is_equal(["AM"])
	assert_array(_flights.active_contract_ids()).is_equal(["PM"])
