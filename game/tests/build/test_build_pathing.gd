class_name TestBuildPathing
extends GdUnitTestSuite


func _floored_grid(size: Vector2i) -> BuildGrid:
	var grid := BuildGrid.new(size)
	for y in size.y:
		for x in size.x:
			grid.apply(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	return grid


## Index of the first step that goes from column x - 1 into column x, or -1.
func _crossing_row(path: Array[Vector2i], x: int) -> int:
	for i in range(1, path.size()):
		if path[i - 1].x == x - 1 and path[i].x == x:
			return path[i].y
	return -1


func test_open_floor_route_is_straight() -> void:
	var grid := _floored_grid(Vector2i(12, 8))
	var path := grid.find_path(Vector2i(2, 1), Vector2i(10, 1))
	assert_int(path.size()).is_equal(9)
	assert_that(path[0]).is_equal(Vector2i(2, 1))
	assert_that(path[path.size() - 1]).is_equal(Vector2i(10, 1))


func test_route_changes_after_a_wall_is_placed_and_after_it_is_removed() -> void:
	var grid := _floored_grid(Vector2i(12, 8))
	var before := grid.find_path(Vector2i(2, 1), Vector2i(10, 1))
	assert_int(_crossing_row(before, 6)).is_equal(1)
	for y in 7:
		(
			assert_bool(grid.apply(BuildEdit.place_wall(Vector2i(6, y), BuildGrid.Side.WEST)).ok)
			. is_true()
		)
	var walled := grid.find_path(Vector2i(2, 1), Vector2i(10, 1))
	assert_int(walled.size()).is_greater(before.size())
	assert_int(_crossing_row(walled, 6)).is_equal(7)
	for y in 7:
		(
			assert_bool(grid.apply(BuildEdit.remove_wall(Vector2i(6, y), BuildGrid.Side.WEST)).ok)
			. is_true()
		)
	var reopened := grid.find_path(Vector2i(2, 1), Vector2i(10, 1))
	assert_int(reopened.size()).is_equal(before.size())
	assert_int(_crossing_row(reopened, 6)).is_equal(1)


func test_a_full_wall_line_leaves_no_route() -> void:
	var grid := _floored_grid(Vector2i(6, 4))
	for y in 4:
		grid.apply(BuildEdit.place_wall(Vector2i(3, y), BuildGrid.Side.WEST))
	assert_array(grid.find_path(Vector2i(0, 0), Vector2i(5, 0))).is_empty()
	assert_bool(grid.can_step(Vector2i(2, 1), Vector2i(3, 2))).is_false()


func test_diagonal_steps_do_not_cut_wall_corners() -> void:
	var grid := _floored_grid(Vector2i(4, 4))
	assert_bool(grid.can_step(Vector2i(1, 1), Vector2i(2, 2))).is_true()
	grid.apply(BuildEdit.place_wall(Vector2i(1, 1), BuildGrid.Side.EAST))
	assert_bool(grid.can_step(Vector2i(1, 1), Vector2i(2, 2))).is_false()
	assert_bool(grid.can_step(Vector2i(1, 1), Vector2i(1, 2))).is_true()


func test_blocking_object_reroutes_and_removal_restores() -> void:
	var grid := _floored_grid(Vector2i(9, 5))
	var before := grid.find_path(Vector2i(4, 0), Vector2i(4, 4))
	assert_int(before.size()).is_equal(5)
	var seats := grid.apply(BuildEdit.place_object(&"seat_row", Vector2i(3, 2), 0))
	var around := grid.find_path(Vector2i(4, 0), Vector2i(4, 4))
	assert_bool(around.has(Vector2i(4, 2))).is_false()
	assert_int(around.size()).is_greater(before.size())
	grid.apply(BuildEdit.remove_object(seats.object_id))
	assert_int(grid.find_path(Vector2i(4, 0), Vector2i(4, 4)).size()).is_equal(5)


func test_unwalkable_cells_have_no_route() -> void:
	var grid := _floored_grid(Vector2i(5, 5))
	grid.apply(BuildEdit.remove_floor(Vector2i(4, 4)))
	assert_bool(grid.is_walkable(Vector2i(4, 4))).is_false()
	assert_array(grid.find_path(Vector2i(0, 0), Vector2i(4, 4))).is_empty()
	assert_array(grid.find_path(Vector2i(0, 0), Vector2i(9, 9))).is_empty()


## A wall line across the room with one gap, where the scanner stands. The
## scanner can be stepped through along its axis (the passenger it serves walks
## through it), but generic routing never links its cells: the only way across
## is security service. With the scanner gone the gap is an open route again,
## and a seat row in the gap closes it.
func test_scanner_is_walk_through_along_its_axis_only() -> void:
	var grid := _floored_grid(Vector2i(7, 7))
	for x in 7:
		if x != 3:
			grid.apply(BuildEdit.place_wall(Vector2i(x, 4), BuildGrid.Side.NORTH))
	var scanner := grid.apply(BuildEdit.place_object(&"security_scanner", Vector2i(3, 3), 0))
	assert_bool(scanner.ok).is_true()
	assert_bool(grid.is_walkable(Vector2i(3, 3))).is_true()
	assert_bool(grid.is_walkable(Vector2i(3, 4))).is_true()
	assert_array(grid.find_path(Vector2i(3, 0), Vector2i(3, 6))).is_empty()
	assert_bool(grid.can_step(Vector2i(3, 2), Vector2i(3, 3))).is_true()
	assert_bool(grid.can_route(Vector2i(3, 2), Vector2i(3, 3))).is_false()
	assert_bool(grid.can_step(Vector2i(2, 3), Vector2i(3, 3))).is_false()
	assert_bool(grid.can_step(Vector2i(4, 4), Vector2i(3, 4))).is_false()
	assert_bool(grid.can_step(Vector2i(2, 2), Vector2i(3, 3))).is_false()
	grid.apply(BuildEdit.remove_object(scanner.object_id))
	var open := grid.find_path(Vector2i(3, 0), Vector2i(3, 6))
	assert_bool(open.has(Vector2i(3, 3))).is_true()
	assert_bool(open.has(Vector2i(3, 4))).is_true()
	grid.apply(BuildEdit.place_object(&"seat_row", Vector2i(3, 3), 1))
	assert_array(grid.find_path(Vector2i(3, 0), Vector2i(3, 6))).is_empty()


func test_rotated_scanner_passes_along_x() -> void:
	var grid := _floored_grid(Vector2i(6, 6))
	var scanner := grid.apply(BuildEdit.place_object(&"security_scanner", Vector2i(3, 2), 1))
	assert_bool(scanner.ok).is_true()
	assert_bool(grid.can_step(Vector2i(1, 2), Vector2i(2, 2))).is_true()
	assert_bool(grid.can_step(Vector2i(2, 2), Vector2i(3, 2))).is_true()
	assert_bool(grid.can_step(Vector2i(3, 1), Vector2i(3, 2))).is_false()
