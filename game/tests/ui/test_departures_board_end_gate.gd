class_name TestDeparturesBoardEndGate
extends GdUnitTestSuite
## The reason for the End button: a gate that a running contract keeps busy
## cannot be removed (GATE_FLIGHTS_STUCK, GateDesks._removal_problem), and
## ending that contract from the Departures list frees it. One gate, one
## contract, a board on the same FlightSim.

const SITE := preload("res://build/terminal_site.tres")
const DESK_WEST := Vector2i(19, 115)

var _grid: SiteGrid
var _flights: FlightSim
var _gates: GateDesks
var _clock: SimClock
var _board: DeparturesBoard


func before_test() -> void:
	_grid = SiteGrid.new(SITE)
	assert_bool(StarterShell.place(_grid, SITE.starter_offset)).is_true()
	_flights = auto_free(FlightSim.new()) as FlightSim
	_flights.open_airport()
	_gates = auto_free(GateDesks.new()) as GateDesks
	_gates.bind(_grid, _flights)
	_grid.guard = _gates.edit_problem
	_clock = auto_free(SimClock.new()) as SimClock
	_board = DeparturesBoard.new()
	_board.settings_path = SaveTestKit.run_path("departures_board_end_gate")
	_board.flights = _flights
	_board.clock = _clock


func after_test() -> void:
	var path := _board.settings_path
	_board.free()
	DirAccess.remove_absolute(path)


func test_ending_the_only_contract_lets_its_gate_be_removed() -> void:
	var desk := _grid.apply(BuildEdit.place_object(GateDesks.DESK, DESK_WEST, 0))
	assert_bool(desk.ok).is_true()
	assert_bool(_flights.accept_contract(TestFlightContracts.terms("X", 620))).is_true()
	add_child(_board)
	_board.refresh()
	var refused := _grid.apply(BuildEdit.remove_object(desk.object_id))
	print("before end: ", refused.reason_text())
	assert_int(refused.reason).is_equal(BuildResult.Reason.GATE_FLIGHTS_STUCK)
	_board.end_button("X", 0).pressed.emit()
	_board.confirm_end_button().pressed.emit()
	assert_array(_flights.active_contract_ids()).is_empty()
	var removed := _grid.apply(BuildEdit.remove_object(desk.object_id))
	print("after end: ok=", removed.ok, " gates=", _gates.gate_ids())
	assert_bool(removed.ok).is_true()
	assert_array(_flights.gate_ids()).is_empty()
