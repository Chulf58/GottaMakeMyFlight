class_name TestFlightGates
extends GdUnitTestSuite
## Several gates (decision gates-technical-design-gate-desks-link-to-north-
## exits-one-st, points 4 and 5): FlightSim's gates come from gate_source; an
## accepted contract gets the best-fit gate its timetable fits at (with no
## stand_source every fallback gate takes any class, so the lowest letter);
## reassign_gate moves a contract's days not yet issued, and the occurrences
## already issued keep their gate. The shared runway and lane are the taxi
## planner's (test_flight_planner_wiring.gd).
##
## Times: tick 0 is 06:00. A contract departing at 10:00 (minute 600) has its
## first state at tick 2140, inside the issue lead, so it is issued when it is
## accepted at tick 0 (one departing at 10:20 starts at 2540 and is issued at
## 140). One departing 60 minutes later overlaps it at a gate.

const GATES: Array[String] = ["C", "A", "B"]

var _sim: FlightSim


func before_test() -> void:
	_sim = auto_free(FlightSim.new()) as FlightSim
	_sim.gate_source = func() -> Array[String]: return GATES
	_sim.open_airport()


func _accept(id: String, minute: int) -> String:
	assert_bool(_sim.accept_contract(TestFlightContracts.terms(id, minute))).is_true()
	return _sim.contract_of(id)["gate"]


func test_gate_ids_are_the_sources_gates_sorted_and_default_to_c() -> void:
	assert_array(_sim.gate_ids()).is_equal(["A", "B", "C"])
	var plain := auto_free(FlightSim.new()) as FlightSim
	assert_array(plain.gate_ids()).is_equal(["C"])
	plain.gate_source = func() -> Array: return ["A", "A"]
	assert_array(plain.gate_ids()).is_empty()
	plain.gate_source = func() -> String: return "A"
	assert_array(plain.gate_ids()).is_empty()


func test_each_contract_gets_the_lowest_gate_its_timetable_fits_at() -> void:
	assert_str(_sim.accept_gate(TestFlightContracts.terms("X", 600))).is_equal("A")
	assert_str(_accept("X", 600)).is_equal("A")
	assert_str(_accept("Y", 660)).is_equal("B")
	# Five hours later gate A is free again.
	assert_str(_accept("W", 900)).is_equal("A")


func test_one_gate_refuses_a_flight_that_overlaps_at_the_gate() -> void:
	_sim.gate_source = func() -> Array[String]: return ["C"] as Array[String]
	assert_str(_accept("X", 600)).is_equal("C")
	assert_str(_sim.accept_problem(TestFlightContracts.terms("Y", 660))).is_equal(
		"contract Y clashes with X at gate C"
	)


func test_reassign_moves_the_contract_with_the_same_check() -> void:
	_accept("X", 600)
	_accept("Y", 660)
	assert_str(_sim.reassign_problem("Y", "A")).is_equal("contract Y clashes with X at gate A")
	assert_str(_sim.reassign_problem("Y", "B")).is_equal("contract Y is already at gate B")
	assert_str(_sim.reassign_problem("Y", "D")).is_equal("gate 'D' has no stand")
	assert_str(_sim.reassign_problem("NONE", "C")).is_equal("no contract 'NONE'")
	assert_bool(_sim.reassign_gate("Y", "A")).is_false()
	assert_str(_sim.contract_of("Y")["gate"]).is_equal("B")
	assert_str(_sim.reassign_problem("Y", "C")).is_empty()
	assert_bool(_sim.reassign_gate("Y", "C")).is_true()
	var moved := _sim.contract_of("Y")
	assert_str(moved["gate"]).is_equal("C")
	assert_bool(moved.is_read_only()).is_true()
	assert_array(_sim.contract_ids()).is_equal(["X", "Y"])
	_sim.on_tick(200)
	_sim.end_contract("Y")
	assert_str(_sim.reassign_problem("Y", "B")).is_equal("contract Y has ended")


func test_issued_occurrences_keep_their_gate_as_fixed_holds() -> void:
	_accept("X", 600)
	_sim.on_tick(200)
	assert_array(_sim.flight_ids()).is_equal(["X-d0"])
	assert_bool(_sim.reassign_gate("X", "B")).is_true()
	# X-d0 was issued at gate A and stays there; day 1 is issued at B.
	assert_str(_sim.flight_gate("X-d0")).is_equal("A")
	assert_str(_sim.flight_at_gate("A")).is_equal("")
	_sim.on_tick(2540)
	assert_str(_sim.flight_at_gate("A")).is_equal("X-d0")
	assert_str(_sim.flight_at_gate("B")).is_equal("")
	# 11:00 overlaps X-d0 at gate A, which X-d0 still holds, and X's later days
	# at gate B; only gate C is free.
	_sim.gate_source = func() -> Array[String]: return ["A", "B"] as Array[String]
	assert_str(_sim.accept_problem(TestFlightContracts.terms("Y", 660))).is_equal(
		"contract Y clashes with flight X-d0 at gate A"
	)
	_sim.gate_source = func() -> Array[String]: return GATES
	assert_str(_accept("Y", 660)).is_equal("C")
	# Moving Y to A clashes with X-d0's fixed hold, not with X (now at B).
	assert_str(_sim.reassign_problem("Y", "A")).is_equal(
		"contract Y clashes with flight X-d0 at gate A"
	)
	var day_one := FlightTimetable.issue_tick(_sim.contract_of("X"), 1)
	_sim.on_tick(day_one)
	assert_str(_sim.flight_gate("X-d1")).is_equal("B")


func test_a_moved_occurrence_round_trips_and_bad_gates_are_refused() -> void:
	_accept("X", 600)
	_sim.on_tick(200)
	_sim.reassign_gate("X", "B")
	var data: Dictionary = JSON.parse_string(JSON.stringify(_sim.to_snapshot()))
	assert_str(data["contracts"][0]["gate"]).is_equal("B")
	assert_str(data["flights"][0]["gate"]).is_equal("A")
	var loaded := auto_free(FlightSim.new()) as FlightSim
	loaded.gate_source = func() -> Array[String]: return GATES
	assert_bool(loaded.from_snapshot(data.duplicate(true))).is_true()
	assert_dict(loaded.to_snapshot()).is_equal(_sim.to_snapshot())
	assert_str(loaded.flight_gate("X-d0")).is_equal("A")
	# Gate A is gone: X-d0's gate has no stand.
	var two: Array[String] = ["B", "C"]
	assert_str(FlightSnapshot.load(data.duplicate(true), two).get("error", "")).contains(
		"X-d0 is at a gate with no stand"
	)


func test_a_save_holding_a_gate_twice_is_refused() -> void:
	_accept("X", 600)
	_accept("Y", 660)
	_sim.on_tick(200)
	var data: Dictionary = _sim.to_snapshot()
	assert_bool(FlightSnapshot.load(data.duplicate(true), GATES).has("error")).is_false()
	# X-d0 moved onto gate B would overlap Y's days there.
	var gate := data.duplicate(true)
	gate["flights"][0]["gate"] = "B"
	var problem: String = FlightSnapshot.load(gate, GATES).get("error", "")
	print("occurrence moved onto a busy gate: %s" % problem)
	assert_str(problem).is_equal("contract Y clashes with flight X-d0")
