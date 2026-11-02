class_name TestRoomMove
extends GdUnitTestSuite
## Moving a built room with its furniture (decision
## move-rooms-technical-design-roommove-plan-of-existing-edits, parts 1 and 2;
## ruling moving-a-room-with-its-furniture-is-free-and-keeps-paid-pric): the
## pieces keep their ids, defs and paid, only bare new floor is charged, old
## and new rectangles may overlap, a quarter turn turns the pieces with the
## room, one undo puts it all back and refunds the floor, belts are reshaped
## around both rectangles, and a moved room saves and loads. The grid is
## RoomMoveKit's: a 4x3 cafe on columns 2 to 5, rows 2 to 4, floor on columns
## 1 to 12.

const START := 5000

var _kit: RoomMoveKit
var _wallet: Wallet
var _history: UndoStack


func before_test() -> void:
	_kit = RoomMoveKit.new()
	_wallet = Wallet.new(START)
	_history = UndoStack.new()
	_history.watch(_kit.grid, _wallet)


func _move(centre: Vector2i, turns := 0) -> BuildResult:
	return RoomMove.commit(_kit.grid, _kit.room, centre, turns, _wallet, _history)


func _ids() -> Array[int]:
	return [_kit.bin, _kit.statue, _kit.pot]


func test_a_move_on_laid_floor_is_free_and_keeps_ids_defs_and_paid() -> void:
	var before := {}
	for id in _ids():
		before[id] = _kit.record(id)
	var objects_before := _kit.grid.object_ids().size()
	# Centre (9, 7): the cafe goes to columns 8 to 11, rows 6 to 8, all floored.
	var result := _move(Vector2i(9, 7))
	print("move: ok=%s reason=%s balance=%d" % [result.ok, result.reason, _wallet.balance])
	assert_bool(result.ok).is_true()
	assert_int(result.room_id).is_equal(_kit.room)
	assert_that(_kit.rect()).is_equal(Rect2i(8, 6, 4, 3))
	assert_int(_wallet.balance).is_equal(START)
	assert_int(_kit.grid.object_ids().size()).is_equal(objects_before)
	for id in _ids():
		var now := _kit.record(id)
		var was: Dictionary = before[id]
		print("piece %d: %s -> %s" % [id, was, now])
		assert_str(String(now["def"])).is_equal(String(was["def"]))
		assert_int(now["paid"]).is_equal(was["paid"])
		assert_int(now["facing"]).is_equal(was["facing"])
		assert_that(now["anchor"]).is_equal((was["anchor"] as Vector2i) + Vector2i(6, 4))
		assert_int(_kit.grid.object_at(was["anchor"])).is_equal(0)
	assert_int(_kit.record(_kit.statue)["paid"]).is_equal(RoomMoveKit.STATUE_PAID)
	# The old cells keep their floor and leave the room.
	assert_int(_kit.grid.floor_at(Vector2i(2, 2))).is_equal(BuildGrid.FLOOR_TILE)
	assert_int(_kit.grid.room_at(Vector2i(2, 2))).is_equal(0)
	assert_int(_history.size()).is_equal(1)


func test_only_new_cells_with_no_floor_are_charged_at_the_floor_price() -> void:
	# Centre (12, 7): columns 11 to 14, rows 6 to 8; columns 13 and 14 are bare.
	var planned := RoomMove.plan(_kit.grid, _kit.room, Vector2i(12, 7), 0, _wallet)
	var bare := 6
	print("plan: ok=%s cost=%d" % [planned.result.ok, planned.cost])
	assert_bool(planned.result.ok).is_true()
	assert_int(planned.cost).is_equal(bare * PriceTable.FLOOR_PRICE)
	var result := RoomMove.commit_move(_kit.grid, planned, _wallet, _history)
	print("commit: ok=%s balance=%d" % [result.ok, _wallet.balance])
	assert_bool(result.ok).is_true()
	assert_int(_wallet.balance).is_equal(START - bare * PriceTable.FLOOR_PRICE)
	for cell in [Vector2i(13, 6), Vector2i(14, 8)]:
		assert_int(_kit.grid.floor_at(cell)).is_equal(BuildGrid.FLOOR_TILE)
		assert_int(_kit.grid.zone_at(cell)).is_equal(RoomMoveKit.ZONE)
		assert_int(_kit.grid.floor_paid(cell)).is_equal(PriceTable.FLOOR_PRICE)
	# A floored cell of the new rectangle was not repainted or charged.
	assert_int(_kit.grid.floor_paid(Vector2i(11, 6))).is_equal(0)


