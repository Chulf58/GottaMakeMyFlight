class_name TestDeparturesBoardGates
extends GdUnitTestSuite
## The gate on each Departures row (gates 3/4, decision gates-are-placed-gate-
## desks-each-desk-links-automatically-to): a gate button per row, a picker
## under the clicked row that moves the contract to another gate through
## FlightSim.reassign_gate, FlightSim's own reason when the gate is taken, and
## the plain note when no other gate exists. FlightSim.gate_source supplies the
## gates here.
##
## Tick 0 is 06:00. X leaves at 10:00 and takes gate A; Y leaves at 11:00, which
## overlaps X at a gate but not on the runway, so Y takes gate B.

const GATES: Array[String] = ["C", "A", "B"]

var _sim: FlightSim
var _clock: SimClock
var _board: DeparturesBoard


func before_test() -> void:
	_sim = auto_free(FlightSim.new()) as FlightSim
	_clock = auto_free(SimClock.new()) as SimClock
	_sim.open_airport()
	_board = DeparturesBoard.new()
	_board.settings_path = SaveTestKit.run_path("departures_board_gates")
	_board.flights = _sim
	_board.clock = _clock


func after_test() -> void:
	var path := _board.settings_path
	_board.free()
	DirAccess.remove_absolute(path)


func _three_gates() -> void:
	_sim.gate_source = func() -> Array[String]: return GATES


## Accepts X (gate A) and Y (gate B), then builds the board.
func _accept_x_and_y() -> void:
	for spec: Array in [["X", 600, "Oslo"], ["Y", 660, "Rome"]]:
		var terms := TestFlightContracts.terms(spec[0], spec[1])
		terms["destination"] = spec[2]
		assert_bool(_sim.accept_contract(terms)).is_true()
	add_child(_board)
	_board.refresh()


func _run_to(tick: int) -> void:
	for t in range(_sim.tick + 1, tick + 1):
		_sim.on_tick(t)
	_clock.tick = tick
	_board.refresh()


func _press(button: Button) -> void:
	assert_object(button).is_not_null()
	button.pressed.emit()


func test_each_row_shows_the_gate_its_flight_holds() -> void:
	_three_gates()
	_accept_x_and_y()
	print("gate buttons: ", _board.gate_button("X", 0).text, " ", _board.gate_button("Y", 0).text)
	assert_str(_board.gate_button("X", 0).text).is_equal("Gate A")
	assert_str(_board.gate_button("Y", 0).text).is_equal("Gate B")
	assert_str(_board.gate_button("Y", 1).text).is_equal("Gate B")
	# The row text itself is DepartureList's and carries no gate.
	assert_array(_board.shown_lines()).contains(
		["10:00  Oslo  Gotta Air", "11:00  Rome  Gotta Air"]
	)


func test_choosing_a_free_gate_moves_the_contract_and_confirms() -> void:
	_three_gates()
	_accept_x_and_y()
	_press(_board.gate_button("Y", 0))
	assert_object(_board.picker_button("B")).is_null()
	assert_object(_board.picker_button("A")).is_not_null()
	_press(_board.picker_button("C"))
	print("moved: gate=", _sim.contract_of("Y")["gate"], " message=", _board.message_text())
	assert_str(_sim.contract_of("Y")["gate"]).is_equal("C")
	assert_str(_board.message_text()).is_equal(DeparturesBoard.MOVED_TEXT % ["Rome", "C"])
	assert_str(_board.gate_button("Y", 0).text).is_equal("Gate C")
	assert_object(_board.picker_button("A")).is_null()


func test_an_occurrence_already_issued_keeps_its_gate_after_a_move() -> void:
	_three_gates()
	_accept_x_and_y()
	_run_to(FlightTimetable.issue_tick(_sim.contract_of("Y"), 0))
	assert_str(_sim.flight_gate("Y-d0")).is_equal("B")
	_press(_board.gate_button("Y", 0))
	_press(_board.picker_button("C"))
	print(
		"today: ", _board.gate_button("Y", 0).text, " tomorrow: ", _board.gate_button("Y", 1).text
	)
	assert_str(_board.gate_button("Y", 0).text).is_equal("Gate B")
	assert_str(_board.gate_button("Y", 1).text).is_equal("Gate C")


func test_a_taken_gate_is_refused_with_the_reason_and_the_picker_stays() -> void:
	_three_gates()
	_accept_x_and_y()
	_press(_board.gate_button("Y", 0))
	_press(_board.picker_button("A"))
	var reason := _sim.reassign_problem("Y", "A")
	print("refused: ", _board.message_text())
	assert_str(reason).is_equal("contract Y clashes with X at gate A")
	assert_str(_board.message_text()).is_equal(DeparturesBoard.REFUSED_TEXT % reason)
	assert_str(_sim.contract_of("Y")["gate"]).is_equal("B")
	assert_str(_board.gate_button("Y", 0).text).is_equal("Gate B")
	assert_object(_board.picker_button("C")).is_not_null()


func test_clicking_the_gate_again_closes_the_picker_and_clears_the_message() -> void:
	_three_gates()
	_accept_x_and_y()
	_press(_board.gate_button("Y", 0))
	_press(_board.picker_button("A"))
	_press(_board.gate_button("Y", 0))
	assert_object(_board.picker_button("C")).is_null()
	assert_str(_board.message_text()).is_empty()


func test_with_one_gate_the_picker_says_no_other_gate_exists() -> void:
	assert_array(_sim.gate_ids()).is_equal(["C"])
	assert_bool(_sim.accept_contract(TestFlightContracts.terms("X", 600))).is_true()
	add_child(_board)
	_board.refresh()
	assert_str(_board.gate_button("X", 0).text).is_equal("Gate C")
	_press(_board.gate_button("X", 0))
	print("single gate picker: ", _board.picker_note())
	assert_str(_board.picker_note()).is_equal(DeparturesBoard.NO_OTHER_TEXT)
	assert_object(_board.picker_button("C")).is_null()
	assert_str(_sim.contract_of("X")["gate"]).is_equal("C")
