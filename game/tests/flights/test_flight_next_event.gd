class_name TestFlightNextEvent
extends GdUnitTestSuite
## FlightSim.next_event_tick() and has_moving_flight(), which the quiet-night
## fast-forward reads (decision quiet-nights-fast-forward-automatically-when-
## nothing-is-due): the next state change of a flight not yet departed, or the
## next occurrence a running contract issues while the airport is open.

var _clock: SimClock
var _sim: FlightSim


func before_test() -> void:
	_clock = auto_free(SimClock.new()) as SimClock
	_sim = auto_free(FlightSim.new()) as FlightSim
	_sim.bind_clock(_clock)


func _run_to(target: int) -> void:
	while _clock.tick < target:
		_clock.advance(SimClock.STEP)


func _terms(id: String, minute: int) -> Dictionary:
	var terms := TestFlightContracts.terms(id, minute)
	terms["plane_size"] = "small"
	terms["booked_passengers"] = 12
	return terms


func test_nothing_scheduled_has_no_next_event() -> void:
	assert_int(_sim.next_event_tick()).is_equal(-1)
	assert_bool(_sim.has_moving_flight()).is_false()


func test_a_scheduled_flight_is_due_at_its_next_state_and_is_not_moving() -> void:
	var starts := FlightSim.schedule_starts(1000)
	assert_bool(_sim.add_flight("GA1", starts)).is_true()
	print("next=%d approach=%d" % [_sim.next_event_tick(), starts[FlightSim.State.APPROACH]])
	assert_int(_sim.next_event_tick()).is_equal(starts[FlightSim.State.APPROACH])
	assert_bool(_sim.has_moving_flight()).is_false()


func test_a_flight_on_approach_is_moving_and_due_at_its_landing() -> void:
	var starts := FlightSim.schedule_starts(0)
	assert_bool(_sim.add_flight("GA1", starts)).is_true()
	_run_to(starts[FlightSim.State.APPROACH])
	assert_int(_sim.state_of("GA1")).is_equal(FlightSim.State.APPROACH)
	assert_bool(_sim.has_moving_flight()).is_true()
	assert_int(_sim.next_event_tick()).is_equal(starts[FlightSim.State.LANDING])


func test_a_departed_one_off_flight_is_neither_moving_nor_due() -> void:
	var starts := FlightSim.schedule_starts(0)
	assert_bool(_sim.add_flight("GA1", starts)).is_true()
	_run_to(starts[FlightSim.State.TAKEOFF])
	assert_bool(_sim.has_moving_flight()).is_true()
	_run_to(starts[FlightSim.State.DEPARTED])
	print("state=%d next=%d" % [_sim.state_of("GA1"), _sim.next_event_tick()])
	assert_int(_sim.state_of("GA1")).is_equal(FlightSim.State.DEPARTED)
	assert_bool(_sim.has_moving_flight()).is_false()
	assert_int(_sim.next_event_tick()).is_equal(-1)


func test_an_open_airport_is_due_at_a_contracts_next_issue() -> void:
	_sim.open_airport()
	# 20:00 departs well after tick 0 (06:00), so day 0 is not issued yet.
	assert_bool(_sim.accept_contract(_terms("GA2", 20 * 60))).is_true()
	var contract := _sim.contract_of("GA2")
	var issue := FlightTimetable.issue_tick(contract, 0)
	print("issue=%d next=%d" % [issue, _sim.next_event_tick()])
	assert_int(issue).is_greater(0)
	assert_array(_sim.flight_ids()).is_empty()
	assert_int(_sim.next_event_tick()).is_equal(issue)


func test_after_an_issue_the_occurrence_and_the_next_day_are_both_counted() -> void:
	_sim.open_airport()
	assert_bool(_sim.accept_contract(_terms("GA2", 20 * 60))).is_true()
	var contract := _sim.contract_of("GA2")
	_run_to(FlightTimetable.issue_tick(contract, 0))
	assert_array(_sim.flight_ids()).is_equal(["GA2-d0"])
	var first_state := _sim.state_start("GA2-d0", FlightSim.State.SCHEDULED)
	var approach := _sim.state_start("GA2-d0", FlightSim.State.APPROACH)
	print("first=%d approach=%d next=%d" % [first_state, approach, _sim.next_event_tick()])
	assert_int(_sim.next_event_tick()).is_equal(approach)
	assert_int(_sim.next_event_tick()).is_less(FlightTimetable.issue_tick(contract, 1))


func test_a_closed_airport_issues_nothing_so_its_contracts_are_not_due() -> void:
	assert_bool(_sim.accept_contract(_terms("GA2", 20 * 60))).is_true()
	assert_int(_sim.next_event_tick()).is_equal(-1)
	_sim.open_airport()
	assert_int(_sim.next_event_tick()).is_greater(0)


func test_an_ended_contract_is_never_due_again() -> void:
	_sim.open_airport()
	assert_bool(_sim.accept_contract(_terms("GA2", 20 * 60))).is_true()
	assert_int(_sim.next_event_tick()).is_greater(0)
	assert_bool(_sim.end_contract("GA2")).is_true()
	assert_int(_sim.next_event_tick()).is_equal(-1)
