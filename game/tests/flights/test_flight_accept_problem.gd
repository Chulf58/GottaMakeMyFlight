class_name TestFlightAcceptProblem
extends GdUnitTestSuite
## FlightSim.accept_problem(terms): the reason accept_contract would refuse the
## terms, "" when it would take them. It changes nothing, so the offer panel can
## ask before it accepts and show why an accept was refused.

var _sim: FlightSim


func before_test() -> void:
	_sim = auto_free(FlightSim.new()) as FlightSim


func test_terms_that_fit_have_no_problem() -> void:
	assert_str(_sim.accept_problem(TestFlightContracts.terms("A1", 600))).is_empty()


func test_malformed_terms_name_what_is_wrong() -> void:
	var terms := TestFlightContracts.terms("A1", 600)
	terms.erase("fee_per_passenger")
	assert_str(_sim.accept_problem(terms)).contains("fee_per_passenger")
	terms = TestFlightContracts.terms("A1", 600)
	terms["id"] = "bad id!"
	assert_str(_sim.accept_problem(terms)).contains("contract id")
	assert_str(_sim.accept_problem({})).is_not_empty()


func test_a_gate_without_a_stand_is_named() -> void:
	assert_str(_sim.accept_problem(TestFlightContracts.terms("A1", 600, "B"))).is_equal(
		"gate 'B' has no stand"
	)


func test_a_used_contract_id_is_named() -> void:
	assert_bool(_sim.accept_contract(TestFlightContracts.terms("A1", 900))).is_true()
	assert_str(_sim.accept_problem(TestFlightContracts.terms("A1", 600))).is_equal(
		"contract id 'A1' is already used"
	)


func test_a_gate_clash_with_a_contract_names_both_and_the_gate() -> void:
	assert_bool(_sim.accept_contract(TestFlightContracts.terms("A1", 600))).is_true()
	var problem := _sim.accept_problem(TestFlightContracts.terms("A2", 660))
	assert_str(problem).is_equal("contract A2 clashes with A1 at gate C")


func test_a_gate_clash_with_a_one_off_flight_names_the_flight() -> void:
	assert_bool(_sim.add_default_flight()).is_true()
	assert_str(_sim.accept_problem(TestFlightContracts.terms("A2", 458))).is_equal(
		"contract A2 clashes with flight GMF101 at gate C"
	)


func test_asking_changes_nothing() -> void:
	assert_bool(_sim.accept_contract(TestFlightContracts.terms("A1", 600))).is_true()
	var before := _sim.to_snapshot()
	_sim.accept_problem(TestFlightContracts.terms("A2", 660))
	_sim.accept_problem(TestFlightContracts.terms("A3", 1000))
	_sim.accept_problem({})
	assert_dict(_sim.to_snapshot()).is_equal(before)
	assert_array(_sim.contract_ids()).is_equal(["A1"])


func test_it_agrees_with_accept_contract() -> void:
	assert_bool(_sim.accept_contract(TestFlightContracts.terms("A1", 600))).is_true()
	for minute in [600, 630, 660, 700, 900, 1200]:
		var terms := TestFlightContracts.terms("B%d" % minute, minute)
		var fits := _sim.accept_problem(terms) == ""
		assert_bool(_sim.accept_contract(terms)).is_equal(fits)
