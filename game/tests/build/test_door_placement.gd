class_name TestDoorPlacement
extends GdUnitTestSuite
## DoorPlacement's rules on a bare BuildGrid, with no BuildMode node.

const NORTH := BuildGrid.Side.NORTH
const WEST := BuildGrid.Side.WEST
const PLAIN := BuildGrid.WallKind.PLAIN
const GLASS := BuildGrid.WallKind.GLASS

var _grid: BuildGrid


## A 10x10 grid with floor on x 2..7, y 2..7 and no floor around it.
func before_test() -> void:
	_grid = BuildGrid.new(Vector2i(10, 10))
	for y in range(2, 8):
		for x in range(2, 8):
			_grid.apply(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))


func _near_edge(cell: Vector2i, side: int) -> Vector3:
	var step := BuildGrid.SIDE_STEP[side]
	return _grid.cell_to_world(cell) + Vector3(step.x * 0.45, 0.0, step.y * 0.45)


func test_the_back_step_of_each_facing_is_north_east_south_west() -> void:
	for turn in 4:
		assert_that(DoorPlacement.back_step(turn)).is_equal(BuildGrid.SIDE_STEP[turn])


func test_the_outside_door_problem_for_each_back_edge() -> void:
	var exit := Vector2i(4, 2)
	assert_bool(DoorPlacement.outside_door_problem(_grid, exit, 0).ok).is_true()
	var inward := DoorPlacement.outside_door_problem(_grid, exit, 2)
	assert_int(inward.reason).is_equal(BuildResult.Reason.DOOR_NOT_ON_EDGE)
	_grid.apply(BuildEdit.place_wall(exit, NORTH, PLAIN))
	assert_bool(DoorPlacement.outside_door_problem(_grid, exit, 0).ok).is_true()
	_grid.apply(BuildEdit.place_wall(exit, NORTH, GLASS))
	var glass := DoorPlacement.outside_door_problem(_grid, exit, 0)
	assert_int(glass.reason).is_equal(BuildResult.Reason.DOOR_WALLED)


func test_a_plain_wall_that_holds_a_door_wall_refuses() -> void:
	for x in [3, 4, 5]:
		_grid.apply(BuildEdit.place_wall(Vector2i(x, 2), NORTH, PLAIN))
	_grid.apply(BuildEdit.place_wall(Vector2i(4, 2), NORTH, BuildGrid.WallKind.DOOR))
	var holds := DoorPlacement.outside_door_problem(_grid, Vector2i(5, 2), 0)
	assert_int(holds.reason).is_equal(BuildResult.Reason.WALL_HOLDS_DOOR)


func test_edits_for_takes_down_a_plain_wall_before_the_door() -> void:
	var door := BuildEdit.place_object(&"exit_door", Vector2i(4, 2), 0)
	assert_array(DoorPlacement.edits_for(_grid, door)).is_equal([door])
	_grid.apply(BuildEdit.place_wall(Vector2i(4, 2), NORTH, PLAIN))
	var plan := DoorPlacement.edits_for(_grid, door)
	assert_int(plan.size()).is_equal(2)
	assert_int(plan[0].kind).is_equal(BuildEdit.Kind.REMOVE_WALL)
	assert_that(plan[0].cell).is_equal(Vector2i(4, 2))
	assert_int(plan[0].side).is_equal(NORTH)
	assert_object(plan[1]).is_same(door)
	var desk := BuildEdit.place_object(&"checkin_desk", Vector2i(4, 2), 2)
	assert_array(DoorPlacement.edits_for(_grid, desk)).is_equal([desk])


func test_auto_facing_falls_back_inside_and_follows_the_cursor_in_a_corner() -> void:
	var middle := _grid.cell_to_world(Vector2i(4, 4))
	assert_int(DoorPlacement.auto_facing(_grid, &"entrance_door", middle, 1)).is_equal(1)
	var corner := Vector2i(2, 2)
	var north := DoorPlacement.auto_facing(_grid, &"entrance_door", _near_edge(corner, NORTH), 1)
	assert_int(north).is_equal(0)
	var west := DoorPlacement.auto_facing(_grid, &"entrance_door", _near_edge(corner, WEST), 1)
	assert_int(west).is_equal(3)
	_grid.apply(BuildEdit.place_wall(corner, WEST, GLASS))
	var past_glass := DoorPlacement.auto_facing(
		_grid, &"entrance_door", _near_edge(corner, WEST), 1
	)
	assert_int(past_glass).is_equal(0)


func test_a_standing_door_guards_its_back_edge_and_the_cell_beyond() -> void:
	assert_bool(_grid.apply(BuildEdit.place_object(&"exit_door", Vector2i(4, 2), 0)).ok).is_true()
	assert_int(DoorPlacement.ways_out(_grid).size()).is_equal(1)
	assert_bool(DoorPlacement.on_a_way_out(_grid, Vector2i(4, 2), NORTH)).is_true()
	assert_bool(DoorPlacement.on_a_way_out(_grid, Vector2i(4, 1), BuildGrid.Side.SOUTH)).is_true()
	assert_bool(DoorPlacement.on_a_way_out(_grid, Vector2i(4, 2), WEST)).is_false()
	assert_bool(DoorPlacement.beyond_a_door(_grid, Vector2i(4, 1))).is_true()
	assert_bool(DoorPlacement.beyond_a_door(_grid, Vector2i(5, 1))).is_false()
	var wall := DoorPlacement.check(_grid, BuildEdit.place_wall(Vector2i(4, 2), NORTH, PLAIN))
	assert_int(wall.reason).is_equal(BuildResult.Reason.DOOR_WALLED)
	var floor := DoorPlacement.check(_grid, BuildEdit.paint_floor(Vector2i(4, 1), 1, 1))
	assert_int(floor.reason).is_equal(BuildResult.Reason.DOOR_NOT_ON_EDGE)
