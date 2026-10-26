class_name TestPassengerSnapshot
extends GdUnitTestSuite
## A save in the middle of a queue loads into a world that then plays out
## exactly like the one that never stopped.

const SAVE_TICK := 205

var _a: PassengerTestWorld
var _b: PassengerTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	for world in [_a, _b]:
		if world != null:
			world.free_all()
	_a = null
	_b = null


func _save(world: PassengerTestWorld) -> String:
	return (
		JSON
		. stringify(
			{
				"clock": world.clock.to_snapshot(),
				"flights": world.flights.to_snapshot(),
				"grid": world.grid.to_snapshot(),
				"passengers": world.sim.to_snapshot(),
			}
		)
	)


func _load(text: String) -> PassengerTestWorld:
	var data: Dictionary = JSON.parse_string(text)
	var grid := BuildGrid.new()
	assert_bool(grid.from_snapshot(data["grid"])).is_true()
	var world := PassengerTestWorld.make(grid, FlightSim.schedule_starts(0), 99)
	assert_bool(world.clock.from_snapshot(data["clock"])).is_true()
	assert_bool(world.flights.from_snapshot(data["flights"])).is_true()
	assert_bool(world.sim.from_snapshot(data["passengers"])).is_true()
	return world


func test_mid_queue_save_load_plays_out_identically_through_doors_close() -> void:
	_a = PassengerTestWorld.reference_world(4242)
	_a.sim.schedule_flight(PassengerTestWorld.FLIGHT, 24)
	for i in 10:
		_a.sim.spawn_now(PassengerTestWorld.FLIGHT)
	_a.run_to(SAVE_TICK)
	# Mid-queue: someone is being served and someone waits behind them.
	var waiting := 0
	var serving := 0
	for id in _a.sim.passenger_ids():
		var stage := _a.passenger(id).stage
		waiting += int(stage == Passenger.Stage.CHECKIN_QUEUE)
		serving += int(stage == Passenger.Stage.CHECKIN)
	assert_int(waiting).is_greater(0)
	assert_int(serving).is_greater(0)
	assert_int(_a.sim.pending_spawns()).is_greater(0)
	_b = _load(_save(_a))
	assert_str(_b.signature()).is_equal(_a.signature())
	var doors := _a.flights.doors_close_tick(PassengerTestWorld.FLIGHT)
	var differing := 0
	var first_bad := -1
	while _a.clock.tick <= doors:
		_a.step()
		_b.step()
		if _a.signature() != _b.signature():
			differing += 1
			if first_bad < 0:
				first_bad = _a.clock.tick
	assert_int(first_bad).override_failure_message("first differing tick %d" % first_bad).is_equal(
		-1
	)
	assert_int(differing).is_equal(0)
	assert_int(_a.sim.made_count() + _a.sim.missed_count()).is_equal(34)
	assert_int(_b.sim.made_count()).is_equal(_a.sim.made_count())


func test_bad_snapshots_are_rejected_whole() -> void:
	_a = PassengerTestWorld.reference_world()
	_a.sim.schedule_flight(PassengerTestWorld.FLIGHT, 4)
	_a.sim.spawn_now(PassengerTestWorld.FLIGHT)
	_a.sim.spawn_now(PassengerTestWorld.FLIGHT)
	_a.run_to(80)
	var good: Dictionary = JSON.parse_string(JSON.stringify(_a.sim.to_snapshot()))
	var bad_cases: Array[Dictionary] = []
	for key: String in good:
		var missing := good.duplicate(true)
		missing.erase(key)
		bad_cases.append(missing)
	var version := good.duplicate(true)
	version["save_version"] = PassengerSim.SAVE_VERSION + 1
	bad_cases.append(version)
	var stage := good.duplicate(true)
	stage["passengers"][0]["stage"] = 99
	bad_cases.append(stage)
	var off_grid := good.duplicate(true)
	off_grid["passengers"][0]["at"] = [500, 2]
	bad_cases.append(off_grid)
	var ghost_queue := good.duplicate(true)
	ghost_queue["queues"].append({"station": 1, "lane": [12345], "holding": [], "serving": 0})
	bad_cases.append(ghost_queue)
	_b = PassengerTestWorld.reference_world()
	var before := _b.signature()
	for bad in bad_cases:
		assert_bool(_b.sim.from_snapshot(bad)).is_false()
		assert_str(_b.signature()).is_equal(before)
		assert_int(_b.sim.pending_spawns()).is_equal(0)


func test_out_of_range_passenger_fields_are_rejected_whole() -> void:
	_a = PassengerTestWorld.reference_world()
	_a.sim.spawn_now(PassengerTestWorld.FLIGHT)
	_a.run_to(40)
	var good: Dictionary = JSON.parse_string(JSON.stringify(_a.sim.to_snapshot()))
	_b = PassengerTestWorld.reference_world()
	var before := _b.signature()
	for change in [
		["variant", 2],
		["variant", -1],
		["mood", PassengerSim.MOOD_MAX + 1],
		["mood", -1],
		["seg_mm", -1],
		["apron_mm", -1],
		["odometer_mm", -1],
	]:
		var bad := good.duplicate(true)
		bad["passengers"][0][change[0]] = change[1]
		assert_bool(_b.sim.from_snapshot(bad)).override_failure_message(str(change)).is_false()
		assert_str(_b.signature()).is_equal(before)
		assert_int(_b.sim.passenger_ids().size()).is_equal(0)
