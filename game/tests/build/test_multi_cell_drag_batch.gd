class_name TestMultiCellDragBatch
extends GdUnitTestSuite
## Coalesced relink, batch reach checks, and signal ordering for multi-cell
## build drags (wall/glass rows, belt lines, area-with-walls, and failed
## BuildTransaction.commit_plan rollbacks).

const GRID_SIZE := Vector2i(30, 20)
const NORTH := BuildGrid.Side.NORTH
const SOUTH := BuildGrid.Side.SOUTH

var _mode: BuildMode
var _finances: Finances
var _events: Array[String] = []
var _graph_batches: Array = []


func before_test() -> void:
	_events.clear()
	_graph_batches.clear()
	_finances = Finances.new()
	add_child(_finances)
	_mode = BuildMode.new()
	_mode.grid_size = GRID_SIZE
	_mode.grid_centred = false
	_mode.finances = _finances
	add_child(_mode)
	_set_balance(500_000)
	_paint_rect(Rect2i(2, 2, 26, 16))
	_mode.clear_undo()


func after_test() -> void:
	_mode.free()
	_finances.free()


func _set_balance(amount: int) -> void:
	assert_bool(_finances.wallet.from_snapshot({"balance": str(amount)})).is_true()


func _paint_rect(area: Rect2i) -> void:
	var edits: Array[BuildEdit] = []
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	for res in _mode.grid.apply_batch(edits):
		assert_bool(res.ok).is_true()


func _connect_signals(grid: BuildGrid) -> void:
	_events.clear()
	_graph_batches.clear()
	grid.edit_applied.connect(
		func(_e: BuildEdit, _r: BuildResult) -> void: _events.append("applied")
	)
	grid.edit_refused.connect(
		func(_e: BuildEdit, _r: BuildResult) -> void: _events.append("refused")
	)
	grid.graph_changed.connect(
		func(cells: Array[Vector2i]) -> void:
			_events.append("graph")
			_graph_batches.append(cells)
	)


func _row_edits(
	from_x: int, count: int, y: int, kind := BuildGrid.WallKind.PLAIN
) -> Array[BuildEdit]:
	var edits: Array[BuildEdit] = []
	for x in range(from_x, from_x + count):
		edits.append(BuildEdit.place_wall(Vector2i(x, y), NORTH, kind))
	return edits


func _place_entrance_and_desk() -> int:
	(
		assert_bool(
			_mode.grid.apply(BuildEdit.place_object(&"entrance_door", Vector2i(2, 2), 0)).ok
		)
		. is_true()
	)
	var desk := _mode.grid.apply(BuildEdit.place_object(&"checkin_desk", Vector2i(14, 14), 0))
	assert_bool(desk.ok).is_true()
	return desk.object_id


func test_20_cell_wall_drag_coalesces_relink_and_undoes_in_one_step() -> void:
	_place_entrance_and_desk()
	_connect_signals(_mode.grid)
	var relinks_0 := _mode.grid.relink_count
	var floods_0 := GridReach.reach_flood_calls
	var balance_0 := _finances.wallet.balance
	var wall_price := PriceTable.price_of_wall(BuildGrid.WallKind.PLAIN)

	var edits := _row_edits(4, 20, 6)
	var dirty: Array[Vector2i] = []
	_mode.undo_history().begin_action()
	var t0 := Time.get_ticks_usec()
	var outcome := WallRowDrag.apply(_mode.grid, edits, _mode.check, _mode.wallet(), dirty)
	var dt_ms := (Time.get_ticks_usec() - t0) / 1000.0
	_mode.undo_history().end_action()
	print(
		(
			"20-cell WallRowDrag.apply dt_ms=%.2f relinks=%d floods=%d"
			% [
				dt_ms,
				_mode.grid.relink_count - relinks_0,
				GridReach.reach_flood_calls - floods_0,
			]
		)
	)

	assert_int(outcome.placed).is_equal(20)
	assert_int(outcome.skipped).is_equal(0)
	assert_int(_mode.grid.relink_count - relinks_0).is_equal(1)
	assert_int(GridReach.reach_flood_calls - floods_0).is_equal(1)
	assert_int(_graph_batches.size()).is_equal(1)
	assert_int(_events.size()).is_equal(21)
	for i in 20:
		assert_str(_events[i]).is_equal("applied")
	assert_str(_events[20]).is_equal("graph")
	for x in range(4, 24):
		assert_int(_mode.grid.wall_kind(Vector2i(x, 6), NORTH)).is_equal(BuildGrid.WallKind.PLAIN)
	assert_int(_finances.wallet.balance).is_equal(balance_0 - 20 * wall_price)

	var undo_res := _mode.undo()
	assert_bool(undo_res.ok).is_true()
	for x in range(4, 24):
		assert_int(_mode.grid.wall_kind(Vector2i(x, 6), NORTH)).is_equal(BuildGrid.WallKind.NONE)
	assert_int(_finances.wallet.balance).is_equal(balance_0)


