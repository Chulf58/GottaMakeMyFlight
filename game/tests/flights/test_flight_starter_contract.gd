class_name TestFlightStarterContract
extends GdUnitTestSuite
## The starter contract (Economy 7/8) is accepted when the airport opens
## (decision airport-opening-design-stays-open-once-opened-starter-flight-
## placed-after-opening), not when a new game starts. The calendar starts at
## the opening (decision closed-airport-calendar-design-an-explicit-calendar-
## epoch-pa), so StarterSlot.terms() departs StarterSlot.lead() after it, rounded
## up to a whole calendar minute, and its first occurrence is issued at once.
## AirportGate.open() accepts it (test_airport_gate.gd).

var _clock: SimClock
var _sim: FlightSim


func before_test() -> void:
	_clock = auto_free(SimClock.new())
	_sim = auto_free(FlightSim.new())
	_sim.bind_clock(_clock)


func test_the_starter_terms_are_a_valid_contract_that_would_be_accepted() -> void:
	var terms := StarterSlot.terms(_sim)
	assert_str(FlightContract.problem(terms, FlightContract.TERM_KEYS)).is_equal("")
	assert_str(_sim.accept_problem(terms)).is_equal("")
	for key in FlightSim.STARTER_TERMS:
		assert_that(terms[key]).is_equal(FlightSim.STARTER_TERMS[key])


## [opening tick, old first state]. The old starter's first state was
## ISSUE_LEAD_TICKS (2400) after the opening, rounded up to a raw minute:
## 2400, 3400, 3420, 3420. Now the calendar starts on the opening tick, so
## every opening is a whole calendar minute and, at a TaxiTimes.BASE gate, the
## departure is StarterSlot.lead() after it and the first state is on or after
## the opening tick (the opening tick itself while the plane's lead is the
## longer one): issued at once.
func test_the_starter_departs_the_lead_after_the_opening_and_is_issued_at_once() -> void:
	var cases := [[0, 2400], [1000, 3400], [1007, 3420], [1019, 3420]]
	var lead := StarterSlot.lead(TaxiTimes.BASE)
	var first_after := lead - FlightTimetable.departure_offset(TaxiTimes.BASE)
	for case: Array in cases:
		var opened: int = case[0]
		var clock: SimClock = auto_free(SimClock.new())
		var sim: FlightSim = auto_free(FlightSim.new())
		sim.bind_clock(clock)
		clock.hold_calendar()
		while clock.tick < opened:
			clock.advance(SimClock.STEP)
		assert_int(sim.epoch).is_equal(opened)
		var terms := StarterSlot.terms(sim)
		sim.open_airport()
		assert_bool(sim.accept_contract(terms)).is_true()
		var id := FlightTimetable.occurrence_id(FlightSim.DEFAULT_ID, 0)
		var label := "%s: old first state %d" % [case, case[1]]
		assert_array(sim.flight_ids()).override_failure_message(label).is_equal([id])
		var first := sim.state_start(id, FlightSim.State.SCHEDULED)
		assert_int(first).override_failure_message(label).is_equal(opened + first_after)
		assert_int(first).override_failure_message(label).is_greater_equal(opened)
		var pushback := sim.state_start(id, FlightSim.State.PUSHBACK)
		assert_int(pushback).override_failure_message(label).is_equal(opened + lead)
		assert_int(GameCalendar.minute_of_day(pushback, sim.epoch)).is_equal(
			terms["departure_minute"]
		)


func test_a_new_game_s_flight_sim_has_no_contract_and_no_flight() -> void:
	var sim: FlightSim = auto_free(FlightSim.new())
	sim.clock = _clock
	add_child(sim)
	assert_array(sim.contract_ids()).is_empty()
	assert_array(sim.flight_ids()).is_empty()
	assert_int(sim.opened_tick).is_equal(-1)
