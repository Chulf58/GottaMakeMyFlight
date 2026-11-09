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


## Keeps `desk`'s passenger in service two ticks past now. In the short lane
## world the hold cells lie past the lane, and walkers now come round the
## lane over the desk's far side instead of through it (decision queue-
## walkers-route-around-their-own-line-a-walker-heading-t), so the line fills
## after the first service would end. Its service ends two ticks after the
## last hold, so it is still seen in service once the line is full.
func _hold_service(desk: int) -> void:
	var serving: int = _world.sim._queue(desk)["serving"]
	if serving != 0:
		var p := _world.passenger(serving)
		p.service_end = maxi(p.service_end, _world.sim.tick + 2)


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
	# Three ticks apart: the fifth walks on past the first hold cell and turns
	# back onto the second (TerminalLayout.line_of(), StationQueue.approach()),
	# and stands there before the first is served.
	# One tick apart (was three): one walker at a time enters the line now
	# (decision hold-line-rebuild-the-security-line-follows-where-people-sta),
	# so the five must arrive closer together to fill it before the first is
	# served.
	for i in 5:
		spawned.append(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
		_world.run_to(_world.clock.tick + 1)
	for i in 300:
		if _world.sim.holding_of(desk).size() == 2:
			break
		_world.step()
		_hold_service(desk)
	assert_int(_world.sim.queue_of(desk).size()).is_equal(3)
	assert_int(_world.sim.holding_of(desk).size()).is_equal(2)
	# Moved for the latched claim (decision hold-line-rebuild-the-security-
	# line-follows-where-people-sta): first in is the first to enter the queue
	# (the soonest to reach its tail when the claim is free), not the first to
	# choose the desk.
	var entered := _world.sim.queue_of(desk) + _world.sim.holding_of(desk)
	var served: Array[int] = []
	var guard := 0
	while served.size() < 5 and guard < 2000:
		_world.step()
		guard += 1
		for id in _world.sim.queue_of(desk) + _world.sim.holding_of(desk):
			if not entered.has(id):
				entered.append(id)
		for id in spawned:
			var p := _world.passenger(id)
			if p.stage == Passenger.Stage.CHECKIN and not served.has(id):
				served.append(id)
		assert_int(_world.sim.queue_of(desk).size()).is_less_equal(3)
	print("entered %s, served %s" % [entered, served])
	assert_array(served).is_equal(entered)
	assert_int(served.size()).is_equal(spawned.size())


func test_holding_shows_queue_full_until_a_slot_frees() -> void:
	_world = _short_lane_world()
	var desk: int = _world.sim.get_meta(&"desk")
	var ids: Array[int] = []
	# Six ticks apart: the fourth walks past the first hold cell and turns back
	# onto it (StationQueue.approach()), and joins before the first is served.
	for i in 4:
		ids.append(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
		_world.run_to(_world.clock.tick + 6)
	for i in 300:
		if _world.sim.holding_of(desk).size() == 1:
			break
		_world.step()
		_hold_service(desk)
	# Moved for the latched claim (decision hold-line-rebuild-the-security-
	# line-follows-where-people-sta): the holder is the last to enter, which
	# need not be the last to choose the desk.
	assert_int(_world.sim.holding_of(desk).size()).is_equal(1)
	var fourth := _world.passenger(_world.sim.holding_of(desk)[0])
	assert_bool(ids.has(fourth.id)).is_true()
	assert_int(fourth.stuck).is_equal(Passenger.Stuck.QUEUE_FULL)
	assert_str(_world.sim.bubble_text(fourth)).is_equal("Queue full")
	var guard := 0
	while _world.sim.holding_of(desk).size() > 0 and guard < 400:
		_world.step()
		guard += 1
	assert_array(_world.sim.queue_of(desk)).contains([fourth.id])
	assert_int(fourth.stuck).is_equal(Passenger.Stuck.NONE)
	assert_int(_world.sim.queue_of(desk).find(fourth.id)).is_equal(2)


func test_desk_nearly_done_is_not_counted_a_full_service_slower() -> void:
	# Entrance at x = 2: the west lane is a few metres nearer than the east.
	var grid := PassengerTestWorld.floored(Vector2i(9, 6))
	var west := PassengerTestWorld.place(grid, &"checkin_desk", Vector2i(1, 1), 0)
	PassengerTestWorld.place(grid, &"checkin_desk", Vector2i(7, 1), 0)
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(2, 5), 2)
	_world = PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(4000, 5000))
	var busy := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	var served := _world.passenger(busy)
	served.stage = Passenger.Stage.CHECKIN
	served.station = west
	served.at = _world.sim.layout.lanes[west][0]
	served.service_end = _world.sim.tick + 5
	var q: Dictionary = _world.sim._queue(west)
	q["lane"].append(busy)
	q["serving"] = busy
	var id := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	_world.step()
	assert_int(_world.passenger(id).station).is_equal(west)


## A lane place freed while holders wait (an admission frees it before
## promote() runs) goes to the holders: a newcomer joins behind them in the
## holding list, never ahead of them in the lane (decision hold-line-as-built-
## physical-line-order-one-latched-tail-clai, rule 1).
func test_a_newcomer_joins_behind_waiting_holders_when_a_lane_place_frees() -> void:
	var cells := [Vector2i(0, 0), Vector2i(0, 1), Vector2i(0, 2)]
	var queue := {"lane": [1, 2], "holding": [3, 4], "serving": 0}
	var got_lane := StationQueue.join(queue, cells, 5)
	print("lane %s, holding %s" % [queue["lane"], queue["holding"]])
	assert_bool(got_lane).is_false()
	assert_array(queue["lane"]).is_equal([1, 2])
	assert_array(queue["holding"]).is_equal([3, 4, 5])
	# Promotion then fills the lane in that order.
	StationQueue.promote(queue, cells)
	assert_array(StationQueue.members(queue)).is_equal([1, 2, 3, 4, 5])
	# Control: with no one holding, the newcomer takes the free lane place.
	var open := {"lane": [1, 2], "holding": [], "serving": 0}
	assert_bool(StationQueue.join(open, cells, 5)).is_true()
	assert_array(open["lane"]).is_equal([1, 2, 5])
	assert_array(open["holding"]).is_empty()