func test_multi_cell_belt_line_emits_graph_changed_once_after_all_edit_applied() -> void:
	_place_entrance_and_desk()
	_connect_signals(_mode.grid)
	var relinks_0 := _mode.grid.relink_count

	var result := _mode.lay_belt(Vector2i(4, 10), Vector2i(13, 12))
	assert_bool(result.ok).override_failure_message(result.reason_text()).is_true()
	assert_int(_mode.grid.relink_count - relinks_0).is_equal(1)
	assert_int(_graph_batches.size()).is_equal(1)
	assert_int(_events.size()).is_greater(12)
	assert_str(_events.back()).is_equal("graph")
	for i in _events.size() - 1:
		assert_str(_events[i]).is_equal("applied")
	for x in range(4, 14):
		assert_int(_mode.grid.object_at(Vector2i(x, 10))).is_greater(0)
	for y in range(11, 13):
		assert_int(_mode.grid.object_at(Vector2i(13, y))).is_greater(0)


func test_failed_commit_plan_rollback_clears_batch_dirty() -> void:
	var grid := BuildGrid.new(Vector2i(12, 12))
	for y in range(2, 8):
		for x in range(2, 8):
			assert_bool(grid.apply(BuildEdit.paint_floor(Vector2i(x, y), 1, 1)).ok).is_true()
	var wall_edit := BuildEdit.place_wall(Vector2i(3, 6), SOUTH)
	wall_edit.paid = PriceTable.price_of_wall(BuildGrid.WallKind.PLAIN)
	assert_bool(grid.apply(wall_edit).ok).is_true()

	var plan: Array[BuildEdit] = [
		BuildEdit.remove_wall(Vector2i(3, 6), SOUTH),
		BuildEdit.place_object(&"seat_row", Vector2i(10, 10), 0),
	]
	var wallet := Wallet.new(Wallet.MAX_BALANCE - 10)
	_connect_signals(grid)
	var relinks_0 := grid.relink_count

	var res := BuildTransaction.commit_plan(grid, plan, wallet)
	assert_bool(res.ok).is_false()
	assert_int(res.reason).is_equal(BuildResult.Reason.WALLET_FULL)
	assert_int(grid.relink_count - relinks_0).is_equal(0)
	assert_array(_events).is_equal(["refused"])
	assert_int(grid.wall_kind(Vector2i(3, 6), SOUTH)).is_equal(BuildGrid.WallKind.PLAIN)

	# Next unrelated edit relinks only its own neighbourhood (no leaked (3, 6) cells).
	_events.clear()
	_graph_batches.clear()
	var next := grid.apply(BuildEdit.paint_floor(Vector2i(9, 9), 1, 1))
	assert_bool(next.ok).is_true()
	assert_int(_graph_batches.size()).is_equal(1)
	assert_array(_graph_batches[0]).not_contains([Vector2i(3, 6), Vector2i(3, 7)])
	assert_array(_events).is_equal(["applied", "graph"])


