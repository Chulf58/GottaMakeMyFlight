class_name TestScreenPlacing
extends GdUnitTestSuite
## Placing a screen stand (Boredom 4/5; decision boredom-screens-are-floor-
## standing-screen-stands-placed-like): the Screen tool places it on one floor
## cell, R turns it, and while it is placed the ghost tints the cells it would
## cover (ScreenCoverage.covered_cells) besides the stand itself. Other objects
## show no coverage.

const CELL := Vector2i(6, 3)

var _mode: BuildMode


## A 14x14 grid floored all over.
func before_test() -> void:
	_mode = BuildMode.new()
	_mode.grid_size = Vector2i(14, 14)
	add_child(_mode)
	_mode.set_tool(BuildMode.Tool.FLOOR)
	for y in 14:
		for x in 14:
			_mode.apply_at(_mode.grid.cell_to_world(Vector2i(x, y)))


func after_test() -> void:
	_mode.free()


func _coverage_tiles() -> int:
	var count := 0
	for child in _mode.get_node("Ghost").get_children():
		if not child.is_queued_for_deletion() and str(child.name).contains("Coverage"):
			count += 1
	return count


func test_the_ghost_tints_the_cells_the_screen_would_cover() -> void:
	_mode.set_tool(BuildMode.Tool.SCREEN)
	var point := _mode.grid.cell_to_world(CELL)
	var edit := _mode.edit_at(point)
	var expected := ScreenCoverage.covered_cells(_mode.grid, CELL, _mode.facing)
	assert_array(_mode.coverage_preview(edit)).is_equal(expected)
	_mode._update_ghost(point)
	print("ghost coverage tiles %d, covered cells %d" % [_coverage_tiles(), expected.size()])
	assert_int(expected.size()).is_greater(10)
	assert_int(_coverage_tiles()).is_equal(expected.size())


func test_a_wall_shrinks_the_preview_and_turning_moves_it() -> void:
	_mode.set_tool(BuildMode.Tool.SCREEN)
	var point := _mode.grid.cell_to_world(CELL)
	var open := _mode.coverage_preview(_mode.edit_at(point)).size()
	var wall := BuildEdit.place_wall(CELL + Vector2i(0, 1), BuildGrid.Side.SOUTH)
	assert_bool(_mode.grid.apply(wall).ok).is_true()
	var walled := _mode.coverage_preview(_mode.edit_at(point))
	assert_int(walled.size()).is_less(open)
	assert_bool(walled.has(CELL + Vector2i(0, 3))).is_false()
	_mode.rotate_facing()
	var turned := _mode.coverage_preview(_mode.edit_at(point))
	assert_bool(turned.has(CELL + Vector2i(-1, 0))).is_true()
	assert_bool(turned.has(CELL + Vector2i(0, 1))).is_false()


func test_placing_it_builds_one_screen_and_other_objects_show_no_coverage() -> void:
	_mode.set_tool(BuildMode.Tool.SCREEN)
	var placed := _mode.apply_at(_mode.grid.cell_to_world(CELL))
	assert_bool(placed.ok).is_true()
	assert_array(ScreenCoverage.screen_ids(_mode.grid)).is_equal([placed.object_id])
	_mode.set_tool(BuildMode.Tool.SEATS)
	var seats := _mode.edit_at(_mode.grid.cell_to_world(Vector2i(2, 9)))
	assert_array(_mode.coverage_preview(seats)).is_empty()
