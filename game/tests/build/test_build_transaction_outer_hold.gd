class_name TestBuildTransactionOuterHold
extends GdUnitTestSuite
## A refusal from BuildTransaction joins an outer BuildGrid signal hold in
## order: an edit queued before the transaction is heard before the refusal
## (board item 94be4a7c, Sol's re-check of b4210dc).

const SOUTH := BuildGrid.Side.SOUTH

var _events: Array[String] = []


## An 8x8 grid with floor on x 1..6, y 1..6 and a paid wall on the south edge
## of (3, 6), laid for 40.
func _grid_with_paid_wall() -> BuildGrid:
	var grid := BuildGrid.new(Vector2i(8, 8))
	for y in range(1, 7):
		for x in range(1, 7):
			grid.apply(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	var plan: Array[BuildEdit] = [BuildEdit.place_wall(Vector2i(3, 6), SOUTH)]
	BuildTransaction.commit_plan(grid, plan, Wallet.new(40))
	return grid


## A refund of 20 that fits only with the edit the grid refuses, so the
## settlement of the applied part fails once the grid refuses the second edit.
func _mixed_edits() -> Array[BuildEdit]:
	var edits: Array[BuildEdit] = [
		BuildEdit.remove_wall(Vector2i(3, 6), SOUTH),
		BuildEdit.place_object(&"seat_row", Vector2i(7, 7), 0),
	]
	return edits


func _unaffordable_edits() -> Array[BuildEdit]:
	var edits: Array[BuildEdit] = [BuildEdit.paint_floor(Vector2i(0, 1), BuildGrid.FLOOR_TILE, 1)]
	return edits


## Opens the outer hold and queues edit A (a floor at (0, 0)) in it, after
## recording every signal that arrives from here on.
func _hold_with_queued_edit(grid: BuildGrid) -> void:
	_events.clear()
	grid.edit_applied.connect(
		func(edit: BuildEdit, _r: BuildResult) -> void: _events.append("applied %s" % edit.cell)
	)
	grid.edit_refused.connect(
		func(edit: BuildEdit, _r: BuildResult) -> void: _events.append("refused %s" % edit.cell)
	)
	grid.hold_signals()
	grid.apply(BuildEdit.paint_floor(Vector2i(0, 0), BuildGrid.FLOOR_TILE, 1))


func test_a_plan_settlement_refusal_waits_behind_the_outer_holds_queued_edit() -> void:
	var grid := _grid_with_paid_wall()
	_hold_with_queued_edit(grid)
	var wallet := Wallet.new(Wallet.MAX_BALANCE - 10)
	var result := BuildTransaction.commit_plan(grid, _mixed_edits(), wallet)
	var heard_during_hold := _events.duplicate()
	grid.release_signals()
	print("reason %d, during hold %s, events %s" % [result.reason, heard_during_hold, _events])
	assert_int(result.reason).is_equal(BuildResult.Reason.WALLET_FULL)
	assert_array(heard_during_hold).is_empty()
	assert_array(_events).is_equal(["applied (0, 0)", "refused (7, 7)"])


func test_a_batch_settlement_refusal_waits_behind_the_outer_holds_queued_edit() -> void:
	var grid := _grid_with_paid_wall()
	_hold_with_queued_edit(grid)
	var wallet := Wallet.new(Wallet.MAX_BALANCE - 10)
	var results := BuildTransaction.commit_batch(grid, _mixed_edits(), wallet)
	var heard_during_hold := _events.duplicate()
	grid.release_signals()
	print("results %d, during hold %s, events %s" % [results.size(), heard_during_hold, _events])
	assert_int(results.size()).is_equal(2)
	assert_array(heard_during_hold).is_empty()
	assert_array(_events).is_equal(["applied (0, 0)", "refused (3, 6)", "refused (7, 7)"])


func test_a_plan_up_front_refusal_waits_behind_the_outer_holds_queued_edit() -> void:
	var grid := _grid_with_paid_wall()
	_hold_with_queued_edit(grid)
	var result := BuildTransaction.commit_plan(grid, _unaffordable_edits(), Wallet.new(0))
	var heard_during_hold := _events.duplicate()
	grid.release_signals()
	print("reason %d, during hold %s, events %s" % [result.reason, heard_during_hold, _events])
	assert_int(result.reason).is_equal(BuildResult.Reason.CANT_AFFORD)
	assert_array(heard_during_hold).is_empty()
	assert_array(_events).is_equal(["applied (0, 0)", "refused (0, 1)"])


func test_a_batch_up_front_refusal_waits_behind_the_outer_holds_queued_edit() -> void:
	var grid := _grid_with_paid_wall()
	_hold_with_queued_edit(grid)
	var results := BuildTransaction.commit_batch(grid, _unaffordable_edits(), Wallet.new(0))
	var heard_during_hold := _events.duplicate()
	grid.release_signals()
	print("results %d, during hold %s, events %s" % [results.size(), heard_during_hold, _events])
	assert_int(results.size()).is_equal(1)
	assert_array(heard_during_hold).is_empty()
	assert_array(_events).is_equal(["applied (0, 0)", "refused (0, 1)"])


## With no outer hold the refusal still reaches listeners at once.
func test_a_refusal_without_an_outer_hold_is_emitted_at_once() -> void:
	var grid := _grid_with_paid_wall()
	_hold_with_queued_edit(grid)
	grid.release_signals()
	_events.clear()
	BuildTransaction.commit_plan(grid, _unaffordable_edits(), Wallet.new(0))
	assert_array(_events).is_equal(["refused (0, 1)"])
