class_name TestBaggageEdits
extends GdUnitTestSuite
## Build edits while bags ride (BaggageSim reconcile; decision baggage-bag-
## sim-design-route-field-belt-capacity-cutoff): the grid as it stands at the
## next tick decides; a vanished edge stops a bag where it is; a belt or room
## taken from under a bag loses it, settled once at once.

var _world: BagTestWorld
var _desk := 0


func before_test() -> void:
	_world = BagTestWorld.make(self)
	_desk = _world.line()


func test_a_belt_taken_away_and_laid_again_before_the_next_tick_changes_nothing() -> void:
	var bag := _world.sim.check_in(1, BagTestWorld.FLIGHT, _desk)
	_world.run_to(40)
	_world.unlay(Vector2i(5, 7))
	_world.unlay(Vector2i(8, 7))
	assert_bool(_world.sim.routes_stale).is_true()
	_world.lay(Vector2i(4, 7), Vector2i(9, 7))
	_world.run_to(BagTestWorld.ARRIVAL)
	assert_int(bag.state).is_equal(Bag.State.IN_ROOM)
	assert_int(bag.rest_tick).is_equal(BagTestWorld.ARRIVAL)
	assert_bool(_world.sim.routes_stale).is_false()


func test_a_belt_taken_from_under_a_bag_loses_it_once() -> void:
	var bag := _world.sim.check_in(3, BagTestWorld.FLIGHT, _desk)
	_world.run_to(38)
	# Entered (5, 7) on tick 31: its body is still on (4, 7) until tick 40.
	assert_that(bag.physical_cell()).is_equal(Vector2i(4, 7))
	_world.unlay(Vector2i(4, 7))
	assert_int(bag.state).is_equal(Bag.State.RIDING)
	_world.step()
	assert_int(bag.state).is_equal(Bag.State.MISSED)
	assert_int(bag.cause).is_equal(Bag.Cause.LOST)
	assert_array(_world.settled).is_equal([[bag.id, 3, BagTestWorld.FLIGHT, false, 39]])
	_world.run_to(3801)
	assert_int(_world.settled.size()).is_equal(1)
	assert_that(_world.sim.results[BagTestWorld.FLIGHT]["causes"]).is_equal({"lost": 1})


func test_a_bag_stops_short_of_its_centre_when_the_cell_behind_goes_until_it_is_back() -> void:
	var bag := _world.sim.check_in(1, BagTestWorld.FLIGHT, _desk)
	_world.run_to(45)
	# Its body is on (5, 7), but its edge from (4, 7) is not done.
	assert_that(bag.physical_cell()).is_equal(Vector2i(5, 7))
	assert_int(bag.remain_mm).is_equal(250)
	_world.unlay(Vector2i(4, 7))
	_world.run_to(60)
	assert_int(bag.state).is_equal(Bag.State.BLOCKED)
	assert_that(bag.cell).is_equal(Vector2i(5, 7))
	assert_int(bag.remain_mm).is_equal(250)
	_world.lay(Vector2i(4, 7), Vector2i(4, 7))
	_world.run_to(BagTestWorld.ARRIVAL + 15)
	# Stopped on ticks 46 to 60.
	assert_int(bag.state).is_equal(Bag.State.IN_ROOM)
	assert_int(bag.rest_tick).is_equal(BagTestWorld.ARRIVAL + 15)


func test_a_bag_leaving_its_desk_rides_on_when_the_desk_goes() -> void:
	var bag := _world.sim.check_in(1, BagTestWorld.FLIGHT, _desk)
	_world.run_to(3)
	assert_bool(bag.from_desk).is_true()
	assert_int(bag.remain_mm).is_equal(350)
	assert_bool(_world.grid.apply(BuildEdit.remove_object(_desk)).ok).is_true()
	var entry: Array[Vector2i] = [BagTestWorld.ENTRY]
	_world.grid.apply_batch(BeltShaper.reshape_edits(_world.grid, entry))
	_world.run_to(BagTestWorld.ARRIVAL)
	assert_int(bag.state).is_equal(Bag.State.IN_ROOM)
	assert_int(bag.rest_tick).is_equal(BagTestWorld.ARRIVAL)


