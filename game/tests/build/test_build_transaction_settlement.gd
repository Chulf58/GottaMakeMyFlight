class_name TestBuildTransactionSettlement
extends GdUnitTestSuite
## BuildTransaction settles the wallet exactly before BuildGrid publishes its
## signals, and checks wallet capacity against the exact final settlement
## (board item build-transaction-staging-residual-findings-from-sol-s-re-ch).

const SOUTH := BuildGrid.Side.SOUTH

var _events: Array[String] = []


## An 8x8 grid with floor on x 1..6, y 1..6, laid with nothing paid.
func _floored_grid() -> BuildGrid:
	var grid := BuildGrid.new(Vector2i(8, 8))
	for y in range(1, 7):
		for x in range(1, 7):
			grid.apply(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	return grid


func _plan(edit: BuildEdit) -> Array[BuildEdit]:
	var plan: Array[BuildEdit] = [edit]
	return plan


## Records each grid signal by name, in the order it arrives.
func _record_events(grid: BuildGrid) -> void:
	_events.clear()
	grid.edit_applied.connect(
		func(_e: BuildEdit, _r: BuildResult) -> void: _events.append("applied")
	)
	grid.edit_refused.connect(
		func(_e: BuildEdit, _r: BuildResult) -> void: _events.append("refused")
	)
	grid.graph_changed.connect(func(_c: Array[Vector2i]) -> void: _events.append("graph"))


## A paid wall on the south edge of (3, 6), laid for 40 (refund 20).
func _grid_with_paid_wall() -> BuildGrid:
	var grid := _floored_grid()
	var wall := BuildEdit.place_wall(Vector2i(3, 6), SOUTH)
	BuildTransaction.commit_plan(grid, _plan(wall), Wallet.new(40))
	return grid


func _entrance_plan(grid: BuildGrid) -> Array[BuildEdit]:
	return DoorPlacement.edits_for(
		grid, BuildEdit.place_object(&"entrance_door", Vector2i(3, 6), 2)
	)


## Finding 1: a grid listener that fills the wallet must find the refund
## already paid, so it can no longer make the refund fail.
func test_a_plan_refund_is_paid_before_the_grid_signals() -> void:
	var grid := _floored_grid()
	var wallet := Wallet.new(1000)
	var laid := BuildEdit.paint_floor(Vector2i(0, 0), BuildGrid.FLOOR_TILE, 1)
	BuildTransaction.commit_plan(grid, _plan(laid), wallet)
	var before := wallet.balance
	var seen: Array[int] = []
	grid.edit_applied.connect(
		func(_edit: BuildEdit, _result: BuildResult) -> void:
			seen.append(wallet.balance)
			wallet.credit(Wallet.MAX_BALANCE - wallet.balance, Wallet.Category.FEES)
	)
	var removal := _plan(BuildEdit.remove_floor(Vector2i(0, 0)))
	var result := BuildTransaction.commit_plan(grid, removal, wallet)
	var refund := PriceTable.refund_of(PriceTable.FLOOR_PRICE)
	print("balance seen %s, expected %d" % [seen, before + refund])
	assert_bool(result.ok).is_true()
	assert_array(seen).is_equal([before + refund])
	assert_int(wallet.balance).is_equal(Wallet.MAX_BALANCE)


## Finding 1 for a batch: the price of a refused edit comes back, and the
## refunds of applied ones are paid, before any signal.
func test_a_batch_settles_exactly_before_the_grid_signals() -> void:
	var grid := BuildGrid.new(Vector2i(4, 4))
	var wallet := Wallet.new(1000)
	var seen: Array[int] = []
	grid.edit_applied.connect(
		func(_edit: BuildEdit, _result: BuildResult) -> void: seen.append(wallet.balance)
	)
	grid.edit_refused.connect(
		func(_edit: BuildEdit, _result: BuildResult) -> void: seen.append(wallet.balance)
	)
	var edits: Array[BuildEdit] = []
	for x in range(2, 5):
		edits.append(BuildEdit.paint_floor(Vector2i(x, 2), BuildGrid.FLOOR_TILE, 1))
	var results := BuildTransaction.commit_batch(grid, edits, wallet)
	print("balance seen %s, after %d" % [seen, wallet.balance])
	assert_bool(results[2].ok).is_false()
	assert_array(seen).is_equal([1000 - 50, 1000 - 50, 1000 - 50])
	assert_int(wallet.balance).is_equal(1000 - 50)


## The listeners see the same signals in the same order as before staging.
func test_a_plan_publishes_one_applied_and_one_graph_signal_per_edit_in_order() -> void:
	var grid := _grid_with_paid_wall()
	_record_events(grid)
	var result := BuildTransaction.commit_plan(grid, _entrance_plan(grid), Wallet.new(1000))
	print("events %s" % [_events])
	assert_bool(result.ok).is_true()
	assert_array(_events).is_equal(["applied", "graph", "applied", "graph"])


func test_a_batch_publishes_its_signals_in_edit_order_then_one_graph_signal() -> void:
	var grid := BuildGrid.new(Vector2i(4, 4))
	_record_events(grid)
	var edits: Array[BuildEdit] = []
	for x in range(2, 5):
		edits.append(BuildEdit.paint_floor(Vector2i(x, 2), BuildGrid.FLOOR_TILE, 1))
	BuildTransaction.commit_batch(grid, edits, Wallet.new(1000))
	print("events %s" % [_events])
	assert_array(_events).is_equal(["applied", "applied", "refused", "graph"])


func test_signals_are_not_held_after_a_transaction() -> void:
	var grid := _floored_grid()
	_record_events(grid)
	BuildTransaction.commit_plan(
		grid, _plan(BuildEdit.paint_floor(Vector2i(0, 0), BuildGrid.FLOOR_TILE, 1)), Wallet.new(100)
	)
	_events.clear()
	grid.apply(BuildEdit.paint_floor(Vector2i(0, 1), BuildGrid.FLOOR_TILE, 1))
	assert_array(_events).is_equal(["applied", "graph"])


## Finding 2: the entrance's charge makes room for the wall's refund, so a
## full wallet takes the conversion.
func test_a_full_wallet_takes_a_paid_wall_to_entrance_conversion() -> void:
	var grid := _grid_with_paid_wall()
	var plan := _entrance_plan(grid)
	var wallet := Wallet.new(Wallet.MAX_BALANCE)
	var checked := BuildTransaction.check(grid, plan, wallet)
	var result := BuildTransaction.commit_plan(grid, plan, wallet)
	var expected := Wallet.MAX_BALANCE - 300 + 20
	print("check '%s', balance %d expected %d" % [checked.reason_text(), wallet.balance, expected])
	assert_bool(checked.ok).is_true()
	assert_bool(result.ok).is_true()
	assert_int(wallet.balance).is_equal(expected)
	assert_int(grid.wall_kind(Vector2i(3, 6), SOUTH)).is_equal(0)


## The check is exact, not lax: a plan whose final balance would pass the
## limit is still refused, and nothing changes.
func test_a_plan_whose_final_balance_would_pass_the_limit_is_still_refused() -> void:
	var grid := _grid_with_paid_wall()
	var plan := _entrance_plan(grid)
	# A bare removal pays 20 back into a wallet with 10 of room; the conversion
	# also spends 300, so it fits.
	var removal := _plan(BuildEdit.remove_wall(Vector2i(3, 6), SOUTH))
	var tight := Wallet.new(Wallet.MAX_BALANCE - 10)
	assert_int(BuildTransaction.check(grid, removal, tight).reason).is_equal(
		BuildResult.Reason.WALLET_FULL
	)
	assert_bool(BuildTransaction.check(grid, plan, tight).ok).is_true()
	var result := BuildTransaction.commit_plan(grid, removal, tight)
	assert_int(result.reason).is_equal(BuildResult.Reason.WALLET_FULL)
	assert_int(grid.wall_kind(Vector2i(3, 6), SOUTH)).is_not_equal(0)
	assert_int(tight.balance).is_equal(Wallet.MAX_BALANCE - 10)


## Finding 2: a listener of edit_applied gets that edit's own result, not the
## plan's aggregate.
func test_edit_applied_payloads_keep_each_edits_own_dirty_cells() -> void:
	var grid := _grid_with_paid_wall()
	var reference := _grid_with_paid_wall()
	var plan := _entrance_plan(grid)
	var expected: Array = []
	for edit in _entrance_plan(reference):
		expected.append(reference.apply(edit).dirty_cells.duplicate())
	var payloads: Array[BuildResult] = []
	grid.edit_applied.connect(
		func(_edit: BuildEdit, result: BuildResult) -> void: payloads.append(result)
	)
	var returned := BuildTransaction.commit_plan(grid, plan, Wallet.new(1000))
	print("payload cells %s, expected %s" % [payloads.map(_cells_of), expected])
	assert_int(payloads.size()).is_equal(2)
	assert_array(payloads[0].dirty_cells).is_equal(expected[0])
	assert_array(payloads[1].dirty_cells).is_equal(expected[1])
	# The caller still gets every applied edit's cells on the last result.
	assert_int(returned.dirty_cells.size()).is_equal(expected[0].size() + expected[1].size())


func _cells_of(result: BuildResult) -> Array[Vector2i]:
	return result.dirty_cells


## A mixed plan whose first edit refunds 20 and whose second the grid refuses
## (no floor at (7, 7)): all-applied it fits a wallet 10 below the limit, but
## the applied part alone does not.
func _mixed_edits() -> Array[BuildEdit]:
	var edits: Array[BuildEdit] = [
		BuildEdit.remove_wall(Vector2i(3, 6), SOUTH),
		BuildEdit.place_object(&"seat_row", Vector2i(7, 7), 0),
	]
	return edits


## Finding 1: when the exact settlement fails after a partial refusal, the
## grid goes back, the wallet stays, listeners see only the refusal.
func test_a_plan_whose_settlement_fails_changes_nothing_and_is_refused() -> void:
	var grid := _grid_with_paid_wall()
	var before := grid.to_snapshot()
	var wallet := Wallet.new(Wallet.MAX_BALANCE - 10)
	_record_events(grid)
	var result := BuildTransaction.commit_plan(grid, _mixed_edits(), wallet)
	print("result '%s', events %s" % [result.reason_text(), _events])
	assert_bool(result.ok).is_false()
	assert_int(result.reason).is_equal(BuildResult.Reason.WALLET_FULL)
	assert_dict(grid.to_snapshot()).is_equal(before)
	assert_int(wallet.balance).is_equal(Wallet.MAX_BALANCE - 10)
	assert_array(_events).is_equal(["refused"])


func test_a_batch_whose_settlement_fails_changes_nothing_and_refuses_every_edit() -> void:
	var grid := _grid_with_paid_wall()
	var before := grid.to_snapshot()
	var wallet := Wallet.new(Wallet.MAX_BALANCE - 10)
	_record_events(grid)
	var results := BuildTransaction.commit_batch(grid, _mixed_edits(), wallet)
	print(
		(
			"reasons %s, events %s"
			% [results.map(func(r: BuildResult) -> int: return r.reason), _events]
		)
	)
	assert_int(results.size()).is_equal(2)
	for result in results:
		assert_bool(result.ok).is_false()
		assert_int(result.reason).is_equal(BuildResult.Reason.WALLET_FULL)
	assert_dict(grid.to_snapshot()).is_equal(before)
	assert_int(wallet.balance).is_equal(Wallet.MAX_BALANCE - 10)
	assert_array(_events).is_equal(["refused", "refused"])


## Finding 3: holds nest; signals go out at the outermost release only.
func test_nested_holds_publish_only_at_the_outermost_release() -> void:
	var grid := _floored_grid()
	_record_events(grid)
	grid.hold_signals()
	grid.hold_signals()
	grid.apply(BuildEdit.paint_floor(Vector2i(0, 0), BuildGrid.FLOOR_TILE, 1))
	grid.release_signals()
	assert_array(_events).is_empty()
	grid.release_signals()
	assert_array(_events).is_equal(["applied", "graph"])


## A listener that opens its own hold while the queue is flushing neither
## loses nor reorders the rest of the flush: the first edit's applied signal
## reaches the listener, which paints a second cell and releases its own hold,
## so the second edit's signals go out in full before the first edit's graph
## signal resumes the outer queue.
func test_a_hold_opened_by_a_listener_during_the_flush_keeps_the_queue() -> void:
	var grid := _floored_grid()
	var seen: Array[String] = []
	grid.edit_applied.connect(
		func(edit: BuildEdit, _result: BuildResult) -> void: seen.append("applied %s" % edit.cell)
	)
	grid.graph_changed.connect(
		func(cells: Array[Vector2i]) -> void: seen.append("graph %s" % [cells])
	)
	var nested: Array[bool] = [false]
	grid.edit_applied.connect(
		func(_edit: BuildEdit, _result: BuildResult) -> void:
			if nested[0]:
				return
			nested[0] = true
			grid.hold_signals()
			grid.apply(BuildEdit.paint_floor(Vector2i(0, 1), BuildGrid.FLOOR_TILE, 1))
			grid.release_signals()
	)
	grid.hold_signals()
	grid.apply(BuildEdit.paint_floor(Vector2i(0, 0), BuildGrid.FLOOR_TILE, 1))
	grid.release_signals()
	print("events %s" % [seen])
	# graph_changed carries the relinked cells: the second edit's wider block
	# (rows 0 to 2) first, then the first edit's (rows 0 to 1).
	var second_block := "graph [(0, 0), (1, 0), (0, 1), (1, 1), (0, 2), (1, 2)]"
	var first_block := "graph [(0, 0), (1, 0), (0, 1), (1, 1)]"
	assert_array(seen).is_equal(["applied (0, 0)", "applied (0, 1)", second_block, first_block])
