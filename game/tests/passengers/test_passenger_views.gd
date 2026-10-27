class_name TestPassengerViews
extends GdUnitTestSuite
## Pooled character views follow stable passenger ids and interpolate with
## the clock's alpha.

var _world: PassengerTestWorld
var _views: PassengerViews


func before() -> void:
	PassengerTestWorld.tracker = self


func after() -> void:
	PassengerTestWorld.tracker = null


func before_test() -> void:
	var grid := PassengerTestWorld.floored(Vector2i(8, 6))
	PassengerTestWorld.place(grid, &"entrance_door", Vector2i(0, 5), 3)
	PassengerTestWorld.place(grid, &"checkin_desk", Vector2i(5, 1), 0)
	_world = PassengerTestWorld.make(grid, PassengerTestWorld.starts_with(30, 40))
	_views = PassengerViews.new()
	_views.clock = _world.clock
	_views.sim = _world.sim
	add_child(_views)


func after_test() -> void:
	_views.free()
	_world.free_all()


func test_each_passenger_keeps_one_pooled_node() -> void:
	var a := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	var b := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	_world.step()
	assert_int(_views.active_count()).is_equal(2)
	var node_a := _views.node_for(a)
	assert_object(node_a).is_not_null()
	assert_object(node_a).is_not_same(_views.node_for(b))
	_world.run_to(10)
	assert_object(_views.node_for(a)).is_same(node_a)


func test_missed_passengers_release_their_node_for_reuse() -> void:
	var a := _world.sim.spawn_now(PassengerTestWorld.FLIGHT, 0)
	_world.step()
	var node_a := _views.node_for(a)
	var passenger_a := _world.passenger(a)
	_world.run_to(40 + PassengerViews.MISSED_LINGER_TICKS + 1)
	# Retired from the sim by now; the held record still says it missed.
	assert_int(passenger_a.stage).is_equal(Passenger.Stage.MISSED)
	assert_object(_world.passenger(a)).is_null()
	assert_object(_views.node_for(a)).is_null()
	assert_int(_views.active_count()).is_equal(0)
	var b := _world.sim.spawn_now(PassengerTestWorld.FLIGHT, 0)
	_world.step()
	assert_object(_views.node_for(b)).is_same(node_a)


func test_draw_position_interpolates_with_the_clock_alpha() -> void:
	var a := _world.sim.spawn_now(PassengerTestWorld.FLIGHT)
	_world.run_to(5)
	var before := _views.tick_position(a, false)
	var after := _views.tick_position(a, true)
	assert_float(before.distance_to(after)).is_greater(0.05)
	_world.clock.advance(SimClock.STEP * 0.5)
	assert_float(_world.clock.alpha).is_equal_approx(0.5, 0.001)
	_views.draw()
	var drawn := _views.node_for(a).position
	assert_float(drawn.distance_to(before.lerp(after, 0.5))).is_less(0.001)