func test_wall_row_fallback_preserves_reach_blocking_and_cant_afford() -> void:
	# Enclose a 3x3 pocket around a desk at (10, 10) (staff spot at (10, 9))
	# leaving a 3-cell gap along x=9..11 on row 8 NORTH; sealing all 3 breaks
	# reach, so the third wall is skipped via STAFF_SPOT while the first two stay.
	_place_entrance_and_desk()
	(
		assert_bool(
			_mode.grid.apply(BuildEdit.place_object(&"checkin_desk", Vector2i(10, 10), 0)).ok
		)
		. is_true()
	)
	var pocket: Array[BuildEdit] = [
		BuildEdit.place_wall(Vector2i(9, 8), BuildGrid.Side.WEST),
		BuildEdit.place_wall(Vector2i(9, 9), BuildGrid.Side.WEST),
		BuildEdit.place_wall(Vector2i(9, 10), BuildGrid.Side.WEST),
		BuildEdit.place_wall(Vector2i(9, 11), BuildGrid.Side.WEST),
		BuildEdit.place_wall(Vector2i(11, 8), BuildGrid.Side.EAST),
		BuildEdit.place_wall(Vector2i(11, 9), BuildGrid.Side.EAST),
		BuildEdit.place_wall(Vector2i(11, 10), BuildGrid.Side.EAST),
		BuildEdit.place_wall(Vector2i(11, 11), BuildGrid.Side.EAST),
		BuildEdit.place_wall(Vector2i(9, 11), SOUTH),
		BuildEdit.place_wall(Vector2i(10, 11), SOUTH),
		BuildEdit.place_wall(Vector2i(11, 11), SOUTH),
	]
	for res in _mode.grid.apply_batch(pocket):
		assert_bool(res.ok).is_true()

	_connect_signals(_mode.grid)
	var relinks_0 := _mode.grid.relink_count
	var row := _row_edits(9, 3, 8)
	var dirty: Array[Vector2i] = []
	var outcome := WallRowDrag.apply(_mode.grid, row, _mode.check, _mode.wallet(), dirty)
	assert_int(outcome.placed).is_equal(2)
	assert_int(outcome.skipped).is_equal(1)
	assert_int(_mode.grid.relink_count - relinks_0).is_equal(1)
	assert_int(_graph_batches.size()).is_equal(1)
	assert_array(_events).is_equal(["applied", "applied", "refused", "graph"])
	assert_int(_mode.grid.wall_kind(Vector2i(9, 8), NORTH)).is_equal(BuildGrid.WallKind.PLAIN)
	assert_int(_mode.grid.wall_kind(Vector2i(10, 8), NORTH)).is_equal(BuildGrid.WallKind.PLAIN)
	assert_int(_mode.grid.wall_kind(Vector2i(11, 8), NORTH)).is_equal(BuildGrid.WallKind.NONE)

	# CANT_AFFORD mid-row stops at the fifth wall and still coalesces into one relink.
	var wall_price := PriceTable.price_of_wall(BuildGrid.WallKind.PLAIN)
	_set_balance(wall_price * 4)
	_events.clear()
	_graph_batches.clear()
	relinks_0 = _mode.grid.relink_count
	var afford_row := _row_edits(4, 10, 4)
	var afford_dirty: Array[Vector2i] = []
	var afford_out := WallRowDrag.apply(
		_mode.grid, afford_row, _mode.check, _mode.wallet(), afford_dirty
	)
	assert_int(afford_out.placed).is_equal(4)
	assert_int(afford_out.skipped).is_equal(6)
	assert_int(_mode.grid.relink_count - relinks_0).is_equal(1)
	assert_int(_graph_batches.size()).is_equal(1)
	assert_array(_events).is_equal(["applied", "applied", "applied", "applied", "refused", "graph"])


