class_name TestRepairPlanUndo
extends GdUnitTestSuite
## RepairPlan takes back each tried choice's edits on its working copy, and
## counts any it cannot (undo_failures, with an error naming the edit and why).
## The two backtrack tests of test_rescue_grant_backtrack used to push "could
## not undo a tried repair edit": a choice's walk and its piece both painted one
## cell, each build recorded a remove_floor, and the second remove found the
## cell bare. A paint that changes nothing records no way back.

const CELL := Vector2i(2, 2)


static func _paint(cell: Vector2i) -> BuildEdit:
	return BuildEdit.paint_floor(cell, BuildGrid.FLOOR_TILE, BuildMode.TERMINAL_ZONE)


func _plan_on(grid: BuildGrid) -> RepairPlan:
	var plan := RepairPlan.new()
	plan._grid = grid
	return plan


## A walk and a piece that both floor one cell are built, then taken back.
func test_a_cell_painted_twice_in_one_choice_is_taken_back_cleanly() -> void:
	var grid := BuildGrid.new(Vector2i(6, 6))
	var plan := _plan_on(grid)
	var done: Array[BuildEdit] = []
	var undo: Array[BuildEdit] = []
	assert_bool(plan._build(_paint(CELL), done, undo)).is_true()
	assert_bool(plan._build(_paint(CELL), done, undo)).is_true()
	assert_int(grid.floor_at(CELL)).is_not_equal(BuildGrid.FLOOR_NONE)
	plan._undo(undo)
	prints("undo failures", plan.undo_failures, "floor", grid.floor_at(CELL))
	assert_int(plan.undo_failures).is_equal(0)
	assert_int(grid.floor_at(CELL)).is_equal(BuildGrid.FLOOR_NONE)


## A paint over a floor that already stands must not take that floor up when
## the choice is backed out.
func test_backing_out_leaves_a_floor_that_was_already_there() -> void:
	var grid := BuildGrid.new(Vector2i(6, 6))
	assert_bool(grid.apply(_paint(CELL)).ok).is_true()
	var plan := _plan_on(grid)
	var done: Array[BuildEdit] = []
	var undo: Array[BuildEdit] = []
	assert_bool(plan._build(_paint(CELL), done, undo)).is_true()
	plan._undo(undo)
	prints("undo failures", plan.undo_failures, "floor", grid.floor_at(CELL))
	assert_int(plan.undo_failures).is_equal(0)
	assert_int(grid.floor_at(CELL)).is_equal(BuildGrid.FLOOR_TILE)


## An edit that cannot be taken back is counted, not lost.
func test_an_edit_that_cannot_be_taken_back_is_counted() -> void:
	var grid := BuildGrid.new(Vector2i(6, 6))
	var plan := _plan_on(grid)
	var undo: Array[BuildEdit] = [BuildEdit.remove_floor(CELL)]
	plan._undo(undo)
	assert_int(plan.undo_failures).is_equal(1)
	assert_array(undo).is_empty()
