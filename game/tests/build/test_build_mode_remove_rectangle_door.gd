class_name TestBuildModeRemoveRectangleDoor
extends GdUnitTestSuite
## A Remove rectangle over an entrance or exit puts the plain wall back on its
## edge like a click does (decision removing-an-exit-or-entrance-door-puts-the-
## plain-wall-back): no gap in the terminal's enclosure, the refund of the door
## less the price of the wall, the whole rectangle one undo step and, short of
## the money, nothing removed at all.

const NORTH := BuildGrid.Side.NORTH
const EXIT_CELL := Vector2i(4, 2)
const DESK_CELL := Vector2i(4, 5)

var _finances: Finances
var _mode: BuildMode
var _door_id := 0
var _desk_id := 0


## A 12x12 grid with floor on x 2..7, y 2..7, a plain wall round it, an exit
## on the north edge at (4,2) and a check-in desk inside at (4,5).
func before_test() -> void:
	_finances = Finances.new()
	add_child(_finances)
	_mode = BuildMode.new()
	_mode.grid_size = Vector2i(12, 12)
	_mode.finances = _finances
	add_child(_mode)
	_mode.set_tool(BuildMode.Tool.FLOOR)
	for y in range(2, 8):
		for x in range(2, 8):
			_mode.apply_at(_at(Vector2i(x, y)))
	assert_int(EnclosureKit.close_floor(_mode.grid)).is_greater(0)
	_mode.set_tool(BuildMode.Tool.EXIT)
	var door := _mode.apply_at(_at(EXIT_CELL))
	assert_bool(door.ok).is_true()
	_door_id = door.object_id
	_mode.set_tool(BuildMode.Tool.DESK)
	var desk := _mode.apply_at(_at(DESK_CELL))
	assert_bool(desk.ok).is_true()
	_desk_id = desk.object_id
	_mode.set_tool(BuildMode.Tool.REMOVE)


func after_test() -> void:
	_mode.free()
	_finances.free()


func _at(cell: Vector2i) -> Vector3:
	return _mode.grid.cell_to_world(cell)


func _drag(area: Rect2i) -> AreaDrag.Outcome:
	_mode.begin_area(_at(area.position))
	_mode.move_area(_at(area.end - Vector2i.ONE))
	return _mode.finish_area()


func _refund_of(object_id: int) -> int:
	return PriceTable.refund_of(int(_mode.grid.get_object(object_id)["paid"]))


func test_a_rectangle_over_an_exit_puts_the_wall_back_and_leaves_no_gap() -> void:
	# Control: the standing exit has no wall on its edge and the terminal has no gap.
	assert_int(_mode.grid.wall_kind(EXIT_CELL, NORTH)).is_equal(BuildGrid.WallKind.NONE)
	assert_array(EnclosureGaps.gap_edges(_mode.grid)).is_empty()
	var balance := _finances.wallet.balance
	var door_refund := _refund_of(_door_id)
	var wall_price := PriceTable.price_of_wall(BuildGrid.WallKind.PLAIN)
	var outcome := _drag(Rect2i(3, 2, 3, 1))
	print(
		(
			"exit rectangle: placed=%d wall=%d balance %d want %d"
			% [
				outcome.placed,
				_mode.grid.wall_kind(EXIT_CELL, NORTH),
				_finances.wallet.balance,
				balance + door_refund - wall_price
			]
		)
	)
	assert_int(outcome.placed).is_equal(1)
	assert_int(outcome.skipped).is_equal(0)
	assert_array(_mode.grid.object_ids()).is_equal([_desk_id])
	assert_int(_mode.grid.wall_kind(EXIT_CELL, NORTH)).is_equal(BuildGrid.WallKind.PLAIN)
	assert_array(EnclosureGaps.gap_edges(_mode.grid)).is_empty()
	assert_int(_finances.wallet.balance).is_equal(balance + door_refund - wall_price)
	assert_int(outcome.money).is_equal(door_refund - wall_price)
	assert_bool(outcome.charged).is_false()


