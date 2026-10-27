class_name TestPassengerHudDepartures
extends GdUnitTestSuite
## The flight panel's list of today's departures (Economy 7/8, DepartureList): every flight
## leaving today in time order, with how far along it is, drawn from the
## contracts' timetable and any one-off flight.

var _world: PassengerTestWorld
var _hud: PassengerHud


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	var grid := PassengerTestWorld.floored(Vector2i(8, 6))
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(0, 5), 3)
	_world = PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(10, 20))
	_hud = PassengerHud.new()
	_hud.clock = _world.clock
	_hud.flights = _world.flights
	_hud.sim = _world.sim
	add_child(_hud)


func after_test() -> void:
	_hud.free()
	_world.free_all()


func _terms(id: String, minute: int, destination: String, airline: String) -> Dictionary:
	return {
		"id": id,
		"airline": airline,
		"destination": destination,
		"departure_minute": minute,
		"gate": "C",
		"plane_size": "small",
		"booked_passengers": 12,
		"fee_per_passenger": 20,
	}


func _text() -> String:
	return DepartureList.text(_hud.flights, _world.clock.tick)


func _lines() -> PackedStringArray:
	return _text().split("\n")


func test_the_departures_list_today_s_flights_in_time_order() -> void:
	(
		assert_bool(
			_world.flights.accept_contract(_terms("NW200", 14 * 60, "Berlin", "Nordic Wing"))
		)
		. is_true()
	)
	(
		assert_bool(_world.flights.accept_contract(_terms("GA100", 11 * 60, "Oslo", "Gotta Air")))
		. is_true()
	)
	assert_array(_lines()).is_equal(
		["06:04  GMF101", "11:00  Oslo  Gotta Air", "14:00  Berlin  Nordic Wing"]
	)


func test_a_one_off_flight_shows_how_far_along_it_is() -> void:
	_world.run_to(21)
	assert_str(_lines()[0]).is_equal("06:04  GMF101  Doors closed")
	_world.run_to(85)
	assert_str(_lines()[0]).is_equal("06:04  GMF101  Pushback")
	_world.run_to(705)
	assert_str(_lines()[0]).is_equal("06:04  GMF101  Departed")


func test_a_contract_flight_boards_then_departs() -> void:
	_world.flights.accept_contract(_terms("GA100", 11 * 60, "Oslo", "Gotta Air"))
	assert_str(_lines()[1]).is_equal("11:00  Oslo  Gotta Air")
	var starts := FlightTimetable.starts_for(_world.flights.contract_of("GA100"), 0)
	_world.run_to(starts[FlightSim.State.BOARDING] + 1)
	assert_str(_lines()[1]).is_equal("11:00  Oslo  Gotta Air  Boarding")
	_world.run_to(starts[FlightSim.State.DEPARTED] + 1)
	assert_str(_lines()[1]).is_equal("11:00  Oslo  Gotta Air  Departed")


func test_a_contract_that_starts_tomorrow_is_not_listed_today() -> void:
	_world.run_to(3000)
	(
		assert_bool(_world.flights.accept_contract(_terms("EARLY", 6 * 60 + 30, "Rome", "Sunhop")))
		. is_true()
	)
	assert_int(_world.flights.contract_of("EARLY")["first_day"]).is_equal(1)
	assert_str(_text()).not_contains("Rome")


func test_the_list_names_the_day_s_flights_again_after_midnight() -> void:
	_world.flights.accept_contract(_terms("GA100", 11 * 60, "Oslo", "Gotta Air"))
	_world.run_to(GameCalendar.day_start(1) + 1)
	assert_array(_lines()).is_equal(["11:00  Oslo  Gotta Air"])


func test_no_flights_says_so() -> void:
	var empty: FlightSim = auto_free(FlightSim.new())
	empty.bind_clock(_world.clock)
	_hud.flights = empty
	assert_str(_text()).is_equal("No departures today")


func test_a_long_day_shows_the_first_lines_and_counts_the_rest() -> void:
	var minutes := [9 * 60, 12 * 60, 15 * 60, 18 * 60, 21 * 60]
	for i in minutes.size():
		(
			assert_bool(
				_world.flights.accept_contract(_terms("C%d" % i, minutes[i], "Rome", "Sunhop"))
			)
			. is_true()
		)
	var lines := _lines()
	assert_int(lines.size()).is_equal(DepartureList.MAX_LINES)
	assert_str(lines[0]).is_equal("06:04  GMF101")
	assert_str(lines[lines.size() - 1]).is_equal("+4 more")


func test_departed_flights_make_room_for_later_ones() -> void:
	var minutes := [9 * 60, 12 * 60, 15 * 60, 18 * 60, 21 * 60]
	for i in minutes.size():
		_world.flights.accept_contract(_terms("C%d" % i, minutes[i], "Rome", "Sunhop"))
	_world.run_to(705)
	var lines := _lines()
	assert_str(lines[0]).is_equal("09:00  Rome  Sunhop")
	assert_str(lines[lines.size() - 1]).is_equal("+3 more")


func test_the_flight_panel_shows_the_list() -> void:
	_world.flights.accept_contract(_terms("GA100", 11 * 60, "Oslo", "Gotta Air"))
	_hud.refresh()
	var label := _hud.find_child("Departures", true, false) as Label
	assert_str(label.text).is_equal(_text())
	assert_str(label.text).contains("11:00  Oslo  Gotta Air")
