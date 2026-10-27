class_name TestBaggageViews
extends GdUnitTestSuite
## BaggageViews (headless: positions only; how a bag looks is a windowed
## plate): a bag on a belt lies on the belt top behind its cell's centre and
## turned along its edge, the newest bag at an end rests on the end's
## Mount_BagRest, and bags at a desk, older bags in the room and settled bags
## are not drawn.

var _world: BagTestWorld
var _views: BaggageViews
var _desk := 0


func before_test() -> void:
	_world = BagTestWorld.make(self, 600)
	_desk = _world.line()
	_views = auto_free(BaggageViews.new())
	_views.clock = _world.clock
	_views.sim = _world.sim
	add_child(_views)


func _origin(id: int) -> Vector3:
	_views.draw()
	return _views.node_for(id).transform.origin


func test_the_rest_mount_is_read_from_the_end_piece() -> void:
	var mount := BaggageViews.mount_transform(BaggageViews.END_SCENE, BaggageViews.REST_MOUNT)
	assert_bool(mount.is_equal_approx(Transform3D.IDENTITY)).is_false()
	assert_float(mount.origin.y).is_between(0.1, 0.8)
	assert_float(absf(mount.origin.x)).is_less(0.5)
	assert_float(absf(mount.origin.z)).is_less(0.5)


func test_a_riding_bag_lies_on_the_belt_behind_its_cell_centre() -> void:
	var bag := _world.sim.check_in(1, BagTestWorld.FLIGHT, _desk)
	assert_int(_views.active_count()).is_equal(0)
	_world.step()
	assert_int(_views.active_count()).is_equal(1)
	var centre := _world.grid.cell_to_world(BagTestWorld.ENTRY)
	var expected := centre + Vector3(0.0, BaggageViews.BELT_TOP, 0.45)
	assert_vector(_origin(bag.id)).is_equal_approx(expected, Vector3.ONE * 0.0001)
	var heading := _views.node_for(bag.id).transform.basis.z
	assert_vector(heading).is_equal_approx(Vector3(0.0, 0.0, -1.0), Vector3.ONE * 0.0001)
	_world.run_to(20)
	var along := BaggageViews.belt_transform(_world.grid, bag)
	assert_vector(along.origin).is_equal_approx(
		_world.grid.cell_to_world(Vector2i(4, 7)) + Vector3(-0.5, BaggageViews.BELT_TOP, 0.0),
		Vector3.ONE * 0.0001
	)
	assert_vector(along.basis.z).is_equal_approx(Vector3(1.0, 0.0, 0.0), Vector3.ONE * 0.0001)


func test_a_bag_is_drawn_between_its_last_two_tick_positions() -> void:
	var bag := _world.sim.check_in(1, BagTestWorld.FLIGHT, _desk)
	_world.run_to(3)
	var before := BaggageViews.belt_transform(_world.grid, bag).origin
	_world.step()
	var after := BaggageViews.belt_transform(_world.grid, bag).origin
	# The clock advanced by whole steps: alpha 0 draws the tick before.
	assert_float(_world.clock.alpha).is_equal(0.0)
	assert_vector(_origin(bag.id)).is_equal_approx(before, Vector3.ONE * 0.0001)
	_world.clock.advance(SimClock.STEP * 0.5)
	assert_vector(_origin(bag.id)).is_equal_approx(before.lerp(after, 0.5), Vector3.ONE * 0.001)


func test_only_the_newest_bag_at_an_end_rests_on_it_and_settled_bags_go() -> void:
	var first := _world.sim.check_in(1, BagTestWorld.FLIGHT, _desk)
	var second := _world.sim.check_in(2, BagTestWorld.FLIGHT, _desk)
	# One tick after arriving, so the last two tick positions are both at rest.
	_world.run_to(BagTestWorld.ARRIVAL + 1)
	assert_int(first.state).is_equal(Bag.State.IN_ROOM)
	var rest: Transform3D = _views.rest_transform(_world.grid, BagTestWorld.END)
	assert_vector(_origin(first.id)).is_equal_approx(rest.origin, Vector3.ONE * 0.0001)
	assert_object(_views.node_for(second.id)).is_not_null()
	_world.run_to(BagTestWorld.ARRIVAL + 31)
	assert_int(second.state).is_equal(Bag.State.IN_ROOM)
	assert_object(_views.node_for(first.id)).is_null()
	assert_vector(_origin(second.id)).is_equal_approx(rest.origin, Vector3.ONE * 0.0001)
	assert_int(_views.active_count()).is_equal(1)
	_world.run_to(second.cutoff_tick)
	assert_int(second.state).is_equal(Bag.State.LOADED)
	assert_int(_views.active_count()).is_equal(0)
	# Two bags were drawn at most at once, so the pool made two nodes, both
	# hidden now.
	var nodes := _views.get_children().filter(func(n: Node) -> bool: return n is Node3D)
	assert_int(nodes.size()).is_equal(2)
	assert_bool(nodes.any(func(n: Node3D) -> bool: return n.visible)).is_false()
	assert_object(_views.rest_transform(_world.grid, Vector2i(5, 7))).is_null()
