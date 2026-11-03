class_name TestRoomMoveIntegrity
extends GdUnitTestSuite
## RoomMove.commit_move() applies only the move it plans again from the grid
## as it stands (decision
## move-rooms-technical-design-roommove-plan-of-existing-edits, part 2; Sol
## review of 0d6888c): a plan that differs from that in any edit is refused
## with MOVE_CHANGED, and the grid, the wallet and the undo history stay as
## they were, the earlier undo step still undoing. Each forged plan here is
## one the grid itself would accept, so only the commit's own check stops it.
## The grid is RoomMoveKit's: a 4x3 cafe on columns 2 to 5, rows 2 to 4.

const START := 5000
const EARLIER := Vector2i(20, 12)
## Centre (9, 7): columns 8 to 11, rows 6 to 8, all floored. The bin lands on
## (8, 6), the statue on (9, 8), the pot on (10, 7) to (11, 8).
const TARGET := Vector2i(9, 7)
## Centre (12, 7): columns 11 to 14; columns 13 and 14 need floor.
const PART_BARE := Vector2i(12, 7)

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
	_snapshot = _kit.grid.to_snapshot()
	_balance = _wallet.balance


func _plan(centre: Vector2i) -> RoomMove:
	var planned := RoomMove.plan(_kit.grid, _kit.room, centre, 0, _wallet)
	assert_bool(planned.result.ok).is_true()
	return planned


## Commits `planned` and checks it was refused with MOVE_CHANGED and changed
## nothing, the earlier undo step still undoing.
func _assert_changed_refused(planned: RoomMove) -> BuildResult:
	var result := RoomMove.commit_move(_kit.grid, planned, _wallet, _history)
	print(
		(
			"refused: ok=%s reason=%s blocker=%d"
			% [result.ok, result.reason, result.blocking_object_id]
		)
	)
	assert_bool(result.ok).is_false()
	assert_int(result.reason).is_equal(BuildResult.Reason.MOVE_CHANGED)
	assert_that(_kit.grid.to_snapshot()).is_equal(_snapshot)
	assert_int(_wallet.balance).is_equal(_balance)
	assert_int(_history.size()).is_equal(1)
	assert_bool(_history.undo().ok).is_true()
	assert_int(_kit.grid.floor_at(EARLIER)).is_equal(BuildGrid.FLOOR_NONE)
	return result


## The first edit of `planned` of `kind` that names object `id` (0: any).
func _edit(planned: RoomMove, kind: BuildEdit.Kind, id := 0) -> BuildEdit:
	for edit in planned.edits:
		if edit.kind == kind and (id == 0 or edit.object_id == id):
			return edit
	return null


func test_a_piece_set_down_on_another_cell_inside_the_room_is_refused() -> void:
	_arm()
	var planned := _plan(TARGET)
	var bin := _edit(planned, BuildEdit.Kind.PLACE_OBJECT, _kit.bin)
	# (9, 6) is free and inside the new rect, so the grid would take it.
	bin.cell = Vector2i(9, 6)
	var result := _assert_changed_refused(planned)
	assert_int(result.blocking_object_id).is_equal(_kit.bin)


func test_a_piece_set_down_with_another_facing_is_refused() -> void:
	_arm()
	var planned := _plan(TARGET)
	_edit(planned, BuildEdit.Kind.PLACE_OBJECT, _kit.bin).facing = 2
	var result := _assert_changed_refused(planned)
	assert_int(result.blocking_object_id).is_equal(_kit.bin)


func test_a_plan_made_before_the_room_was_resized_is_refused() -> void:
	var planned := _plan(TARGET)
	var grown := BuildEdit.resize_room(_kit.room, Rect2i(2, 2, 4, 4))
	assert_bool(_kit.grid.apply(grown).ok).is_true()
	_arm()
	_assert_changed_refused(planned)


func test_a_plan_whose_new_rect_is_not_the_rooms_size_is_refused() -> void:
	_arm()
	var planned := _plan(TARGET)
	planned.to_rect = Rect2i(planned.to_rect.position, Vector2i(5, 3))
	_edit(planned, BuildEdit.Kind.RESIZE_ROOM).room_size = Vector2i(5, 3)
	_assert_changed_refused(planned)


func test_new_floor_of_another_zone_is_refused() -> void:
	_arm()
	var planned := _plan(PART_BARE)
	_edit(planned, BuildEdit.Kind.PAINT_FLOOR).zone_id = RoomMoveKit.ZONE + 1
	_assert_changed_refused(planned)


func test_an_extra_floor_edit_is_refused() -> void:
	_arm()
	var planned := _plan(PART_BARE)
	var at := planned.edits.find(_edit(planned, BuildEdit.Kind.RESIZE_ROOM))
	planned.edits.insert(at, BuildEdit.paint_floor(Vector2i(20, 3), BuildGrid.FLOOR_TILE, 1))
	_assert_changed_refused(planned)


func test_a_piece_removed_twice_is_refused() -> void:
	_arm()
	var planned := _plan(TARGET)
	planned.edits.insert(1, BuildEdit.remove_object(_kit.bin))
	var result := _assert_changed_refused(planned)
	assert_int(result.blocking_object_id).is_equal(_kit.bin)


func test_a_piece_from_outside_the_room_is_refused() -> void:
	var outsider := _kit.place(&"statue_indoor", Vector2i(10, 1), 0, 500)
	assert_int(outsider).is_greater(0)
	_arm()
	var planned := _plan(TARGET)
	planned.edits.insert(0, BuildEdit.remove_object(outsider))
	var carried := BuildEdit.place_object(&"statue_indoor", Vector2i(9, 6), 0)
	carried.object_id = outsider
	carried.paid = 500
	planned.edits.append(carried)
	var result := _assert_changed_refused(planned)
	assert_int(result.blocking_object_id).is_equal(outsider)


## Control: the plan as made is accepted, so each refusal above is the forgery's.
func test_the_unchanged_plan_is_accepted() -> void:
	_arm()
	var result := RoomMove.commit_move(_kit.grid, _plan(PART_BARE), _wallet, _history)
	print("unchanged plan: ok=%s reason=%s" % [result.ok, result.reason_text()])
	assert_bool(result.ok).is_true()
	assert_int(_history.size()).is_equal(2)
