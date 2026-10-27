class_name TestAirportOpenFlights
extends GdUnitTestSuite
## FlightSim and the airport's open state (decision airport-opening-design-
## stays-open-once-opened-starter-flight-placed-after-opening): a FlightSim
## starts closed and issues no occurrence until open_airport(); an offer
## accepted while closed starts on its first day issued ISSUE_LEAD_TICKS or
## more after opening, and the days it skipped are never reported as flown.
##
## AM (08:00) has its first state at 440 on day 0 and is issued at -1960; PM
## (14:00) has its first state at 7640 and is issued at 5240.

var _sim: FlightSim
var _added: Array[String] = []


func before_test() -> void:
	_added.clear()
	_sim = auto_free(FlightSim.new()) as FlightSim
	_sim.occurrence_added.connect(func(id: String) -> void: _added.append(id))


func _run_to(target: int) -> void:
	for t in range(_sim.tick + 1, target + 1):
		_sim.on_tick(t)


func test_a_new_flight_sim_is_closed() -> void:
	assert_int(_sim.opened_tick).is_equal(-1)


func test_a_closed_airport_issues_nothing_even_after_accept_contract() -> void:
	assert_bool(_sim.accept_contract(TestFlightContracts.terms("AM", 480))).is_true()
	assert_bool(_sim.accept_contract(TestFlightContracts.terms("PM", 840))).is_true()
	assert_array(_sim.contract_ids()).is_equal(["AM", "PM"])
	assert_array(_sim.flight_ids()).is_empty()
	_run_to(2 * GameCalendar.TICKS_PER_DAY)
	assert_array(_sim.flight_ids()).is_empty()
	assert_array(_added).is_empty()
	for id in ["AM-d0", "AM-d1", "PM-d0", "PM-d1"]:
		assert_int(_sim.state_of(id)).override_failure_message(id).is_equal(-1)


## A one-off flight is a test and debug tool, not part of the timetable: it
## runs while the airport is closed.
func test_a_one_off_flight_runs_while_closed() -> void:
	assert_bool(_sim.add_default_flight()).is_true()
	_run_to(800)
	assert_int(_sim.state_of(FlightSim.DEFAULT_ID)).is_equal(FlightSim.State.BOARDING)


func test_opening_records_the_tick_and_a_second_open_is_refused() -> void:
	_run_to(300)
	assert_bool(_sim.open_airport()).is_true()
	assert_int(_sim.opened_tick).is_equal(300)
	_run_to(400)
	await (
		assert_error(func() -> void: _sim.open_airport())
		. is_push_error("FlightSim.open_airport: the airport opened at tick 300")
	)
	assert_int(_sim.opened_tick).is_equal(300)


## Opened at tick 0, AM's day-0 issue tick (-1960) is gone, so AM starts on
## day 1, issued at 28800 + 440 - 2400.
func test_an_offer_accepted_while_closed_starts_at_its_first_slot_that_leaves_the_lead() -> void:
	_sim.accept_contract(TestFlightContracts.terms("AM", 480))
	assert_bool(_sim.open_airport()).is_true()
	assert_array(_sim.flight_ids()).is_empty()
	var issue := GameCalendar.TICKS_PER_DAY + 440 - FlightTimetable.ISSUE_LEAD_TICKS
	_run_to(issue - 1)
	assert_array(_added).is_empty()
	_run_to(issue)
	assert_array(_added).is_equal(["AM-d1"])
	assert_int(_sim.state_start("AM-d1", FlightSim.State.SCHEDULED)).is_equal(
		GameCalendar.TICKS_PER_DAY + 440
	)
	assert_int(_sim.state_of("AM-d0")).is_equal(-1)


## PM's day-0 issue tick is 5240: opening at 5240 still flies day 0, opening a
## tick later moves it to day 1.
func test_the_slot_on_the_opening_tick_is_kept_and_the_one_before_it_is_not() -> void:
	_sim.accept_contract(TestFlightContracts.terms("PM", 840))
	_run_to(5240)
	_sim.open_airport()
	assert_array(_added).is_equal(["PM-d0"])
	var late: FlightSim = auto_free(FlightSim.new())
	late.accept_contract(TestFlightContracts.terms("PM", 840))
	for t in range(1, 5242):
		late.on_tick(t)
	late.open_airport()
	assert_array(late.flight_ids()).is_empty()
	for t in range(5242, GameCalendar.TICKS_PER_DAY + 5241):
		late.on_tick(t)
	assert_array(late.flight_ids()).is_equal(["PM-d1"])
	assert_int(late.state_of("PM-d0")).is_equal(-1)


