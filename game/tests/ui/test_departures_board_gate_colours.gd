class_name TestDeparturesBoardGateColours
extends GdUnitTestSuite
## Shared move_choices/move_outcome/reason_text helpers on DeparturesBoard
## used by FlightPlanner, and FlightPlanner bar/Move_ button colours.

const GATES: Array[String] = ["C", "A", "B"]

var _sim: FlightSim
var _clock: SimClock
var _planner: FlightPlanner


func before_test() -> void:
	_sim = auto_free(FlightSim.new()) as FlightSim
	_clock = auto_free(SimClock.new()) as SimClock
	_sim.open_airport()
	_sim.gate_source = func() -> Array[String]: return GATES
	_planner = FlightPlanner.new()
	_planner.flights = _sim
	_planner.clock = _clock
	add_child(_planner)


func after_test() -> void:
	_planner.free()


func _accept(id: String, minute: int) -> void:
	assert_bool(_sim.accept_contract(TestFlightContracts.terms(id, minute))).is_true()


func _assert_colour(actual: Color, expected: Color) -> void:
	(
		assert_bool(actual.is_equal_approx(expected))
		. override_failure_message("%s is not %s" % [actual, expected])
		. is_true()
	)


func _fill(button: Button) -> Color:
	return (button.get_theme_stylebox("normal") as StyleBoxFlat).bg_color


func test_each_planner_bar_and_move_button_takes_its_gates_colour() -> void:
	_accept("X", 600)
	_accept("Y", 660)
	_planner.open()
	var x := _planner.bar_button("X", 0)
	var y := _planner.bar_button("Y", 0)
	_assert_colour(_fill(x), GateColours.of("A"))
	_assert_colour(_fill(y), GateColours.of("B"))
	assert_object(_fill(x)).is_not_equal(_fill(y))


func test_the_colour_follows_a_move_to_another_gate() -> void:
	_accept("X", 660)
	_planner.open()
	_assert_colour(_fill(_planner.bar_button("X", 0)), GateColours.of("A"))
	_planner.bar_button("X", 0).pressed.emit()
	(_planner.part("Move_C") as Button).pressed.emit()
	_assert_colour(_fill(_planner.bar_button("X", 0)), GateColours.of("C"))


func test_the_shared_entry_points_match_the_expected_outcomes() -> void:
	_accept("X", 600)
	_accept("Y", 660)
	var choices := DeparturesBoard.move_choices(_sim, "Y", _sim.gate_ids())
	assert_array(choices["fitting"]).is_equal(["C"])
	assert_bool(choices["any_other"]).is_true()
	var outcome := DeparturesBoard.move_outcome(_sim, "Y", "A")
	assert_bool(outcome["moved"]).is_false()
	assert_str(outcome["text"]).is_equal(
		DeparturesBoard.reason_text(_sim, _sim.reassign_problem("Y", "A"), "A")
	)
	outcome = DeparturesBoard.move_outcome(_sim, "Y", "C")
	assert_bool(outcome["moved"]).is_true()
	assert_str(outcome["text"]).is_equal(
		DeparturesBoard.MOVED_TEXT.format({"destination": "Oslo", "gate": "C"})
	)
