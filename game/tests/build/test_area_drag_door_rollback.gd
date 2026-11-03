class_name TestAreaDragDoorRollback
extends GdUnitTestSuite
## A Remove rectangle over a paid door whose restoring wall the grid refuses:
## the door's refund alone does not fit the wallet, so the rectangle is put
## back whole, nothing is paid, and the refusal it emits waits in the grid's
## hold queue behind the signals an outer caller already queued there.

const ZONE := 1

var _grid: RefusingWallGrid
var _events: Array[String] = []


## A grid that takes a door out but refuses every wall put in.
class RefusingWallGrid:
	extends BuildGrid

	func _commit(edit: BuildEdit) -> BuildResult:
		if edit.kind == BuildEdit.Kind.PLACE_WALL:
			return BuildResult.refused(BuildResult.Reason.OVERLAP)
		return super._commit(edit)


func before_test() -> void:
	_events.clear()
	_grid = RefusingWallGrid.new(Vector2i(20, 20))
	for cell in [Vector2i(5, 5), Vector2i(5, 6), Vector2i(6, 5)]:
		var painted := _grid.apply(BuildEdit.paint_floor(cell, BuildGrid.FLOOR_TILE, ZONE))
		assert_bool(painted.ok).is_true()
	var door: Array[BuildEdit] = [BuildEdit.place_object(&"entrance_door", Vector2i(5, 5), 0)]
	var placed := BuildTransaction.commit_batch(_grid, door, Wallet.new(100_000))
	assert_bool(placed[0].ok).is_true()
	_grid.edit_applied.connect(
		func(_e: BuildEdit, _r: BuildResult) -> void: _events.append("applied")
	)
	_grid.edit_refused.connect(
		func(_e: BuildEdit, _r: BuildResult) -> void: _events.append("refused")
	)


func test_a_refused_wall_puts_the_rectangle_back_and_the_refusal_waits_in_the_hold() -> void:
	var door_id := _grid.object_ids()[0]
	var refund := PriceTable.refund_of(int(_grid.get_object(door_id)["paid"]))
	var wall_price := PriceTable.price_of_wall(BuildGrid.WallKind.PLAIN)
	# Control: the refund alone does not fit, though the net of door and wall does.
	assert_int(refund).is_greater(refund - wall_price)
	var wallet := Wallet.new(Wallet.MAX_BALANCE - (refund - wall_price))
	var balance := wallet.balance
	# An outer caller holds the grid's signals and has queued one already.
	_grid.hold_signals()
	(
		assert_bool(_grid.apply(BuildEdit.paint_floor(Vector2i(6, 5), BuildGrid.FLOOR_TILE, 2)).ok)
		. is_true()
	)
	var outcome := AreaDrag.clear(_grid, Rect2i(5, 5, 1, 1), wallet)
	print(
		(
			"rolled back: placed=%d skipped=%d events held=%s balance %d was %d"
			% [outcome.placed, outcome.skipped, _events, wallet.balance, balance]
		)
	)
	assert_array(_events).is_empty()
	_grid.release_signals()
	assert_array(_events).is_equal(["applied", "refused"])
	assert_array(_grid.object_ids()).is_equal([door_id])
	assert_int(wallet.balance).is_equal(balance)
	assert_int(outcome.placed).is_equal(0)
	assert_int(outcome.skipped).is_equal(1)
	assert_str(outcome.first_reason).is_equal(
		BuildResult.REASON_TEXT[BuildResult.Reason.WALLET_FULL]
	)
	assert_int(outcome.money).is_equal(0)
