class_name TestDeparturesBoardGateColours
extends GdUnitTestSuite
## The Gate button on a Departures row wears the gate's colour (decision
## flight-planner-a-full-screen-day-planner-with-one-row-per-ga), the same as the
## flight planner's bar for that gate.

const GATES: Array[String] = ["C", "A", "B"]

var _sim: FlightSim
var _clock: SimClock
var _board: DeparturesBoard


func before_test() -> void:
	_sim = auto_free(FlightSim.new()) as FlightSim
	_clock = auto_free(SimClock.new()) as SimClock
	_sim.open_airport()
	_sim.gate_source = func() -> Array[String]: return GATES
	_board = DeparturesBoard.new()
	_board.settings_path = SaveTestKit.run_path("departures_board_gate_colours")
	_board.flights = _sim
	_board.clock = _clock
	add_child(_board)


func after_test() -> void:
	var path := _board.settings_path
	_board.free()
	DirAccess.remove_absolute(path)


func _accept(id: String, minute: int) -> void:
	assert_bool(_sim.accept_contract(TestFlightContracts.terms(id, minute))).is_true()


func _assert_colour(actual: Color, expected: Color) -> void:
	(
		assert_bool(actual.is_equal_approx(expected))
		. override_failure_message("%s is not %s" % [actual, expected])
		. is_true()
	)


## The colour the button draws its normal fill in: the theme fill times the tint.
func _fill(button: Button) -> Color:
	return (button.get_theme_stylebox("normal") as StyleBoxFlat).bg_color * button.self_modulate


func test_each_gate_button_takes_its_gates_colour() -> void:
	_accept("X", 600)
	_accept("Y", 660)
	_board.refresh()
	var x := _board.gate_button("X", 0)
	var y := _board.gate_button("Y", 0)
	print("gate buttons: ", x.text, " ", _fill(x), "  ", y.text, " ", _fill(y))
	_assert_colour(_fill(x), GateColours.of("A"))
	_assert_colour(_fill(y), GateColours.of("B"))
	assert_object(_fill(x)).is_not_equal(_fill(y))


func test_the_colour_follows_a_move_to_another_gate() -> void:
	_accept("X", 660)
	_board.refresh()
	_assert_colour(_fill(_board.gate_button("X", 0)), GateColours.of("A"))
	_board.gate_button("X", 0).pressed.emit()
	_board.picker_button("C").pressed.emit()
	assert_str(_board.gate_button("X", 0).text).is_equal("Gate C")
	_assert_colour(_fill(_board.gate_button("X", 0)), GateColours.of("C"))


func test_the_shared_entry_points_match_the_pickers_words() -> void:
	_accept("X", 600)
	_accept("Y", 660)
	var choices := DeparturesBoard.move_choices(_sim, "Y", _sim.gate_ids())
	assert_array(choices["fitting"]).is_equal(["C"])
	assert_bool(choices["any_other"]).is_true()
	var outcome := DeparturesBoard.move_outcome(_sim, "Y", "A")
	assert_bool(outcome["moved"]).is_false()
	assert_str(outcome["text"]).is_equal(
		_board.friendly_reason(_sim.reassign_problem("Y", "A"), "A")
	)
	outcome = DeparturesBoard.move_outcome(_sim, "Y", "C")
	assert_bool(outcome["moved"]).is_true()
	assert_str(outcome["text"]).is_equal(DeparturesBoard.MOVED_TEXT % ["Oslo", "C"])
