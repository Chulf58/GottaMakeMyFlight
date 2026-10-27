class_name TestFlightStarterContract
extends GdUnitTestSuite
## The starter contract a new game begins with (Economy 7/8): it replaces the
## one-off bootstrap flight, so day one has a flight and the timetable repeats
## it every day. Its first occurrence starts at tick 0, the timing the
## bootstrap flight had.

var _clock: SimClock
var _sim: FlightSim


func before_test() -> void:
	_clock = auto_free(SimClock.new())
	_sim = auto_free(FlightSim.new())
	_sim.bind_clock(_clock)


func test_the_starter_terms_are_a_valid_contract_that_would_be_accepted() -> void:
	assert_str(FlightContract.problem(FlightSim.STARTER_TERMS, FlightContract.TERM_KEYS)).is_equal(
		""
	)
	assert_str(_sim.accept_problem(FlightSim.STARTER_TERMS)).is_equal("")


func test_a_new_game_has_one_starter_contract_and_one_flight_on_day_one() -> void:
	assert_bool(_sim.add_starter_contract()).is_true()
	var id := FlightTimetable.occurrence_id(FlightSim.STARTER_TERMS["id"], 0)
	assert_array(_sim.contract_ids()).is_equal([FlightSim.STARTER_TERMS["id"]])
	assert_array(_sim.flight_ids()).is_equal([id])
	assert_str(_sim.flight_contract_id(id)).is_equal(FlightSim.STARTER_TERMS["id"])


func test_the_first_occurrence_starts_at_tick_zero_like_the_bootstrap_flight() -> void:
	_sim.add_starter_contract()
	var id := _sim.flight_ids()[0]
	var starts := []
	for state in FlightSim.STATE_COUNT:
		starts.append(_sim.state_start(id, state))
	assert_array(starts).is_equal(FlightSim.schedule_starts(0))
	assert_int(_sim.state_of(id)).is_equal(FlightSim.State.SCHEDULED)


func test_the_starter_flight_departs_on_day_one_and_repeats_the_next_day() -> void:
	_sim.add_starter_contract()
	var id := _sim.flight_ids()[0]
	var pushback := _sim.state_start(id, FlightSim.State.PUSHBACK)
	assert_int(GameCalendar.day_of(pushback)).is_equal(0)
	assert_int(GameCalendar.minute_of_day(pushback)).is_equal(
		FlightSim.STARTER_TERMS["departure_minute"]
	)
	_sim.on_tick(GameCalendar.TICKS_PER_DAY)
	var next := FlightTimetable.occurrence_id(FlightSim.STARTER_TERMS["id"], 1)
	assert_bool(_sim.flight_ids().has(next)).is_true()


func test_a_second_starter_contract_is_refused() -> void:
	assert_bool(_sim.add_starter_contract()).is_true()
	await (
		assert_error(func() -> void: _sim.add_starter_contract())
		. is_push_error("FlightSim.accept_contract: contract id 'GMF101' is already used")
	)
	assert_array(_sim.contract_ids()).has_size(1)


func test_the_node_adds_the_starter_contract_when_it_enters_a_scene_with_a_clock() -> void:
	var sim: FlightSim = auto_free(FlightSim.new())
	sim.clock = _clock
	add_child(sim)
	assert_array(sim.contract_ids()).is_equal([FlightSim.STARTER_TERMS["id"]])
	assert_array(sim.flight_ids()).is_equal(
		[FlightTimetable.occurrence_id(FlightSim.STARTER_TERMS["id"], 0)]
	)
