class_name TestMissMarkersShortLane
extends GdUnitTestSuite
## The queue-full sign's hover text says the lane is short when the queue is cut
## short, by the rule the alert detail uses (MissSignals.is_short, a lane shorter
## than TerminalLayout.LANE_SLOTS; decision first-time-hints-gain-place-gate-desk-
## and-place-seats-the-hi). A full-length lane keeps the plain words.

var _world: PassengerTestWorld
var _views: PassengerViews
var _markers: MissMarkers


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func after_test() -> void:
	if _views != null:
		_views.free()
		_views = null
	if _world != null:
		_world.free_all()
		_world = null


func _attach(grid: BuildGrid) -> int:
	_world = PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(4000, 5000))
	_views = PassengerTestWorld.views()
	_views.clock = _world.clock
	_views.sim = _world.sim
	add_child(_views)
	_markers = _views.get_node("MissMarkers") as MissMarkers
	_world.step()
	return _world.sim.layout.desks[0]


## Spawns `count` passengers three ticks apart, then steps until the desk's lane
## is full or `limit` ticks pass, keeping the served one in service.
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
	_world.run_to(_world.clock.tick + 25)


func test_a_full_queue_on_a_short_lane_says_the_lane_is_short_on_the_sign() -> void:
	var grid := PassengerTestWorld.floored(Vector2i(6, 5))
	PassengerTestWorld.place(grid, &"checkin_desk", Vector2i(2, 1), 0)
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(0, 4), 3)
	var desk := _attach(grid)
	assert_bool(MissSignals.is_short(_world.sim, desk)).is_true()
	_fill(desk, 6, 300)
	var text := _markers.sign_text(desk)
	print("short lane sign: %s" % text)
	assert_str(text).starts_with("Queue full · ")
	assert_str(text).ends_with(" waiting · short queue: move the desk away from the wall")


func test_a_full_queue_on_a_full_length_lane_keeps_the_plain_sign_words() -> void:
	var grid := PassengerTestWorld.floored(Vector2i(8, 14))
	PassengerTestWorld.place(grid, &"checkin_desk", Vector2i(3, 2), 0)
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(0, 13), 3)
	var desk := _attach(grid)
	assert_bool(MissSignals.is_short(_world.sim, desk)).is_false()
	_fill(desk, 14, 600)
	var text := _markers.sign_text(desk)
	print("full lane sign: %s" % text)
	assert_str(text).starts_with("Queue full · ")
	assert_str(text).ends_with(" waiting")
	assert_bool(text.contains("short")).is_false()
