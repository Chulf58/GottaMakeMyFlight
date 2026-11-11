class_name TestPassengerHudDepartures
extends GdUnitTestSuite
## Today's departures (Economy 7/8, DepartureList): every flight leaving today
## in time order, with how far along it is, drawn from the contracts' timetable
## and any one-off flight.
##
## Changed for HUD 7/7 (board 3bd42402): DepartureList.text(), the old flight
## panel's text, had no caller left and was removed. These now read today's rows
## as the departures board draws them (DeparturesBoard.entries_for), and a
## departed flight's status word from the day's rows (DepartureList.rows_for_day),
## since the board drops a departed flight from today. Two tests that covered
## only text()'s three-line cap were removed with it; the board's own cap of
## MAX_ROWS_PER_DAY is covered in test_departures_board.gd.

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
	# A FlightSim starts closed; these contracts fly from an open airport.
	_world.flights.open_airport()
	_hud = PassengerHud.new()
	_hud.clock = _world.clock
	_hud.flights = _world.flights
	_hud.sim = _world.sim
	# Per-process settings, so the player's own Departures choice in
	# user://hud_settings.cfg (B hides the board) never reaches the test.
	_hud.alert_settings_path = SaveTestKit.run_path("hud_departures_alerts")
	_hud.departures_settings_path = SaveTestKit.run_path("hud_departures_board")
	add_child(_hud)


func after_test() -> void:
	DirAccess.remove_absolute(_hud.alert_settings_path)
	DirAccess.remove_absolute(_hud.departures_settings_path)
	_hud.free()
	_world.free_all()


func _terms(id: String, minute: int, destination: String, airline: String) -> Dictionary:
	return {
		"id": id,
		"airline": airline,
		"destination": destination,
		"departure_minute": minute,
		"plane_size": "small",
		"booked_passengers": 12,
		"fee_per_passenger": 20,
	}


## Today's rows on the departures board, up to its Tomorrow heading.
func _lines() -> PackedStringArray:
	var lines := PackedStringArray()
	for entry in DeparturesBoard.entries_for(_hud.flights, _world.clock.tick):
		if entry["text"] == DeparturesBoard.TOMORROW_HEADING:
			break
		if entry["kind"] == "row":
			lines.append(entry["text"])
	return lines


func _text() -> String:
	return "\n".join(_lines())


## Today's board row that starts with `prefix`, or "".
func _line_starting(prefix: String) -> String:
	for line in _lines():
		if line.begins_with(prefix):
			return line
	return ""


## The day's row lines with each flight's status word, departed ones included.
func _day_rows() -> PackedStringArray:
	var lines := PackedStringArray()
	var day := GameCalendar.day_of(_world.clock.tick)
	for row in DepartureList.rows_for_day(_hud.flights, day):
		lines.append(row["line"])
	return lines


func test_the_departures_list_today_s_flights_in_time_order() -> void:
	(
		assert_bool(
			_world.flights.accept_contract(_terms("NW200", 14 * 60 + 20, "Berlin", "Nordic Wing"))
		)
		. is_true()
	)
	(
		assert_bool(_world.flights.accept_contract(_terms("GA100", 11 * 60, "Oslo", "Gotta Air")))
		. is_true()
	)
	assert_array(_lines()).is_equal(
		["06:04  GMF101  doors close 06:01", "11:00  Oslo  Gotta Air", "14:20  Berlin  Nordic Wing"]
	)


## Changed for HUD 7/7: "Departed" is read from the day's rows, because the
## board drops a departed flight from today (asserted too).
func test_a_one_off_flight_shows_how_far_along_it_is() -> void:
	_world.run_to(21)
	assert_str(_lines()[0]).is_equal("06:04  GMF101  Doors closed")
	_world.run_to(85)
	assert_str(_lines()[0]).is_equal("06:04  GMF101  Pushback")
	_world.run_to(705)
	assert_str(_day_rows()[0]).is_equal("06:04  GMF101  Departed")
	assert_str(_text()).not_contains("GMF101")


## Changed for HUD 7/7: the flight is found by its time rather than its index,
## since the departed one-off leaves the board, and "Departed" is read from the
## day's rows.
func test_a_contract_flight_boards_then_departs() -> void:
	_world.flights.accept_contract(_terms("GA100", 11 * 60, "Oslo", "Gotta Air"))
	assert_str(_line_starting("11:00")).is_equal("11:00  Oslo  Gotta Air")
	var starts := FlightTimetable.starts_for(_world.flights.contract_of("GA100"), 0)
	_world.run_to(starts[FlightSim.State.BOARDING] + 1)
	assert_str(_line_starting("11:00")).is_equal(
		"11:00  Oslo  Gotta Air  %s" % _doors_text("GA100")
	)
	_world.run_to(starts[FlightSim.State.DEPARTED] + 1)
	assert_str(_day_rows()[1]).is_equal("11:00  Oslo  Gotta Air  Departed")
	assert_str(_line_starting("11:00")).is_equal("")


