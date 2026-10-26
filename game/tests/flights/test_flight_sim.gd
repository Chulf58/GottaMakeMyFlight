class_name TestFlightSim
extends GdUnitTestSuite

const FRAME := 1.0 / 60.0
const STARTS: Array[int] = [0, 100, 220, 360, 660, 700, 1100, 1160, 1280, 1580, 1780]
const FLIGHT := "GMF101"

var _changes: Array[Vector2i] = []
var _door_events: Array[int] = []
var _clock: SimClock
var _sim: FlightSim


func before_test() -> void:
	_changes.clear()
	_door_events.clear()
	_clock = _new_clock()
	_sim = _new_sim(_clock)


func _new_clock() -> SimClock:
	return auto_free(SimClock.new()) as SimClock


func _new_sim(clock: SimClock) -> FlightSim:
	var sim := auto_free(FlightSim.new()) as FlightSim
	sim.bind_clock(clock)
	sim.state_changed.connect(_on_changed.bind(clock))
	sim.doors_closed.connect(_on_doors.bind(clock))
	return sim


func _on_changed(_id: String, state: int, clock: SimClock) -> void:
	_changes.append(Vector2i(clock.tick, state))


func _on_doors(_id: String, clock: SimClock) -> void:
	_door_events.append(clock.tick)


## Steps the clock one sim tick per call until it reaches `target`.
func _run_to_tick(clock: SimClock, target: int) -> void:
	var guard := 0
	while clock.tick < target and guard < 100000:
		clock.advance(SimClock.STEP / clock.speed)
		guard += 1
	assert_int(clock.tick).is_equal(target)


func _transitions() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for state in range(1, STARTS.size()):
		out.append(Vector2i(STARTS[state], state))
	return out


func test_default_flight_uses_the_fixed_timing_table() -> void:
	_sim.add_default_flight()
	assert_array(_sim.flight_ids()).is_equal([FLIGHT])
	for state in STARTS.size():
		assert_int(_sim.state_start(FLIGHT, state)).is_equal(STARTS[state])
	assert_int(_sim.state_of(FLIGHT)).is_equal(FlightSim.State.SCHEDULED)


func test_states_come_in_order_on_the_scheduled_ticks() -> void:
	_sim.add_default_flight()
	_run_to_tick(_clock, 1800)
	assert_array(_changes).is_equal(_transitions())
	assert_int(_sim.state_of(FLIGHT)).is_equal(FlightSim.State.DEPARTED)


func test_state_holds_between_deadlines() -> void:
	_sim.add_default_flight()
	_run_to_tick(_clock, 359)
	assert_int(_sim.state_of(FLIGHT)).is_equal(FlightSim.State.LANDING)
	_run_to_tick(_clock, 360)
	assert_int(_sim.state_of(FLIGHT)).is_equal(FlightSim.State.TAXI_IN)


func _run_real_time(speed: int) -> int:
	var clock := _new_clock()
	var sim := _new_sim(clock)
	sim.add_default_flight()
	assert_bool(clock.set_speed(speed)).is_true()
	_changes.clear()
	var frames := 0
	while sim.state_of(FLIGHT) != FlightSim.State.DEPARTED and frames < 100000:
		clock.advance(FRAME)
		frames += 1
	return frames


func test_transitions_land_on_the_same_sim_ticks_at_1x_and_3x() -> void:
	var frames_1x := _run_real_time(1)
	assert_array(_changes).is_equal(_transitions())
	var frames_3x := _run_real_time(3)
	assert_array(_changes).is_equal(_transitions())
	# Three times the speed needs about a third of the frames.
	assert_int(absi(frames_1x - frames_3x * 3)).is_less_equal(9)


func test_pause_freezes_the_state() -> void:
	_sim.add_default_flight()
	_run_to_tick(_clock, 500)
	assert_int(_sim.state_of(FLIGHT)).is_equal(FlightSim.State.TAXI_IN)
	_clock.set_paused(true)
	for i in 600:
		_clock.advance(FRAME)
	assert_int(_clock.tick).is_equal(500)
	assert_int(_sim.tick).is_equal(500)
	assert_int(_sim.state_of(FLIGHT)).is_equal(FlightSim.State.TAXI_IN)
	assert_int(_changes.size()).is_equal(3)
	_clock.set_paused(false)
	_run_to_tick(_clock, 700)
	assert_int(_sim.state_of(FLIGHT)).is_equal(FlightSim.State.BOARDING)


