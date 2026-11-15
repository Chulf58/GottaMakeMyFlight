class_name TestFlightTaxiBounds
extends GdUnitTestSuite
## A gate whose routes need a taxi pair past TaxiTimes' bounds (MAX_IN, MAX_OUT)
## takes no contract: accept, trials, reassign, move_plan and move_contracts
## refuse it with FlightContract.assignment_problem()'s words, and nothing is
## stored. Gate C keeps today's pair; gate F's stand is a stub whose wall line
## lies far enough south that both routes are too long.

## Far enough south that TAXI_IN would need more than TaxiTimes.MAX_IN.
const FAR_WALL_Z := 1402.0
const DEPARTS := 840


static func _grounds() -> Dictionary:
	var far: Dictionary = FlightGround.fallback("E")["stand"].duplicate()
	far["wall_z"] = FAR_WALL_Z
	return {
		"C": FlightGround.fallback("C"),
		"F": {"stand": far, "max_class": PlaneClasses.LARGE},
	}


func _open(gates: Array[String]) -> FlightSim:
	var sim := auto_free(FlightSim.new()) as FlightSim
	sim.gate_source = func() -> Array[String]: return gates
	sim.stand_source = func() -> Dictionary: return _grounds()
	assert_bool(sim.open_airport()).is_true()
	return sim


func test_the_stub_stand_needs_a_pair_past_the_bounds() -> void:
	var pair := TaxiTimes.for_stand(_grounds()["F"]["stand"])
	print("far stand needs %s" % [pair])
	assert_int(pair[0]).is_greater(TaxiTimes.MAX_IN)
	assert_str(TaxiTimes.problem(pair)).is_not_empty()
	var problem := FlightContract.assignment_problem("F", _grounds()["F"]["stand"])
	assert_str(problem).contains("too long")
	assert_str(FlightContract.assignment_problem("C", _grounds()["C"]["stand"])).is_empty()


func test_accept_and_trials_refuse_the_far_gate_and_store_nothing() -> void:
	var sim := _open(["F"] as Array[String])
	var terms := TestFlightContracts.terms("X", DEPARTS)
	var before := JSON.stringify(sim.to_snapshot())
	var problem := sim.accept_problem(terms)
	print("accept: '%s'" % problem)
	assert_str(problem).contains("gate F's taxi route is too long")
	assert_str(sim.accept_gate(terms)).is_empty()
	var trial := sim.trial_assignment(terms)
	assert_str(trial["gate"]).is_empty()
	assert_str(trial["blocker"]).is_equal(FlightSim.BLOCKER_ROUTE)
	assert_bool(FlightFit.assess(sim, terms)["fits"]).is_false()
	assert_bool(sim.accept_contract(terms)).is_false()
	assert_array(sim.contract_ids()).is_empty()
	assert_str(JSON.stringify(sim.to_snapshot())).is_equal(before)
	# With gate C standing too, the same terms go to C.
	var both := _open(["C", "F"] as Array[String])
	assert_str(both.accept_gate(terms)).is_equal("C")


func test_reassign_and_moves_refuse_the_far_gate_and_change_nothing() -> void:
	var sim := _open(["C", "F"] as Array[String])
	assert_bool(sim.accept_contract(TestFlightContracts.terms("X", DEPARTS))).is_true()
	assert_str(sim.contract_of("X")["gate"]).is_equal("C")
	var before := JSON.stringify(sim.to_snapshot())
	var problem := sim.reassign_problem("X", "F")
	print("reassign: '%s'" % problem)
	assert_str(problem).contains("gate F's taxi route is too long")
	assert_bool(sim.reassign_gate("X", "F")).is_false()
	var plan := sim.move_plan(["C"] as Array[String], ["F"] as Array[String])
	assert_dict(plan["moves"]).is_empty()
	assert_array(plan["stuck"]).is_equal(["X"])
	assert_bool(sim.move_contracts({"moves": {"X": "F"}, "stuck": []})).is_false()
	assert_str(sim.contract_of("X")["gate"]).is_equal("C")
	assert_array(sim.contract_of("X")["taxi"]).is_equal(TaxiTimes.BASE)
	assert_str(JSON.stringify(sim.to_snapshot())).is_equal(before)
