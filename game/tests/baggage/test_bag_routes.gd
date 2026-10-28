class_name TestBagRoutes
extends GdUnitTestSuite
## The route field (BagRoutes; decision baggage-bag-sim-design-route-field-
## belt-capacity-cutoff): roots are belt ends in ready bag rooms, cells join
## only through links and ports, ties are canonical, and each step gets one
## cell closer to a root.

var _world: BagTestWorld


func before_test() -> void:
	_world = BagTestWorld.make(self)


func _routes() -> BagRoutes:
	return BagRoutes.build(_world.grid)


## Every routed cell's next step leads to a cell exactly one closer.
func _assert_descends(routes: BagRoutes) -> void:
	for cell in routes.dist:
		if routes.is_root(cell):
			assert_bool(routes.next.has(cell)).is_false()
			continue
		var to: Vector2i = cell + routes.step_from(cell)
		assert_int(routes.dist[to]).is_equal(routes.dist[cell] - 1)


func test_a_desk_line_routes_to_the_end_in_a_ready_bag_room() -> void:
	var desk_id := _world.line()
	var routes := _routes()
	assert_bool(routes.is_root(BagTestWorld.END)).is_true()
	assert_int(routes.dist[BagTestWorld.ENTRY]).is_equal(7)
	assert_that(routes.step_from(BagTestWorld.ENTRY)).is_equal(Vector2i(1, 0))
	assert_that(routes.entry_of(desk_id)).is_equal(
		{"cell": BagTestWorld.ENTRY, "step": Vector2i(0, -1)}
	)
	assert_int(routes.dist.size()).is_equal(8)
	_assert_descends(routes)


func test_an_end_outside_a_room_or_in_a_room_not_ready_is_no_root() -> void:
	_world.desk(BagTestWorld.DESK)
	_world.lay(BagTestWorld.ENTRY, BagTestWorld.END)
	assert_int(_routes().dist.size()).is_equal(0)
	# A 1x2 bag room is under the 2x2 minimum: its end is no root.
	_world.room(Rect2i(12, 2, 1, 2))
	_world.lay(Vector2i(12, 3), Vector2i(12, 5))
	var shaped := _world.grid.get_object(_world.grid.object_at(Vector2i(12, 3)))
	assert_str(str(shaped["def"])).is_equal("baggage_belt_end")
	assert_int(_routes().dist.size()).is_equal(0)


func test_a_wall_or_a_mismatched_piece_cuts_the_route() -> void:
	_world.line()
	assert_bool(_routes().has_route(BagTestWorld.ENTRY)).is_true()
	# A straight turned across the line has no port toward its neighbours.
	_world.grid.apply(BuildEdit.reshape_belt(Vector2i(6, 7), &"baggage_belt", 0))
	var routes := _routes()
	assert_bool(routes.has_route(Vector2i(7, 7))).is_true()
	assert_bool(routes.has_route(Vector2i(6, 7))).is_false()
	assert_bool(routes.has_route(BagTestWorld.ENTRY)).is_false()
	assert_bool(routes.joined(Vector2i(5, 7), Vector2i(1, 0))).is_false()


func test_a_desk_with_no_belt_or_a_removed_desk_has_no_entry() -> void:
	var desk_id := _world.desk(BagTestWorld.DESK)
	assert_that(_routes().entry_of(desk_id)).is_equal({})
	_world.room(BagTestWorld.ROOM)
	_world.lay(BagTestWorld.ENTRY, BagTestWorld.END)
	assert_that(_routes().entry_of(desk_id)).is_not_equal({})
	assert_bool(_world.grid.apply(BuildEdit.remove_object(desk_id)).ok).is_true()
	assert_that(_routes().entry_of(desk_id)).is_equal({})
	assert_that(_routes().entry_of(0)).is_equal({})


func test_equal_routes_go_to_the_first_root_in_coordinate_order() -> void:
	# A line from (2, 3) to (12, 3) with a bag room at each end and a desk two
	# rows below (its agent row between, decision desk-belts-run-one-row-back-
	# desk-then-the-agent-row-then-the) whose outlet cell (7, 4) feeds (7, 3)
	# from below: both ends are 5 cells from (7, 3).
	_world.room(Rect2i(0, 2, 3, 3))
	_world.room(Rect2i(12, 2, 3, 3))
	var desk_id := _world.desk(Vector2i(6, 5))
	_world.lay(Vector2i(2, 3), Vector2i(12, 3))
	_world.lay(Vector2i(7, 4), Vector2i(7, 4))
	var routes := _routes()
	assert_bool(routes.is_root(Vector2i(2, 3))).is_true()
	assert_bool(routes.is_root(Vector2i(12, 3))).is_true()
	assert_that(routes.entry_of(desk_id)["cell"]).is_equal(Vector2i(7, 4))
	assert_int(routes.dist[Vector2i(7, 4)]).is_equal(6)
	assert_int(routes.dist[Vector2i(7, 3)]).is_equal(5)
	assert_that(routes.step_from(Vector2i(7, 4))).is_equal(Vector2i(0, -1))
	assert_that(routes.step_from(Vector2i(7, 3))).is_equal(Vector2i(-1, 0))
	assert_that(routes.step_from(Vector2i(8, 3))).is_equal(Vector2i(1, 0))
	_assert_descends(routes)
	# The same layout always gives the same field.
	var again := _routes()
	assert_that(again.next).is_equal(routes.next)
	assert_that(again.dist).is_equal(routes.dist)


func test_a_bag_may_ride_a_line_laid_from_the_room_toward_the_desk() -> void:
	_world.room(BagTestWorld.ROOM)
	var desk_id := _world.desk(BagTestWorld.DESK)
	_world.lay(BagTestWorld.END, BagTestWorld.ENTRY)
	var routes := _routes()
	assert_int(routes.dist[routes.entry_of(desk_id)["cell"]]).is_equal(7)
	_assert_descends(routes)


func test_the_nearest_of_two_bag_rooms_wins() -> void:
	_world.line()
	# A second room two cells above the entry, reached by a short spur.
	_world.room(Rect2i(2, 2, 3, 3))
	_world.lay(Vector2i(3, 6), Vector2i(3, 4))
	var routes := _routes()
	assert_bool(routes.is_root(Vector2i(3, 4))).is_true()
	assert_that(routes.step_from(BagTestWorld.ENTRY)).is_equal(Vector2i(0, -1))
	assert_int(routes.dist[BagTestWorld.ENTRY]).is_equal(3)
	_assert_descends(routes)