func test_doors_closed_query_and_signal() -> void:
	_sim.add_default_flight()
	assert_bool(_sim.is_doors_closed(FLIGHT)).is_false()
	assert_that(_sim.boarding_window(FLIGHT)).is_equal(Vector2i(700, 1100))
	assert_int(_sim.doors_close_tick(FLIGHT)).is_equal(1100)
	_run_to_tick(_clock, 1099)
	assert_int(_sim.state_of(FLIGHT)).is_equal(FlightSim.State.BOARDING)
	assert_bool(_sim.is_doors_closed(FLIGHT)).is_false()
	_run_to_tick(_clock, 1100)
	assert_bool(_sim.is_doors_closed(FLIGHT)).is_true()
	assert_array(_door_events).is_equal([1100])
	_run_to_tick(_clock, 1800)
	assert_bool(_sim.is_doors_closed(FLIGHT)).is_true()
	assert_array(_door_events).is_equal([1100])


func test_phase_progress_runs_from_zero_to_one_in_each_phase() -> void:
	_sim.add_default_flight()
	assert_float(_sim.phase_progress(FLIGHT, 0.0)).is_equal(0.0)
	assert_float(_sim.phase_progress(FLIGHT, 50.0)).is_equal(0.5)
	_run_to_tick(_clock, 360)
	assert_float(_sim.phase_progress(FLIGHT, 360.0)).is_equal(0.0)
	assert_float(_sim.phase_progress(FLIGHT, 510.0)).is_equal(0.5)
	assert_float(_sim.phase_progress(FLIGHT, 659.9)).is_between(0.99, 1.0)
	_run_to_tick(_clock, 1800)
	assert_float(_sim.phase_progress(FLIGHT, 1800.0)).is_equal(1.0)


func test_duplicate_flight_ids_are_rejected() -> void:
	assert_bool(_sim.add_default_flight()).is_true()
	assert_bool(_sim.add_default_flight()).is_false()
	assert_int(_sim.flight_ids().size()).is_equal(1)


func test_snapshot_round_trip_mid_taxi() -> void:
	_sim.add_default_flight()
	_run_to_tick(_clock, 480)
	assert_int(_sim.state_of(FLIGHT)).is_equal(FlightSim.State.TAXI_IN)
	var saved := JSON.stringify({"clock": _clock.to_snapshot(), "flights": _sim.to_snapshot()})
	var data: Dictionary = JSON.parse_string(saved)
	var clock2 := _new_clock()
	var sim2 := _new_sim(clock2)
	assert_bool(clock2.from_snapshot(data["clock"])).is_true()
	assert_bool(sim2.from_snapshot(data["flights"])).is_true()
	assert_int(sim2.tick).is_equal(480)
	assert_int(sim2.state_of(FLIGHT)).is_equal(FlightSim.State.TAXI_IN)
	assert_that(sim2.boarding_window(FLIGHT)).is_equal(Vector2i(700, 1100))
	_changes.clear()
	_run_to_tick(clock2, 1800)
	var expected: Array[Vector2i] = []
	for state in range(FlightSim.State.AT_STAND, STARTS.size()):
		expected.append(Vector2i(STARTS[state], state))
	assert_array(_changes).is_equal(expected)


func test_snapshot_rejects_bad_input_whole() -> void:
	_sim.add_default_flight()
	_run_to_tick(_clock, 480)
	var good := _sim.to_snapshot()
	var bad_cases: Array[Dictionary] = []
	var missing := good.duplicate(true)
	missing.erase("tick")
	bad_cases.append(missing)
	var wrong_state := good.duplicate(true)
	wrong_state["flights"][0]["state"] = FlightSim.State.PUSHBACK
	bad_cases.append(wrong_state)
	var backwards := good.duplicate(true)
	backwards["flights"][0]["starts"][4] = 100
	bad_cases.append(backwards)
	var short := good.duplicate(true)
	short["flights"][0]["starts"].pop_back()
	bad_cases.append(short)
	var twins := good.duplicate(true)
	twins["flights"].append(twins["flights"][0].duplicate(true))
	bad_cases.append(twins)
	var negative := good.duplicate(true)
	negative["tick"] = -1
	bad_cases.append(negative)
	for bad in bad_cases:
		var target := _new_sim(_new_clock())
		assert_bool(target.from_snapshot(bad)).is_false()
		assert_int(target.flight_ids().size()).is_equal(0)
		assert_int(target.tick).is_equal(0)
