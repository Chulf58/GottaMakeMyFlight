class_name TestNoShows
extends GdUnitTestSuite
## Passengers still scheduled when their flight's doors close are finalized as
## no-shows with a cause, saved with the sim, and never spawn afterwards.

var _worlds: Array[PassengerTestWorld] = []


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	for world in _worlds:
		world.free_all()
	_worlds.clear()


func _room(with_entrance: bool) -> PassengerTestWorld:
	var grid := PassengerTestWorld.floored(Vector2i(8, 6))
	if with_entrance:
		PassengerTestWorld.place(grid, &"entrance_door", Vector2i(0, 5), 3)
	var world := PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(10, 20))
	_worlds.append(world)
	return world


func _no_shows(world: PassengerTestWorld, cause: String) -> int:
	var counts: Dictionary = world.sim.no_shows.get(PassengerTestWorld.FLIGHT, {})
	return counts.get(cause, 0)


func _round_trip(world: PassengerTestWorld) -> Dictionary:
	return JSON.parse_string(JSON.stringify(world.sim.to_snapshot()))


func _loaded(from: PassengerTestWorld, data: Dictionary) -> bool:
	var other := PassengerTestWorld.make(from.grid, PassengerTestWorld.starts_with(10, 20))
	_worlds.append(other)
	return other.sim.from_snapshot(data)


func test_a_batch_one_tick_before_the_doors_close_is_finalized_as_late() -> void:
	var world := _room(true)
	world.run_to(19)
	assert_bool(world.sim.spawn_batch(300, 5)).is_true()
	world.run_to(21)
	assert_int(world.sim.passenger_ids().size()).is_equal(1)
	assert_int(world.sim.missed_count()).is_equal(1)
	assert_int(world.sim.pending_spawns()).is_equal(0)
	assert_int(_no_shows(world, "late")).is_equal(299)
	assert_int(_no_shows(world, "no_entrance")).is_equal(0)
	var summary := FlightResult.summarize(world.sim, PassengerTestWorld.FLIGHT)
	assert_int(summary["missed"]).is_equal(1)
	var got := []
	for reason in summary["reasons"]:
		got.append("%d %s" % [reason["count"], reason["text"]])
	assert_array(got).contains(["299 Did not arrive before the doors closed"])
	assert_array(got).not_contains(["299 %s" % FlightResult.NEVER_ARRIVED])


func test_the_result_does_not_change_after_the_doors_close() -> void:
	var world := _room(true)
	world.run_to(19)
	world.sim.spawn_batch(300, 5)
	world.run_to(21)
	var before := JSON.stringify(FlightResult.summarize(world.sim, PassengerTestWorld.FLIGHT))
	world.run_to(400)
	assert_int(world.sim.passenger_ids().size()).is_equal(1)
	(
		assert_str(JSON.stringify(FlightResult.summarize(world.sim, PassengerTestWorld.FLIGHT)))
		. is_equal(before)
	)


func test_no_entrance_at_close_is_the_cause_only_when_there_was_none() -> void:
	var world := _room(false)
	world.sim.schedule_flight(PassengerTestWorld.FLIGHT, 5)
	world.run_to(21)
	assert_int(world.sim.pending_spawns()).is_equal(0)
	assert_int(world.sim.passenger_ids().size()).is_equal(0)
	assert_int(_no_shows(world, "no_entrance")).is_equal(5)
	assert_int(_no_shows(world, "late")).is_equal(0)
	var reasons: Array = FlightResult.summarize(world.sim, PassengerTestWorld.FLIGHT)["reasons"]
	assert_int(reasons.size()).is_equal(1)
	assert_int(reasons[0]["count"]).is_equal(5)
	assert_str(reasons[0]["text"]).is_equal(FlightResult.NEVER_ARRIVED)


func test_another_flights_schedule_is_left_alone() -> void:
	var world := _room(true)
	world.flights.add_flight("GMF202", PassengerTestWorld.starts_with(100, 200))
	world.sim.schedule_flight("GMF202", 4)
	world.run_to(21)
	assert_bool(world.sim.no_shows.has("GMF202")).is_false()
	assert_int(world.sim.pending_spawns() + world.sim.passenger_ids().size()).is_equal(4)


func test_no_shows_survive_a_save_and_load() -> void:
	var world := _room(false)
	world.sim.schedule_flight(PassengerTestWorld.FLIGHT, 5)
	world.run_to(21)
	var data := _round_trip(world)
	var other := PassengerTestWorld.make(world.grid, PassengerTestWorld.starts_with(10, 20))
	_worlds.append(other)
	assert_bool(other.sim.from_snapshot(data)).is_true()
	assert_int(_no_shows(other, "no_entrance")).is_equal(5)
	(
		assert_str(JSON.stringify(FlightResult.summarize(other.sim, PassengerTestWorld.FLIGHT)))
		. is_equal(JSON.stringify(FlightResult.summarize(world.sim, PassengerTestWorld.FLIGHT)))
	)


func test_bad_missed_fields_and_no_shows_are_refused_whole() -> void:
	var world := _room(true)
	world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	world.run_to(21)
	world.sim.no_shows[PassengerTestWorld.FLIGHT] = {"no_entrance": 1, "late": 2}
	var good := _round_trip(world)
	assert_bool(_loaded(world, good.duplicate(true))).is_true()
	var bad_cases: Array[Dictionary] = []
	for field in ["missed_stage", "missed_stuck"]:
		for value in [99, -1, 1.5, "x", null, true]:
			var bad := good.duplicate(true)
			bad["passengers"][0][field] = value
			bad_cases.append(bad)
	var no_key := good.duplicate(true)
	no_key.erase("no_shows")
	bad_cases.append(no_key)
	for value in [-1, 1.5, "x", null]:
		for cause in ["no_entrance", "late"]:
			var bad := good.duplicate(true)
			bad["no_shows"][0][cause] = value
			bad_cases.append(bad)
	var wrong_flight := good.duplicate(true)
	wrong_flight["no_shows"][0]["flight"] = 7
	bad_cases.append(wrong_flight)
	var repeated := good.duplicate(true)
	repeated["no_shows"].append(repeated["no_shows"][0].duplicate())
	bad_cases.append(repeated)
	var not_a_list := good.duplicate(true)
	not_a_list["no_shows"] = {}
	bad_cases.append(not_a_list)
	for bad in bad_cases:
		assert_bool(_loaded(world, bad)).is_false()