func test_a_contract_that_starts_tomorrow_is_not_listed_today() -> void:
	_world.run_to(3000)
	assert_bool(_world.flights.accept_contract(_terms("EARLY", 7 * 60, "Rome", "Sunhop"))).is_true()
	assert_int(_world.flights.contract_of("EARLY")["first_day"]).is_equal(1)
	assert_str(_text()).not_contains("Rome")


func test_the_list_names_the_day_s_flights_again_after_midnight() -> void:
	_world.flights.accept_contract(_terms("GA100", 11 * 60, "Oslo", "Gotta Air"))
	_world.run_to(GameCalendar.day_start(1) + 1)
	assert_int(_lines().size()).is_equal(1)
	assert_str(_lines()[0]).is_equal("11:00  Oslo  Gotta Air  %s" % _doors_text("GA100"))


## Changed for HUD 7/7: the board's empty text, as text()'s is gone.
func test_no_flights_says_so() -> void:
	var empty: FlightSim = auto_free(FlightSim.new())
	empty.bind_clock(_world.clock)
	_hud.flights = empty
	assert_array(Array(DeparturesBoard.lines_for(empty, _world.clock.tick))).is_equal(
		[DeparturesBoard.EMPTY_TEXT]
	)


## Changed for HUD 7/7: text() dropped departed flights only to fit its three
## lines; the board drops every departed flight from today, so the later ones
## all show and no "+n more" is needed for four.
func test_departed_flights_make_room_for_later_ones() -> void:
	# Four 200 minutes apart from 09:00: a fifth at 22:20 would depart in the
	# quiet night, which Runway R7 refuses.
	var minutes := [9 * 60, 12 * 60 + 20, 15 * 60 + 40, 19 * 60]
	for i in minutes.size():
		_world.flights.accept_contract(_terms("C%d" % i, minutes[i], "Rome", "Sunhop"))
	_world.run_to(705)
	var lines := _lines()
	assert_int(lines.size()).is_equal(4)
	assert_str(lines[0]).starts_with("09:00  Rome  Sunhop  doors close ")
	assert_str(_text()).not_contains("more")


func test_the_departures_list_shows_the_flights() -> void:
	_world.flights.accept_contract(_terms("GA100", 11 * 60, "Oslo", "Gotta Air"))
	_hud.refresh()
	var board := _hud.find_child("DeparturesBoard", true, false) as DeparturesBoard
	assert_array(board.shown_lines()).contains(["11:00  Oslo  Gotta Air"])


func _doors_text(contract_id: String) -> String:
	var starts := FlightTimetable.starts_for(_world.flights.contract_of(contract_id), 0)
	return "doors close %s" % GameCalendar.clock_text(starts[FlightSim.State.DOORS_CLOSED])


func test_only_the_next_departing_flight_shows_when_its_doors_close() -> void:
	_world.flights.accept_contract(_terms("GA100", 11 * 60, "Oslo", "Gotta Air"))
	_world.flights.accept_contract(_terms("NW200", 14 * 60 + 20, "Berlin", "Nordic Wing"))
	var lines := _lines()
	assert_str(lines[0]).ends_with("doors close 06:01")
	assert_str(lines[1]).is_equal("11:00  Oslo  Gotta Air")
	assert_str(lines[2]).is_equal("14:20  Berlin  Nordic Wing")


func test_the_doors_time_moves_to_the_following_flight_once_the_doors_close() -> void:
	_world.flights.accept_contract(_terms("GA100", 11 * 60, "Oslo", "Gotta Air"))
	_world.flights.accept_contract(_terms("NW200", 14 * 60 + 20, "Berlin", "Nordic Wing"))
	_world.run_to(21)
	var lines := _lines()
	assert_str(lines[0]).is_equal("06:04  GMF101  Doors closed")
	assert_str(lines[1]).is_equal("11:00  Oslo  Gotta Air  %s" % _doors_text("GA100"))
	assert_str(lines[2]).is_equal("14:20  Berlin  Nordic Wing")


## Changed for HUD 7/7: the flight is found by its time, as above.
func test_the_doors_time_replaces_the_boarding_word() -> void:
	_world.flights.accept_contract(_terms("GA100", 11 * 60, "Oslo", "Gotta Air"))
	_world.run_to(21)
	var starts := FlightTimetable.starts_for(_world.flights.contract_of("GA100"), 0)
	_world.run_to(starts[FlightSim.State.BOARDING] + 1)
	assert_str(_line_starting("11:00")).is_equal(
		"11:00  Oslo  Gotta Air  %s" % _doors_text("GA100")
	)
	_world.run_to(starts[FlightSim.State.DOORS_CLOSED] + 1)
	assert_str(_line_starting("11:00")).is_equal("11:00  Oslo  Gotta Air  Doors closed")


func test_no_flight_counts_down_when_every_door_has_closed() -> void:
	_world.run_to(21)
	assert_str(_text()).is_equal("06:04  GMF101  Doors closed")


## A clock time, not a countdown: the text names the same minute at every tick
## until the doors close, where a countdown line would change every minute.
func test_the_doors_time_does_not_change_as_the_clock_runs() -> void:
	var before := _lines()[0]
	assert_str(before).is_equal("06:04  GMF101  doors close 06:01")
	_world.run_to(5)
	assert_str(_lines()[0]).is_equal(before)
