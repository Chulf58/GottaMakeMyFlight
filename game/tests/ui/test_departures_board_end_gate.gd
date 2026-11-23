class_name TestDeparturesBoardEndGate
extends GdUnitTestSuite
## Ending a contract from FlightPlanner (P) frees a gate that a running
## contract kept busy (GATE_FLIGHTS_STUCK -> removed).

const SITE := preload("res://build/terminal_site.tres")

var _desk_west := ReferenceTerminal.GATE_DESK_CELL + SITE.starter_offset

var _grid: SiteGrid
var _flights: FlightSim
var _gates: GateDesks
var _clock: SimClock
var _planner: FlightPlanner


func before_test() -> void:
	_grid = SiteGrid.new(SITE)
	assert_bool(StarterShell.place(_grid, SITE.starter_offset)).is_true()
	_flights = auto_free(FlightSim.new()) as FlightSim
	_flights.open_airport()
	_gates = auto_free(GateDesks.new()) as GateDesks
	_gates.bind(_grid, _flights)
	_grid.guard = _gates.edit_problem
	_clock = auto_free(SimClock.new()) as SimClock
	_planner = FlightPlanner.new()
	_planner.flights = _flights
	_planner.clock = _clock


func after_test() -> void:
	_planner.free()


func test_ending_the_only_contract_lets_its_gate_be_removed() -> void:
	var desk := _grid.apply(BuildEdit.place_object(GateDesks.DESK, _desk_west, 0))
	assert_bool(desk.ok).is_true()
	assert_bool(_flights.accept_contract(TestFlightContracts.terms("X", 620))).is_true()
	add_child(_planner)
	_planner.open()
	var refused := _grid.apply(BuildEdit.remove_object(desk.object_id))
	print("before end: ", refused.reason_text())
	assert_int(refused.reason).is_equal(BuildResult.Reason.GATE_FLIGHTS_STUCK)
	_planner.bar_button("X", 0).pressed.emit()
	(_planner.part("EndContract") as Button).pressed.emit()
	(_planner.part("ConfirmEnd") as Button).pressed.emit()
	assert_array(_flights.active_contract_ids()).is_empty()
	var removed := _grid.apply(BuildEdit.remove_object(desk.object_id))
	print("after end: ok=", removed.ok, " gates=", _gates.gate_ids())
	assert_bool(removed.ok).is_true()
	assert_array(_flights.gate_ids()).is_empty()