func test_a_move_onto_its_own_cells_works_when_old_and_new_overlap() -> void:
	var anchor_before: Vector2i = _kit.record(_kit.pot)["anchor"]
	# Centre (4, 3): one column east, columns 3 to 6, overlapping columns 3 to 5.
	var result := _move(Vector2i(4, 3))
	print("overlap move: ok=%s reason=%s" % [result.ok, result.reason_text()])
	assert_bool(result.ok).is_true()
	assert_that(_kit.rect()).is_equal(Rect2i(3, 2, 4, 3))
	assert_that(_kit.record(_kit.pot)["anchor"]).is_equal(anchor_before + Vector2i(1, 0))
	assert_that(_kit.record(_kit.bin)["anchor"]).is_equal(Vector2i(3, 2))
	assert_int(_kit.grid.room_at(Vector2i(2, 2))).is_equal(0)
	assert_int(_kit.grid.room_at(Vector2i(6, 4))).is_equal(_kit.room)
	assert_int(_wallet.balance).is_equal(START)


func test_a_quarter_turn_turns_the_room_and_its_pieces_clockwise() -> void:
	# A 4x3 room turned once is 3x4: centre (9, 6) gives columns 8 to 10, rows 5 to 8.
	var result := _move(Vector2i(9, 6), 1)
	print("turned move: ok=%s reason=%s" % [result.ok, result.reason_text()])
	assert_bool(result.ok).is_true()
	var turned := Rect2i(8, 5, 3, 4)
	assert_that(_kit.rect()).is_equal(turned)
	# The north-west corner cell turns to the north-east corner.
	assert_that(_kit.record(_kit.bin)["anchor"]).is_equal(Vector2i(10, 5))
	for id in _ids():
		var record := _kit.record(id)
		var def := BuildCatalog.get_def(record["def"])
		var cells := def.footprint(record["anchor"], record["facing"])
		print("piece %d at %s facing %d: %s" % [id, record["anchor"], record["facing"], cells])
		assert_int(record["facing"]).is_equal(1)
		for cell in cells:
			assert_bool(turned.has_point(cell)).is_true()
			assert_int(_kit.grid.object_at(cell)).is_equal(id)


func test_one_undo_puts_back_rect_ids_and_prices_and_refunds_the_floor() -> void:
	var before := _kit.grid.to_snapshot()
	assert_bool(_move(Vector2i(12, 7)).ok).is_true()
	var spent := START - _wallet.balance
	print("spent on floor: %d, steps: %d" % [spent, _history.size()])
	assert_int(spent).is_equal(6 * PriceTable.FLOOR_PRICE)
	assert_int(_history.size()).is_equal(1)
	var undone := _history.undo()
	print("undo: ok=%s reason=%s balance=%d" % [undone.ok, undone.reason, _wallet.balance])
	assert_bool(undone.ok).is_true()
	assert_int(_wallet.balance).is_equal(START)
	assert_int(_history.size()).is_equal(0)
	assert_that(_kit.rect()).is_equal(RoomMoveKit.CAFE)
	assert_that(_kit.record(_kit.pot)["anchor"]).is_equal(Vector2i(4, 3))
	assert_int(_kit.record(_kit.pot)["paid"]).is_equal(RoomMoveKit.POT_PAID)
	assert_int(_kit.grid.floor_at(Vector2i(13, 6))).is_equal(BuildGrid.FLOOR_NONE)
	assert_that(_kit.grid.to_snapshot()).is_equal(before)


