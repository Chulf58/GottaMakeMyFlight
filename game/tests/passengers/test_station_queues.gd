class_name TestStationQueues
extends GdUnitTestSuite
## Station choice, bounded FIFO lanes and the holding area.

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
## west edge and no scanner.
func _short_lane_world() -> PassengerTestWorld:
	var grid := PassengerTestWorld.floored(Vector2i(6, 5))
	var desk := PassengerTestWorld.place(grid, &"checkin_desk", Vector2i(2, 1), 0)
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(0, 4), 3)
	var world := PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(4000, 5000))
	world.sim.set_meta(&"desk", desk)
	return world


func test_first_choice_is_the_desk_that_finishes_soonest() -> void:
	_world = PassengerTestWorld.reference_world()
	var ids := ReferenceTerminal.object_ids(_world.grid)
	var first := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	_world.step()
	# The east desk is nearer the entrance, so it finishes first.
	assert_int(_world.passenger(first).station).is_equal(ids["desks"][1])
	var second := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	_world.step()
	# The east desk now has one passenger's service ahead; the west desk is idle.
	assert_int(_world.passenger(second).station).is_equal(ids["desks"][0])


func test_equal_estimates_choose_the_lower_station_id() -> void:
	# Entrance at x = 4. Lanes at x = 1 and x = 6: the nearer east desk wins,
	# which proves the walk counts.
	var near := _two_desk_world(6)
	var id := near.sim.spawn_now(PassengerTestWorld.FLIGHT)
	near.step()
	assert_int(near.passenger(id).station).is_equal(near.sim.get_meta(&"east"))
	near.free_all()
	# Lanes at x = 1 and x = 7 are both 3 columns away: the lower id wins.
	_world = _two_desk_world(7)
	var west: int = _world.sim.get_meta(&"west")
	assert_int(west).is_less(_world.sim.get_meta(&"east"))
	var other := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	_world.step()
	assert_int(_world.passenger(other).station).is_equal(west)


func _two_desk_world(east_x: int) -> PassengerTestWorld:
	var grid := PassengerTestWorld.floored(Vector2i(9, 6))
	var west := PassengerTestWorld.place(grid, &"checkin_desk", Vector2i(1, 1), 0)
	var east := PassengerTestWorld.place(grid, &"checkin_desk", Vector2i(east_x, 1), 0)
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(4, 5), 2)
	var world := PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(4000, 5000))
	world.sim.set_meta(&"west", west)
	world.sim.set_meta(&"east", east)
	return world


func test_lane_is_bounded_and_served_first_in_first_out() -> void:
	_world = _short_lane_world()
	var desk: int = _world.sim.get_meta(&"desk")
	var spawned: Array[int] = []
	for i in 5:
		spawned.append(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
		_world.run_to(_world.clock.tick + 12)
	_world.run_to(_world.clock.tick + 25)
	assert_int(_world.sim.queue_of(desk).size()).is_equal(3)
	assert_int(_world.sim.holding_of(desk).size()).is_equal(2)
	var served: Array[int] = []
	var guard := 0
	while served.size() < 5 and guard < 2000:
		_world.step()
		guard += 1
		for id in spawned:
			var p := _world.passenger(id)
			if p.stage == Passenger.Stage.CHECKIN and not served.has(id):
				served.append(id)
		assert_int(_world.sim.queue_of(desk).size()).is_less_equal(3)
	assert_array(served).is_equal(spawned)


func test_holding_shows_queue_full_until_a_slot_frees() -> void:
	_world = _short_lane_world()
	var desk: int = _world.sim.get_meta(&"desk")
	var ids: Array[int] = []
	for i in 4:
		ids.append(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
		_world.run_to(_world.clock.tick + 12)
	_world.run_to(_world.clock.tick + 30)
	var fourth := _world.passenger(ids[3])
	assert_array(_world.sim.holding_of(desk)).is_equal([ids[3]])
	assert_int(fourth.stuck).is_equal(Passenger.Stuck.QUEUE_FULL)
	assert_str(_world.sim.bubble_text(fourth)).is_equal("Queue full")
	var guard := 0
	while _world.sim.holding_of(desk).size() > 0 and guard < 400:
		_world.step()
		guard += 1
	assert_array(_world.sim.queue_of(desk)).contains([ids[3]])
	assert_int(fourth.stuck).is_equal(Passenger.Stuck.NONE)
	assert_int(_world.sim.queue_of(desk).find(ids[3])).is_equal(2)
