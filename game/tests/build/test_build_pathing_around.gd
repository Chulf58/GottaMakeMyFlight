class_name TestBuildPathingAround
extends GdUnitTestSuite
## BuildGrid.find_path_around(): the passenger A* route with some cells shut
## for one query (decision queue-walkers-route-around-their-own-line-a-walker-
## heading-t). The shut cells are never on the route but its two ends may be,
## and the graph is left as it was, cells already off (not indoor) included.


func _wall_column(grid: BuildGrid, x: int, rows: Array) -> void:
	for y: int in rows:
		(
			assert_bool(grid.apply(BuildEdit.place_wall(Vector2i(x, y), BuildGrid.Side.WEST)).ok)
			. is_true()
		)


func test_the_route_goes_round_the_shut_cells() -> void:
	var grid := PassengerTestWorld.floored(Vector2i(7, 5))
	var shut: Array[Vector2i] = [Vector2i(3, 1), Vector2i(3, 2), Vector2i(3, 3)]
	var plain := grid.find_path(Vector2i(1, 2), Vector2i(5, 2))
	var around := grid.find_path_around(Vector2i(1, 2), Vector2i(5, 2), shut)
	print("plain %s, around %s" % [plain, around])
	assert_bool(plain.has(Vector2i(3, 2))).is_true()
	assert_int(Passenger.path_mm(around)).is_greater(Passenger.path_mm(plain))
	assert_that(around[0]).is_equal(Vector2i(1, 2))
	assert_that(around[around.size() - 1]).is_equal(Vector2i(5, 2))
	for cell in shut:
		assert_bool(around.has(cell)).is_false()


func test_the_graph_is_as_it_was_after_the_query() -> void:
	var grid := PassengerTestWorld.floored(Vector2i(7, 5))
	var shut: Array[Vector2i] = [Vector2i(3, 0), Vector2i(3, 1), Vector2i(3, 2), Vector2i(3, 3)]
	var before := grid.find_path(Vector2i(1, 2), Vector2i(5, 2))
	grid.find_path_around(Vector2i(1, 2), Vector2i(5, 2), shut)
	assert_array(grid.find_path(Vector2i(1, 2), Vector2i(5, 2))).is_equal(before)
	# The shut cells are on again: a route along them is straight.
	assert_int(grid.find_path(Vector2i(3, 0), Vector2i(3, 3)).size()).is_equal(4)


func test_a_cell_already_off_stays_off() -> void:
	# (3, 2) has no floor, so it is not indoor and its point is off before the
	# query; shutting it too must not switch it back on afterwards.
	var grid := BuildGrid.new(Vector2i(7, 5))
	var edits: Array[BuildEdit] = []
	for y in 5:
		for x in 7:
			if Vector2i(x, y) != Vector2i(3, 2):
				edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	grid.apply_batch(edits)
	EnclosureKit.close_floor(grid)
	var before := grid.find_path(Vector2i(1, 2), Vector2i(5, 2))
	assert_bool(before.has(Vector2i(3, 2))).is_false()
	var shut: Array[Vector2i] = [Vector2i(3, 2), Vector2i(3, 1)]
	var around := grid.find_path_around(Vector2i(1, 2), Vector2i(5, 2), shut)
	assert_bool(around.has(Vector2i(3, 1))).is_false()
	var after := grid.find_path(Vector2i(1, 2), Vector2i(5, 2))
	print("before %s, around %s, after %s" % [before, around, after])
	assert_array(after).is_equal(before)
	assert_bool(after.has(Vector2i(3, 2))).is_false()


func test_the_two_ends_may_be_shut_cells() -> void:
	var grid := PassengerTestWorld.floored(Vector2i(7, 5))
	var shut: Array[Vector2i] = [Vector2i(1, 2), Vector2i(2, 2), Vector2i(3, 2), Vector2i(5, 2)]
	var around := grid.find_path_around(Vector2i(1, 2), Vector2i(5, 2), shut)
	print("around %s" % [around])
	assert_that(around[0]).is_equal(Vector2i(1, 2))
	assert_that(around[around.size() - 1]).is_equal(Vector2i(5, 2))
	assert_bool(around.has(Vector2i(2, 2)) or around.has(Vector2i(3, 2))).is_false()


func test_no_way_round_gives_no_route_and_the_plain_one_stays() -> void:
	var grid := PassengerTestWorld.floored(Vector2i(7, 5))
	# A wall down column 3 but for row 2: the only way across is (3, 2).
	_wall_column(grid, 3, [0, 1, 3, 4])
	_wall_column(grid, 4, [0, 1, 3, 4])
	var shut: Array[Vector2i] = [Vector2i(3, 2)]
	assert_array(grid.find_path_around(Vector2i(1, 2), Vector2i(5, 2), shut)).is_empty()
	assert_bool(grid.find_path(Vector2i(1, 2), Vector2i(5, 2)).has(Vector2i(3, 2))).is_true()
