class_name TestFlightStarterContract
extends GdUnitTestSuite
## The starter contract (Economy 7/8) is accepted when the airport opens
## (decision airport-opening-design-stays-open-once-opened-starter-flight-
## placed-after-opening), not when a new game starts: starter_terms(now)
## departs so its first state is ISSUE_LEAD_TICKS after `now`, rounded up to
## a whole minute. AirportGate.open() accepts it (test_airport_gate.gd).

var _clock: SimClock
var _sim: FlightSim


func before_test() -> void:
	_clock = auto_free(SimClock.new())
	_sim = auto_free(FlightSim.new())
	_sim.bind_clock(_clock)


func test_the_starter_terms_are_a_valid_contract_that_would_be_accepted() -> void:
	var terms := FlightSim.starter_terms(0)
	assert_str(FlightContract.problem(terms, FlightContract.TERM_KEYS)).is_equal("")
	assert_str(_sim.accept_problem(terms)).is_equal("")
	for key in FlightSim.STARTER_TERMS:
		assert_that(terms[key]).is_equal(FlightSim.STARTER_TERMS[key])


## [now, first state of its first occurrence]: whole minutes keep the lead
## exactly, others round up, and 22:40 (tick 20000) crosses midnight.
func test_the_first_state_is_the_lead_after_now_rounded_up_to_a_minute() -> void:
	var cases := [[0, 2400], [1000, 3400], [1007, 3420], [1019, 3420], [20000, 22400]]
	for case: Array in cases:
		var sim: FlightSim = auto_free(FlightSim.new())
		for t in range(1, case[0] + 1):
			sim.on_tick(t)
		sim.open_airport()
		assert_bool(sim.accept_contract(FlightSim.starter_terms(case[0]))).is_true()
		var contract := sim.contract_of(FlightSim.DEFAULT_ID)
		var day: int = contract["first_day"]
		var first := FlightTimetable.starts_for(contract, day)[0]
		assert_int(first).override_failure_message(str(case)).is_equal(case[1])
		assert_int(FlightTimetable.issue_tick(contract, day)).is_greater_equal(case[0])


func test_a_new_game_s_flight_sim_has_no_contract_and_no_flight() -> void:
	var sim: FlightSim = auto_free(FlightSim.new())
	sim.clock = _clock
	add_child(sim)
	assert_array(sim.contract_ids()).is_empty()
	assert_array(sim.flight_ids()).is_empty()
	assert_int(sim.opened_tick).is_equal(-1)