func test_a_rectangle_over_an_exit_and_a_desk_removes_both_and_settles_the_money() -> void:
	var balance := _finances.wallet.balance
	var refunds := _refund_of(_door_id) + _refund_of(_desk_id)
	var wall_price := PriceTable.price_of_wall(BuildGrid.WallKind.PLAIN)
	var outcome := _drag(Rect2i(3, 2, 4, 5))
	print("exit and desk: placed=%d objects=%d" % [outcome.placed, _mode.grid.object_ids().size()])
	assert_int(outcome.placed).is_equal(2)
	assert_array(_mode.grid.object_ids()).is_empty()
	assert_int(_mode.grid.wall_kind(EXIT_CELL, NORTH)).is_equal(BuildGrid.WallKind.PLAIN)
	assert_array(EnclosureGaps.gap_edges(_mode.grid)).is_empty()
	assert_int(_finances.wallet.balance).is_equal(balance + refunds - wall_price)


func test_one_undo_brings_back_the_exit_and_the_desk_without_the_wall() -> void:
	var balance := _finances.wallet.balance
	var ids := _mode.grid.object_ids()
	_drag(Rect2i(3, 2, 4, 5))
	assert_bool(_mode.undo().ok).is_true()
	print(
		(
			"undone: objects=%d wall=%d balance %d was %d"
			% [
				_mode.grid.object_ids().size(),
				_mode.grid.wall_kind(EXIT_CELL, NORTH),
				_finances.wallet.balance,
				balance
			]
		)
	)
	assert_array(_mode.grid.object_ids()).contains_exactly_in_any_order(ids)
	assert_int(_mode.grid.wall_kind(EXIT_CELL, NORTH)).is_equal(BuildGrid.WallKind.NONE)
	assert_array(EnclosureGaps.gap_edges(_mode.grid)).is_empty()
	assert_int(_finances.wallet.balance).is_equal(balance)


func test_a_rectangle_the_wallet_cannot_pay_the_wall_for_removes_nothing() -> void:
	var wall_price := PriceTable.price_of_wall(BuildGrid.WallKind.PLAIN)
	_finances.wallet.spend(_finances.wallet.balance - (wall_price - 1), Wallet.Category.BUILD)
	var balance := _finances.wallet.balance
	var ids := _mode.grid.object_ids()
	var outcome := _drag(Rect2i(3, 2, 4, 5))
	print(
		(
			"poor: unaffordable=%d balance %d was %d"
			% [outcome.unaffordable_tiles, _finances.wallet.balance, balance]
		)
	)
	assert_int(outcome.unaffordable_tiles).is_greater(0)
	assert_int(outcome.placed).is_equal(0)
	assert_array(_mode.grid.object_ids()).is_equal(ids)
	assert_int(_mode.grid.wall_kind(EXIT_CELL, NORTH)).is_equal(BuildGrid.WallKind.NONE)
	assert_int(_finances.wallet.balance).is_equal(balance)


func test_a_second_drag_takes_the_restored_wall_and_pays_only_its_own_refunds() -> void:
	var area := Rect2i(3, 2, 3, 1)
	_drag(area)
	var restored := _mode.grid.wall_paid(EXIT_CELL, NORTH)
	# Control: the first drag saved the price of the wall it bought on the wall.
	assert_int(restored).is_equal(PriceTable.price_of_wall(BuildGrid.WallKind.PLAIN))
	var balance := _finances.wallet.balance
	var want := 0
	for x in range(3, 6):
		var cell := Vector2i(x, 2)
		want += PriceTable.refund_of(_mode.grid.floor_paid(cell))
		if _mode.grid.wall_kind(cell, NORTH) != BuildGrid.WallKind.NONE:
			want += PriceTable.refund_of(_mode.grid.wall_paid(cell, NORTH))
	var second := _drag(area)
	print(
		(
			"second drag: placed=%d balance %d want %d"
			% [second.placed, _finances.wallet.balance, balance + want]
		)
	)
	assert_int(_mode.grid.wall_kind(EXIT_CELL, NORTH)).is_equal(BuildGrid.WallKind.NONE)
	assert_int(_mode.grid.floor_at(EXIT_CELL)).is_equal(BuildGrid.FLOOR_NONE)
	assert_int(_finances.wallet.balance).is_equal(balance + want)
	assert_bool(second.charged).is_false()


