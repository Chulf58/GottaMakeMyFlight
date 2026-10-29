class_name TestBuildUndo
extends GdUnitTestSuite
## Ctrl+Z in build mode reverses the last build action and settles its money
## (decision build-mode-undo-design-action-receipts-with-before-values-at): a
## floor drag, a wall, an object, a room with its pieces, a belt line and a
## removal each come back as they were, a removed piece with its id and saved
## price, and the money moves back in full. Refusals are in
## test_build_undo_refusal.gd, the history's limits in test_build_undo_history.gd.
##
## The grid is 14x14 with floor on columns 0 to 9; columns 10 to 13 are bare.

const NORTH := BuildGrid.Side.NORTH
const DESK := &"checkin_desk"

var _mode: BuildMode
var _finances: Finances


func before_test() -> void:
	_finances = Finances.new()
	add_child(_finances)
	_mode = BuildMode.new()
	_mode.grid_size = Vector2i(14, 14)
	_mode.finances = _finances
	add_child(_mode)
	var edits: Array[BuildEdit] = []
	for y in 14:
		for x in 10:
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	_mode.grid.apply_batch(edits)


func after_test() -> void:
	_mode.free()
	_finances.free()


func _balance() -> int:
	return _finances.wallet.balance


func _at(cell: Vector2i) -> Vector3:
	return _mode.grid.cell_to_world(cell)


func _near_edge(cell: Vector2i, side: int) -> Vector3:
	var step := BuildGrid.SIDE_STEP[side]
	return _at(cell) + Vector3(step.x * 0.45, 0.0, step.y * 0.45)


func _click(tool: BuildMode.Tool, cell: Vector2i) -> BuildResult:
	_mode.set_tool(tool)
	return _mode.apply_at(_at(cell))


func _drag(tool: BuildMode.Tool, area: Rect2i) -> AreaDrag.Outcome:
	_mode.set_tool(tool)
	_mode.begin_area(_at(area.position))
	_mode.move_area(_at(area.end - Vector2i.ONE))
	return _mode.finish_area()


## The grid's snapshot less its next ids: an undone placement used an id up.
func _layout() -> Dictionary:
	var snapshot := _mode.grid.to_snapshot()
	snapshot.erase("next_object_id")
	snapshot.erase("next_room_id")
	return snapshot


func _undo_ok() -> void:
	var result := _mode.undo()
	assert_object(result).is_not_null()
	print("undo: ok %s, status '%s'" % [result.ok, _mode.status_text()])
	assert_bool(result.ok).is_true()


func test_undo_of_a_floor_drag_takes_the_tiles_up_and_refunds_the_full_price() -> void:
	var start := _balance()
	var outcome := _drag(BuildMode.Tool.FLOOR, Rect2i(10, 1, 3, 2))
	assert_int(outcome.placed).is_equal(6)
	print("floor drag spent %d" % (start - _balance()))
	assert_int(start - _balance()).is_equal(6 * PriceTable.FLOOR_PRICE)
	assert_int(_mode.undo_history().size()).is_equal(1)
	_undo_ok()
	for y in range(1, 3):
		for x in range(10, 13):
			assert_int(_mode.grid.floor_at(Vector2i(x, y))).is_equal(BuildGrid.FLOOR_NONE)
	assert_int(_balance()).is_equal(start)
	assert_int(_mode.undo_history().size()).is_equal(0)


func test_undo_of_a_wall_takes_it_down_and_refunds_it() -> void:
	var start := _balance()
	_mode.set_tool(BuildMode.Tool.WALL)
	assert_bool(_mode.apply_at(_near_edge(Vector2i(3, 3), NORTH)).ok).is_true()
	assert_bool(_mode.grid.has_wall(Vector2i(3, 3), NORTH)).is_true()
	assert_int(_balance()).is_less(start)
	_undo_ok()
	assert_bool(_mode.grid.has_wall(Vector2i(3, 3), NORTH)).is_false()
	assert_int(_mode.grid.wall_paid(Vector2i(3, 3), NORTH)).is_equal(0)
	assert_int(_balance()).is_equal(start)


