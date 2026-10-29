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
	assert_int(ids.size()).is_equal(4)
	# Fake a spread of recorded stages, as the flight keeps them: three at
	# security, one at the gate.
	world.sim.flight_results[PassengerTestWorld.FLIGHT]["causes"] = {
		Vector2i(Passenger.Stage.SECURITY_QUEUE, Passenger.Stuck.NONE): 3,
		Vector2i(Passenger.Stage.SEATED, Passenger.Stuck.NONE): 1,
	}
	var reasons: Array = FlightResult.summarize(world.sim, PassengerTestWorld.FLIGHT)["reasons"]
	assert_int(reasons.size()).is_equal(2)
	assert_int(reasons[0]["count"]).is_equal(3)
	assert_int(reasons[1]["count"]).is_equal(1)


func test_reasons_that_tie_sort_by_text_ascending() -> void:
	var world := _bare_room()
	var ids: Array[int] = []
	for i in 5:
		ids.append(world.sim.spawn_now(PassengerTestWorld.FLIGHT))
	world.run_to(21)
	var fates := [
		Passenger.Stage.SECURITY_QUEUE,
		Passenger.Stage.SECURITY_QUEUE,
		Passenger.Stage.CHECKIN_QUEUE,
		Passenger.Stage.CHECKIN_QUEUE,
		Passenger.Stage.SEATED
	]
	assert_int(ids.size()).is_equal(5)
	var causes := {}
	for fate in fates:
		var cause := Vector2i(fate, Passenger.Stuck.NONE)
		causes[cause] = int(causes.get(cause, 0)) + 1
	world.sim.flight_results[PassengerTestWorld.FLIGHT]["causes"] = causes
	var reasons: Array = FlightResult.summarize(world.sim, PassengerTestWorld.FLIGHT)["reasons"]
	var got := []
	for reason in reasons:
		got.append("%d %s" % [reason["count"], reason["text"]])
	assert_array(got).is_equal(
		[
			"2 Still queuing for check-in",
			"2 Still queuing for security",
			"1 At the gate, but not boarded in time"
		]
	)


func test_passengers_who_made_the_flight_are_counted_apart_from_the_missed() -> void:
	var world := PassengerTestWorld.reference_world()
	_worlds.append(world)
	for i in 2:
		world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	world.run_to(1700)
	var late := world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	world.run_to(1900)
	var summary := FlightResult.summarize(world.sim, PassengerTestWorld.FLIGHT)
	assert_int(summary["made"]).is_equal(2)
	assert_int(summary["missed"]).is_equal(1)
	var reasons: Array = summary["reasons"]
	assert_int(reasons.size()).is_equal(1)
	assert_int(reasons[0]["count"]).is_equal(1)
	var p := world.passenger(late)
	assert_str(reasons[0]["text"]).is_equal(
		FlightResult.reason_text(p.missed_stage, p.missed_stuck)
	)


func test_the_summary_ignores_other_flights() -> void:
	var world := _bare_room()
	world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	world.run_to(21)
	var summary := FlightResult.summarize(world.sim, "OTHER")
	assert_int(summary["missed"]).is_equal(0)
	assert_int(summary["made"]).is_equal(0)
	assert_array(summary["reasons"]).is_empty()


func test_each_stage_has_its_exact_reason_text() -> void:
	var gate := "At the gate, but not boarded in time"
	var late_exit := "Left the gate too late for the plane"
	var cafe := "Still at the cafe"
	var toilet := "Still at the toilet"
	# A miss records only the stage, not which shop (kiosk or store) it was at.
	var kiosk := "Still at a shop"
	var expected := {
		Passenger.Stage.SPAWNED: "Arrived after the doors closed",
		Passenger.Stage.TO_CHECKIN: "Still walking to check-in",
		Passenger.Stage.CHECKIN_QUEUE: "Still queuing for check-in",
		Passenger.Stage.CHECKIN: "Still at the check-in desk",
		Passenger.Stage.TO_SECURITY: "Still walking to security",
		Passenger.Stage.SECURITY_QUEUE: "Still queuing for security",
		Passenger.Stage.SECURITY: "Still at security",
		Passenger.Stage.TO_GATE: "Still walking to the gate",
		Passenger.Stage.SITTING_DOWN: gate,
		Passenger.Stage.SEATED: gate,
		Passenger.Stage.STANDING: gate,
		Passenger.Stage.STANDING_UP: gate,
		Passenger.Stage.TO_EXIT: late_exit,
		Passenger.Stage.APRON: late_exit,
		Passenger.Stage.CAFE_WALK: cafe,
		Passenger.Stage.CAFE_QUEUE: cafe,
		Passenger.Stage.CAFE_ORDER: cafe,
		Passenger.Stage.CAFE_TO_SEAT: cafe,
		Passenger.Stage.CAFE_SITTING_DOWN: cafe,
		Passenger.Stage.CAFE_SEATED: cafe,
		Passenger.Stage.CAFE_STANDING_UP: cafe,
		Passenger.Stage.TOILET_WALK: toilet,
		Passenger.Stage.TOILET_ENTER: toilet,
		Passenger.Stage.TOILET_SITTING_DOWN: toilet,
		Passenger.Stage.TOILET_USE: toilet,
		Passenger.Stage.TOILET_STANDING_UP: toilet,
		Passenger.Stage.TOILET_EXIT: toilet,
		Passenger.Stage.SHOP_WALK: kiosk,
		Passenger.Stage.SHOP_BROWSE: kiosk,
	}
	# Every stage a passenger can be missed in is in the table, so a stage added
	# to the enum without a reason fails here.
	assert_int(expected.size()).is_equal(Passenger.Stage.size() - 2)
	for stage in expected:
		assert_str(FlightResult.reason_text(stage, Passenger.Stuck.NONE)).is_equal(expected[stage])


func test_each_stuck_status_has_its_exact_reason_text_and_beats_the_stage() -> void:
	var expected := {
		Passenger.Stuck.NO_CHECKIN: "No check-in desk to go to",
		Passenger.Stuck.NO_SECURITY: "No security scanner or lane to go to",
		Passenger.Stuck.QUEUE_FULL: "Waiting outside a full queue",
		Passenger.Stuck.NO_ROUTE: "No walkable route",
		Passenger.Stuck.EXIT_BLOCKED: "The exit to the plane was blocked",
	}
	assert_int(expected.size()).is_equal(Passenger.Stuck.size() - 1)
	for stuck in expected:
		assert_str(FlightResult.reason_text(Passenger.Stage.SEATED, stuck)).is_equal(
			expected[stuck]
		)


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