## Accepted on day 0 and opened on day 2: days 0 to 2 were never flown, so
## they are not answered as departed, while the days that ran are.
func test_skipped_days_leave_no_departed_flights_in_history() -> void:
	_sim.accept_contract(TestFlightContracts.terms("AM", 480))
	var day_two := 2 * GameCalendar.TICKS_PER_DAY + 1000
	_run_to(day_two)
	_sim.open_airport()
	var day_three := 3 * GameCalendar.TICKS_PER_DAY
	_run_to(day_three + 440 + FlightTimetable.reserved_ticks() + FlightTimetable.PRUNE_AFTER_TICKS)
	assert_array(_added).is_equal(["AM-d3"])
	assert_array(_sim.flight_ids()).is_empty()
	for id in ["AM-d0", "AM-d1", "AM-d2"]:
		assert_int(_sim.state_of(id)).override_failure_message(id).is_equal(-1)
		assert_str(_sim.flight_contract_id(id)).override_failure_message(id).is_equal("")
	assert_int(_sim.state_of("AM-d3")).is_equal(FlightSim.State.DEPARTED)
	assert_str(_sim.flight_contract_id("AM-d3")).is_equal("AM")


## A contract accepted after opening keeps the ordinary rule: its first
## occurrence is the first whose preparation window is ahead, issued at once.
func test_an_offer_accepted_after_opening_starts_as_before() -> void:
	_sim.open_airport()
	_run_to(100)
	assert_bool(_sim.accept_contract(TestFlightContracts.terms("AM", 480))).is_true()
	assert_array(_added).is_equal(["AM-d0"])
	assert_int(_sim.state_start("AM-d0", FlightSim.State.SCHEDULED)).is_equal(440)


## The gate is asked before anything is issued: opening on PM's issue tick
## (5240) still issues PM-d0 on that tick. The starter then takes the first
## minute after PM's reservation (7640 to 10220), so it starts at 10220.
func test_the_gate_opens_the_airport_before_the_tick_s_issue() -> void:
	var gate: ReadyGate = auto_free(ReadyGate.new())
	gate.flights = _sim
	gate.from_tick = 5240
	_sim.gate = gate
	_sim.accept_contract(TestFlightContracts.terms("PM", 840))
	_run_to(5239)
	assert_int(_sim.opened_tick).is_equal(-1)
	_run_to(5240)
	assert_int(_sim.opened_tick).is_equal(5240)
	assert_array(_added).is_equal(["PM-d0"])
	assert_array(_sim.contract_ids()).is_equal(["PM", FlightSim.DEFAULT_ID])
	var starter := FlightTimetable.occurrence_id(FlightSim.DEFAULT_ID, 0)
	_run_to(10220 - FlightTimetable.ISSUE_LEAD_TICKS - 1)
	assert_array(_added).is_equal(["PM-d0"])
	_run_to(10220 - FlightTimetable.ISSUE_LEAD_TICKS)
	assert_array(_added).is_equal(["PM-d0", starter])
	assert_int(_sim.state_start(starter, FlightSim.State.SCHEDULED)).is_equal(10220)


## Eleven offers accepted while closed, at minutes 0, 129, ... 1290, each hold
## gate C for 129 minutes and leave no 129-minute gap, so the starter has no
## slot: the airport still opens, with no starter and no error, and each offer
## starts at its first slot after the lead.
func test_a_gate_full_all_day_opens_with_no_starter_and_no_error() -> void:
	var ids: Array[String] = []
	for i in 11:
		ids.append("S%d" % i)
		assert_bool(_sim.accept_contract(TestFlightContracts.terms(ids[i], 129 * i))).is_true()
	assert_int(FlightTimetable.reserved_ticks()).is_equal(129 * GameCalendar.TICKS_PER_MINUTE)
	var gate: AirportGate = auto_free(AirportGate.new())
	gate.flights = _sim
	_run_to(1000)
	await assert_error(func() -> void: gate.open()).is_success()
	assert_int(_sim.opened_tick).is_equal(1000)
	assert_bool(gate.is_open()).is_true()
	assert_bool(gate.opened_without_starter).is_true()
	assert_array(_sim.contract_ids()).is_equal(ids)
	var start_days := _sim.start_days
	for id in ids:
		var contract := _sim.contract_of(id)
		var day: int = start_days[id]
		var issue := FlightTimetable.issue_tick(contract, day)
		var day_before := FlightTimetable.issue_tick(contract, day - 1)
		assert_int(day).override_failure_message(id).is_equal(
			FlightTimetable.opening_day(contract, 1000)
		)
		assert_int(issue).override_failure_message(id).is_greater_equal(1000)
		assert_int(day_before).override_failure_message(id).is_less(1000)


## start_days reads the recorded start as a copy, and refuses a write.
func test_start_days_is_a_read_only_copy_of_the_recorded_start() -> void:
	_sim.accept_contract(TestFlightContracts.terms("AM", 480))
	assert_dict(_sim.start_days).is_equal({"AM": 0})
	_sim.open_airport()
	var days := _sim.start_days
	assert_dict(days).is_equal({"AM": 1})
	days["AM"] = 7
	assert_dict(_sim.start_days).is_equal({"AM": 1})
	await (
		assert_error(func() -> void: _sim.start_days = {"AM": 5})
		. is_push_error("FlightSim.start_days is read-only")
	)
	assert_dict(_sim.start_days).is_equal({"AM": 1})


## A gate that is ready from `from_tick` on, whatever the staff.
class ReadyGate:
	extends AirportGate
	var from_tick := 0

	func ready_to_open() -> bool:
		return not is_open() and flights.tick >= from_tick
