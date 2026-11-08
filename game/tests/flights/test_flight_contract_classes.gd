class_name TestFlightContractClasses
extends GdUnitTestSuite
## A contract holds its plane class to the class's passenger range (decision
## runway-upgrade-works-wait-for-a-timetable-gap-passengers-per-plane-class):
## FlightContract.problem refuses a count outside it, so FlightSim.accept_contract
## and a FlightSnapshot load both refuse one.

## [plane_size, booked_passengers, fits]: the edges of each class and one past them.
const CASES := [
	["small", 7, false],
	["small", 8, true],
	["small", 16, true],
	["small", 17, false],
	["medium", 23, false],
	["medium", 24, true],
	["medium", 48, true],
	["medium", 49, false],
	["large", 47, false],
	["large", 48, true],
	["large", 120, true],
	["large", 121, false],
]

var _sim: FlightSim


func before_test() -> void:
	_sim = auto_free(FlightSim.new()) as FlightSim
	_sim.open_airport()


func _terms(size: String, booked: int) -> Dictionary:
	var terms := TestFlightContracts.terms("PC1", TestFlightContracts.bootstrap_minute())
	terms["plane_size"] = size
	terms["booked_passengers"] = booked
	return terms


func test_the_contract_check_refuses_a_count_outside_the_class_range() -> void:
	for case in CASES:
		var problem := FlightContract.problem(_terms(case[0], case[1]), FlightContract.TERM_KEYS)
		print("%s %d -> '%s'" % [case[0], case[1], problem])
		if case[2]:
			assert_str(problem).override_failure_message(str(case)).is_empty()
		else:
			assert_str(problem).override_failure_message(str(case)).contains("booked_passengers")


func test_accepting_a_contract_outside_the_class_range_is_refused() -> void:
	for case in CASES:
		var sim := auto_free(FlightSim.new()) as FlightSim
		sim.open_airport()
		var terms := _terms(case[0], case[1])
		assert_bool(sim.accept_problem(terms) == "").override_failure_message(str(case)).is_equal(
			case[2]
		)
		if not case[2]:
			var before := sim.contract_ids()
			assert_bool(sim.accept_contract(terms)).override_failure_message(str(case)).is_false()
			assert_array(sim.contract_ids()).is_equal(before)


func test_a_saved_starter_with_20_small_passengers_is_refused_on_load() -> void:
	assert_bool(_sim.accept_contract(FlightSim.starter_terms(0))).is_true()
	var data := _sim.to_snapshot()
	# The control: the snapshot as saved loads.
	assert_bool((auto_free(FlightSim.new()) as FlightSim).from_snapshot(data)).is_true()
	var bad := data.duplicate(true)
	assert_str(bad["contracts"][0]["plane_size"]).is_equal("small")
	bad["contracts"][0]["booked_passengers"] = 20
	var loaded := auto_free(FlightSim.new()) as FlightSim
	assert_bool(loaded.from_snapshot(bad)).is_false()
	assert_array(loaded.contract_ids()).is_empty()
	assert_str(FlightSnapshot.load(bad, loaded.gate_ids()).get("error", "")).contains(
		"booked_passengers"
	)


func test_the_offer_board_refuses_a_count_just_outside_its_size_range_on_load() -> void:
	var small: Array = OfferBoard.STARTER_SIZES["small"]
	for booked in [small[0] - 1, small[1] + 1]:
		var offers := TestOfferBoard.day_records(0, [480, 540, 600])
		offers[0]["booked_passengers"] = booked
		var terms := OfferBoard.terms_of(offers[0])
		assert_str(FlightContract.problem(terms, FlightContract.TERM_KEYS)).is_not_empty()
		var board := OfferBoard.new()
		assert_bool(board.from_snapshot(TestOfferBoard.save_of(offers))).is_false()


## The accepted save domain changed (contracts hold their class's passenger
## range), so the version moved from 4; Runway R7's taxi plans moved it to 7;
## there is no migration.
func test_the_flight_save_version_is_7() -> void:
	assert_int(FlightSim.SAVE_VERSION).is_equal(7)
	assert_int(int(_sim.to_snapshot()["save_version"])).is_equal(7)