func test_undo_of_an_object_removes_it_and_an_empty_history_does_nothing() -> void:
	var start := _balance()
	var placed := _click(BuildMode.Tool.DESK, Vector2i(4, 4))
	assert_bool(placed.ok).is_true()
	assert_int(start - _balance()).is_equal(PriceTable.price_of_object(DESK))
	_undo_ok()
	assert_dict(_mode.grid.get_object(placed.object_id)).is_empty()
	assert_int(_mode.grid.object_at(Vector2i(4, 4))).is_equal(0)
	assert_int(_balance()).is_equal(start)
	var snapshot := _mode.grid.to_snapshot()
	assert_object(_mode.undo()).is_null()
	print("empty history status '%s'" % _mode.status_text())
	assert_str(_mode.status_text()).is_equal(UndoStack.NOTHING_TO_UNDO)
	assert_dict(_mode.grid.to_snapshot()).is_equal(snapshot)
	assert_int(_balance()).is_equal(start)


## Build A, remove A, undo, undo: the removal comes back first, as the same
## object with the same saved price, its refund charged back; then the build.
func test_build_remove_undo_undo_restores_identity_then_takes_the_build_back() -> void:
	var start := _balance()
	var desk := _click(BuildMode.Tool.DESK, Vector2i(4, 4)).object_id
	var record := _mode.grid.get_object(desk)
	var after_build := _balance()
	assert_bool(_click(BuildMode.Tool.REMOVE, Vector2i(4, 4)).ok).is_true()
	var refund := _balance() - after_build
	print("price %d refund %d" % [start - after_build, refund])
	assert_int(refund).is_greater(0)
	assert_dict(_mode.grid.get_object(desk)).is_empty()
	_undo_ok()
	assert_dict(_mode.grid.get_object(desk)).is_equal(record)
	assert_int(_mode.grid.object_at(Vector2i(4, 4))).is_equal(desk)
	assert_int(_balance()).is_equal(after_build)
	_undo_ok()
	assert_dict(_mode.grid.get_object(desk)).is_empty()
	assert_int(_balance()).is_equal(start)
	assert_int(_mode.undo_history().size()).is_equal(0)


## A refund that owed wages took before it reached the balance is still
## charged back whole: the undo takes the gross refund from the balance.
func test_undo_of_a_remove_charges_back_a_refund_that_went_to_owed_wages() -> void:
	var desk := _click(BuildMode.Tool.DESK, Vector2i(4, 4)).object_id
	var paid := int(_mode.grid.get_object(desk)["paid"])
	var owed := [100000]
	_finances.wallet.credit_claim = func(amount: int, commit: bool) -> Dictionary:
		var share := mini(amount, owed[0])
		if commit:
			owed[0] -= share
		return {Wallet.Category.WAGES: share}
	var before := _balance()
	assert_bool(_click(BuildMode.Tool.REMOVE, Vector2i(4, 4)).ok).is_true()
	var refund := PriceTable.refund_of(paid)
	print("refund %d, owed left %d, balance %d -> %d" % [refund, owed[0], before, _balance()])
	assert_int(_balance()).is_equal(before)
	assert_int(owed[0]).is_equal(100000 - refund)
	_undo_ok()
	assert_int(_balance()).is_equal(before - refund)
	assert_int(int(_mode.grid.get_object(desk)["paid"])).is_equal(paid)
	assert_int(owed[0]).is_equal(100000 - refund)


