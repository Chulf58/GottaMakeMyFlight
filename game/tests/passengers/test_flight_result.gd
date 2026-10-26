class_name TestFlightResult
extends GdUnitTestSuite
## Why passengers miss: the stage and stuck status recorded when the doors
## close, the per-flight summary built from them, and the saved record.

var _worlds: Array[PassengerTestWorld] = []


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	for world in _worlds:
		world.free_all()
	_worlds.clear()


## A floored 8x6 room with an entrance and nothing else: nobody can check in.
func _bare_room(with_entrance := true) -> PassengerTestWorld:
	var grid := PassengerTestWorld.floored(Vector2i(8, 6))
	if with_entrance:
		PassengerTestWorld.place(grid, &"entrance_door", Vector2i(0, 5), 3)
	var world := PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(10, 20))
	_worlds.append(world)
	return world


func test_a_miss_records_where_the_passenger_was_and_why_it_was_stuck() -> void:
	var world := _bare_room()
	var id := world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	world.run_to(15)
	assert_int(world.passenger(id).stage).is_equal(Passenger.Stage.TO_CHECKIN)
	world.run_to(21)
	var p := world.passenger(id)
	assert_int(p.stage).is_equal(Passenger.Stage.MISSED)
	assert_int(p.missed_stage).is_equal(Passenger.Stage.TO_CHECKIN)
	assert_int(p.missed_stuck).is_equal(Passenger.Stuck.NO_CHECKIN)


func test_the_summary_counts_made_and_missed_and_groups_the_reasons() -> void:
	var world := _bare_room()
	for i in 3:
		world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	world.run_to(21)
	var summary := FlightResult.summarize(world.sim, PassengerTestWorld.FLIGHT)
	assert_str(summary["flight"]).is_equal(PassengerTestWorld.FLIGHT)
	assert_int(summary["made"]).is_equal(0)
	assert_int(summary["missed"]).is_equal(3)
	var reasons: Array = summary["reasons"]
	assert_int(reasons.size()).is_equal(1)
	assert_int(reasons[0]["count"]).is_equal(3)
	assert_str(reasons[0]["text"]).is_equal(
		FlightResult.reason_text(Passenger.Stage.TO_CHECKIN, Passenger.Stuck.NO_CHECKIN)
	)


func test_reasons_are_sorted_by_count_largest_first() -> void:
	var world := _bare_room()
	var ids: Array[int] = []
	for i in 4:
		ids.append(world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	world.run_to(21)
	# Fake a spread of recorded stages: three at security, one at the gate.
	for i in 3:
		world.passenger(ids[i]).missed_stage = Passenger.Stage.SECURITY_QUEUE
		world.passenger(ids[i]).missed_stuck = Passenger.Stuck.NONE
	world.passenger(ids[3]).missed_stage = Passenger.Stage.SEATED
	world.passenger(ids[3]).missed_stuck = Passenger.Stuck.NONE
	var reasons: Array = FlightResult.summarize(world.sim, PassengerTestWorld.FLIGHT)["reasons"]
	assert_int(reasons.size()).is_equal(2)
	assert_int(reasons[0]["count"]).is_equal(3)
	assert_int(reasons[1]["count"]).is_equal(1)


func test_passengers_who_never_arrived_because_there_is_no_entrance_are_counted() -> void:
	var world := _bare_room(false)
	world.sim.schedule_flight(PassengerTestWorld.FLIGHT, 5)
	world.run_to(21)
	assert_int(world.sim.passenger_ids().size()).is_equal(0)
	assert_int(world.sim.pending_spawns(PassengerTestWorld.FLIGHT)).is_equal(5)
	assert_int(world.sim.pending_spawns("OTHER")).is_equal(0)
	var summary := FlightResult.summarize(world.sim, PassengerTestWorld.FLIGHT)
	assert_int(summary["missed"]).is_equal(0)
	var reasons: Array = summary["reasons"]
	assert_int(reasons.size()).is_equal(1)
	assert_int(reasons[0]["count"]).is_equal(5)
	assert_str(reasons[0]["text"]).contains("entrance")


func test_the_summary_ignores_other_flights() -> void:
	var world := _bare_room()
	world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	world.run_to(21)
	var summary := FlightResult.summarize(world.sim, "OTHER")
	assert_int(summary["missed"]).is_equal(0)
	assert_int(summary["made"]).is_equal(0)
	assert_array(summary["reasons"]).is_empty()


func test_every_stage_and_stuck_status_has_a_reason_text() -> void:
	var texts := {}
	for stage in Passenger.Stage.values():
		if stage == Passenger.Stage.MADE or stage == Passenger.Stage.MISSED:
			continue
		var text := FlightResult.reason_text(stage, Passenger.Stuck.NONE)
		assert_str(text).is_not_empty()
		texts[text] = true
	for stuck in Passenger.Stuck.values():
		if stuck == Passenger.Stuck.NONE:
			continue
		var text := FlightResult.reason_text(Passenger.Stage.TO_CHECKIN, stuck)
		assert_str(text).is_not_empty()
		texts[text] = true
	# Stuck wins over the stage, so a stuck reason differs from the stage's own.
	(
		assert_str(FlightResult.reason_text(Passenger.Stage.TO_CHECKIN, Passenger.Stuck.NO_CHECKIN))
		. is_not_equal(FlightResult.reason_text(Passenger.Stage.TO_CHECKIN, Passenger.Stuck.NONE))
	)
	assert_int(texts.size()).is_greater(6)


func test_the_missed_stage_survives_a_save_and_load() -> void:
	var a := _bare_room()
	var id := a.sim.spawn_now(PassengerTestWorld.FLIGHT)
	a.run_to(21)
	var data: Dictionary = JSON.parse_string(JSON.stringify(a.sim.to_snapshot()))
	var b := PassengerTestWorld.make(a.grid, PassengerTestWorld.starts_with(10, 20))
	_worlds.append(b)
	assert_bool(b.sim.from_snapshot(data)).is_true()
	var p := b.passenger(id)
	assert_int(p.missed_stage).is_equal(Passenger.Stage.TO_CHECKIN)
	assert_int(p.missed_stuck).is_equal(Passenger.Stuck.NO_CHECKIN)


func test_a_record_without_the_missed_fields_is_refused() -> void:
	var a := _bare_room()
	a.sim.spawn_now(PassengerTestWorld.FLIGHT)
	a.run_to(21)
	var data: Dictionary = JSON.parse_string(JSON.stringify(a.sim.to_snapshot()))
	(data["passengers"][0] as Dictionary).erase("missed_stage")
	var b := PassengerTestWorld.make(a.grid, PassengerTestWorld.starts_with(10, 20))
	_worlds.append(b)
	assert_bool(b.sim.from_snapshot(data)).is_false()
