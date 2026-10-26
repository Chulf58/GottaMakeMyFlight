class_name TestBuildWallKinds
extends GdUnitTestSuite
## Wall kinds on cell edges: plain, glass and door. A door sits only between
## plain walls in line with it, those walls cannot go while it stands, and
## only a door edge lets a passenger through.

const NORTH := BuildGrid.Side.NORTH
const PLAIN := BuildGrid.WallKind.PLAIN
const GLASS := BuildGrid.WallKind.GLASS
const DOOR := BuildGrid.WallKind.DOOR

var _grid: BuildGrid


## A 5x5 floored grid split by a plain wall along the north edge of row 2.
func before_test() -> void:
	_grid = BuildGrid.new(Vector2i(5, 5))
	for y in 5:
		for x in 5:
			_grid.apply(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	for x in 5:
		_grid.apply(BuildEdit.place_wall(Vector2i(x, 2), NORTH))


func test_walls_are_plain_by_default_and_report_their_kind_from_either_side() -> void:
	assert_int(_grid.wall_kind(Vector2i(2, 2), NORTH)).is_equal(PLAIN)
	assert_int(_grid.wall_kind(Vector2i(2, 1), BuildGrid.Side.SOUTH)).is_equal(PLAIN)
	assert_int(_grid.wall_kind(Vector2i(2, 3), NORTH)).is_equal(BuildGrid.WallKind.NONE)
	assert_int(_grid.wall_kind(Vector2i(9, 9), NORTH)).is_equal(BuildGrid.WallKind.NONE)


func test_glass_and_door_replace_a_wall_and_the_same_kind_again_is_refused() -> void:
	var glass := _grid.apply(BuildEdit.place_wall(Vector2i(0, 2), NORTH, GLASS))
	assert_bool(glass.ok).is_true()
	assert_int(_grid.wall_kind(Vector2i(0, 2), NORTH)).is_equal(GLASS)
	assert_bool(_grid.has_wall(Vector2i(0, 2), NORTH)).is_true()
	var again := _grid.apply(BuildEdit.place_wall(Vector2i(0, 2), NORTH, GLASS))
	assert_int(again.reason).is_equal(BuildResult.Reason.WALL_EXISTS)
	var door := _grid.apply(BuildEdit.place_wall(Vector2i(2, 2), NORTH, DOOR))
	assert_bool(door.ok).is_true()
	assert_int(_grid.wall_kind(Vector2i(2, 2), NORTH)).is_equal(DOOR)
	var back := _grid.apply(BuildEdit.place_wall(Vector2i(0, 2), NORTH, PLAIN))
	assert_bool(back.ok).is_true()
	assert_int(_grid.wall_kind(Vector2i(0, 2), NORTH)).is_equal(PLAIN)


func test_validate_of_a_kind_change_leaves_the_wall_as_it_was() -> void:
	var check := _grid.validate(BuildEdit.place_wall(Vector2i(1, 2), NORTH, GLASS))
	assert_bool(check.ok).is_true()
	assert_int(_grid.wall_kind(Vector2i(1, 2), NORTH)).is_equal(PLAIN)


func test_a_door_needs_a_plain_wall_in_line_on_both_sides() -> void:
	var open := BuildGrid.new(Vector2i(5, 5))
	var alone := open.apply(BuildEdit.place_wall(Vector2i(2, 2), NORTH, DOOR))
	assert_int(alone.reason).is_equal(BuildResult.Reason.DOOR_NEEDS_WALLS)
	_grid.apply(BuildEdit.place_wall(Vector2i(3, 2), NORTH, GLASS))
	var by_glass := _grid.apply(BuildEdit.place_wall(Vector2i(2, 2), NORTH, DOOR))
	assert_int(by_glass.reason).is_equal(BuildResult.Reason.DOOR_NEEDS_WALLS)
	assert_int(_grid.wall_kind(Vector2i(2, 2), NORTH)).is_equal(PLAIN)
	var at_border := _grid.apply(BuildEdit.place_wall(Vector2i(0, 2), NORTH, DOOR))
	assert_int(at_border.reason).is_equal(BuildResult.Reason.DOOR_NEEDS_WALLS)
	# A wall across the line at the door's end is not in line with it.
	_grid.apply(BuildEdit.place_wall(Vector2i(4, 2), BuildGrid.Side.WEST))
	var by_corner := _grid.apply(BuildEdit.place_wall(Vector2i(4, 2), NORTH, DOOR))
	assert_int(by_corner.reason).is_equal(BuildResult.Reason.DOOR_NEEDS_WALLS)


func test_a_door_on_an_empty_edge_between_plain_walls_is_accepted() -> void:
	_grid.apply(BuildEdit.remove_wall(Vector2i(2, 2), NORTH))
	var door := _grid.apply(BuildEdit.place_wall(Vector2i(2, 2), NORTH, DOOR))
	assert_bool(door.ok).is_true()
	assert_int(_grid.wall_kind(Vector2i(2, 2), NORTH)).is_equal(DOOR)


func test_doors_side_by_side_are_refused() -> void:
	assert_bool(_grid.apply(BuildEdit.place_wall(Vector2i(2, 2), NORTH, DOOR)).ok).is_true()
	var second := _grid.apply(BuildEdit.place_wall(Vector2i(3, 2), NORTH, DOOR))
	assert_int(second.reason).is_equal(BuildResult.Reason.DOOR_NEEDS_WALLS)


func test_the_walls_beside_a_door_stay_until_the_door_goes() -> void:
	_grid.apply(BuildEdit.place_wall(Vector2i(2, 2), NORTH, DOOR))
	var remove := _grid.apply(BuildEdit.remove_wall(Vector2i(1, 2), NORTH))
	assert_int(remove.reason).is_equal(BuildResult.Reason.WALL_HOLDS_DOOR)
	var to_glass := _grid.apply(BuildEdit.place_wall(Vector2i(3, 2), NORTH, GLASS))
	assert_int(to_glass.reason).is_equal(BuildResult.Reason.WALL_HOLDS_DOOR)
	assert_int(_grid.wall_kind(Vector2i(1, 2), NORTH)).is_equal(PLAIN)
	assert_int(_grid.wall_kind(Vector2i(3, 2), NORTH)).is_equal(PLAIN)
	assert_bool(_grid.apply(BuildEdit.remove_wall(Vector2i(2, 2), NORTH)).ok).is_true()
	assert_bool(_grid.apply(BuildEdit.remove_wall(Vector2i(1, 2), NORTH)).ok).is_true()


func test_only_a_door_edge_lets_a_route_through_the_wall() -> void:
	var from := Vector2i(2, 4)
	var to := Vector2i(2, 0)
	assert_array(_grid.find_path(from, to)).is_empty()
	_grid.apply(BuildEdit.place_wall(Vector2i(2, 2), NORTH, GLASS))
	assert_array(_grid.find_path(from, to)).is_empty()
	assert_bool(_grid.apply(BuildEdit.place_wall(Vector2i(2, 2), NORTH, DOOR)).ok).is_true()
	var path := _grid.find_path(from, to)
	assert_array(path).contains([Vector2i(2, 2), Vector2i(2, 1)])
	assert_int(path.find(Vector2i(2, 1))).is_equal(path.find(Vector2i(2, 2)) + 1)
	assert_bool(_grid.can_route(Vector2i(2, 2), Vector2i(2, 1))).is_true()
	assert_bool(_grid.apply(BuildEdit.place_wall(Vector2i(2, 2), NORTH, GLASS)).ok).is_true()
	assert_array(_grid.find_path(from, to)).is_empty()


func test_a_diagonal_step_never_slips_through_a_door() -> void:
	_grid.apply(BuildEdit.place_wall(Vector2i(2, 2), NORTH, DOOR))
	assert_bool(_grid.can_step(Vector2i(2, 2), Vector2i(2, 1))).is_true()
	assert_bool(_grid.can_step(Vector2i(2, 2), Vector2i(1, 1))).is_false()
	assert_bool(_grid.can_step(Vector2i(1, 2), Vector2i(2, 1))).is_false()
