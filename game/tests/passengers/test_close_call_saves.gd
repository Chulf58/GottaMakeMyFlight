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
	assert_array(PassengerThoughts.entries(missed)).is_empty()


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
	# Bad close_calls values are rejected.
	var bad_neg: Dictionary = data.duplicate(true)
	bad_neg["flight_results"][0]["close_calls"] = -1
	assert_bool(_other.sim.from_snapshot(bad_neg)).is_false()
	var bad_over: Dictionary = data.duplicate(true)
	bad_over["flight_results"][0]["close_calls"] = 2
	assert_bool(_other.sim.from_snapshot(bad_over)).is_false()
