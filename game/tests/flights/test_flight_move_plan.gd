class_name TestFlightMovePlan
extends GdUnitTestSuite
## FlightSim.move_plan and move_contracts (decision gates-technical-design-
## gate-desks-link-to-north-exits-one-st, point 6): the running contracts at
## gates that go are moved to the lowest other gate their timetable fits,
## oldest first, each checked against the ones already moved; a contract no
## gate takes is named as stuck; the plan changes nothing until it is carried
## out. Times as in test_flight_gates.gd: minute 600 and 660 overlap at a gate
## but not on the runway or lane.

var _sim: FlightSim
var _gates: Array[String] = ["A", "B", "C"]


func before_test() -> void:
	_gates = ["A", "B", "C"]
	_sim = auto_free(FlightSim.new()) as FlightSim
	_sim.gate_source = func() -> Array[String]: return _gates
	_sim.open_airport()


func _accept(id: String, minute: int) -> String:
	assert_bool(_sim.accept_contract(TestFlightContracts.terms(id, minute))).is_true()
	return _sim.contract_of(id)["gate"]


func test_contracts_at_a_going_gate_move_to_the_lowest_gate_they_fit_oldest_first() -> void:
	assert_str(_accept("X", 600)).is_equal("A")
	assert_str(_accept("Y", 660)).is_equal("B")
	# Gate A goes: X fits at B? No, Y holds B over the same hours, so C.
	var plan := _sim.move_plan(["A"] as Array[String], ["B", "C"] as Array[String])
	print("plan for A going: %s" % [plan])
	assert_dict(plan["moves"]).is_equal({"X": "C"})
	assert_array(plan["stuck"]).is_empty()
	# Read-only: nothing moved yet.
	assert_str(_sim.contract_of("X")["gate"]).is_equal("A")
	assert_bool(_sim.move_contracts(plan)).is_true()
	assert_str(_sim.contract_of("X")["gate"]).is_equal("C")
	assert_str(_sim.contract_of("Y")["gate"]).is_equal("B")


func test_each_move_is_checked_against_the_ones_moved_before_it() -> void:
	assert_str(_accept("X", 600)).is_equal("A")
	assert_str(_accept("Y", 660)).is_equal("B")
	# A and B both go to C alone: X takes C, and Y, overlapping X there, fits
	# nowhere.
	var plan := _sim.move_plan(["A", "B"] as Array[String], ["C"] as Array[String])
	print("plan for A and B going: %s" % [plan])
	assert_dict(plan["moves"]).is_equal({"X": "C"})
	assert_array(plan["stuck"]).is_equal(["Y"])
	assert_bool(_sim.move_contracts(plan)).is_false()
	assert_str(_sim.contract_of("X")["gate"]).is_equal("A")


func test_ended_contracts_and_contracts_at_other_gates_are_left_alone() -> void:
	assert_str(_accept("X", 600)).is_equal("A")
	assert_str(_accept("W", 900)).is_equal("A")
	assert_str(_accept("Y", 660)).is_equal("B")
	assert_bool(_sim.end_contract("W")).is_true()
	var plan := _sim.move_plan(["A"] as Array[String], ["C"] as Array[String])
	print("plan with W ended: %s" % [plan])
	assert_dict(plan["moves"]).is_equal({"X": "C"})
	assert_array(plan["stuck"]).is_empty()


func test_a_gate_with_no_contracts_plans_no_moves() -> void:
	assert_str(_accept("X", 600)).is_equal("A")
	var plan := _sim.move_plan(["B"] as Array[String], ["A", "C"] as Array[String])
	assert_dict(plan["moves"]).is_empty()
	assert_array(plan["stuck"]).is_empty()
	# A control: the same call for A does plan a move.
	var for_a := _sim.move_plan(["A"] as Array[String], ["B", "C"] as Array[String])
	assert_dict(for_a["moves"]).is_equal({"X": "B"})


func test_a_plan_that_does_not_fit_whole_moves_nothing() -> void:
	assert_str(_accept("X", 600)).is_equal("A")
	assert_str(_accept("Y", 660)).is_equal("B")
	# Both to C: X fits there, then Y overlaps X at C. Checked whole, nothing
	# moves (it used to move X and then fail halfway).
	var stale := {"moves": {"X": "C", "Y": "C"}, "stuck": []}
	assert_bool(_sim.move_contracts(stale)).is_false()
	var x_gate: String = _sim.contract_of("X")["gate"]
	var y_gate: String = _sim.contract_of("Y")["gate"]
	print("after the refused plan: X at %s, Y at %s" % [x_gate, y_gate])
	assert_str(x_gate).is_equal("A")
	assert_str(y_gate).is_equal("B")
	# A control: moves that fit together go through together.
	assert_bool(_sim.move_contracts({"moves": {"X": "C", "Y": "A"}, "stuck": []})).is_true()
	assert_str(_sim.contract_of("X")["gate"]).is_equal("C")
	assert_str(_sim.contract_of("Y")["gate"]).is_equal("A")
