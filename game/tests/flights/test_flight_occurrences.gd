class_name TestFlightOccurrences
extends GdUnitTestSuite
## Daily occurrences: issued two hours ahead of their first state, named
## <contract>-d<day> after their departure day, pruned an hour after they
## depart, and still answered for after pruning.

var _sim: FlightSim
var _added: Array[Vector2i] = []
var _added_ids: Array[String] = []
var _most_live := 0


func before_test() -> void:
	_added.clear()
	_added_ids.clear()
	_most_live = 0
	_sim = auto_free(FlightSim.new()) as FlightSim
	_sim.occurrence_added.connect(_on_added)


func _on_added(id: String) -> void:
	_added.append(Vector2i(_sim.tick, _added_ids.size()))
	_added_ids.append(id)


## Feeds the sim every tick up to `target`, as the clock would.
func _run_to(target: int) -> void:
	for t in range(_sim.tick + 1, target + 1):
		_sim.on_tick(t)
		_most_live = maxi(_most_live, _sim.flight_ids().size())


## 00:30 on day 1 is tick 22200. Its occurrence starts at 22:52 on day 0
## (tick 20240), is issued two hours earlier (17840) and departs at 22820.
func test_an_occurrence_crosses_midnight_under_its_departure_day() -> void:
	assert_bool(_sim.accept_contract(TestFlightContracts.terms("NIGHT", 30))).is_true()
	_run_to(17839)
	assert_array(_added_ids).is_empty()
	_run_to(17840)
	assert_array(_added_ids).is_equal(["NIGHT-d1"])
	assert_int(_added[0].x).is_equal(17840)
	assert_int(_sim.state_start("NIGHT-d1", FlightSim.State.SCHEDULED)).is_equal(20240)
	assert_int(GameCalendar.day_of(20240)).is_equal(0)
	var pushback := _sim.state_start("NIGHT-d1", FlightSim.State.PUSHBACK)
	assert_int(pushback).is_equal(22200)
	assert_int(GameCalendar.day_of(pushback)).is_equal(1)
	assert_str(GameCalendar.clock_text(pushback)).is_equal("00:30")
	_run_to(21600)
	assert_int(_sim.state_of("NIGHT-d1")).is_equal(FlightSim.State.BOARDING)
	_run_to(22820)
	assert_int(_sim.state_of("NIGHT-d1")).is_equal(FlightSim.State.DEPARTED)
	assert_array(_added_ids).is_equal(["NIGHT-d1"])


func test_a_departed_occurrence_is_pruned_an_hour_later_and_still_answers() -> void:
	_sim.accept_contract(TestFlightContracts.terms("NIGHT", 30))
	_run_to(24019)
	assert_array(_sim.flight_ids()).is_equal(["NIGHT-d1"])
	var window := _sim.boarding_window("NIGHT-d1")
	_run_to(24020)
	assert_array(_sim.flight_ids()).is_empty()
	assert_int(_sim.state_of("NIGHT-d1")).is_equal(FlightSim.State.DEPARTED)
	assert_bool(_sim.is_doors_closed("NIGHT-d1")).is_true()
	assert_that(_sim.boarding_window("NIGHT-d1")).is_equal(window)
	assert_int(_sim.doors_close_tick("NIGHT-d1")).is_equal(window.y)
	assert_float(_sim.phase_progress("NIGHT-d1", 24020.0)).is_equal(1.0)
	assert_str(_sim.flight_contract_id("NIGHT-d1")).is_equal("NIGHT")


func test_only_issued_canonical_ids_are_answered() -> void:
	_sim.accept_contract(TestFlightContracts.terms("NIGHT", 30))
	_run_to(24020)
	for id in ["NIGHT-d0", "NIGHT-d2", "NIGHT-d01", "NIGHT-d", "OTHER-d1", "NIGHT-d1x"]:
		assert_int(_sim.state_of(id)).override_failure_message(id).is_equal(-1)
		assert_bool(_sim.is_doors_closed(id)).is_false()
		assert_str(_sim.flight_contract_id(id)).is_equal("")


