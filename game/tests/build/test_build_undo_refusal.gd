class_name TestBuildUndoRefusal
extends GdUnitTestSuite
## A refused undo changes nothing: the grid, the wallet and the history stay
## as they were and the status line says why (decision
## build-mode-undo-design-action-receipts-with-before-values-at, point 2). The
## whole ordered inverse is checked on a copy of the grid with every build rule
## that applies, and the money, before anything reaches the live grid.
##
## The grid is 12x12 and floored except row 5, with the entrance at (0, 11)
## and a desk at (6, 3) whose staff spot (6, 2) lies beyond the bare row.

const DESK := &"checkin_desk"
const DESK_SPOT := Vector2i(6, 2)
const ROW := 5
const WIDTH := 12

var _mode: BuildMode
var _finances: Finances


func before_test() -> void:
	_finances = Finances.new()
	add_child(_finances)
	_mode = BuildMode.new()
	_mode.grid_size = Vector2i(WIDTH, 12)
	_mode.finances = _finances
	add_child(_mode)
	var edits: Array[BuildEdit] = []
	for y in 12:
		for x in WIDTH:
			if y != ROW:
				edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	_mode.grid.apply_batch(edits)
	PassengerTestWorld.place(_mode.grid, DESK, Vector2i(6, 3), 0)
	PassengerTestWorld.place(_mode.grid, &"entrance_door", Vector2i(0, 11), 2)


func after_test() -> void:
	_mode.free()
	_finances.free()


func _at(cell: Vector2i) -> Vector3:
	return _mode.grid.cell_to_world(cell)


func _click(tool: BuildMode.Tool, cell: Vector2i) -> BuildResult:
	_mode.set_tool(tool)
	return _mode.apply_at(_at(cell))


func _expect_unchanged(snapshot: Dictionary, balance: int, steps: int) -> void:
	assert_dict(_mode.grid.to_snapshot()).is_equal(snapshot)
	assert_int(_finances.wallet.balance).is_equal(balance)
	assert_int(_mode.undo_history().size()).is_equal(steps)


## Floor across the bare row lets staff reach the desk's spot. Taking it up
## again would cut the spot off, so the undo is refused; only the row's last
## cell to go cuts it, so an undo that applied the cells one by one and kept
## the ones it could would leave the row half taken up.
func test_an_undo_that_would_cut_off_a_reached_staff_spot_changes_nothing() -> void:
	assert_bool(_mode.grid.staff_reach().has(DESK_SPOT)).is_false()
	_mode.set_tool(BuildMode.Tool.FLOOR)
	_mode.begin_area(_at(Vector2i(0, ROW)))
	_mode.move_area(_at(Vector2i(WIDTH - 1, ROW)))
	assert_int(_mode.finish_area().placed).is_equal(WIDTH)
	assert_bool(_mode.grid.staff_reach().has(DESK_SPOT)).is_true()
	var snapshot := _mode.grid.to_snapshot()
	var balance := _finances.wallet.balance
	var result := _mode.undo()
	print("undo: %s (%d), status '%s'" % [result.reason_text(), result.reason, _mode.status_text()])
	assert_bool(result.ok).is_false()
	assert_int(result.reason).is_equal(BuildResult.Reason.STAFF_SPOT)
	for x in WIDTH:
		assert_int(_mode.grid.floor_at(Vector2i(x, ROW))).is_equal(BuildGrid.FLOOR_TILE)
	_expect_unchanged(snapshot, balance, 1)
	assert_str(_mode.status_text()).contains(result.reason_text())
	assert_str(_mode.status_text()).starts_with(UndoStack.CANT_UNDO)


## Undoing a removal charges its refund back; a wallet that cannot pay it
## refuses the undo and keeps the piece removed.
func test_an_undo_the_wallet_cannot_pay_for_changes_nothing() -> void:
	var desk := _click(BuildMode.Tool.DESK, Vector2i(3, 8)).object_id
	assert_int(desk).is_greater(0)
	assert_bool(_click(BuildMode.Tool.REMOVE, Vector2i(3, 8)).ok).is_true()
	var refund := PriceTable.refund_of(PriceTable.price_of_object(DESK))
	# A restore is not a transaction, so it is not a reason to clear the history.
	assert_bool(_finances.wallet.from_snapshot({"balance": str(refund - 1)})).is_true()
	var snapshot := _mode.grid.to_snapshot()
	var result := _mode.undo()
	print("undo: %s, status '%s'" % [result.reason_text(), _mode.status_text()])
	assert_int(result.reason).is_equal(BuildResult.Reason.CANT_AFFORD)
	assert_dict(_mode.grid.get_object(desk)).is_empty()
	_expect_unchanged(snapshot, refund - 1, 2)
	# With the refund back in the wallet the same undo goes through.
	assert_bool(_finances.wallet.from_snapshot({"balance": str(refund)})).is_true()
	assert_bool(_mode.undo().ok).is_true()
	assert_int(_mode.grid.object_at(Vector2i(3, 8))).is_equal(desk)
	assert_int(_finances.wallet.balance).is_equal(0)


## The entrance and exit rules apply to an undo too: an entrance cannot come
## back where floor now lies behind it. Only an edit from outside BuildMode can
## put the floor there, and that clears the history, so the receipt is undone
## through BuildUndo directly.
func test_an_undo_the_door_rules_refuse_changes_nothing() -> void:
	var cleared := BuildEdit.remove_floor(Vector2i(WIDTH - 1, 8))
	assert_bool(_mode.grid.apply(cleared).ok).is_true()
	var entrance := _click(BuildMode.Tool.ENTRANCE, Vector2i(WIDTH - 2, 8))
	print("entrance: %s" % [entrance.reason_text() if not entrance.ok else "placed"])
	assert_bool(entrance.ok).is_true()
	var door := _mode.grid.object_at(Vector2i(WIDTH - 2, 8))
	assert_bool(_click(BuildMode.Tool.REMOVE, Vector2i(WIDTH - 2, 8)).ok).is_true()
	var receipt := _mode.undo_history().peek()
	assert_object(receipt).is_not_null()
	var behind := BuildEdit.paint_floor(Vector2i(WIDTH - 1, 8), BuildGrid.FLOOR_TILE, 1)
	assert_bool(_mode.grid.apply(behind).ok).is_true()
	assert_int(_mode.undo_history().size()).is_equal(0)
	var snapshot := _mode.grid.to_snapshot()
	var balance := _finances.wallet.balance
	var result := BuildUndo.commit(_mode.grid, receipt, _finances.wallet)
	print("undo: %s (%d)" % [result.reason_text(), result.reason])
	assert_int(result.reason).is_equal(BuildResult.Reason.DOOR_NOT_ON_EDGE)
	assert_dict(_mode.grid.get_object(door)).is_empty()
	_expect_unchanged(snapshot, balance, 0)