## Ruling build-mode-pauses-the-game-while-a-build-tray-is-open-closin: once
## build mode ends and clears the history, the move cannot be undone, and a
## moved piece sells back at the refund share of what it was bought for, not
## at full price.
func test_after_the_history_clears_a_moved_piece_refunds_only_its_share() -> void:
	assert_bool(_move(Vector2i(9, 7)).ok).is_true()
	_history.clear()
	assert_object(_history.undo()).is_null()
	assert_that(_kit.rect()).is_equal(Rect2i(8, 6, 4, 3))
	var before := _wallet.balance
	var sell: Array[BuildEdit] = [BuildEdit.remove_object(_kit.pot)]
	assert_bool(BuildTransaction.commit_plan(_kit.grid, sell, _wallet).ok).is_true()
	print("pot sold back for %d" % (_wallet.balance - before))
	assert_int(_wallet.balance - before).is_equal(PriceTable.refund_of(RoomMoveKit.POT_PAID))
	assert_int(_wallet.balance - before).is_less(RoomMoveKit.POT_PAID)


func test_belts_are_reshaped_around_the_old_and_the_new_rect() -> void:
	var grid := _kit.grid
	# A belt inside the cafe's west edge, an L outside it, and a lone belt just
	# west of where the cafe lands, running north-south (facing 0) with no
	# links. Shaped once, as the Belt tool leaves them.
	var inside := Vector2i(2, 3)
	var bend := Vector2i(1, 3)
	var lone := Vector2i(7, 7)
	for cell in [inside, bend, Vector2i(1, 2)]:
		assert_int(_kit.place(BeltShaper.BELT, cell, 1, 20)).is_greater(0)
	assert_int(_kit.place(BeltShaper.BELT, lone, 0, 20)).is_greater(0)
	var everywhere := _all_cells()
	assert_bool(grid.apply_sequence(BeltShaper.reshape_edits(grid, everywhere), Callable()).ok)
	assert_str(String(grid.get_object(grid.object_at(bend))["def"])).is_equal(
		String(BeltShaper.CORNER)
	)
	var moving := grid.object_at(inside)
	# Centre (9, 7): columns 8 to 11; the inside belt lands on (8, 7) beside the lone one.
	var planned := RoomMove.plan(grid, _kit.room, Vector2i(9, 7), 0, _wallet)
	var reshaped: Array[Vector2i] = []
	for edit in planned.edits:
		if edit.kind == BuildEdit.Kind.RESHAPE_BELT:
			reshaped.append(edit.cell)
	print("planned reshapes at %s" % [reshaped])
	# The bend loses its east link at the old rect; the lone belt gains one at the new.
	assert_bool(reshaped.has(bend)).is_true()
	assert_bool(reshaped.has(lone)).is_true()
	assert_bool(RoomMove.commit_move(grid, planned, _wallet, _history).ok).is_true()
	assert_that(grid.get_object(moving)["anchor"]).is_equal(Vector2i(8, 7))
	assert_str(String(grid.get_object(grid.object_at(bend))["def"])).is_equal(
		String(BeltShaper.BELT)
	)
	assert_int(grid.get_object(grid.object_at(lone))["facing"]).is_equal(1)
	var left := BeltShaper.reshape_edits(grid, everywhere)
	print("belts still out of shape: %d" % left.size())
	assert_int(left.size()).is_equal(0)


func test_a_moved_room_saves_and_loads_with_its_ids_and_prices() -> void:
	assert_bool(_move(Vector2i(12, 7), 1).ok).is_true()
	var loaded := BuildGrid.new(RoomMoveKit.SIZE)
	assert_bool(loaded.from_snapshot(_kit.grid.to_snapshot())).is_true()
	print("loaded room: %s" % [loaded.get_room(_kit.room)])
	assert_that(loaded.get_room(_kit.room)["rect"]).is_equal(_kit.rect())
	for id in _ids():
		assert_that(loaded.get_object(id)).is_equal(_kit.record(id))
	assert_int(loaded.floor_paid(Vector2i(13, 6))).is_equal(PriceTable.FLOOR_PRICE)


func _all_cells() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in RoomMoveKit.SIZE.y:
		for x in RoomMoveKit.SIZE.x:
			out.append(Vector2i(x, y))
	return out
