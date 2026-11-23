class_name TestDeparturesBoardGates
extends GdUnitTestSuite
## Gate reassignment now lives exclusively in FlightPlanner (P) (decision
## departures-live-ops-drawer-and-actionable-on-time-hud-stat, 35d321c7),
## sharing DeparturesBoard's static move_choices, move_outcome, and reason_text
## helpers. DeparturesBoard rows have no inline Gate picker buttons.

const GATES: Array[String] = ["C", "A", "B"]

var _sim: FlightSim
var _clock: SimClock
var _board: DeparturesBoard
var _planner: FlightPlanner


func before_test() -> void:
	_sim = auto_free(FlightSim.new()) as FlightSim
	_clock = auto_free(SimClock.new()) as SimClock
	_sim.open_airport()
	_board = DeparturesBoard.new()
	_board.settings_path = SaveTestKit.run_path("departures_board_gates")
	_board.flights = _sim
	_board.clock = _clock
	add_child(_board)
	_planner = FlightPlanner.new()
	_planner.flights = _sim
	_planner.clock = _clock
	add_child(_planner)


func after_test() -> void:
	var path := _board.settings_path
	_board.free()
	_planner.free()
	DirAccess.remove_absolute(path)


func _three_gates() -> void:
	_sim.gate_source = func() -> Array[String]: return GATES


func _accept_x_and_y() -> void:
	for spec: Array in [["X", 600, "Oslo"], ["Y", 660, "Rome"]]:
		var terms := TestFlightContracts.terms(spec[0], spec[1])
		terms["destination"] = spec[2]
		assert_bool(_sim.accept_contract(terms)).is_true()
	_board.set_shown(true)
	_planner.open()


func _run_to(tick: int) -> void:
	for t in range(_sim.tick + 1, tick + 1):
		_sim.on_tick(t)
	_clock.tick = tick
	_board.refresh()
	_planner.refresh()


func test_departures_rows_have_no_inline_gate_buttons_and_planner_moves_contracts() -> void:
	_three_gates()
	_accept_x_and_y()
	assert_array(_board.find_children("Gate_*", "Button", true, false)).is_empty()
	_planner.bar_button("Y", 0).pressed.emit()
	assert_object(_planner.part("Move_A")).is_null()
	assert_object(_planner.part("Move_B")).is_null()
	var move_c := _planner.part("Move_C") as Button
	assert_object(move_c).is_not_null()
	move_c.pressed.emit()
	assert_str(_sim.contract_of("Y")["gate"]).is_equal("C")
	assert_str(_planner.message_text()).is_equal(
		DeparturesBoard.MOVED_TEXT.format({"destination": "Rome", "gate": "C"})
	)


func test_an_occurrence_already_issued_keeps_its_gate_after_a_move() -> void:
	_three_gates()
	_accept_x_and_y()
	_run_to(FlightTimetable.issue_tick(_sim.contract_of("Y"), 0, 0))
	assert_str(_sim.flight_gate("Y-d0")).is_equal("B")
	_planner.bar_button("Y", 0).pressed.emit()
	(_planner.part("Move_C") as Button).pressed.emit()
	assert_str(_sim.flight_gate("Y-d0")).is_equal("B")
	assert_str(_sim.contract_of("Y")["gate"]).is_equal("C")


func test_a_clash_with_an_issued_flight_names_it_by_time_and_destination() -> void:
	_three_gates()
	_accept_x_and_y()
	_run_to(FlightTimetable.issue_tick(_sim.contract_of("Y"), 0, 0))
	assert_bool(_sim.end_contract("X")).is_true()
	var reason := _sim.reassign_problem("Y", "A")
	assert_str(reason).contains("with flight X-d0 at gate A")
	assert_str(DeparturesBoard.reason_text(_sim, reason, "A")).is_equal(
		"Gate A is taken by the 10:00 Oslo flight"
	)


func test_a_reason_that_cannot_be_resolved_falls_back_to_a_plain_busy_text() -> void:
	_three_gates()
	_accept_x_and_y()
	var busy := "Gate A is busy when this flight needs it"
	(
		assert_str(DeparturesBoard.reason_text(_sim, "contract Q clashes with Z at gate A", "A"))
		. is_equal(busy)
	)
	assert_str(DeparturesBoard.reason_text(_sim, "gate 'D' has no stand", "A")).is_equal(busy)
	assert_str(DeparturesBoard.reason_text(_sim, FlightSim.TAXI_BUSY_TEXT, "A")).is_equal(busy)
	(
		assert_str(
			DeparturesBoard.reason_text(_sim, "contract Y clashes with X on the runway", "B")
		)
		. is_equal("The runway is taken by the 10:00 Oslo flight")
	)


func test_with_one_gate_move_choices_finds_no_other_gate() -> void:
	assert_array(_sim.gate_ids()).is_equal(["C"])
	assert_bool(_sim.accept_contract(TestFlightContracts.terms("X", 600))).is_true()
	var choices := DeparturesBoard.move_choices(_sim, "X", _sim.gate_ids())
	assert_array(choices["fitting"]).is_empty()
	assert_bool(choices["any_other"]).is_false()
