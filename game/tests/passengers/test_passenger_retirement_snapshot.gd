class_name TestPassengerRetirementSnapshot
extends GdUnitTestSuite
## What retirement leaves behind is saved: the made and missed totals, each
## flight's results and the occurrences already scheduled. A version 4 save,
## which rebuilt the totals from retained passengers, is refused.

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


func _round_trip() -> Dictionary:
	return JSON.parse_string(JSON.stringify(_a.sim.to_snapshot()))


## A world whose settled passengers have all been retired, with some misses.
func _retired() -> void:
	_a = PassengerTestWorld.reference_world(11)
	_a.sim.schedule_flight(PassengerTestWorld.FLIGHT, 8)
	for i in 4:
		_a.sim.spawn_now(PassengerTestWorld.FLIGHT)
	# Arrivals after this tick cannot reach the plane before the doors close.
	_a.run_to(1700)
	for i in 3:
		_a.sim.spawn_now(PassengerTestWorld.FLIGHT)
	_a.run_to(1900 + PassengerSim.SETTLED_KEEP_TICKS + 5)
	assert_int(_a.sim.passenger_ids().size()).is_equal(0)
	assert_int(_a.sim.made_count() + _a.sim.missed_count()).is_equal(15)
	assert_int(_a.sim.missed_count()).is_greater(0)


func test_version_is_5_and_a_version_4_save_is_refused() -> void:
	assert_int(PassengerSim.SAVE_VERSION).is_equal(5)
	_retired()
	var data := _round_trip()
	assert_int(int(data["save_version"])).is_equal(5)
	data["save_version"] = 4
	_b = PassengerTestWorld.reference_world()
	assert_bool(_b.sim.from_snapshot(data)).is_false()


func test_totals_results_and_scheduled_flights_survive_a_save_after_retirement() -> void:
	_retired()
	_b = PassengerTestWorld.reference_world()
	assert_bool(_b.sim.from_snapshot(_round_trip())).is_true()
	assert_int(_b.sim.passenger_ids().size()).is_equal(0)
	assert_int(_b.sim.made_count()).is_equal(_a.sim.made_count())
	assert_int(_b.sim.missed_count()).is_equal(_a.sim.missed_count())
	assert_int(_b.sim.active_count()).is_equal(0)
	assert_dict(FlightResult.summarize(_b.sim, PassengerTestWorld.FLIGHT)).is_equal(
		FlightResult.summarize(_a.sim, PassengerTestWorld.FLIGHT)
	)


func test_a_scheduled_flight_stays_scheduled_after_a_load() -> void:
	_a = PassengerTestWorld.reference_world(11)
	_a.sim.schedule_flight(PassengerTestWorld.FLIGHT, 8)
	_a.run_to(100)
	_b = PassengerTestWorld.reference_world()
	assert_bool(_b.sim.from_snapshot(_round_trip())).is_true()
	assert_bool(_b.sim._scheduled.has(PassengerTestWorld.FLIGHT)).is_true()
	assert_bool(_b.sim.schedule_flight(PassengerTestWorld.FLIGHT, 3)).is_false()


func test_inconsistent_totals_and_results_are_refused_whole() -> void:
	_retired()
	var good := _round_trip()
	_b = PassengerTestWorld.reference_world()
	var before := _b.signature()
	# The causes must add up to the flight's missed passengers (case 10), and the
	# flights' counts must fit inside the totals (case 11).
	var cases: Array[Callable] = [
		func(d: Dictionary) -> void: d["made"] = -1,
		func(d: Dictionary) -> void: d["made"] = 0.5,
		func(d: Dictionary) -> void: d["missed"] = "3",
		func(d: Dictionary) -> void: d["flight_results"] = {},
		func(d: Dictionary) -> void: d["scheduled"] = [1],
		func(d: Dictionary) -> void: d["scheduled"] = ["a", "a"],
		func(d: Dictionary) -> void: d["flight_results"][0]["made"] = -1,
		func(d: Dictionary) -> void: d["flight_results"][0]["causes"][0]["count"] = -1,
		func(d: Dictionary) -> void: d["flight_results"][0]["causes"][0]["stage"] = 99,
		func(d: Dictionary) -> void:
			d["flight_results"].append(d["flight_results"][0].duplicate(true)),
		func(d: Dictionary) -> void: d["flight_results"][0]["missed"] += 1,
		func(d: Dictionary) -> void: d["made"] = 0,
	]
	for i in cases.size():
		var bad := good.duplicate(true)
		cases[i].call(bad)
		assert_bool(_b.sim.from_snapshot(bad)).override_failure_message("case %d" % i).is_false()
		assert_str(_b.signature()).is_equal(before)


func test_totals_below_the_retained_settled_passengers_are_refused() -> void:
	_a = PassengerTestWorld.reference_world(11)
	_a.run_to(1890)
	for i in 4:
		_a.sim.spawn_now(PassengerTestWorld.FLIGHT)
	_a.run_to(1950)
	assert_int(_a.sim.passenger_ids().size()).is_equal(4)
	var data := _round_trip()
	_b = PassengerTestWorld.reference_world()
	assert_bool(_b.sim.from_snapshot(data)).is_true()
	data["made"] = 0
	data["missed"] = 0
	assert_bool(_b.sim.from_snapshot(data)).is_false()


func test_totals_larger_than_the_passengers_ever_spawned_are_refused() -> void:
	_retired()
	var good := _round_trip()
	var spawned := int(good["next_id"]) - 1
	assert_int(int(good["made"]) + int(good["missed"])).is_equal(spawned)
	var cases := {
		"excessive combined": {"made": int(good["made"]) + 1},
		"excessive missed": {"missed": int(good["missed"]) + 1},
		"excessive made alone": {"made": spawned + 1, "missed": 0},
		"excessive missed alone": {"made": 0, "missed": spawned + 1},
		"huge made": {"made": 1e15},
		"huge both": {"made": 1e15, "missed": 1e15},
	}
	_b = PassengerTestWorld.reference_world()
	var before := _b.signature()
	for label: String in cases:
		var bad := good.duplicate(true)
		bad.merge(cases[label], true)
		assert_bool(_b.sim.from_snapshot(bad)).override_failure_message(label).is_false()
		assert_str(_b.signature()).is_equal(before)


func test_an_empty_world_cannot_show_made_passengers() -> void:
	_a = PassengerTestWorld.reference_world()
	var data := _round_trip()
	assert_int(int(data["next_id"])).is_equal(1)
	data["made"] = 100
	_b = PassengerTestWorld.reference_world()
	assert_bool(_b.sim.from_snapshot(data)).is_false()
	assert_int(_b.sim.made_count()).is_equal(0)
