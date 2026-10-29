class_name TestWallRowDrag
extends GdUnitTestSuite
## WallRowDrag: the straight row the Wall and Glass tools drag (the cells it
## covers, its axis snap) and what applying or previewing it does.

const NORTH := BuildGrid.Side.NORTH
const WEST := BuildGrid.Side.WEST
const SIZE := Vector2i(12, 12)

var _grid: BuildGrid
var _row: WallRowDrag


func before_test() -> void:
	_grid = BuildGrid.new(SIZE)
	_row = WallRowDrag.new()


func _begin(cell: Vector2i, side := NORTH) -> void:
	_row.begin(cell, side, SIZE)


func _accept_all(_edit: BuildEdit) -> BuildResult:
	return BuildResult.accepted()


func test_a_new_row_is_not_active() -> void:
	assert_bool(_row.active).is_false()
	_begin(Vector2i(2, 2))
	assert_bool(_row.active).is_true()
	_row.cancel()
	assert_bool(_row.active).is_false()


func test_a_row_that_never_left_its_cell_is_one_edge() -> void:
	_begin(Vector2i(3, 4))
	assert_array(_row.cells()).is_equal([Vector2i(3, 4)])
	assert_bool(_row.is_single_cell()).is_true()


func test_dragging_along_x_covers_every_cell_between() -> void:
	_begin(Vector2i(2, 4))
	_row.move(Vector2i(6, 4))
	assert_array(_row.cells()).is_equal(
		[Vector2i(2, 4), Vector2i(3, 4), Vector2i(4, 4), Vector2i(5, 4), Vector2i(6, 4)]
	)


func test_dragging_along_z_covers_every_cell_between() -> void:
	_begin(Vector2i(4, 2), BuildGrid.Side.WEST)
	_row.move(Vector2i(4, 5))
	assert_array(_row.cells()).is_equal(
		[Vector2i(4, 2), Vector2i(4, 3), Vector2i(4, 4), Vector2i(4, 5)]
	)


func test_dragging_backwards_walks_from_the_press_cell() -> void:
	_begin(Vector2i(6, 4))
	_row.move(Vector2i(3, 4))
	assert_array(_row.cells()).is_equal(
		[Vector2i(6, 4), Vector2i(5, 4), Vector2i(4, 4), Vector2i(3, 4)]
	)


func test_a_diagonal_drag_snaps_to_the_longer_axis() -> void:
	_begin(Vector2i(2, 2))
	_row.move(Vector2i(7, 4))
	assert_int(_row.cells().size()).is_equal(6)
	for cell in _row.cells():
		assert_int(cell.y).is_equal(2)
	_row.move(Vector2i(3, 8))
	assert_int(_row.cells().size()).is_equal(7)
	for cell in _row.cells():
		assert_int(cell.x).is_equal(2)


func test_a_tie_between_the_axes_goes_along_x() -> void:
	_begin(Vector2i(2, 2))
	_row.move(Vector2i(5, 5))
	assert_int(_row.cells().size()).is_equal(4)
	assert_int(_row.cells().back().y).is_equal(2)


func test_the_far_end_stays_inside_the_grid() -> void:
	_begin(Vector2i(8, 4))
	_row.move(Vector2i(40, 4))
	assert_that(_row.cells().back()).is_equal(Vector2i(11, 4))


func test_every_edge_keeps_the_side_the_press_chose() -> void:
	_begin(Vector2i(2, 4), WEST)
	_row.move(Vector2i(4, 4))
	var edits := _row.edits(BuildGrid.WallKind.GLASS)
	assert_int(edits.size()).is_equal(3)
	for edit in edits:
		assert_int(edit.kind).is_equal(BuildEdit.Kind.PLACE_WALL)
		assert_int(edit.side).is_equal(WEST)
		assert_int(edit.wall_kind).is_equal(BuildGrid.WallKind.GLASS)


func test_applying_places_every_edge_and_counts_them() -> void:
	_begin(Vector2i(2, 4))
	_row.move(Vector2i(5, 4))
	var dirty: Array[Vector2i] = []
	var outcome := WallRowDrag.apply(
		_grid, _row.edits(BuildGrid.WallKind.PLAIN), _accept_all, null, dirty
	)
	assert_int(outcome.placed).is_equal(4)
	assert_int(outcome.skipped).is_equal(0)
	for x in range(2, 6):
		assert_bool(_grid.has_wall(Vector2i(x, 4), NORTH)).is_true()
	assert_bool(_grid.has_wall(Vector2i(6, 4), NORTH)).is_false()
	assert_bool(dirty.is_empty()).is_false()


func test_a_refused_edge_is_skipped_and_the_rest_placed() -> void:
	_grid.apply(BuildEdit.place_wall(Vector2i(3, 4), NORTH))
	_begin(Vector2i(2, 4))
	_row.move(Vector2i(4, 4))
	var check := func(edit: BuildEdit) -> BuildResult: return _grid.validate(edit)
	var dirty: Array[Vector2i] = []
	var outcome := WallRowDrag.apply(
		_grid, _row.edits(BuildGrid.WallKind.PLAIN), check, null, dirty
	)
	print("outcome: %s" % outcome.message())
	assert_int(outcome.placed).is_equal(2)
	assert_int(outcome.skipped).is_equal(1)
	assert_str(outcome.first_reason).is_not_empty()
	assert_bool(_grid.has_wall(Vector2i(4, 4), NORTH)).is_true()


func test_the_preview_prices_the_row_and_marks_what_would_be_skipped() -> void:
	_grid.apply(BuildEdit.place_wall(Vector2i(3, 4), NORTH))
	_begin(Vector2i(2, 4))
	_row.move(Vector2i(4, 4))
	var check := func(edit: BuildEdit) -> BuildResult: return _grid.validate(edit)
	var preview := WallRowDrag.preview(_grid, _row.edits(BuildGrid.WallKind.PLAIN), check, null)
	assert_array(preview.valid).is_equal([true, false, true])
	assert_int(preview.blocked).is_equal(1)
	assert_str(preview.first_reason).is_not_empty()
	assert_int(preview.cost).is_equal(0)


func test_a_refusal_reaches_listeners_in_row_order_behind_the_edits_before_it() -> void:
	_grid.apply(BuildEdit.place_wall(Vector2i(3, 4), NORTH))
	var events: Array[String] = []
	_grid.edit_applied.connect(
		func(edit: BuildEdit, _result: BuildResult) -> void:
			events.append("applied:%d" % edit.cell.x)
	)
	_grid.edit_refused.connect(
		func(edit: BuildEdit, _result: BuildResult) -> void:
			events.append("refused:%d" % edit.cell.x)
	)
	_begin(Vector2i(2, 4))
	_row.move(Vector2i(4, 4))
	var check := func(edit: BuildEdit) -> BuildResult: return _grid.validate(edit)
	var dirty: Array[Vector2i] = []
	WallRowDrag.apply(_grid, _row.edits(BuildGrid.WallKind.PLAIN), check, null, dirty)
	print("events: %s" % [events])
	assert_array(events).is_equal(["applied:2", "refused:3", "applied:4"])
