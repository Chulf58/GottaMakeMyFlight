class_name TestFlightRunwayGating
extends GdUnitTestSuite
## FlightSim refuses a contract whose plane class the runway cannot take
## (decision runway-and-taxi-technical-design-movement-plan-analytic-bookings-
## planned-pauses, points 1 and 8), through accept_problem() and so
## accept_contract() and accept_gate().

var _sim: FlightSim


func before_test() -> void:
	_sim = auto_free(FlightSim.new()) as FlightSim
	_sim.runway.size = PlaneClasses.SMALL


func _terms(id: String, plane_class: String) -> Dictionary:
	var terms := TestFlightContracts.terms(id, 600)
	terms["plane_size"] = plane_class
	terms["booked_passengers"] = PlaneClasses.passenger_range(plane_class)[0]
	return terms


## A sim made in code takes every class until a test or the scene makes the
## runway smaller; the game scene starts it medium for now (runway_start).
func test_a_bare_sim_takes_every_class_and_the_scene_starts_medium() -> void:
	var bare := auto_free(FlightSim.new()) as FlightSim
	assert_str(bare.runway.size).is_equal(PlaneClasses.LARGE)
	bare.runway_start = PlaneClasses.SMALL
	assert_str(bare.runway.size).is_equal(PlaneClasses.SMALL)
	var main := (load("res://main/main.tscn") as PackedScene).get_state()
	var starts := []
	for node in main.get_node_count():
		if main.get_node_name(node) == "FlightSim":
			for property in main.get_node_property_count(node):
				if main.get_node_property_name(node, property) == "runway_start":
					starts.append(main.get_node_property_value(node, property))
	assert_array(starts).is_equal(["medium"])


func test_a_small_runway_refuses_medium_and_large_and_takes_small() -> void:
	assert_str(_sim.accept_problem(_terms("S1", "small"))).is_empty()
	for plane_class in ["medium", "large"]:
		var problem := _sim.accept_problem(_terms("B1", plane_class))
		print("small runway, %s: '%s'" % [plane_class, problem])
		assert_str(problem).is_equal("the runway is too short for a %s plane" % plane_class)
		assert_str(_sim.accept_gate(_terms("B1", plane_class))).is_empty()
		var expected := "FlightSim.accept_contract: " + problem
		var refuse := func() -> void:
			assert_bool(_sim.accept_contract(_terms("B1", plane_class))).is_false()
		assert_error(refuse).is_push_error(expected)
		assert_array(_sim.contract_ids()).is_empty()


func test_a_refusal_changes_nothing() -> void:
	assert_str(_sim.accept_problem(_terms("B1", "medium"))).is_not_empty()
	assert_array(_sim.contract_ids()).is_empty()
	assert_array(_sim.flight_ids()).is_empty()


## Positive control: the same terms are taken once the runway is big enough.
func test_a_bigger_runway_takes_the_classes_up_to_its_own() -> void:
	_sim.runway.size = PlaneClasses.MEDIUM
	assert_str(_sim.accept_problem(_terms("M1", "medium"))).is_empty()
	assert_str(_sim.accept_problem(_terms("L1", "large"))).is_equal(
		"the runway is too short for a large plane"
	)
	_sim.runway.size = PlaneClasses.LARGE
	assert_str(_sim.accept_problem(_terms("L1", "large"))).is_empty()
	assert_bool(_sim.accept_contract(_terms("L1", "large"))).is_true()
	assert_array(_sim.contract_ids()).is_equal(["L1"])


## The malformed-terms and used-id reasons still come first.
func test_the_runway_reason_follows_the_term_checks() -> void:
	var terms := _terms("B1", "medium")
	terms.erase("fee_per_passenger")
	assert_str(_sim.accept_problem(terms)).contains("fee_per_passenger")
