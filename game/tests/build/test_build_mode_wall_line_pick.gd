class_name TestBuildModeWallLinePick
extends GdUnitTestSuite
## A click exactly on a room's outer wall line picks the edge cell inside it,
## the same for every placeable piece. The cell under a point is floor(), which
## puts a point on the east or south line in the cell outside the room.

const NORTH := BuildGrid.Side.NORTH
const EAST := BuildGrid.Side.EAST
const SOUTH := BuildGrid.Side.SOUTH
const WEST := BuildGrid.Side.WEST
## The edge cell of the x 2..7, y 2..7 room that each outer wall line bounds.
const EDGE_CELLS := {
	NORTH: Vector2i(4, 2),
	EAST: Vector2i(7, 4),
	SOUTH: Vector2i(4, 7),
	WEST: Vector2i(2, 4),
}

var _mode: BuildMode


## A 10x10 grid with floor on x 2..7, y 2..7 and no floor around it.
func before_test() -> void:
	_mode = BuildMode.new()
	_mode.grid_size = Vector2i(10, 10)
	add_child(_mode)
	_mode.set_tool(BuildMode.Tool.FLOOR)
	for y in range(2, 8):
		for x in range(2, 8):
			_mode.apply_at(_mode.grid.cell_to_world(Vector2i(x, y)))


func after_test() -> void:
	_mode.free()


## The point exactly on the wall line that bounds `side` of the edge cell,
## halfway along it.
func _on_line(side: int) -> Vector3:
	var cell: Vector2i = EDGE_CELLS[side]
	var step: Vector2i = BuildGrid.SIDE_STEP[side]
	return _mode.grid.cell_to_world(cell) + Vector3(step.x * 0.5, 0.0, step.y * 0.5)


func _assert_line_picks_the_inside_cell(tool: BuildMode.Tool) -> void:
	_mode.set_tool(tool)
	for side in EDGE_CELLS:
		var edit := _mode.edit_at(_on_line(side))
		var why := "tool %d, outer line %d" % [tool, side]
		assert_object(edit).override_failure_message(why).is_not_null()
		assert_vector(edit.cell).override_failure_message(why).is_equal(EDGE_CELLS[side])
		assert_int(_mode.check(edit).reason).override_failure_message(why).is_equal(
			BuildResult.Reason.NONE
		)


func test_the_entrance_picks_the_inside_cell_on_every_outer_line() -> void:
	_assert_line_picks_the_inside_cell(BuildMode.Tool.ENTRANCE)


func test_the_exit_picks_the_inside_cell_on_every_outer_line() -> void:
	_assert_line_picks_the_inside_cell(BuildMode.Tool.EXIT)


func test_every_object_tool_picks_the_inside_cell_on_the_east_line() -> void:
	var tools := [BuildMode.Tool.ENTRANCE, BuildMode.Tool.EXIT, BuildMode.Tool.DESK]
	for tool in tools:
		_mode.set_tool(tool)
		var edit := _mode.edit_at(_on_line(EAST))
		assert_object(edit).is_not_null()
		assert_vector(edit.cell).is_equal(EDGE_CELLS[EAST])


func test_an_exit_clicked_on_the_east_line_of_a_walled_room_is_placed() -> void:
	_mode.set_tool(BuildMode.Tool.WALL)
	for i in range(2, 8):
		_mode.apply_at(_mode.grid.cell_to_world(Vector2i(7, i)) + Vector3(0.45, 0.0, 0.0))
	_mode.set_tool(BuildMode.Tool.EXIT)
	var result := _mode.apply_at(_on_line(EAST))
	assert_int(result.reason).is_equal(BuildResult.Reason.NONE)
	assert_bool(_mode.grid.object_at(EDGE_CELLS[EAST]) != 0).is_true()


func test_a_point_well_outside_the_room_still_picks_the_cell_it_is_in() -> void:
	_mode.set_tool(BuildMode.Tool.EXIT)
	var outside := _mode.grid.cell_to_world(Vector2i(8, 4)) + Vector3(0.1, 0.0, 0.0)
	var edit := _mode.edit_at(outside)
	assert_vector(edit.cell).is_equal(Vector2i(8, 4))
	assert_int(_mode.check(edit).reason).is_equal(BuildResult.Reason.NO_FLOOR)