## Near the balance cap, the credit an undo of a build makes still fits when a
## debt takes it first: the wallet is asked the way a credit counts the claim.
## Without the debt the same undo is refused WALLET_FULL and changes nothing.
func _undo_near_the_cap_with_a_debt(debt_category: Wallet.Category) -> void:
	var desk := _click(BuildMode.Tool.DESK, Vector2i(4, 4)).object_id
	var price := PriceTable.price_of_object(DESK)
	var near_cap := str(Wallet.MAX_BALANCE - 5)
	assert_bool(_finances.wallet.from_snapshot({"balance": near_cap})).is_true()
	var refused := _mode.undo()
	print("no debt: %s" % refused.reason_text())
	assert_int(refused.reason).is_equal(BuildResult.Reason.WALLET_FULL)
	assert_int(_mode.grid.object_at(Vector2i(4, 4))).is_equal(desk)
	assert_int(_mode.undo_history().size()).is_equal(1)
	var owed := [price]
	_finances.wallet.credit_claim = func(amount: int, commit: bool) -> Dictionary:
		var share := mini(amount, owed[0])
		if commit:
			owed[0] -= share
		return {debt_category: share}
	_undo_ok()
	assert_int(_mode.grid.object_at(Vector2i(4, 4))).is_equal(0)
	assert_int(owed[0]).is_equal(0)
	assert_int(_balance()).is_equal(Wallet.MAX_BALANCE - 5)


func test_an_undo_near_the_cap_fits_when_owed_wages_take_the_refund() -> void:
	_undo_near_the_cap_with_a_debt(Wallet.Category.WAGES)


func test_an_undo_near_the_cap_fits_when_owed_upkeep_takes_the_refund() -> void:
	_undo_near_the_cap_with_a_debt(Wallet.Category.UPKEEP)


func test_undo_of_a_remove_drag_brings_a_room_and_its_pieces_back() -> void:
	_drag(BuildMode.Tool.CAFE_ROOM, Rect2i(2, 2, 6, 5))
	var room := _mode.grid.room_at(Vector2i(2, 2))
	assert_int(room).is_greater(0)
	var counter := _click(BuildMode.Tool.COUNTER, Vector2i(3, 3)).object_id
	var table := _click(BuildMode.Tool.TABLE, Vector2i(6, 5)).object_id
	assert_int(counter).is_greater(0)
	assert_int(table).is_greater(0)
	var built := _mode.grid.to_snapshot()
	var before := _balance()
	var outcome := _drag(BuildMode.Tool.REMOVE, Rect2i(2, 2, 6, 5))
	print("remove drag: %s" % outcome.message())
	assert_int(_mode.grid.room_ids().size()).is_equal(0)
	assert_int(_mode.grid.object_ids().size()).is_equal(0)
	_undo_ok()
	assert_dict(_mode.grid.to_snapshot()).is_equal(built)
	assert_int(_mode.grid.room_at(Vector2i(2, 2))).is_equal(room)
	assert_int(_balance()).is_equal(before)
	# Then the table, the counter and the room go back in turn.
	for i in 3:
		_undo_ok()
	assert_int(_mode.grid.room_ids().size()).is_equal(0)
	assert_int(_mode.grid.object_ids().size()).is_equal(0)


## A belt line laid next to a belt reshapes it; the undo takes the new cell up
## and gives the old belt back its shape.
func test_undo_of_a_belt_line_takes_it_up_and_restores_the_neighbours_shape() -> void:
	_mode.set_tool(BuildMode.Tool.BELT)
	assert_bool(_mode.lay_belt(Vector2i(2, 6), Vector2i(8, 6)).ok).is_true()
	var line := _layout()
	var before := _balance()
	var middle := _mode.grid.get_object(_mode.grid.object_at(Vector2i(5, 6)))
	assert_bool(_mode.lay_belt(Vector2i(5, 5), Vector2i(5, 5)).ok).is_true()
	var reshaped := _mode.grid.get_object(_mode.grid.object_at(Vector2i(5, 6)))
	print("(5, 6): %s -> %s" % [middle["def"], reshaped["def"]])
	assert_str(str(reshaped["def"])).is_not_equal(str(middle["def"]))
	_undo_ok()
	assert_int(_mode.grid.object_at(Vector2i(5, 5))).is_equal(0)
	assert_dict(_layout()).is_equal(line)
	assert_int(_balance()).is_equal(before)
