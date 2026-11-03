class_name TestRoomMoveRefusals
extends GdUnitTestSuite
## A refused room move changes nothing (decision
## move-rooms-technical-design-roommove-plan-of-existing-edits, parts 2 and
## 3): for each reason (another room, an inner wall, a straddling or unmovable
## piece, a piece that does not fit, floor the wallet cannot pay, a cell kept
## clear for leaving passengers, a plan whose pieces were changed) the grid,
## the wallet and the undo history stay as they were, and the undo step made
## before the refusal still undoes. The grid is RoomMoveKit's: a 4x3 cafe on
## columns 2 to 5, rows 2 to 4, floor on columns 1 to 12.

const START := 5000
## The bare cell the earlier undo step lays floor on.
const EARLIER := Vector2i(20, 12)
## Centre (9, 7) puts the cafe on columns 8 to 11, rows 6 to 8, all floored.
const TARGET := Vector2i(9, 7)

var _kit: RoomMoveKit
var _wallet: Wallet
var _history: UndoStack
var _snapshot: Dictionary
var _balance := 0


func before_test() -> void:
	_kit = RoomMoveKit.new()
	_wallet = Wallet.new(START)
	_history = UndoStack.new()
	_history.watch(_kit.grid, _wallet)


## Makes the earlier undo step and notes grid and wallet. Call after any
## direct grid edit, which clears the history.
func _arm() -> void:
	assert_bool(_kit.earlier_action(_history, _wallet, EARLIER).ok).is_true()
	assert_int(_history.size()).is_equal(1)
	_snapshot = _kit.grid.to_snapshot()
	_balance = _wallet.balance


## The refusal is `reason`, and nothing changed: grid, wallet, one undo step,
## and that step still undoes the earlier floor.
func _assert_refused_unchanged(result: BuildResult, reason: BuildResult.Reason) -> void:
	print("refused: ok=%s reason=%s text=%s" % [result.ok, result.reason, result.reason_text()])
	assert_bool(result.ok).is_false()
	assert_int(result.reason).is_equal(reason)
	assert_that(_kit.grid.to_snapshot()).is_equal(_snapshot)
	assert_int(_wallet.balance).is_equal(_balance)
	assert_int(_history.size()).is_equal(1)
	var undone := _history.undo()
	print("earlier undo: ok=%s balance=%d" % [undone.ok, _wallet.balance])
	assert_bool(undone.ok).is_true()
	assert_int(_kit.grid.floor_at(EARLIER)).is_equal(BuildGrid.FLOOR_NONE)
	assert_int(_wallet.balance).is_equal(_balance + PriceTable.FLOOR_PRICE)


func _move(centre: Vector2i, keep_clear: Array[Vector2i] = []) -> BuildResult:
	return RoomMove.commit(_kit.grid, _kit.room, centre, 0, _wallet, _history, keep_clear)


func test_another_room_at_the_new_spot_refuses() -> void:
	var toilet := BuildEdit.place_room(Rect2i(10, 7, 2, 2), &"toilet")
	assert_int(_kit.grid.apply(toilet).room_id).is_greater(0)
	_arm()
	_assert_refused_unchanged(_move(TARGET), BuildResult.Reason.ROOM_OVERLAP)


func test_a_wall_inside_the_new_rect_refuses() -> void:
	var wall := BuildEdit.place_wall(Vector2i(9, 7), BuildGrid.Side.EAST, BuildGrid.WallKind.PLAIN)
	assert_bool(_kit.grid.apply(wall).ok).is_true()
	_arm()
	_assert_refused_unchanged(_move(TARGET), BuildResult.Reason.ROOM_WALL)


func test_a_wall_on_the_new_rects_edge_does_not_refuse() -> void:
	var wall := BuildEdit.place_wall(Vector2i(11, 7), BuildGrid.Side.EAST, BuildGrid.WallKind.PLAIN)
	assert_bool(_kit.grid.apply(wall).ok).is_true()
	assert_bool(_move(TARGET).ok).is_true()


func test_a_piece_across_the_rooms_edge_refuses_and_names_it() -> void:
	# A 2x2 pot on columns 5 and 6, rows 1 and 2: only (5, 2) is in the cafe.
	var straddler := _kit.place(&"plant_pot_2a", Vector2i(5, 1), 0, 10)
	print("straddling pot id %d at %s" % [straddler, _kit.record(straddler)])
	assert_int(straddler).is_greater(0)
	_arm()
	var result := _move(TARGET)
	assert_int(result.blocking_object_id).is_equal(straddler)
	_assert_refused_unchanged(result, BuildResult.Reason.MOVE_STRADDLES)


func test_a_security_piece_in_the_room_refuses_as_unmovable() -> void:
	var arch := _kit.place(&"security_arch", Vector2i(5, 2), 2, 10)
	print("arch id %d" % arch)
	assert_int(arch).is_greater(0)
	_arm()
	var result := _move(TARGET)
	assert_int(result.blocking_object_id).is_equal(arch)
	_assert_refused_unchanged(result, BuildResult.Reason.MOVE_UNMOVABLE)


