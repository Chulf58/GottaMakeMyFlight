class_name TestBuildTransactionRollback
extends GdUnitTestSuite
## When the exact settlement of a partly applied build does not fit,
## BuildTransaction puts the grid back with BuildGrid.from_snapshot(). If that
## restore is itself refused, the build is still refused (nothing is paid),
## an error names the failed restore, and the grid's held signals are
## published rather than dropped, since the grid really holds the applied
## edits. The restore is made to fail with a grid whose from_snapshot()
## refuses everything; the control is the same build on a plain grid, which
## puts everything back.

const SOUTH := BuildGrid.Side.SOUTH


## A grid that cannot be restored from a snapshot.
class UnrestorableGrid:
	extends BuildGrid

	func from_snapshot(_data: Dictionary) -> bool:
		return false


var _events: Array[String] = []


## An 8x8 grid (`broken`: one that cannot be restored) with floor on x 1..6,
## y 1..6 and a paid wall on the south edge of (3, 6), laid for 40.
func _grid(broken: bool) -> BuildGrid:
	var grid: BuildGrid = (
		UnrestorableGrid.new(Vector2i(8, 8)) if broken else BuildGrid.new(Vector2i(8, 8))
	)
	for y in range(1, 7):
		for x in range(1, 7):
			grid.apply(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	var wall: Array[BuildEdit] = [BuildEdit.place_wall(Vector2i(3, 6), SOUTH)]
	BuildTransaction.commit_plan(grid, wall, Wallet.new(40))
	_events.clear()
	grid.edit_applied.connect(
		func(_e: BuildEdit, _r: BuildResult) -> void: _events.append("applied")
	)
	grid.edit_refused.connect(
		func(_e: BuildEdit, _r: BuildResult) -> void: _events.append("refused")
	)
	return grid


## Takes down the paid wall (refund 20) and places a seat row off the floor
## (refused): applied, the refund alone does not fit a wallet 10 below the
## limit, so the settlement fails after the wall came down.
func _mixed_edits() -> Array[BuildEdit]:
	var edits: Array[BuildEdit] = [
		BuildEdit.remove_wall(Vector2i(3, 6), SOUTH),
		BuildEdit.place_object(&"seat_row", Vector2i(7, 7), 0),
	]
	return edits


func test_a_plan_whose_rollback_fails_is_refused_loudly_and_publishes_what_applied() -> void:
	var grid := _grid(true)
	var wallet := Wallet.new(Wallet.MAX_BALANCE - 10)
	var out: Array[BuildResult] = []
	(
		assert_error(
			func() -> void: out.append(BuildTransaction.commit_plan(grid, _mixed_edits(), wallet))
		)
		. is_push_error(
			(
				(
					"BuildTransaction.commit_plan: the settlement was refused (%s) and restoring"
					+ " the grid failed; the applied edits stay on the grid, unpaid"
				)
				% BuildResult.REASON_TEXT[BuildResult.Reason.WALLET_FULL]
			)
		)
	)
	var result := out[0]
	var wall := grid.wall_kind(Vector2i(3, 6), SOUTH)
	print("result '%s', events %s, wall %d" % [result.reason_text(), _events, wall])
	assert_bool(result.ok).is_false()
	assert_int(result.reason).is_equal(BuildResult.Reason.WALLET_FULL)
	assert_int(wallet.balance).is_equal(Wallet.MAX_BALANCE - 10)
	# The restore failed: the wall stays down, and listeners hear of it (the
	# grid's own refusal of the seat row too), then of the build's refusal.
	assert_int(wall).is_equal(BuildGrid.WallKind.NONE)
	assert_array(_events).is_equal(["applied", "refused", "refused"])


func test_a_batch_whose_rollback_fails_is_refused_loudly_and_publishes_what_applied() -> void:
	var grid := _grid(true)
	var wallet := Wallet.new(Wallet.MAX_BALANCE - 10)
	var results := BuildTransaction.commit_batch(grid, _mixed_edits(), wallet)
	print("events %s" % [_events])
	for result in results:
		assert_bool(result.ok).is_false()
	assert_int(wallet.balance).is_equal(Wallet.MAX_BALANCE - 10)
	assert_int(grid.wall_kind(Vector2i(3, 6), SOUTH)).is_equal(BuildGrid.WallKind.NONE)
	assert_array(_events).is_equal(["applied", "refused", "refused", "refused"])


func test_control_a_plain_grid_is_put_back() -> void:
	var grid := _grid(false)
	var wallet := Wallet.new(Wallet.MAX_BALANCE - 10)
	var result := BuildTransaction.commit_plan(grid, _mixed_edits(), wallet)
	assert_bool(result.ok).is_false()
	assert_int(grid.wall_kind(Vector2i(3, 6), SOUTH)).is_equal(BuildGrid.WallKind.PLAIN)
	assert_array(_events).is_equal(["refused"])
