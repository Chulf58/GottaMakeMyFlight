class_name TestCloseCallSaves
extends GdUnitTestSuite
## Last-second save detection in PassengerLifecycle.finish (board ccbc48f5):
## a boarding passenger who was running late or boarded within
## CLOSE_CALL_TICKS of doors closing increments flight_results["close_calls"]
## and records a positive MADE_CLOSE_CALL thought; both survive snapshot
## round-trip.

var _world: PassengerTestWorld
var _other: PassengerTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	for world in [_world, _other]:
		if world != null:
			world.free_all()
	_world = null
	_other = null


func test_late_passenger_who_boards_early_records_close_call_and_thought() -> void:
	_world = PassengerTestWorld.reference_world()
	var id := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	_world.run_to(100)
	var p := _world.passenger(id)
	p.late = true
	PassengerLifecycle.finish(_world.sim, p, true)
	assert_bool(p.late).is_false()
	assert_int(_world.sim.flight_results[PassengerTestWorld.FLIGHT]["close_calls"]).is_equal(1)
	var summary := FlightResult.summarize(_world.sim, PassengerTestWorld.FLIGHT)
	assert_int(summary["close_calls"]).is_equal(1)
	var entries := PassengerThoughts.entries(p)
	assert_int(entries.size()).is_equal(1)
	assert_int(entries[0]["kind"]).is_equal(PassengerThoughts.Kind.MADE_CLOSE_CALL)
	assert_bool(entries[0]["positive"]).is_true()
	assert_str(entries[0]["text"]).is_equal("Made my flight at the last second!")


func test_on_time_passenger_within_close_call_window_records_close_call_and_thought() -> void:
	_world = PassengerTestWorld.reference_world()
	var id := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	var at := PassengerTestWorld.doors_tick() - PassengerLifecycle.CLOSE_CALL_TICKS
	_world.run_to(at)
	var p := _world.passenger(id)
	p.late = false
	PassengerLifecycle.finish(_world.sim, p, true)
	assert_int(_world.sim.flight_results[PassengerTestWorld.FLIGHT]["close_calls"]).is_equal(1)
	var entries := PassengerThoughts.entries(p)
	assert_int(entries.size()).is_equal(1)
	assert_int(entries[0]["kind"]).is_equal(PassengerThoughts.Kind.MADE_CLOSE_CALL)


func test_on_time_outside_window_and_missed_late_do_not_count() -> void:
	_world = PassengerTestWorld.reference_world()
	var id_early := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	var id_missed := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	var before_window := PassengerTestWorld.doors_tick() - PassengerLifecycle.CLOSE_CALL_TICKS - 1
	_world.run_to(before_window)
	var early := _world.passenger(id_early)
	early.late = false
	PassengerLifecycle.finish(_world.sim, early, true)
	var missed := _world.passenger(id_missed)
	missed.late = true
	PassengerLifecycle.finish(_world.sim, missed, false)
	assert_int(_world.sim.flight_results[PassengerTestWorld.FLIGHT]["close_calls"]).is_equal(0)
	assert_array(PassengerThoughts.entries(early)).is_empty()
	var missed_entries := PassengerThoughts.entries(missed)
	assert_int(missed_entries.size()).is_equal(1)
	assert_int(missed_entries[0]["kind"]).is_equal(PassengerThoughts.Kind.MISSED_FLIGHT)


func test_close_calls_and_thought_survive_snapshot_round_trip() -> void:
	_world = PassengerTestWorld.reference_world()
	var id := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	_world.run_to(50)
	var p := _world.passenger(id)
	p.late = true
	PassengerLifecycle.finish(_world.sim, p, true)
	var data: Dictionary = JSON.parse_string(JSON.stringify(_world.sim.to_snapshot()))
	_other = PassengerTestWorld.reference_world()
	assert_bool(_other.sim.from_snapshot(data)).is_true()
	assert_int(_other.sim.flight_results[PassengerTestWorld.FLIGHT]["close_calls"]).is_equal(1)
	(
		assert_int(FlightResult.summarize(_other.sim, PassengerTestWorld.FLIGHT)["close_calls"])
		. is_equal(1)
	)
	var loaded := _other.passenger(id)
	assert_array(PassengerThoughts.entries(loaded)).is_equal(PassengerThoughts.entries(p))
	# Absent "close_calls" in an older/manual flight_results entry defaults cleanly to 0.
	var legacy: Dictionary = data.duplicate(true)
	(legacy["flight_results"][0] as Dictionary).erase("close_calls")
	assert_bool(_other.sim.from_snapshot(legacy)).is_true()
	assert_int(_other.sim.flight_results[PassengerTestWorld.FLIGHT]["close_calls"]).is_equal(0)
	# Pre-diff v36 5-mark thought_marks with an existing thought loads cleanly alongside close calls.
	var p2_id := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	_world.run_to(55)
	var p2 := _world.passenger(p2_id)
	PassengerThoughts.record(p2, PassengerThoughts.Kind.MEAL, 52, p2.at, 1)
	var v36_data: Dictionary = JSON.parse_string(JSON.stringify(_world.sim.to_snapshot()))
	assert_int((v36_data["passengers"][1]["thought_marks"] as Array).size()).is_equal(5)
	assert_bool(_other.sim.from_snapshot(v36_data)).is_true()
	assert_int(PassengerThoughts.count(_other.passenger(p2_id))).is_equal(1)
	# Bad flight_results / close_calls values are rejected cleanly without crashing.
	var bad_cases: Array[Callable] = [
		func(d: Dictionary) -> void: d["flight_results"] = [123],
		func(d: Dictionary) -> void:
			(d["flight_results"][0] as Dictionary).erase("made")
			d["flight_results"][0]["close_calls"] = 0,
		func(d: Dictionary) -> void: d["flight_results"][0]["close_calls"] = 1.5,
		func(d: Dictionary) -> void: d["flight_results"][0]["close_calls"] = "1",
		func(d: Dictionary) -> void: d["flight_results"][0]["close_calls"] = true,
		func(d: Dictionary) -> void: d["flight_results"][0]["close_calls"] = -1,
		func(d: Dictionary) -> void: d["flight_results"][0]["close_calls"] = 2,
	]
	for i in bad_cases.size():
		var bad: Dictionary = data.duplicate(true)
		bad_cases[i].call(bad)
		(
			assert_bool(_other.sim.from_snapshot(bad))
			. override_failure_message("case %d" % i)
			. is_false()
		)
