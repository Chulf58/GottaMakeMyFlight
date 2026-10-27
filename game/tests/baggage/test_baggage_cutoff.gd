class_name TestBaggageCutoff
extends GdUnitTestSuite
## Loaded or missed (BaggageSim; decision baggage-bag-sim-design-route-field-
## belt-capacity-cutoff): on the cutoff tick (doors close minus 200) a bag in
## the room is loaded and any other is missed with its cause; bag_settled
## fires once per bag; settled bags are retired and results follow the
## flight.


func _world(doors := 4000) -> BagTestWorld:
	return BagTestWorld.make(self, doors)


func test_a_bag_reaching_the_room_on_the_cutoff_tick_is_loaded() -> void:
	# Doors at 350: cutoff 150, the arrival tick.
	var world := _world(BagTestWorld.ARRIVAL + BaggageSim.LOAD_LEAD_TICKS)
	var bag := world.sim.check_in(4, BagTestWorld.FLIGHT, world.line())
	assert_int(bag.cutoff_tick).is_equal(BagTestWorld.ARRIVAL)
	world.run_to(BagTestWorld.ARRIVAL - 1)
	assert_int(bag.state).is_equal(Bag.State.RIDING)
	assert_array(world.settled).is_empty()
	world.step()
	assert_int(bag.state).is_equal(Bag.State.LOADED)
	assert_int(bag.outcome_tick).is_equal(BagTestWorld.ARRIVAL)
	assert_array(world.settled).is_equal([[bag.id, 4, BagTestWorld.FLIGHT, true, 150]])
	assert_that(world.sim.results[BagTestWorld.FLIGHT]).is_equal(
		{"loaded": 1, "missed": 0, "causes": {}}
	)
	assert_int(world.sim.loaded_total).is_equal(1)


func test_a_bag_one_tick_short_of_the_room_at_cutoff_is_missed_late() -> void:
	var world := _world(BagTestWorld.ARRIVAL - 1 + BaggageSim.LOAD_LEAD_TICKS)
	var bag := world.sim.check_in(4, BagTestWorld.FLIGHT, world.line())
	world.run_to(BagTestWorld.ARRIVAL - 1)
	assert_int(bag.state).is_equal(Bag.State.MISSED)
	assert_int(bag.cause).is_equal(Bag.Cause.LATE)
	assert_int(bag.remain_mm).is_equal(BaggageSim.BELT_MM)
	world.run_to(BagTestWorld.ARRIVAL + 10)
	assert_int(bag.state).is_equal(Bag.State.MISSED)
	assert_array(world.settled).is_equal([[bag.id, 4, BagTestWorld.FLIGHT, false, 149]])
	assert_that(world.sim.results[BagTestWorld.FLIGHT]["causes"]).is_equal({"late": 1})
	assert_int(world.sim.missed_total).is_equal(1)


func test_a_bag_checked_in_on_or_after_the_cutoff_is_missed_at_once() -> void:
	var world := _world(400)
	var desk_id := world.line()
	world.run_to(200)
	var bag := world.sim.check_in(9, BagTestWorld.FLIGHT, desk_id)
	assert_int(bag.state).is_equal(Bag.State.MISSED)
	assert_int(bag.cause).is_equal(Bag.Cause.LATE)
	assert_array(world.settled).is_equal([[bag.id, 9, BagTestWorld.FLIGHT, false, 200]])
	world.run_to(260)
	assert_int(world.settled.size()).is_equal(1)
	assert_int(bag.remain_mm).is_equal(0)


func test_a_bag_one_tick_before_the_cutoff_still_rides() -> void:
	var world := _world(400)
	var desk_id := world.line()
	world.run_to(199)
	var bag := world.sim.check_in(9, BagTestWorld.FLIGHT, desk_id)
	assert_int(bag.state).is_equal(Bag.State.AT_DESK)
	world.step()
	assert_int(bag.state).is_equal(Bag.State.MISSED)
	assert_int(bag.cause).is_equal(Bag.Cause.LATE)


func test_causes_name_a_desk_with_no_belt_and_a_belt_with_no_room() -> void:
	var world := _world(400)
	var bare := world.desk(Vector2i(2, 2))
	var lined := world.desk(BagTestWorld.DESK)
	world.lay(BagTestWorld.ENTRY, BagTestWorld.END)
	# A bag room the belt does not reach: bags are checked in (there is a ready
	# room) and the lined desk's belt has no route to it.
	BagRoomKit.add(world.grid, Rect2i(13, 1, 2, 2))
	var no_belt := world.sim.check_in(1, BagTestWorld.FLIGHT, bare)
	var no_room := world.sim.check_in(2, BagTestWorld.FLIGHT, lined)
	world.run_to(200)
	assert_int(no_belt.cause).is_equal(Bag.Cause.NO_BELT)
	assert_int(no_room.cause).is_equal(Bag.Cause.NO_ROUTE)
	assert_int(no_room.state).is_equal(Bag.State.MISSED)
	assert_that(world.sim.results[BagTestWorld.FLIGHT]).is_equal(
		{"loaded": 0, "missed": 2, "causes": {"no_belt": 1, "no_route": 1}}
	)


func test_a_queued_bag_waiting_for_space_is_missed_late() -> void:
	var world := _world(BagTestWorld.ARRIVAL + BaggageSim.LOAD_LEAD_TICKS)
	var desk_id := world.line()
	var bags: Array[Bag] = []
	for i in 6:
		bags.append(world.sim.check_in(i + 1, BagTestWorld.FLIGHT, desk_id))
	world.run_to(BagTestWorld.ARRIVAL)
	assert_int(bags[0].state).is_equal(Bag.State.LOADED)
	assert_int(bags[5].state).is_equal(Bag.State.MISSED)
	assert_int(bags[5].cause).is_equal(Bag.Cause.LATE)
	assert_int(world.settled.size()).is_equal(6)


func test_settled_bags_are_retired_and_results_follow_the_flight() -> void:
	var world := _world(400)
	var bag := world.sim.check_in(1, BagTestWorld.FLIGHT, world.line())
	world.run_to(200 + BaggageSim.SETTLED_KEEP_TICKS - 1)
	assert_object(world.sim.get_bag(bag.id)).is_not_null()
	world.step()
	assert_object(world.sim.get_bag(bag.id)).is_null()
	assert_array(world.sim.bag_ids()).is_empty()
	assert_bool(world.sim.results.has(BagTestWorld.FLIGHT)).is_true()
	# Results stay while FlightSim lists the flight and go once it does not.
	world.sim.results["GMF999"] = {"loaded": 0, "missed": 1, "causes": {"late": 1}}
	world.step()
	assert_bool(world.sim.results.has("GMF999")).is_false()
	assert_bool(world.sim.results.has(BagTestWorld.FLIGHT)).is_true()
	assert_int(world.sim.loaded_total).is_equal(1)
