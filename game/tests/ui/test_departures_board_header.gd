class_name TestDeparturesBoardHeader
extends GdUnitTestSuite
## HUD 3b (board 05cf0cf6, decision top-right-clock-panel-slims-to-day-time-
## and-speed-flight-row): the Departures list carries the Made / Missed / In
## terminal counts in a header line, and its next departing flight's row shows
## the game-clock time its doors close (decision flight-panel-the-next-
## departing-flight-s-row-shows-a-doors-c); the other rows keep status words.

var _world: PassengerTestWorld
var _board: DeparturesBoard


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	var grid := PassengerTestWorld.floored(Vector2i(8, 6))
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(0, 5), 3)
	_world = PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(10, 20))
	_world.flights.open_airport()
	_board = DeparturesBoard.new()
	_board.settings_path = SaveTestKit.run_path("departures_board_header")
	_board.flights = _world.flights
	_board.clock = _world.clock
	_board.passengers = _world.sim
	add_child(_board)


func after_test() -> void:
	var path := _board.settings_path
	_board.free()
	DirAccess.remove_absolute(path)
	_world.free_all()


## Today's rows only: the list up to the Tomorrow heading.
func _rows() -> Array[String]:
	var rows: Array[String] = []
	for entry in DeparturesBoard.entries_for(_world.flights, _world.clock.tick):
		if entry["text"] == DeparturesBoard.TOMORROW_HEADING:
			break
		if entry["kind"] == "row":
			rows.append(entry["text"])
	return rows


func _terms(id: String, minute: int, destination: String, airline: String) -> Dictionary:
	var terms := TestFlightContracts.terms(id, minute)
	terms["destination"] = destination
	terms["airline"] = airline
	terms["plane_size"] = "small"
	terms["booked_passengers"] = 12
	return terms


func test_the_header_shows_the_counts_and_they_update() -> void:
	_board.refresh()
	var header := _board.find_child("Counts", true, false) as Label
	assert_str(header.text).is_equal("Made 0  Missed 0  In terminal 0")
	_world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	_board.refresh()
	assert_str(header.text).is_equal("Made 0  Missed 0  In terminal 1")
	assert_str(_board.counts_text()).is_equal(header.text)
	_world.run_to(21)
	_board.refresh()
	assert_str(header.text).is_equal("Made 0  Missed 1  In terminal 0")


func test_the_header_shows_when_no_flight_is_scheduled() -> void:
	var empty: FlightSim = auto_free(FlightSim.new())
	empty.bind_clock(_world.clock)
	_board.flights = empty
	_board.refresh()
	assert_array(_board.shown_lines()).contains([DeparturesBoard.EMPTY_TEXT])
	assert_str((_board.find_child("Counts", true, false) as Label).text).starts_with("Made ")


func test_the_header_sits_above_the_rows() -> void:
	_board.refresh()
	var header := _board.find_child("Counts", true, false) as Control
	var rows := _board.find_child("DeparturesPanel", true, false).find_child("Rows", true, false)
	assert_object(rows).is_not_null()
	assert_object(header.get_parent()).is_same(rows.get_parent())
	assert_int(header.get_index()).is_less(rows.get_index())
	assert_bool(header.is_visible_in_tree()).is_true()


func test_only_the_next_departing_row_shows_its_doors_close_time() -> void:
	_world.flights.accept_contract(_terms("GA100", 11 * 60, "Oslo", "Gotta Air"))
	_world.flights.accept_contract(_terms("NW200", 14 * 60 + 20, "Berlin", "Nordic Wing"))
	var rows := _rows()
	(
		assert_array(rows)
		. is_equal(
			[
				"06:04  GMF101  doors close 06:01",
				"11:00  Oslo  Gotta Air",
				"14:20  Berlin  Nordic Wing",
			]
		)
	)


func test_the_doors_time_moves_to_the_following_flight_once_the_doors_close() -> void:
	_world.flights.accept_contract(_terms("GA100", 11 * 60, "Oslo", "Gotta Air"))
	_world.run_to(21)
	var starts := FlightTimetable.starts_for(_world.flights.contract_of("GA100"), 0)
	var doors := GameCalendar.clock_text(starts[FlightSim.State.DOORS_CLOSED])
	assert_array(_rows()).is_equal(
		["06:04  GMF101  Doors closed", "11:00  Oslo  Gotta Air  doors close %s" % doors]
	)


func test_tomorrow_rows_show_no_doors_time() -> void:
	_world.run_to(3000)
	_world.flights.accept_contract(_terms("EARLY", 7 * 60, "Rome", "Sunhop"))
	_board.refresh()
	for entry in DeparturesBoard.entries_for(_world.flights, _world.clock.tick):
		assert_str(entry["text"]).not_contains("doors close")


## The list is narrow, so the doors time sits on a caption line under the next
## flight's row (its entry text still reads the whole "... doors close 06:01").
func test_the_doors_time_is_drawn_under_the_next_row_only() -> void:
	_world.flights.accept_contract(_terms("GA100", 11 * 60, "Oslo", "Gotta Air"))
	_board.refresh()
	var found := _board.find_children("DoorsClose", "Label", true, false)
	assert_int(found.size()).is_equal(1)
	assert_str((found[0] as Label).text).is_equal("doors close 06:01")
	var rows := _board.find_child("Rows", true, false)
	var next_row := rows.get_child((found[0] as Node).get_index() - 1)
	assert_str((next_row.get_child(0) as Label).text).is_equal("06:04  GMF101")
