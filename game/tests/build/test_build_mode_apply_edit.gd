class_name TestBuildModeApplyEdit
extends GdUnitTestSuite
## BuildMode.apply_edit() applies one prepared edit exactly as a click does: the
## same check, payment and one undo step (decision build-mode-undo-design-
## action-receipts-with-before-values-at). The edit here is built by hand, with
## no ground point, as the inspect window's Delete will build it.

const DESK := &"checkin_desk"
const CELL := Vector2i(3, 3)

var _mode: BuildMode
var _finances: Finances


func before_test() -> void:
	_finances = Finances.new()
	add_child(_finances)
	_mode = BuildMode.new()
	_mode.grid_size = Vector2i(10, 10)
	_mode.finances = _finances
	add_child(_mode)
	var edits: Array[BuildEdit] = []
	for y in 10:
		for x in 10:
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	_mode.grid.apply_batch(edits)


func after_test() -> void:
	_mode.free()
	_finances.free()


func test_apply_edit_places_charges_and_undoes_like_a_click() -> void:
	# The reference: a click on the same cell with the same piece.
	var before := _finances.wallet.balance
	_mode.set_tool(BuildMode.Tool.DESK)
	var clicked := _mode.apply_at(_mode.grid.cell_to_world(Vector2i(6, 6)))
	assert_bool(clicked.ok).is_true()
	var click_cost := before - _finances.wallet.balance
	assert_int(click_cost).is_greater(0)
	_mode.undo()
	assert_int(_finances.wallet.balance).is_equal(before)

	var result := _mode.apply_edit(BuildEdit.place_object(DESK, CELL, 0))
	print(
		(
			"apply_edit: ok=%s cost=%d click cost=%d"
			% [result.ok, before - _finances.wallet.balance, click_cost]
		)
	)
	assert_bool(result.ok).is_true()
	assert_int(before - _finances.wallet.balance).is_equal(click_cost)
	assert_int(_mode.grid.object_at(CELL)).is_equal(result.object_id)
	assert_int(_mode.grid.object_at(CELL)).is_not_equal(0)

	assert_bool(_mode.undo().ok).is_true()
	assert_int(_mode.grid.object_at(CELL)).is_equal(0)
	assert_int(_finances.wallet.balance).is_equal(before)
