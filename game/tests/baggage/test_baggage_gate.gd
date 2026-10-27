class_name TestBaggageGate
extends GdUnitTestSuite
## Passengers check no bag until the airport has a ready bag room (decision
## bags-count-only-once-a-ready-bag-room-exists-missed-bag-fee-and-rating).
## "Ready" is read from the grid at the moment of check-in: a bag room whose
## RoomRules status is ok, which needs a belt end in it, so it is exactly a
## room with a root for the route field. Nothing about it is saved.

var _world: BagTestWorld
var _desk: int


func before_test() -> void:
	_world = BagTestWorld.make(self)
	_desk = _world.desk(BagTestWorld.DESK)


func test_with_no_bag_room_a_check_in_makes_no_bag() -> void:
	assert_bool(_world.sim.has_ready_bag_room()).is_false()
	assert_object(_world.sim.check_in(1, BagTestWorld.FLIGHT, _desk)).is_null()
	assert_array(_world.sim.bag_ids()).is_empty()
	assert_array(_world.settled).is_empty()
	_world.run_to(BagTestWorld.ARRIVAL)
	assert_int(_world.sim.missed_total + _world.sim.loaded_total).is_equal(0)
	assert_dict(_world.sim.results).is_empty()


func test_a_bag_room_without_a_belt_end_is_not_ready() -> void:
	_world.room(BagTestWorld.ROOM)
	assert_bool(_world.sim.has_ready_bag_room()).is_false()
	assert_object(_world.sim.check_in(1, BagTestWorld.FLIGHT, _desk)).is_null()


func test_a_bag_room_built_midway_gives_later_check_ins_a_bag() -> void:
	assert_object(_world.sim.check_in(1, BagTestWorld.FLIGHT, _desk)).is_null()
	_world.run_to(100)
	_world.room(BagTestWorld.ROOM)
	_world.lay(BagTestWorld.ENTRY, BagTestWorld.END)
	assert_bool(_world.sim.has_ready_bag_room()).is_true()
	var bag := _world.sim.check_in(2, BagTestWorld.FLIGHT, _desk)
	assert_object(bag).is_not_null()
	assert_array(_world.sim.bag_ids()).is_equal([bag.id])
	_world.run_to(100 + BagTestWorld.ARRIVAL)
	assert_int(bag.state).is_equal(Bag.State.IN_ROOM)
	# The passenger who checked in before the room existed never gets a bag.
	assert_object(_world.sim.bag_of_passenger(1)).is_null()


func test_a_removed_bag_room_gives_later_check_ins_no_bag_and_leaves_riding_bags() -> void:
	var room_id := _build_line()
	var riding := _world.sim.check_in(1, BagTestWorld.FLIGHT, _desk)
	assert_object(riding).is_not_null()
	_world.run_to(20)
	assert_int(riding.state).is_equal(Bag.State.RIDING)
	assert_bool(_world.grid.apply(BuildEdit.remove_room(room_id)).ok).is_true()
	assert_bool(_world.sim.has_ready_bag_room()).is_false()
	assert_object(_world.sim.check_in(2, BagTestWorld.FLIGHT, _desk)).is_null()
	assert_array(_world.sim.bag_ids()).is_equal([riding.id])
	# The bag already on the belt follows the existing rules: it is never
	# dropped, and it settles once, as missed, at its cutoff.
	_world.run_to(riding.cutoff_tick)
	assert_bool(riding.is_settled()).is_true()
	assert_int(riding.state).is_equal(Bag.State.MISSED)
	assert_int(_world.settled.size()).is_equal(1)


func test_the_gate_is_a_pure_function_of_the_grid() -> void:
	var other: BaggageSim = auto_free(BaggageSim.new())
	other.bind(_world.clock, _world.flights, _world.grid)
	assert_bool(other.has_ready_bag_room()).is_equal(_world.sim.has_ready_bag_room())
	_build_line()
	assert_bool(other.has_ready_bag_room()).is_true()
	assert_bool(_world.sim.has_ready_bag_room()).is_true()


## The standard belt line and bag room (the desk is already placed); returns
## the room's id.
func _build_line() -> int:
	var room_id := _world.room(BagTestWorld.ROOM)
	_world.lay(BagTestWorld.ENTRY, BagTestWorld.END)
	return room_id
