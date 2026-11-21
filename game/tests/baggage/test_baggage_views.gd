class_name TestBaggageViews
extends GdUnitTestSuite
## BaggageViews (headless: positions only; how a bag looks is a windowed
## plate): a bag on a belt lies on the belt top behind its cell's centre and
## turned along its edge; waiting IN_ROOM bags at an end and waiting AT_DESK
## bags at a desk render visibly stacked up to their stack caps; settled bags
## are released.

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


func test_waiting_in_room_bags_stack_visibly_at_belt_end_and_settled_bags_go() -> void:
	var bags: Array[Bag] = []
	for i in BaggageViews.MAX_ROOM_STACK + 2:
		bags.append(_world.sim.check_in(i + 1, BagTestWorld.FLIGHT, _desk))
	_world.run_to(BagTestWorld.ARRIVAL + 1)
	assert_int(bags[0].state).is_equal(Bag.State.IN_ROOM)
	var rest: Transform3D = _views.rest_transform(_world.grid, BagTestWorld.END)
	assert_vector(_origin(bags[0].id)).is_equal_approx(rest.origin, Vector3.ONE * 0.0001)
	# Run until all bags arrive in the room.
	_world.run_to(BagTestWorld.ARRIVAL + 30 * (BaggageViews.MAX_ROOM_STACK + 1) + 2)
	for bag in bags:
		assert_int(bag.state).is_equal(Bag.State.IN_ROOM)
	# First MAX_ROOM_STACK bags are drawn stacked along the rest normal; overflow is capped.
	for i in BaggageViews.MAX_ROOM_STACK:
		assert_object(_views.node_for(bags[i].id)).is_not_null()
		var expected: Transform3D = _views.room_stack_transform(_world.grid, BagTestWorld.END, i)
		assert_vector(_origin(bags[i].id)).is_equal_approx(expected.origin, Vector3.ONE * 0.0001)
	assert_object(_views.node_for(bags[BaggageViews.MAX_ROOM_STACK].id)).is_null()
	assert_int(_views.active_count()).is_equal(BaggageViews.MAX_ROOM_STACK)
	# Strictly rising heights across stacked suitcases.
	assert_float(_origin(bags[1].id).y).is_greater(_origin(bags[0].id).y + 0.15)
	_world.run_to(bags[0].cutoff_tick)
	for bag in bags:
		assert_int(bag.state).is_equal(Bag.State.LOADED)
	assert_int(_views.active_count()).is_equal(0)
	var nodes := _views.get_children().filter(func(n: Node) -> bool: return n is Node3D)
	assert_int(nodes.size()).is_equal(BaggageViews.MAX_ROOM_STACK + 2)
	assert_bool(nodes.any(func(n: Node3D) -> bool: return n.visible)).is_false()
	assert_object(_views.rest_transform(_world.grid, Vector2i(5, 7))).is_null()


func test_waiting_at_desk_bags_stack_visibly_and_cap_at_max_desk_stack() -> void:
	var bare := _world.desk(Vector2i(2, 2))
	var bags: Array[Bag] = []
	for i in BaggageViews.MAX_DESK_STACK + 2:
		bags.append(_world.sim.check_in(i + 1, BagTestWorld.FLIGHT, bare))
	_world.step()
	for bag in bags:
		assert_int(bag.state).is_equal(Bag.State.AT_DESK)
	assert_int(_views.active_count()).is_equal(BaggageViews.MAX_DESK_STACK)
	for i in BaggageViews.MAX_DESK_STACK:
		var expected: Transform3D = BaggageViews.desk_transform(_world.grid, bare, i)
		assert_object(_views.node_for(bags[i].id)).is_not_null()
		assert_vector(_origin(bags[i].id)).is_equal_approx(expected.origin, Vector3.ONE * 0.0001)
	assert_float(_origin(bags[1].id).y).is_greater(_origin(bags[0].id).y + 0.15)
	assert_object(_views.node_for(bags[BaggageViews.MAX_DESK_STACK].id)).is_null()


func test_parked_cart_hides_while_shuttle_is_active_and_restores_on_return_and_snap() -> void:
	var cart_id := PassengerTestWorld.place(_world.grid, &"baggage_cart", Vector2i(11, 7), 0)
	var mode: BuildMode = auto_free(BuildMode.new())
	mode.starter_shell = false
	add_child(mode)
	mode.set_process(false)
	var build_view := mode.get_node("BuildView") as BuildView
	build_view.refresh(_world.grid)
	_world.sim.build_mode = mode
	var parked := build_view.object_node(cart_id)
	assert_object(parked).is_not_null()
	var parked_bags := parked.find_child(BaggageViews.CART_BAGS_NODE, true, false) as Node3D
	assert_object(parked_bags).is_not_null()
	_views.draw()
	assert_bool(parked.visible).is_true()
	assert_bool(parked_bags.visible).is_false()
	var bag := _world.sim.check_in(1, BagTestWorld.FLIGHT, _desk)
	_world.run_to(bag.cutoff_tick)
	assert_int(_world.sim.shuttles().size()).is_equal(1)
	_views.draw()
	assert_bool(parked.visible).is_false()
	var shuttle := _world.sim.shuttles()[0]
	var saved: Dictionary = JSON.parse_string(JSON.stringify(_world.sim.to_snapshot()))
	assert_bool(_world.sim.from_snapshot(saved)).is_true()
	_views.snap()
	assert_bool(parked.visible).is_false()
	assert_int(_views.active_shuttle_count()).is_equal(1)
	_world.run_to(shuttle.return_tick)
	_views.draw()
	assert_bool(parked.visible).is_true()
	assert_bool(parked_bags.visible).is_false()