## Two contracts over four days: one live occurrence each at most, issued in
## time order, and the save does not grow.
func test_several_days_run_without_growing_state() -> void:
	_sim.accept_contract(TestFlightContracts.terms("AM", 480))
	_sim.accept_contract(TestFlightContracts.terms("PM", 840))
	_run_to(GameCalendar.TICKS_PER_DAY)
	var day_one_size := JSON.stringify(_sim.to_snapshot()).length()
	_run_to(4 * GameCalendar.TICKS_PER_DAY)
	assert_array(_added_ids).is_equal(
		["AM-d0", "PM-d0", "AM-d1", "PM-d1", "AM-d2", "PM-d2", "AM-d3", "PM-d3", "AM-d4"]
	)
	for i in range(1, _added.size()):
		assert_int(_added[i].x).is_greater(_added[i - 1].x)
	assert_int(_most_live).is_equal(1)
	assert_array(_sim.flight_ids()).is_equal(["AM-d4"])
	var snapshot := _sim.to_snapshot()
	assert_int(snapshot["flights"].size()).is_equal(1)
	assert_int(snapshot["next_day"].size()).is_equal(2)
	# Only the digit counts grow: the tick and the eleven start ticks gain one digit each.
	assert_int(JSON.stringify(snapshot).length()).is_less_equal(day_one_size + 12)


## PlaneView draws the flight holding the gate: SCHEDULED has not reached it yet.
func test_flight_at_gate_follows_each_days_occurrence() -> void:
	_sim.accept_contract(TestFlightContracts.terms("AM", 480))
	assert_array(_sim.flight_ids()).is_equal(["AM-d0"])
	assert_str(_sim.flight_at_gate("C")).is_equal("")
	_run_to(440)
	assert_str(_sim.flight_at_gate("C")).is_equal("AM-d0")
	_run_to(3019)
	assert_str(_sim.flight_at_gate("C")).is_equal("AM-d0")
	_run_to(3020)
	assert_str(_sim.flight_at_gate("C")).is_equal("")
	_run_to(440 + GameCalendar.TICKS_PER_DAY)
	assert_str(_sim.flight_at_gate("C")).is_equal("AM-d1")
	assert_str(_sim.flight_at_gate("A")).is_equal("")


func test_the_bootstrap_flight_holds_gate_c() -> void:
	_sim.add_default_flight()
	assert_str(_sim.flight_at_gate(FlightSim.DEFAULT_GATE)).is_equal(FlightSim.DEFAULT_ID)
	_run_to(2580)
	assert_str(_sim.flight_at_gate(FlightSim.DEFAULT_GATE)).is_equal("")
	assert_array(_sim.flight_ids()).is_equal([FlightSim.DEFAULT_ID])


## A tick that jumps past several issue ticks issues them oldest first.
func test_a_jump_issues_overdue_occurrences_in_time_order() -> void:
	_sim.accept_contract(TestFlightContracts.terms("PM", 840))
	_sim.accept_contract(TestFlightContracts.terms("AM", 480))
	assert_array(_added_ids).is_equal(["AM-d0"])
	_sim.on_tick(2 * GameCalendar.TICKS_PER_DAY)
	assert_array(_added_ids).is_equal(["AM-d0", "PM-d0", "AM-d1", "PM-d1", "AM-d2"])
	assert_array(_sim.flight_ids()).is_equal(["AM-d2"])
	assert_int(_sim.state_of("PM-d1")).is_equal(FlightSim.State.DEPARTED)


## flight_ids() is in timetable order whatever order flights were added in.
func test_flights_are_listed_by_first_start_then_id() -> void:
	assert_bool(_sim.add_flight("LATER", FlightSim.schedule_starts(4000))).is_true()
	assert_bool(_sim.add_flight("SOONER", FlightSim.schedule_starts(3100))).is_true()
	assert_bool(_sim.add_flight("ALSO", FlightSim.schedule_starts(3100))).is_true()
	assert_bool(_sim.accept_contract(TestFlightContracts.terms("AM", 480))).is_true()
	assert_array(_sim.flight_ids()).is_equal(["AM-d0", "ALSO", "SOONER", "LATER"])