func test_a_piece_that_does_not_fit_refuses_with_the_grids_reason() -> void:
	# The bin lands on (8, 6); a statue already stands there.
	assert_int(_kit.place(&"statue_indoor", Vector2i(8, 6), 0, 10)).is_greater(0)
	_arm()
	var result := _move(TARGET)
	assert_int(result.blocking_object_id).is_equal(_kit.bin)
	print("detail: %s" % result.detail)
	assert_str(result.detail).is_equal(BuildResult.REASON_TEXT[BuildResult.Reason.OVERLAP])
	_assert_refused_unchanged(result, BuildResult.Reason.MOVE_NO_FIT)


func test_new_floor_the_wallet_cannot_pay_refuses() -> void:
	_arm()
	# Six bare cells cost 150; leave 100 after the earlier step.
	assert_bool(_wallet.spend(_wallet.balance - 100, Wallet.Category.BUILD)).is_true()
	_balance = _wallet.balance
	_snapshot = _kit.grid.to_snapshot()
	var planned := RoomMove.plan(_kit.grid, _kit.room, Vector2i(12, 7), 0, _wallet)
	print("cost %d against %d" % [planned.cost, _wallet.balance])
	assert_int(planned.cost).is_greater(_wallet.balance)
	_assert_refused_unchanged(_move(Vector2i(12, 7)), BuildResult.Reason.CANT_AFFORD)


func test_a_piece_set_down_on_a_kept_clear_cell_refuses() -> void:
	_arm()
	# The bin lands on (8, 6).
	var keep: Array[Vector2i] = [Vector2i(8, 6)]
	var result := _move(TARGET, keep)
	assert_int(result.blocking_object_id).is_equal(_kit.bin)
	_assert_refused_unchanged(result, BuildResult.Reason.MOVE_EXIT_BLOCKED)


func test_a_kept_clear_cell_no_piece_lands_on_does_not_refuse() -> void:
	# (9, 6) is in the new rect, but no piece lands on it; (2, 2) is the bin's old cell.
	var keep: Array[Vector2i] = [Vector2i(9, 6), Vector2i(2, 2)]
	var result := _move(TARGET, keep)
	print("keep-clear control: ok=%s reason=%s" % [result.ok, result.reason_text()])
	assert_bool(result.ok).is_true()
	assert_that(_kit.rect()).is_equal(Rect2i(8, 6, 4, 3))


## The plan with every PLACE_OBJECT for `id` given to `change`.
func _forged(id: int, change: Callable) -> RoomMove:
	var planned := RoomMove.plan(_kit.grid, _kit.room, TARGET, 0, _wallet)
	assert_bool(planned.result.ok).is_true()
	for edit in planned.edits:
		if edit.kind == BuildEdit.Kind.PLACE_OBJECT and edit.object_id == id:
			change.call(edit)
	return planned


func test_the_commit_refuses_a_different_def_under_a_removed_id() -> void:
	_arm()
	var forged := _forged(_kit.bin, func(edit: BuildEdit) -> void: edit.def_id = &"statue_indoor")
	var result := RoomMove.commit_move(_kit.grid, forged, _wallet, _history)
	assert_int(result.blocking_object_id).is_equal(_kit.bin)
	_assert_refused_unchanged(result, BuildResult.Reason.MOVE_CHANGED)


func test_the_commit_refuses_a_different_paid_under_a_removed_id() -> void:
	_arm()
	var forged := _forged(_kit.statue, func(edit: BuildEdit) -> void: edit.paid += 1000)
	var result := RoomMove.commit_move(_kit.grid, forged, _wallet, _history)
	assert_int(result.blocking_object_id).is_equal(_kit.statue)
	_assert_refused_unchanged(result, BuildResult.Reason.MOVE_CHANGED)


func test_the_commit_refuses_a_plan_that_leaves_a_piece_unrestored() -> void:
	_arm()
	var planned := RoomMove.plan(_kit.grid, _kit.room, TARGET, 0, _wallet)
	var kept: Array[BuildEdit] = []
	for edit in planned.edits:
		if not (edit.kind == BuildEdit.Kind.PLACE_OBJECT and edit.object_id == _kit.pot):
			kept.append(edit)
	assert_int(kept.size()).is_equal(planned.edits.size() - 1)
	planned.edits = kept
	var result := RoomMove.commit_move(_kit.grid, planned, _wallet, _history)
	_assert_refused_unchanged(result, BuildResult.Reason.MOVE_CHANGED)


func test_the_commit_refuses_a_piece_restored_outside_the_new_rect() -> void:
	_arm()
	var forged := _forged(_kit.bin, func(edit: BuildEdit) -> void: edit.cell = Vector2i(1, 10))
	var result := RoomMove.commit_move(_kit.grid, forged, _wallet, _history)
	_assert_refused_unchanged(result, BuildResult.Reason.MOVE_CHANGED)
