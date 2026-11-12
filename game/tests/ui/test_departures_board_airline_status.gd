class_name TestDeparturesBoardAirlineStatus
extends GdUnitTestSuite
## The status word of a Departures row follows the airline on line 2 (decision
## departures-list-row-shows-the-airline-on-a-second-line, user-ruled
## 2026-11-12: "After the airline"), never on line 1. Tick 0 is 06:00. X leaves
## at 10:00 and Y at 11:00; the clock is run to X's doors-close tick, so X reads
## "Doors closed" and Y is the next flight. The world is built once for the
## file and no case changes it.

const GATES: Array[String] = ["C", "A", "B"]
const LONGEST := "Skyline Global"

var _sim: FlightSim
var _clock: SimClock
var _board: DeparturesBoard
var _rows: Control


func before() -> void:
	_sim = FlightSim.new()
	_clock = SimClock.new()
	_sim.gate_source = func() -> Array[String]: return GATES
	_sim.open_airport()
	_accept("X", 600, "Oslo", LONGEST)
	_accept("Y", 660, "Rome", "Gotta Air")
	var doors: int = FlightTimetable.starts_for(_sim.contract_of("X"), 0)[
		FlightSim.State.DOORS_CLOSED
	]
	for t in range(_sim.tick + 1, doors + 1):
		_sim.on_tick(t)
	_clock.tick = doors
	_board = DeparturesBoard.new()
	_board.settings_path = SaveTestKit.run_path("departures_board_airline_status")
	_board.flights = _sim
	_board.clock = _clock
	add_child(_board)
	for i in 3:
		await get_tree().process_frame
	_rows = _board.find_child("Rows", true, false)


func after() -> void:
	var path := _board.settings_path
	_board.free()
	_sim.free()
	_clock.free()
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(path + ".tmp")


func _accept(id: String, minute: int, destination: String, airline: String) -> void:
	var terms := TestFlightContracts.terms(id, minute)
	terms["destination"] = destination
	terms["airline"] = airline
	assert_bool(_sim.accept_contract(terms)).is_true()


func test_the_status_word_is_on_the_airline_line_after_the_airline() -> void:
	# Control: X really is past its doors, so there is a status word to place.
	var state := _sim.state_of(FlightTimetable.occurrence_id("X", 0))
	print("X state ", state, " clock ", _clock.tick)
	assert_int(state).is_equal(FlightSim.State.DOORS_CLOSED)
	var label := _rows.find_child("Airline_X_0", true, false) as Label
	assert_object(label).is_not_null()
	assert_str(label.text).is_equal("%s  Doors closed" % LONGEST)
	assert_int(label.get_line_count()).is_equal(1)


func test_line_one_carries_no_status_word() -> void:
	var line_one := _board.gate_button("X", 0).get_parent() as HBoxContainer
	var head := line_one.get_child(0) as Label
	print("line one: ", head.text)
	assert_str(head.text).is_equal("10:00  Oslo")
	assert_str(head.text).not_contains("Doors closed")


func test_the_next_flight_still_shows_doors_close_under_its_airline() -> void:
	var airline := _rows.find_child("Airline_Y_0", true, false) as Label
	assert_str(airline.text).is_equal("Gotta Air")
	var found := _board.find_children("DoorsClose", "Label", true, false)
	assert_int(found.size()).is_equal(1)
	assert_object(_rows.get_child((found[0] as Node).get_index() - 1)).is_same(airline)
