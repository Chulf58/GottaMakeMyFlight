class_name TestScreenCoverage
extends GdUnitTestSuite
## Screen coverage (Boredom 4/5; decisions boredom-screens-are-floor-standing-
## screen-stands-placed-like and boredom-and-shops-design-boredom-need-while-
## waiting-kiosk-sh, point 3): a screen stand covers a fan in front of the way
## it faces, RANGE rows deep, with floor under it; a plain wall blocks the
## picture, glass and door walls do not, and a corner blocks only when both
## ways round it are walled. ScreenCoverage follows the grid's edits.

const SIZE := Vector2i(20, 20)
const SCREEN := Vector2i(10, 10)
const S := BuildGrid.Side

var _grid: BuildGrid


func before_test() -> void:
	_grid = PassengerTestWorld.floored(SIZE)


func _covered(facing := 0) -> Array[Vector2i]:
	return ScreenCoverage.covered_cells(_grid, SCREEN, facing)


func _wall(cell: Vector2i, side: int, kind := BuildGrid.WallKind.PLAIN) -> void:
	assert_bool(_grid.apply(BuildEdit.place_wall(cell, side, kind)).ok).is_true()


func test_the_screen_is_a_one_cell_stand_with_a_price_and_daily_upkeep() -> void:
	var def := BuildCatalog.get_def(ScreenCoverage.SCREEN_ID)
	assert_object(def).is_not_null()
	assert_vector(Vector2(def.size)).is_equal(Vector2.ONE)
	assert_bool(def.walk_through).is_false()
	assert_int(PriceTable.price_of_object(ScreenCoverage.SCREEN_ID)).is_greater(0)
	assert_int(PriceTable.SCREEN_UPKEEP).is_greater(0)
	# It earns nothing, so it costs less to run than a toilet stall.
	assert_int(PriceTable.SCREEN_UPKEEP).is_less_equal(PriceTable.TOILET_STALL_UPKEEP)


func test_it_covers_a_fan_in_front_of_the_way_it_faces() -> void:
	var cells := _covered(0)
	print("facing 0 covers %d cells: %s" % [cells.size(), cells])
	assert_int(cells.size()).is_equal(3 + 5 * (ScreenCoverage.RANGE - 1))
	for cell in [Vector2i(10, 11), Vector2i(9, 11), Vector2i(11, 11), Vector2i(12, 12)]:
		assert_bool(cells.has(cell)).override_failure_message(str(cell)).is_true()
	# Not its own cell, nothing behind or beside it, and the first row is narrow.
	for cell in [SCREEN, Vector2i(10, 9), Vector2i(11, 10), Vector2i(12, 11), Vector2i(13, 13)]:
		assert_bool(cells.has(cell)).override_failure_message(str(cell)).is_false()
	# Turned a quarter, the fan points west (front (0, 1) turns to (-1, 0)).
	var west := _covered(1)
	assert_bool(west.has(Vector2i(9, 10))).is_true()
	assert_bool(west.has(Vector2i(5, 12))).is_true()
	assert_bool(west.has(Vector2i(10, 11))).is_false()
	assert_bool(west.has(Vector2i(11, 10))).is_false()


func test_it_reaches_range_rows_and_no_further() -> void:
	var cells := _covered(0)
	var last := SCREEN + Vector2i(0, ScreenCoverage.RANGE)
	assert_bool(cells.has(last)).is_true()
	assert_bool(cells.has(last + Vector2i(0, 1))).is_false()
	assert_bool(cells.has(last + Vector2i(ScreenCoverage.MAX_HALF_WIDTH, 0))).is_true()


func test_a_plain_wall_blocks_the_picture_behind_it() -> void:
	_wall(Vector2i(10, 12), S.SOUTH)
	var cells := _covered(0)
	print("behind a plain wall at (10,12) south: %s" % [cells])
	assert_bool(cells.has(Vector2i(10, 12))).is_true()
	for y in range(13, 16):
		assert_bool(cells.has(Vector2i(10, y))).override_failure_message(str(y)).is_false()
	# A line that does not cross that edge still sees.
	assert_bool(cells.has(Vector2i(12, 13))).is_true()


func test_glass_and_door_walls_let_the_picture_through() -> void:
	_wall(Vector2i(10, 12), S.SOUTH, BuildGrid.WallKind.GLASS)
	assert_bool(_covered(0).has(Vector2i(10, 14))).is_true()
	assert_bool(ScreenCoverage.blocks_sight(BuildGrid.WallKind.GLASS)).is_false()
	assert_bool(ScreenCoverage.blocks_sight(BuildGrid.WallKind.DOOR)).is_false()
	assert_bool(ScreenCoverage.blocks_sight(BuildGrid.WallKind.PLAIN)).is_true()
	assert_bool(ScreenCoverage.blocks_sight(BuildGrid.WallKind.NONE)).is_false()


func test_a_corner_blocks_only_when_both_ways_round_are_walled() -> void:
	var diagonal := SCREEN + Vector2i(2, 2)
	_wall(SCREEN, S.EAST)
	assert_bool(_covered(0).has(diagonal)).is_true()
	_wall(SCREEN, S.SOUTH)
	assert_bool(_covered(0).has(diagonal)).is_false()


func test_a_cell_with_no_floor_is_not_covered() -> void:
	var bare := Vector2i(10, 13)
	assert_bool(_grid.apply(BuildEdit.remove_floor(bare)).ok).is_true()
	var cells := _covered(0)
	assert_bool(cells.has(bare)).is_false()
	assert_bool(cells.has(Vector2i(10, 14))).is_true()


func test_objects_do_not_block_the_picture() -> void:
	PassengerTestWorld.place(_grid, &"seat_row", Vector2i(9, 12), 0)
	assert_bool(_covered(0).has(Vector2i(10, 14))).is_true()


func test_coverage_follows_the_grid_and_two_screens_cover_their_union() -> void:
	var coverage := ScreenCoverage.new()
	coverage.bind(_grid)
	assert_int(coverage.cells().size()).is_equal(0)
	PassengerTestWorld.place(_grid, ScreenCoverage.SCREEN_ID, SCREEN, 0)
	assert_bool(coverage.covers(Vector2i(10, 14))).is_true()
	var one := coverage.cells().size()
	PassengerTestWorld.place(_grid, ScreenCoverage.SCREEN_ID, SCREEN + Vector2i(2, 0), 0)
	var both := coverage.cells().size()
	print("one screen %d cells, two overlapping %d" % [one, both])
	assert_int(both).is_greater(one)
	assert_int(both).is_less(2 * one)
	# A wall built later blocks the picture at once: right in front of the first
	# screen, a cell only it covers goes dark.
	assert_bool(coverage.covers(Vector2i(10, 11))).is_true()
	_wall(SCREEN, S.SOUTH)
	assert_bool(coverage.covers(Vector2i(10, 11))).is_false()
	assert_int(ScreenCoverage.screen_ids(_grid).size()).is_equal(2)
	assert_int(ScreenCoverage.daily_upkeep(_grid)).is_equal(2 * PriceTable.SCREEN_UPKEEP)
