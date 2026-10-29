class_name TestBuildMode
extends GdUnitTestSuite

var _mode: BuildMode


func before_test() -> void:
	_mode = BuildMode.new()
	_mode.grid_size = Vector2i(10, 10)
	add_child(_mode)


func after_test() -> void:
	_mode.free()


func _view() -> BuildView:
	return _mode.get_node("BuildView") as BuildView


func _paint_room() -> void:
	_mode.set_tool(BuildMode.Tool.FLOOR)
	for y in 10:
		for x in 10:
			_mode.apply_at(_mode.grid.cell_to_world(Vector2i(x, y)))


func test_ground_point_meets_the_floor_plane() -> void:
	var hit: Variant = BuildMode.ground_point(Vector3(2, 10, 3), Vector3(0, -1, 0))
	assert_that(hit).is_equal(Vector3(2, 0, 3))
	assert_that(BuildMode.ground_point(Vector3(0, 10, 0), Vector3(0, 1, 0))).is_null()


func test_floor_tool_paints_the_cell_under_the_point() -> void:
	_mode.set_tool(BuildMode.Tool.FLOOR)
	var result := _mode.apply_at(_mode.grid.cell_to_world(Vector2i(4, 6)) + Vector3(0.3, 0, -0.2))
	assert_bool(result.ok).is_true()
	assert_int(_mode.grid.floor_at(Vector2i(4, 6))).is_equal(BuildGrid.FLOOR_TILE)
	assert_int(_mode.grid.zone_at(Vector2i(4, 6))).is_equal(BuildMode.TERMINAL_ZONE)


func test_wall_tool_uses_the_nearest_edge() -> void:
	_mode.set_tool(BuildMode.Tool.WALL)
	var near_east := _mode.grid.cell_to_world(Vector2i(2, 2)) + Vector3(0.45, 0, 0.05)
	assert_bool(_mode.apply_at(near_east).ok).is_true()
	assert_bool(_mode.grid.has_wall(Vector2i(2, 2), BuildGrid.Side.EAST)).is_true()


func test_object_tool_places_rotates_and_draws_then_remove_clears() -> void:
	_paint_room()
	_mode.set_tool(BuildMode.Tool.DESK)
	_mode.rotate_facing()
	var at := _mode.grid.cell_to_world(Vector2i(5, 5))
	var placed := _mode.apply_at(at)
	assert_bool(placed.ok).is_true()
	assert_int(_mode.grid.get_object(placed.object_id)["facing"]).is_equal(1)
	assert_int(_view().object_node_count()).is_equal(1)
	var refused := _mode.apply_at(at)
	assert_int(refused.reason).is_equal(BuildResult.Reason.OVERLAP)
	assert_int(_view().object_node_count()).is_equal(1)
	_mode.set_tool(BuildMode.Tool.REMOVE)
	var removed := _mode.apply_at(at)
	assert_bool(removed.ok).is_true()
	assert_int(removed.object_id).is_equal(placed.object_id)
	assert_int(_view().object_node_count()).is_equal(0)


func test_remove_tool_takes_a_wall_near_the_edge_and_floor_in_the_middle() -> void:
	_paint_room()
	_mode.grid.apply(BuildEdit.place_wall(Vector2i(3, 3), BuildGrid.Side.NORTH))
	_mode.set_tool(BuildMode.Tool.REMOVE)
	var centre := _mode.grid.cell_to_world(Vector2i(3, 3))
	assert_int(_mode.edit_at(centre + Vector3(0, 0, -0.4)).kind).is_equal(
		BuildEdit.Kind.REMOVE_WALL
	)
	# The wall band is 0.4 m wide (WALL_PICK_DISTANCE): 0.05 m off the middle is floor.
	assert_int(_mode.edit_at(centre + Vector3(0, 0, -0.05)).kind).is_equal(
		BuildEdit.Kind.REMOVE_FLOOR
	)


func test_no_tool_makes_no_edit() -> void:
	_mode.set_tool(BuildMode.Tool.NONE)
	assert_object(_mode.edit_at(Vector3.ZERO)).is_null()
	assert_object(_mode.apply_at(Vector3.ZERO)).is_null()