func test_wall_row_preview_matches_apply_and_floods_once_for_valid_row() -> void:
	_place_entrance_and_desk()
	var valid_edits := _row_edits(4, 20, 6)
	# Prime staff_reach cache as gameplay does before dragging.
	_mode.grid.staff_reach()
	var floods_0 := GridReach.reach_flood_calls
	var preview := WallRowDrag.preview(_mode.grid, valid_edits, _mode.check, _mode.wallet())
	assert_int(GridReach.reach_flood_calls - floods_0).is_equal(1)
	assert_int(preview.blocked).is_equal(0)
	assert_array(preview.valid).has_size(20)
	for ok in preview.valid:
		assert_bool(ok).is_true()

	# A single edge that immediately closes a 1-cell staff pocket is flagged by both preview and apply.
	(
		assert_bool(
			_mode.grid.apply(BuildEdit.place_object(&"checkin_desk", Vector2i(10, 10), 0)).ok
		)
		. is_true()
	)
	var seal: Array[BuildEdit] = [
		BuildEdit.place_wall(Vector2i(10, 9), BuildGrid.Side.WEST),
		BuildEdit.place_wall(Vector2i(10, 9), BuildGrid.Side.EAST),
	]
	for res in _mode.grid.apply_batch(seal):
		assert_bool(res.ok).is_true()
	var blocking_row := _row_edits(9, 3, 9)
	var block_preview := WallRowDrag.preview(_mode.grid, blocking_row, _mode.check, _mode.wallet())
	assert_array(block_preview.valid).is_equal([true, false, true])
	var dirty: Array[Vector2i] = []
	var block_outcome := WallRowDrag.apply(
		_mode.grid, blocking_row, _mode.check, _mode.wallet(), dirty
	)
	assert_int(block_outcome.placed).is_equal(2)
	assert_int(block_outcome.skipped).is_equal(1)
	assert_int(_mode.grid.wall_kind(Vector2i(9, 9), NORTH)).is_equal(BuildGrid.WallKind.PLAIN)
	assert_int(_mode.grid.wall_kind(Vector2i(10, 9), NORTH)).is_equal(BuildGrid.WallKind.NONE)
	assert_int(_mode.grid.wall_kind(Vector2i(11, 9), NORTH)).is_equal(BuildGrid.WallKind.PLAIN)


func test_area_clear_with_door_and_belt_coalesces_into_one_relink() -> void:
	# Entrance on edge (4, 2) with floor below and two belts beside it so
	# finish_area(REMOVE) runs AreaDrag._commit_with_walls + reshape_belts.
	assert_bool(_mode.grid.apply(BuildEdit.remove_floor(Vector2i(4, 1))).ok).is_false()
	(
		assert_bool(
			_mode.grid.apply(BuildEdit.place_object(&"entrance_door", Vector2i(4, 2), 0)).ok
		)
		. is_true()
	)
	assert_bool(_mode.lay_belt(Vector2i(5, 2), Vector2i(7, 2)).ok).is_true()

	_connect_signals(_mode.grid)
	var relinks_0 := _mode.grid.relink_count
	_mode.set_tool(BuildMode.Tool.REMOVE)
	_mode.begin_area(_mode.grid.cell_to_world(Vector2i(4, 2)))
	_mode.move_area(_mode.grid.cell_to_world(Vector2i(5, 2)))
	var outcome := _mode.finish_area()

	assert_int(outcome.placed).is_equal(2)
	assert_int(_mode.grid.relink_count - relinks_0).is_equal(1)
	assert_int(_graph_batches.size()).is_equal(1)
	assert_str(_events.back()).is_equal("graph")
	for i in _events.size() - 1:
		assert_str(_events[i]).is_equal("applied")
	assert_int(_mode.grid.wall_kind(Vector2i(4, 2), NORTH)).is_equal(BuildGrid.WallKind.PLAIN)
