class_name TestRoomMoveSignals
extends GdUnitTestSuite
## A room move's refusal reaches listeners through BuildGrid's signal hold
## (Sol review of 0d6888c): under an outer hold, a refusal waits behind the
## edit already queued there, whether it comes before anything is applied or
## after the live grid refused a move its copy accepted and was put back. That
## put-back still emits a refusal, drops the move's own signals and keeps the
## earlier undo step. The grid is RoomMoveKit's (a 4x3 cafe on columns 2 to
## 5, rows 2 to 4); centre (12, 7) moves it to columns 11 to 14, rows 6 to 8,
## with new floor on columns 13 and 14.


## A grid that refuses every RESIZE_ROOM once `refuse_resize` is set. Its
## trial copy (BuildGrid.clone()) is a plain BuildGrid, so the copy accepts a
## move the live grid then refuses.
class DivergingGrid:
	extends BuildGrid

	var refuse_resize := false

	func validate(edit: BuildEdit, check_reach := true) -> BuildResult:
		if refuse_resize and edit.kind == BuildEdit.Kind.RESIZE_ROOM:
			return BuildResult.refused(BuildResult.Reason.PLANE_AREA)
		return super(edit, check_reach)


const START := 5000
const CENTRE := Vector2i(12, 7)
## Where the refusal's RESIZE_ROOM edit names the room: the new rect's corner.
const NEW_CORNER := Vector2i(11, 6)
const QUEUED := Vector2i(20, 12)
const DIVERGED := "RoomMove.commit_move: the grid refused a move its copy accepted"

var _events: Array[String] = []


func _listen(grid: BuildGrid) -> void:
	_events.clear()
	grid.edit_applied.connect(
		func(edit: BuildEdit, _r: BuildResult) -> void: _events.append("applied %s" % edit.cell)
	)
	grid.edit_refused.connect(
		func(edit: BuildEdit, _r: BuildResult) -> void: _events.append("refused %s" % edit.cell)
	)


## Opens an outer hold on `grid` and queues a floor edit at QUEUED in it.
func _hold_with_queued_edit(grid: BuildGrid) -> void:
	grid.hold_signals()
	assert_bool(grid.apply(BuildEdit.paint_floor(QUEUED, BuildGrid.FLOOR_TILE, 1)).ok).is_true()


func test_a_planned_refusal_waits_behind_the_outer_holds_queued_edit() -> void:
	var kit := RoomMoveKit.new()
	_listen(kit.grid)
	_hold_with_queued_edit(kit.grid)
	# The new floor costs 150; the wallet holds nothing.
	var result := RoomMove.commit(kit.grid, kit.room, CENTRE, 0, Wallet.new(0))
	var heard_during_hold := _events.duplicate()
	kit.grid.release_signals()
	print("reason %d, during hold %s, events %s" % [result.reason, heard_during_hold, _events])
	assert_int(result.reason).is_equal(BuildResult.Reason.CANT_AFFORD)
	assert_array(heard_during_hold).is_empty()
	assert_array(_events).is_equal(["applied %s" % QUEUED, "refused %s" % NEW_CORNER])


func test_a_commit_refusal_of_a_changed_plan_waits_behind_the_outer_holds_queued_edit() -> void:
	var kit := RoomMoveKit.new()
	var planned := RoomMove.plan(kit.grid, kit.room, CENTRE, 0)
	for edit in planned.edits:
		if edit.kind == BuildEdit.Kind.PLACE_OBJECT and edit.object_id == kit.bin:
			edit.facing = 2
	_listen(kit.grid)
	_hold_with_queued_edit(kit.grid)
	var result := RoomMove.commit_move(kit.grid, planned, Wallet.new(START))
	var heard_during_hold := _events.duplicate()
	kit.grid.release_signals()
	print("reason %d, during hold %s, events %s" % [result.reason, heard_during_hold, _events])
	assert_int(result.reason).is_equal(BuildResult.Reason.MOVE_CHANGED)
	assert_array(heard_during_hold).is_empty()
	assert_array(_events).is_equal(["applied %s" % QUEUED, "refused %s" % NEW_CORNER])


## Runs the move on `kit`'s grid expecting the divergence error; returns the result.
func _diverging_commit(kit: RoomMoveKit, wallet: Wallet, history: UndoStack = null) -> BuildResult:
	var out: Array[BuildResult] = []
	var run := func() -> void:
		out.append(RoomMove.commit(kit.grid, kit.room, CENTRE, 0, wallet, history))
	assert_error(run).is_push_error(DIVERGED)
	return out[0]


func test_a_move_the_live_grid_refuses_is_put_back_and_still_emits_a_refusal() -> void:
	var grid := DivergingGrid.new(RoomMoveKit.SIZE)
	var kit := RoomMoveKit.new(grid)
	var wallet := Wallet.new(START)
	var history := UndoStack.new()
	history.watch(grid, wallet)
	assert_bool(kit.earlier_action(history, wallet, QUEUED).ok).is_true()
	var before := grid.to_snapshot()
	var balance := wallet.balance
	grid.refuse_resize = true
	_listen(grid)
	var result := _diverging_commit(kit, wallet, history)
	print("reason %d, events %s, steps %d" % [result.reason, _events, history.size()])
	assert_bool(result.ok).is_false()
	assert_int(result.reason).is_equal(BuildResult.Reason.PLANE_AREA)
	assert_array(_events).is_equal(["refused %s" % NEW_CORNER])
	assert_that(grid.to_snapshot()).is_equal(before)
	assert_int(wallet.balance).is_equal(balance)
	assert_int(history.size()).is_equal(1)
	grid.refuse_resize = false
	assert_bool(history.undo().ok).is_true()
	assert_int(grid.floor_at(QUEUED)).is_equal(BuildGrid.FLOOR_NONE)


func test_a_put_back_refusal_waits_behind_the_outer_holds_queued_edit() -> void:
	var grid := DivergingGrid.new(RoomMoveKit.SIZE)
	var kit := RoomMoveKit.new(grid)
	grid.refuse_resize = true
	_listen(grid)
	_hold_with_queued_edit(grid)
	var result := _diverging_commit(kit, Wallet.new(START))
	var heard_during_hold := _events.duplicate()
	grid.release_signals()
	print("reason %d, during hold %s, events %s" % [result.reason, heard_during_hold, _events])
	assert_int(result.reason).is_equal(BuildResult.Reason.PLANE_AREA)
	assert_array(heard_during_hold).is_empty()
	assert_array(_events).is_equal(["applied %s" % QUEUED, "refused %s" % NEW_CORNER])
	assert_that(kit.rect()).is_equal(RoomMoveKit.CAFE)
