class_name TestDeparturesBoardHeader
extends GdUnitTestSuite
## Live Ops header telemetry (decision departures-live-ops-drawer-and-actionable-
## on-time-hud-stat): "In terminal: N" (with clickable "· K late" when K > 0)
## and rolling 3-day "On time: XX%" (or "On time: —" with 0 rated passengers),
## plus the next departing flight's doors-close caption under its row.

var _world: PassengerTestWorld
var _rating: AirportRating
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
	_rating = auto_free(AirportRating.new()) as AirportRating
	_rating.bind(_world.clock, _world.flights, _world.sim)
	_board = DeparturesBoard.new()
	_board.settings_path = SaveTestKit.run_path("departures_board_header")
	_board.flights = _world.flights
	_board.clock = _world.clock
	_board.passengers = _world.sim
	_board.rating = _rating
	add_child(_board)
	_board.set_shown(true)


func after_test() -> void:
	var path := _board.settings_path
	_board.free()
	DirAccess.remove_absolute(path)
	_world.free_all()


func _rows() -> Array[String]:
	var rows: Array[String] = []
	for entry in DeparturesBoard.entries_for(_world.flights, _world.clock.tick):
		if entry["kind"] == "row":
			rows.append(entry["text"])
	return rows


func _terms(id: String, minute: int, destination: String, airline: String) -> Dictionary:
	var terms := TestFlightContracts.terms(id, minute)
	terms["destination"] = destination
	terms["airline"] = airline
	terms["plane_size"] = "small"
	terms["booked_passengers"] = 6
	return terms


func test_the_header_shows_in_terminal_on_time_and_late_pill() -> void:
	_board.refresh()
	var in_terminal := _board.find_child("InTerminal", true, false) as Label
	var on_time := _board.find_child("OnTime", true, false) as Label
	var late_btn := _board.find_child("HeaderLate", true, false) as Button
	assert_str(in_terminal.text).is_equal("In terminal: 0")
	assert_str(on_time.text).is_equal("On time: —")
	assert_str(on_time.tooltip_text).contains("70%")
	assert_bool(late_btn.visible).is_false()
	var pid := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	_world.passenger(pid).late = true
	_world.sim.mark_changed()
	_board.refresh()
	assert_str(in_terminal.text).is_equal("In terminal: 1")
	assert_bool(late_btn.visible).is_true()
	assert_str(late_btn.text).is_equal("· 1 late")
	var emitted: Array[String] = []
	_board.follow_late_requested.connect(func(fid: String) -> void: emitted.append(fid))
	late_btn.pressed.emit()
	assert_array(emitted).is_equal([PassengerTestWorld.FLIGHT])
	_world.run_to(21)
	_board.refresh()
	assert_str(in_terminal.text).is_equal("In terminal: 0")
	assert_str(on_time.text).is_equal("On time: 0%")
	assert_bool(late_btn.visible).is_false()


func test_the_header_shows_when_no_flight_is_scheduled() -> void:
	var empty: FlightSim = auto_free(FlightSim.new())
	empty.bind_clock(_world.clock)
	_board.flights = empty
	_board.refresh()
	assert_bool(_board.is_shown()).is_false()
	_board.set_shown(true)
	assert_array(_board.shown_lines()).contains([DeparturesBoard.EMPTY_TEXT])
	assert_str((_board.find_child("InTerminal", true, false) as Label).text).starts_with(
		"In terminal:"
	)
	assert_str((_board.find_child("OnTime", true, false) as Label).text).starts_with("On time:")


func test_the_header_sits_above_the_rows() -> void:
	_board.refresh()
	var header := _board.find_child("Counts", true, false) as Control
	var rows := _board.find_child("DeparturesPanel", true, false).find_child("Rows", true, false)
	assert_object(rows).is_not_null()
	assert_object(header.get_parent()).is_same(rows.get_parent().get_parent())
	assert_int(header.get_index()).is_less(rows.get_parent().get_index())
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
	var starts := FlightTimetable.starts_for(_world.flights.contract_of("GA100"), 0, 0)
	var doors := GameCalendar.clock_text(starts[FlightSim.State.DOORS_CLOSED], 0)
	assert_array(_rows()).is_equal(
		["06:04  GMF101  Doors closed", "11:00  Oslo  Gotta Air  doors close %s" % doors]
	)


func test_tomorrow_rows_are_omitted_and_show_no_doors_time() -> void:
	_world.run_to(3000)
	_world.flights.accept_contract(_terms("EARLY", 7 * 60, "Rome", "Sunhop"))
	_board.refresh()
	assert_array(DeparturesBoard.lines_for(_world.flights, _world.clock.tick)).contains_exactly(
		[DeparturesBoard.EMPTY_TEXT]
	)


func test_the_doors_time_is_drawn_under_the_next_row_only() -> void:
	_world.flights.accept_contract(_terms("GA100", 11 * 60, "Oslo", "Gotta Air"))
	_board.refresh()
	var found := _board.find_children("DoorsClose", "Label", true, false)
	assert_int(found.size()).is_equal(1)
	assert_str((found[0] as Label).text).is_equal("doors close 06:01")
	var rows := _board.find_child("Rows", true, false)
	var doors := found[0] as Node
	var row_box := doors.get_parent() as VBoxContainer
	var head_row := row_box.get_child(0) as HBoxContainer
	assert_str((head_row.get_child(0) as Label).text).is_equal("06:04  GMF101")
	assert_int(rows.get_child_count()).is_greater(1)
