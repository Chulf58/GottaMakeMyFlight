class_name TestMissSignals
extends GdUnitTestSuite
## Which stations count as full.

var _world: PassengerTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _world != null:
		_world.free_all()
		_world = null


## One desk whose lane holds exactly 3 (the floor ends), an entrance on the
## west edge, no scanner and a flight far in the future.
func _short_lane_world() -> PassengerTestWorld:
	var grid := PassengerTestWorld.floored(Vector2i(6, 5))
	var desk := PassengerTestWorld.place(grid, &"checkin_desk", Vector2i(2, 1), 0)
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(0, 4), 3)
	var world := PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(4000, 5000))
	world.sim.set_meta(&"desk", desk)
	return world


func _spawn_spaced(count: int) -> void:
	for i in count:
		_world.sim.spawn_now(PassengerTestWorld.FLIGHT)
		_world.run_to(_world.clock.tick + 12)


func test_a_lane_at_capacity_or_with_overflow_is_full() -> void:
	assert_bool(MissSignals.is_full(6, 6, 0)).is_true()
	assert_bool(MissSignals.is_full(2, 2, 0)).is_true()
	# A scanner moves its front into the passage after the holding refill, so
	# for the rest of that tick its lane is one short with passengers waiting.
	assert_bool(MissSignals.is_full(6, 5, 1)).is_true()
	assert_bool(MissSignals.is_full(6, 5, 0)).is_false()
	assert_bool(MissSignals.is_full(6, 0, 0)).is_false()
	assert_bool(MissSignals.is_full(0, 0, 0)).is_false()


func test_a_part_filled_lane_is_not_full() -> void:
	_world = _short_lane_world()
	var desk: int = _world.sim.get_meta(&"desk")
	assert_dict(MissSignals.full_stations(_world.sim)).is_empty()
	_spawn_spaced(2)
	_world.run_to(_world.clock.tick + 25)
	assert_int(_world.sim.queue_of(desk).size()).is_equal(2)
	assert_dict(MissSignals.full_stations(_world.sim)).is_empty()


func test_an_exactly_full_lane_is_full_with_no_overflow() -> void:
	_world = _short_lane_world()
	var desk: int = _world.sim.get_meta(&"desk")
	_spawn_spaced(3)
	_world.run_to(_world.clock.tick + 25)
	assert_int(_world.sim.queue_of(desk).size()).is_equal(3)
	assert_int(_world.sim.holding_of(desk).size()).is_equal(0)
	assert_dict(MissSignals.full_stations(_world.sim)).is_equal({desk: 0})


func test_overflow_is_counted_and_clears_when_the_queue_drains() -> void:
	_world = _short_lane_world()
	var desk: int = _world.sim.get_meta(&"desk")
	_spawn_spaced(5)
	_world.run_to(_world.clock.tick + 25)
	assert_int(_world.sim.holding_of(desk).size()).is_equal(2)
	assert_dict(MissSignals.full_stations(_world.sim)).is_equal({desk: 2})
	# Five services of 60 ticks; with no scanner the served stay stuck elsewhere.
	_world.run_to(_world.clock.tick + 5 * PassengerSim.CHECKIN_TICKS + 40)
	assert_int(_world.sim.queue_of(desk).size()).is_equal(0)
	assert_dict(MissSignals.full_stations(_world.sim)).is_empty()