## The wallet holds exactly the room the whole rectangle needs: the door's
## refund less the wall's price. The door's refund alone would not fit, so the
## two edits have to settle together.
func _fill_wallet_to_the_net_of_the_exit() -> int:
	var net := _refund_of(_door_id) - PriceTable.price_of_wall(BuildGrid.WallKind.PLAIN)
	_finances.wallet.balance = Wallet.MAX_BALANCE - net
	return net


func test_a_rectangle_over_an_exit_settles_when_only_the_net_fits_in_the_wallet() -> void:
	var net := _fill_wallet_to_the_net_of_the_exit()
	# Control: the refund alone does not fit, so settling the removal first would fail.
	assert_int(_refund_of(_door_id)).is_greater(net)
	var outcome := _drag(Rect2i(3, 2, 3, 1))
	print(
		(
			"net fits: placed=%d skipped=%d balance %d want %d"
			% [outcome.placed, outcome.skipped, _finances.wallet.balance, Wallet.MAX_BALANCE]
		)
	)
	assert_int(outcome.placed).is_equal(1)
	assert_int(outcome.skipped).is_equal(0)
	assert_array(_mode.grid.object_ids()).is_equal([_desk_id])
	assert_int(_mode.grid.wall_kind(EXIT_CELL, NORTH)).is_equal(BuildGrid.WallKind.PLAIN)
	assert_int(_finances.wallet.balance).is_equal(Wallet.MAX_BALANCE)


func test_a_rectangle_whose_net_does_not_fit_in_the_wallet_counts_only_the_removal() -> void:
	_fill_wallet_to_the_net_of_the_exit()
	# One short of the room the net needs.
	_finances.wallet.balance += 1
	var balance := _finances.wallet.balance
	var outcome := _drag(Rect2i(3, 2, 3, 1))
	print(
		(
			"full: placed=%d skipped=%d reason=%s"
			% [outcome.placed, outcome.skipped, outcome.first_reason]
		)
	)
	assert_int(outcome.placed).is_equal(0)
	assert_int(outcome.skipped).is_equal(1)
	assert_str(outcome.first_reason).is_equal(
		BuildResult.REASON_TEXT[BuildResult.Reason.WALLET_FULL]
	)
	assert_array(_mode.grid.object_ids()).contains_exactly_in_any_order([_desk_id, _door_id])
	assert_int(_mode.grid.wall_kind(EXIT_CELL, NORTH)).is_equal(BuildGrid.WallKind.NONE)
	assert_int(_finances.wallet.balance).is_equal(balance)


func test_a_rectangle_the_wallet_cannot_afford_counts_the_removal_not_its_wall() -> void:
	var wall_price := PriceTable.price_of_wall(BuildGrid.WallKind.PLAIN)
	_finances.wallet.spend(_finances.wallet.balance - (wall_price - 1), Wallet.Category.BUILD)
	var outcome := _drag(Rect2i(3, 2, 3, 1))
	print(
		(
			"poor exit: tiles=%d cost=%d message=%s"
			% [outcome.unaffordable_tiles, outcome.unaffordable_cost, outcome.message()]
		)
	)
	assert_int(outcome.unaffordable_tiles).is_equal(1)
	assert_int(outcome.unaffordable_cost).is_equal(wall_price)
	assert_int(outcome.skipped).is_equal(0)
	assert_str(outcome.message()).is_equal("Not enough money: 1 tiles cost %d" % wall_price)
