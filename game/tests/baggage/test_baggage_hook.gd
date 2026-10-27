class_name TestBaggageHook
extends GdUnitTestSuite
## PassengerSim hands each passenger's bag over when check-in ends
## (checked_in), naming the desk; a bound BaggageSim checks one bag in for
## that passenger's flight.

var _world: PassengerTestWorld
var _bags: BaggageSim
## [passenger id, desk, stage at the signal, station at the signal].
var _events: Array = []


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	_events.clear()
	_world = PassengerTestWorld.reference_world()
	_world.sim.checked_in.connect(
		func(id: int, desk: int) -> void:
			var p := _world.passenger(id)
			_events.append([id, desk, p.stage, p.station])
	)
	_bags = auto_free(BaggageSim.new())
	_bags.bind(_world.clock, _world.flights, _world.grid, _world.sim)


func test_check_in_hands_over_one_bag_at_the_serving_desk() -> void:
	var ids: Array[int] = []
	for i in 3:
		ids.append(_world.sim.spawn_now(PassengerTestWorld.FLIGHT, 0))
	var stop := _world.clock.tick + 3000
	while _events.size() < ids.size() and _world.clock.tick < stop:
		_world.step()
	assert_int(_events.size()).is_equal(ids.size())
	var desks := _world.sim.layout.desks
	for event in _events:
		assert_array(ids).contains([event[0]])
		assert_array(desks).contains([event[1]])
		assert_int(event[2]).is_equal(Passenger.Stage.TO_SECURITY)
		assert_int(event[3]).is_equal(0)
	assert_int(_bags.bag_ids().size()).is_equal(ids.size())
	for i in _events.size():
		var bag := _bags.get_bag(i + 1)
		assert_int(bag.passenger).is_equal(_events[i][0])
		assert_int(bag.desk).is_equal(_events[i][1])
		assert_str(bag.flight).is_equal(PassengerTestWorld.FLIGHT)
		assert_int(bag.created_tick).is_less_equal(_world.clock.tick)
	# No more hand-overs than passengers, however long they walk on.
	_world.run_to(_world.clock.tick + 400)
	assert_int(_events.size()).is_equal(ids.size())