func test_a_vanished_edge_stops_a_bag_where_it_is_until_it_comes_back() -> void:
	var bag := _world.sim.check_in(1, BagTestWorld.FLIGHT, _desk)
	_world.run_to(35)
	assert_that(bag.cell).is_equal(Vector2i(5, 7))
	assert_int(bag.remain_mm).is_equal(750)
	# A straight turned across (5, 7) leaves the bag's edge with no port.
	_world.grid.apply(BuildEdit.reshape_belt(Vector2i(5, 7), &"baggage_belt", 0))
	_world.run_to(60)
	assert_int(bag.state).is_equal(Bag.State.BLOCKED)
	assert_int(bag.remain_mm).is_equal(750)
	_world.grid.apply(BuildEdit.reshape_belt(Vector2i(5, 7), &"baggage_belt", 1))
	_world.run_to(BagTestWorld.ARRIVAL + 25)
	assert_int(bag.state).is_equal(Bag.State.IN_ROOM)
	assert_int(bag.rest_tick).is_equal(BagTestWorld.ARRIVAL + 25)


func test_a_bag_with_no_route_waits_blocked_and_rides_on_when_one_comes() -> void:
	var bag := _world.sim.check_in(1, BagTestWorld.FLIGHT, _desk)
	_world.run_to(40)
	var room_id := _world.grid.room_at(BagTestWorld.END)
	assert_bool(_world.grid.apply(BuildEdit.remove_room(room_id)).ok).is_true()
	_world.run_to(60)
	assert_int(bag.state).is_equal(Bag.State.BLOCKED)
	assert_that(bag.cell).is_equal(Vector2i(5, 7))
	assert_int(bag.remain_mm).is_equal(0)
	assert_int(bag.wait_tick).is_equal(50)
	_world.room(BagTestWorld.ROOM)
	_world.step()
	assert_int(bag.state).is_equal(Bag.State.RIDING)
	_world.run_to(200)
	assert_int(bag.state).is_equal(Bag.State.IN_ROOM)
	assert_int(bag.rest_tick).is_equal(61 + 5 * 20 - 1)


func test_a_bag_at_a_desk_with_no_belt_rides_once_one_is_laid() -> void:
	var lone := _world.desk(Vector2i(6, 2))
	var bag := _world.sim.check_in(1, BagTestWorld.FLIGHT, lone)
	_world.run_to(30)
	assert_int(bag.state).is_equal(Bag.State.AT_DESK)
	# The desk's outlet points into (7, 1); a belt round the desk joins the line.
	_world.lay(Vector2i(7, 1), Vector2i(8, 1))
	_world.lay(Vector2i(8, 1), Vector2i(8, 6))
	_world.run_to(400)
	assert_int(bag.state).is_equal(Bag.State.IN_ROOM)


func test_a_bag_in_the_room_is_lost_when_its_end_or_room_goes() -> void:
	var first := _world.sim.check_in(1, BagTestWorld.FLIGHT, _desk)
	_world.run_to(BagTestWorld.ARRIVAL)
	assert_int(first.state).is_equal(Bag.State.IN_ROOM)
	var room_id := _world.grid.room_at(BagTestWorld.END)
	_world.grid.apply(BuildEdit.remove_room(room_id))
	_world.step()
	assert_int(first.state).is_equal(Bag.State.MISSED)
	assert_int(first.cause).is_equal(Bag.Cause.LOST)
	assert_int(_world.settled.size()).is_equal(1)


func test_a_bag_reaching_a_belt_end_after_a_room_is_drawn_around_it_rests() -> void:
	var room_id := _world.grid.room_at(BagTestWorld.END)
	_world.grid.apply(BuildEdit.remove_room(room_id))
	# Another ready bag room, which the belt does not reach, keeps bags being
	# checked in while this one is gone.
	BagRoomKit.add(_world.grid, Rect2i(13, 1, 2, 2))
	var bag := _world.sim.check_in(1, BagTestWorld.FLIGHT, _desk)
	_world.run_to(BagTestWorld.ARRIVAL + 5)
	assert_int(bag.state).is_equal(Bag.State.AT_DESK)
	_world.room(BagTestWorld.ROOM)
	_world.run_to(BagTestWorld.ARRIVAL * 2 + 10)
	assert_int(bag.state).is_equal(Bag.State.IN_ROOM)
	assert_int(bag.rest_tick).is_equal(BagTestWorld.ARRIVAL + 5 + BagTestWorld.ARRIVAL)
