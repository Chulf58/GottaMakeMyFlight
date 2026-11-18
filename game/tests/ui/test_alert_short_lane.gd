class_name TestAlertShortLane
extends GdUnitTestSuite
## A queue-full alert on a short lane says so (decision first-time-hints-gain-
## place-gate-desk-and-place-seats-the-hi, point 3): a desk beside a wall gets a
## lane shorter than TerminalLayout.LANE_SLOTS, so it is "full" at one or two
## waiting, and the detail then names the cause and the fix. A full-length lane
## keeps the plain words. The queue-full rule itself is unchanged.

var _world: PassengerTestWorld


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _world != null:
		_world.free_all()
		_world = null


## Spawns `count` passengers three ticks apart, then steps until the desk's
## lane is full or `limit` ticks pass, keeping the served one in service so the
## line fills.
func _fill(desk: int, count: int, limit: int) -> void:
	for i in count:
		_world.sim.spawn_now(PassengerTestWorld.FLIGHT)
		_world.run_to(_world.clock.tick + 3)
	for i in limit:
		if MissSignals.full_stations(_world.sim).has(desk):
			break
		_world.step()
		var serving: int = _world.sim._queue(desk)["serving"]
		if serving != 0:
			var p := _world.passenger(serving)
			p.service_end = maxi(p.service_end, _world.sim.tick + 2)
	_world.run_to(_world.clock.tick + AlertSources.QUEUE_HOLD_TICKS)


func test_a_full_queue_on_a_short_lane_says_the_lane_is_short() -> void:
	var grid := PassengerTestWorld.floored(Vector2i(6, 5))
	var desk := PassengerTestWorld.place(grid, &"checkin_desk", Vector2i(2, 1), 0)
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(0, 4), 3)
	_world = PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(4000, 5000))
	_world.step()
	var slots: int = (_world.sim.layout.lanes[desk] as Array).size()
	print("lane slots %d of %d" % [slots, TerminalLayout.LANE_SLOTS])
	assert_int(slots).is_less(TerminalLayout.LANE_SLOTS)
	_fill(desk, 6, 300)
	assert_bool(MissSignals.full_stations(_world.sim).has(desk)).is_true()
	var detail: String = AlertSources.queue_full(_world.sim)[0]["detail"]
	print("short lane detail: %s" % detail)
	assert_str(detail).starts_with("1 desk full · ")
	assert_str(detail).ends_with(" waiting · short queue: move the desk away from the wall")


func test_a_full_queue_on_a_full_length_lane_keeps_the_plain_words() -> void:
	var grid := PassengerTestWorld.floored(Vector2i(8, 14))
	var desk := PassengerTestWorld.place(grid, &"checkin_desk", Vector2i(3, 2), 0)
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(0, 13), 3)
	_world = PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(4000, 5000))
	_world.step()
	var slots: int = (_world.sim.layout.lanes[desk] as Array).size()
	print("lane slots %d of %d" % [slots, TerminalLayout.LANE_SLOTS])
	assert_int(slots).is_equal(TerminalLayout.LANE_SLOTS)
	_fill(desk, 14, 600)
	assert_bool(MissSignals.full_stations(_world.sim).has(desk)).is_true()
	var detail: String = AlertSources.queue_full(_world.sim)[0]["detail"]
	print("full lane detail: %s" % detail)
	assert_str(detail).starts_with("1 desk full · ")
	assert_str(detail).ends_with(" waiting")
	assert_bool(detail.contains("short")).is_false()
