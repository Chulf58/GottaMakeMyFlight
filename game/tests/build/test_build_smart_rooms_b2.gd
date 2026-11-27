class_name TestBuildSmartRoomsB2
extends GdUnitTestSuite
## Regression tests for Build Experience Overhaul Slice B2:
## 1) Atomic composite commit in BuildTransaction (single net charge, single Undo,
##    rollback on refusal / insufficient funds / locked tool).
## 2) Door wall-replacement (DOOR, ENTRANCE, EXIT on room-boundary & shared walls,
##    security-divider & terminal-edge rules, net pricing, Undo wall restore).
## 3) Smart Room Drag (auto-floor, perimeter walls, shared border/door reuse,
##    "Needs entrance" note).
## 4) Boundary-aware RoomResize + Tool.NONE handle grab + shrink furniture safety.
## 5) Starter Room Kits (Starter Toilet & Starter Cafe placement, R rotation,
##    unlock gating, single Undo).

const NORTH := BuildGrid.Side.NORTH
const EAST := BuildGrid.Side.EAST
const SOUTH := BuildGrid.Side.SOUTH
const WEST := BuildGrid.Side.WEST

var _finances: Finances
var _mode: BuildMode


func before_test() -> void:
	_finances = Finances.new()
	add_child(_finances)
	_mode = BuildMode.new()
	_mode.grid_size = Vector2i(20, 20)
	_mode.finances = _finances
	add_child(_mode)
	_mode.set_process(false)
	var edits: Array[BuildEdit] = []
	for y in range(2, 12):
		for x in range(2, 12):
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	_mode.grid.apply_batch(edits)


func after_test() -> void:
	_mode.free()
	_finances.free()


func _at(cell: Vector2i) -> Vector3:
	return _mode.grid.cell_to_world(cell)


func _near_edge(cell: Vector2i, side: int) -> Vector3:
	var step := BuildGrid.SIDE_STEP[side]
	return _at(cell) + Vector3(step.x * 0.45, 0.0, step.y * 0.45)


func _drag_room(tool: BuildMode.Tool, rect: Rect2i) -> void:
	_mode.set_tool(tool)
	_mode.begin_area(_at(rect.position))
	_mode.move_area(_at(rect.end - Vector2i.ONE))
	_mode.finish_area()


func _set_balance(amount: int) -> void:
	assert_bool(_finances.wallet.from_snapshot({"balance": str(amount)})).is_true()


func test_composite_commit_charges_single_net_cost_and_rolls_back_atomically_on_failure() -> void:
	var before := _finances.wallet.balance
	# Composite: 2 floor tiles (50) + 1 plain wall (40) + invalid out-of-bounds wall -> must roll back!
	var bad_edits: Array[BuildEdit] = [
		BuildEdit.paint_floor(Vector2i(14, 14), BuildGrid.FLOOR_TILE, 1),
		BuildEdit.paint_floor(Vector2i(15, 14), BuildGrid.FLOOR_TILE, 1),
		BuildEdit.place_wall(Vector2i(14, 14), NORTH, BuildGrid.WallKind.PLAIN),
		BuildEdit.place_wall(Vector2i(99, 99), NORTH, BuildGrid.WallKind.PLAIN),
	]
	var refused := BuildTransaction.commit_composite(_mode.grid, bad_edits, _finances.wallet)
	assert_bool(refused.ok).is_false()
	assert_int(_mode.grid.floor_at(Vector2i(14, 14))).is_equal(BuildGrid.FLOOR_NONE)
	assert_bool(_mode.grid.has_wall(Vector2i(14, 14), NORTH)).is_false()
	assert_int(_finances.wallet.balance).is_equal(before)

	# Insufficient funds: net cost is 50 + 40 = 90; wallet has 89 -> refused with zero mutation.
	_set_balance(89)
	var good_edits: Array[BuildEdit] = [
		BuildEdit.paint_floor(Vector2i(14, 14), BuildGrid.FLOOR_TILE, 1),
		BuildEdit.paint_floor(Vector2i(15, 14), BuildGrid.FLOOR_TILE, 1),
		BuildEdit.place_wall(Vector2i(14, 14), NORTH, BuildGrid.WallKind.PLAIN),
	]
	var cant := BuildTransaction.commit_composite(_mode.grid, good_edits, _finances.wallet)
	assert_int(cant.reason).is_equal(BuildResult.Reason.CANT_AFFORD)
	assert_int(_mode.grid.floor_at(Vector2i(14, 14))).is_equal(BuildGrid.FLOOR_NONE)
	assert_int(_finances.wallet.balance).is_equal(89)


func _make_unlocks() -> BuildUnlocks:
	var unlocks := BuildUnlocks.new()
	unlocks.rating = auto_free(AirportRating.new())
	unlocks.passengers = auto_free(PassengerSim.new())
	unlocks.manual = true
	add_child(unlocks)
	return unlocks


func test_composite_commit_respects_build_unlocks_and_single_undo() -> void:
	var unlocks := _make_unlocks()
	var edits: Array[BuildEdit] = [
		BuildEdit.paint_floor(Vector2i(14, 14), BuildGrid.FLOOR_TILE, 1),
		BuildEdit.place_room(Rect2i(14, 14, 3, 3), &"cafe"),
	]
	var locked := BuildTransaction.commit_composite(
		_mode.grid, edits, _finances.wallet, unlocks, true
	)
	assert_int(locked.reason).is_equal(BuildResult.Reason.LOCKED)
	assert_int(_mode.grid.floor_at(Vector2i(14, 14))).is_equal(BuildGrid.FLOOR_NONE)
	assert_array(_mode.grid.room_ids()).is_empty()
	unlocks.free()


func test_door_replaces_shared_room_wall_with_net_price_and_undo_restores_paid_wall() -> void:
	_drag_room(BuildMode.Tool.TOILET_ROOM, Rect2i(3, 3, 3, 3))
	_drag_room(BuildMode.Tool.CAFE_ROOM, Rect2i(6, 3, 3, 3))
	# Shared wall at (5, 3..5) EAST == (6, 3..5) WEST should exist once as PLAIN paid 40.
	assert_int(_mode.grid.wall_kind(Vector2i(5, 4), EAST)).is_equal(BuildGrid.WallKind.PLAIN)
	assert_int(_mode.grid.wall_paid(Vector2i(5, 4), EAST)).is_equal(40)
	var balance := _finances.wallet.balance
	_mode.set_tool(BuildMode.Tool.DOOR)
	# Click from the neighboring room side (6, 4) WEST -> same shared edge!
	var res := _mode.apply_at(_near_edge(Vector2i(6, 4), WEST))
	assert_bool(res.ok).is_true()
	assert_int(_mode.grid.wall_kind(Vector2i(5, 4), EAST)).is_equal(BuildGrid.WallKind.DOOR)
	var expected_net := PriceTable.price_of_wall(BuildGrid.WallKind.DOOR) - PriceTable.refund_of(40)
	assert_int(_finances.wallet.balance).is_equal(balance - expected_net)
	# Single Ctrl+Z restores the PLAIN wall and its paid price and refunds net cost.
	assert_bool(_mode.undo().ok).is_true()
	assert_int(_mode.grid.wall_kind(Vector2i(5, 4), EAST)).is_equal(BuildGrid.WallKind.PLAIN)
	assert_int(_mode.grid.wall_paid(Vector2i(5, 4), EAST)).is_equal(40)
	assert_int(_finances.wallet.balance).is_equal(balance)


func test_entrance_and_exit_replace_room_boundary_terminal_wall_and_undo() -> void:
	# Room touches terminal north edge y = 2, which gets a PLAIN wall from Smart Room Drag.
	_drag_room(BuildMode.Tool.CAFE_ROOM, Rect2i(3, 2, 4, 4))
	assert_int(_mode.grid.wall_kind(Vector2i(4, 2), NORTH)).is_equal(BuildGrid.WallKind.PLAIN)
	var balance := _finances.wallet.balance
	_mode.set_tool(BuildMode.Tool.ENTRANCE)
	var placed := _mode.apply_at(_near_edge(Vector2i(4, 2), NORTH))
	assert_bool(placed.ok).is_true()
	assert_int(_mode.grid.wall_kind(Vector2i(4, 2), NORTH)).is_equal(BuildGrid.WallKind.NONE)
	assert_int(_finances.wallet.balance).is_equal(
		balance + PriceTable.refund_of(40) - PriceTable.price_of_object(&"entrance_door")
	)
	assert_bool(_mode.undo().ok).is_true()
	assert_int(_mode.grid.wall_kind(Vector2i(4, 2), NORTH)).is_equal(BuildGrid.WallKind.PLAIN)
	assert_int(_finances.wallet.balance).is_equal(balance)


func test_smart_room_drag_auto_floors_walls_reuses_shared_door_and_notes_needs_entrance() -> void:
	# Drag a 3x3 Toilet over bare ground (13..15, 13..15).
	var balance := _finances.wallet.balance
	_drag_room(BuildMode.Tool.TOILET_ROOM, Rect2i(13, 13, 3, 3))
	var room_id := _mode.grid.room_at(Vector2i(13, 13))
	assert_int(room_id).is_greater(0)
	for y in range(13, 16):
		for x in range(13, 16):
			assert_int(_mode.grid.floor_at(Vector2i(x, y))).is_equal(BuildGrid.FLOOR_TILE)
	for edge in RoomTool.perimeter_edges(Rect2i(13, 13, 3, 3)):
		assert_int(_mode.grid.wall_kind(edge[0], edge[1])).is_equal(BuildGrid.WallKind.PLAIN)
	var expected_cost := (
		9 * PriceTable.price_of_floor() + 12 * PriceTable.price_of_wall(BuildGrid.WallKind.PLAIN)
	)
	assert_int(_finances.wallet.balance).is_equal(balance - expected_cost)
	# Sealed room surfaces "Needs entrance".
	var status := RoomRules.status(_mode.grid, room_id)
	assert_array(Array(status.notes)).contains([RoomRules.NO_OPENING])
	# Single Ctrl+Z reverts floor, walls, room, and refunds completely.
	assert_bool(_mode.undo().ok).is_true()
	assert_int(_mode.grid.room_at(Vector2i(13, 13))).is_equal(0)
	assert_int(_mode.grid.floor_at(Vector2i(13, 13))).is_equal(BuildGrid.FLOOR_NONE)
	assert_int(_finances.wallet.balance).is_equal(balance)

	# Adjacent room reuses shared wall & door without overwriting or double-charging.
	_drag_room(BuildMode.Tool.CAFE_ROOM, Rect2i(3, 3, 3, 3))
	_mode.set_tool(BuildMode.Tool.DOOR)
	assert_bool(_mode.apply_at(_near_edge(Vector2i(5, 4), EAST)).ok).is_true()
	var before_second := _finances.wallet.balance
	_drag_room(BuildMode.Tool.KIOSK_ROOM, Rect2i(6, 3, 3, 3))
	# Shared west wall of Kiosk is (5, 3..5) EAST: 2 PLAIN + 1 DOOR already exist, so only 9 new walls!
	assert_int(_mode.grid.wall_kind(Vector2i(5, 4), EAST)).is_equal(BuildGrid.WallKind.DOOR)
	assert_int(_finances.wallet.balance).is_equal(
		before_second - 9 * PriceTable.price_of_wall(BuildGrid.WallKind.PLAIN)
	)


func test_boundary_aware_room_resize_moves_walls_fills_floor_preserves_shared_and_undoes() -> void:
	_drag_room(BuildMode.Tool.TOILET_ROOM, Rect2i(8, 3, 3, 3))
	var toilet_id := _mode.grid.room_at(Vector2i(8, 3))
	_drag_room(BuildMode.Tool.CAFE_ROOM, Rect2i(11, 3, 3, 3))
	var cafe_id := _mode.grid.room_at(Vector2i(11, 3))
	# Cafe east edge is at x=14 (bare ground at x=14..15!). Shared wall with Toilet is at x=11 WEST.
	assert_int(_mode.grid.floor_at(Vector2i(14, 3))).is_equal(BuildGrid.FLOOR_NONE)
	# Grab Cafe east handle in Tool.NONE and grow east to x=15 (onto bare ground!).
	_mode.set_tool(BuildMode.Tool.NONE)
	_mode.set_selected_room(cafe_id)
	var east_handle := RoomResize.handle_positions(_mode.grid, Rect2i(11, 3, 3, 3))[EAST]
	var expected_grow_cost := RoomResize.preview_price(_mode.grid, cafe_id, Rect2i(11, 3, 4, 3))
	assert_int(expected_grow_cost.x).is_greater(0)
	var balance_before_grow := _finances.wallet.balance
	assert_bool(_mode.begin_selected_resize(east_handle, cafe_id)).is_true()
	_mode.move_area(east_handle + Vector3(1.0, 0.0, 0.0))
	_mode.finish_area()
	assert_int(balance_before_grow - _finances.wallet.balance).is_equal(expected_grow_cost.x)
	assert_that(_mode.grid.get_room(cafe_id)["rect"]).is_equal(Rect2i(11, 3, 4, 3))
	assert_int(_mode.grid.floor_at(Vector2i(14, 4))).is_equal(BuildGrid.FLOOR_TILE)
	assert_bool(_mode.grid.has_wall(Vector2i(13, 4), EAST)).is_false()
	assert_int(_mode.grid.wall_kind(Vector2i(14, 4), EAST)).is_equal(BuildGrid.WallKind.PLAIN)
	# Undo restores Cafe to 3x3, old east wall, removes bare-ground floor, and restores balance.
	assert_bool(_mode.undo().ok).is_true()
	assert_that(_mode.grid.get_room(cafe_id)["rect"]).is_equal(Rect2i(11, 3, 3, 3))
	assert_int(_mode.grid.floor_at(Vector2i(14, 4))).is_equal(BuildGrid.FLOOR_NONE)
	assert_int(_mode.grid.wall_kind(Vector2i(13, 4), EAST)).is_equal(BuildGrid.WallKind.PLAIN)
	assert_int(_finances.wallet.balance).is_equal(balance_before_grow)

	# Shrink Cafe west edge from 11 to 12: shared wall with Toilet (10, 3..5) EAST must stay!
	var west_handle := RoomResize.handle_positions(_mode.grid, Rect2i(11, 3, 3, 3))[WEST]
	assert_bool(_mode.begin_selected_resize(west_handle, cafe_id)).is_true()
	_mode.move_area(west_handle + Vector3(1.0, 0.0, 0.0))
	_mode.finish_area()
	assert_that(_mode.grid.get_room(cafe_id)["rect"]).is_equal(Rect2i(12, 3, 2, 3))
	assert_int(_mode.grid.wall_kind(Vector2i(10, 4), EAST)).is_equal(BuildGrid.WallKind.PLAIN)
	assert_int(_mode.grid.wall_kind(Vector2i(12, 4), WEST)).is_equal(BuildGrid.WallKind.PLAIN)
	assert_that(_mode.grid.get_room(toilet_id)["rect"]).is_equal(Rect2i(8, 3, 3, 3))


func test_starter_toilet_and_cafe_kits_place_rotate_check_unlocks_and_single_undo() -> void:
	var balance := _finances.wallet.balance
	_mode.starter_kit.arm(&"toilet")
	_mode.starter_kit.rotate_turns()
	assert_int(_mode.starter_kit.turns).is_equal(1)
	var centre := Vector2i(5, 5)
	var kit_preview := _mode.starter_kit.preview_price_at(centre)
	assert_int(kit_preview.x).is_greater(0)
	var res := _mode.starter_kit.place_at(centre)
	assert_bool(res.ok).override_failure_message(res.reason_text()).is_true()
	assert_int(balance - _finances.wallet.balance).is_equal(kit_preview.x)
	var room_id := res.room_id
	assert_int(room_id).is_greater(0)
	var status := RoomRules.status(_mode.grid, room_id)
	assert_bool(status.ok).override_failure_message(str(status.notes)).is_true()
	# Undo removes room, walls, door, and furniture in one press and refunds exact spent cost.
	assert_bool(_mode.undo().ok).is_true()
	assert_array(_mode.grid.room_ids()).is_empty()
	assert_array(_mode.grid.object_ids()).is_empty()
	assert_int(_finances.wallet.balance).is_equal(balance)

	# Starter Cafe: blocked at Tier 1 when unlocks are required, allowed at Tier 2.
	var unlocks := _make_unlocks()
	_mode.unlocks = unlocks
	_mode.require_unlocks = true
	assert_bool(_mode.starter_kit.try_arm(&"cafe")).is_false()
	assert_str(_mode.starter_kit.status_text()).contains("Unlocks at")
	# Force arm and test commit_composite also refuses LOCKED:
	_mode.starter_kit.armed = &"cafe"
	var locked := _mode.starter_kit.place_at(Vector2i(6, 6))
	assert_int(locked.reason).is_equal(BuildResult.Reason.LOCKED)
	assert_array(_mode.grid.room_ids()).is_empty()

	# Unlock Tier 2 -> Starter Cafe arms, places, and is immediately Ready on walkable floor!
	unlocks.from_snapshot({"tier": 2, "made": 20, "shown": [], "seen": [], "firsts": []})
	assert_bool(_mode.starter_kit.try_arm(&"cafe")).is_true()
	var cafe_res := _mode.starter_kit.place_at(Vector2i(6, 6))
	assert_bool(cafe_res.ok).override_failure_message(cafe_res.reason_text()).is_true()
	var cafe_status := RoomRules.status(_mode.grid, cafe_res.room_id)
	assert_bool(cafe_status.ok).override_failure_message(str(cafe_status.notes)).is_true()
	assert_int(cafe_status.seats).is_equal(2)
	assert_bool(_mode.undo().ok).is_true()
	assert_array(_mode.grid.room_ids()).is_empty()
	assert_array(_mode.grid.object_ids()).is_empty()
	assert_int(_finances.wallet.balance).is_equal(balance)
	unlocks.free()


func test_composite_commit_enforces_staff_reach_and_rolls_back_on_seal() -> void:
	_mode.grid.apply(BuildEdit.place_object(&"entrance_door", Vector2i(2, 2), 2))
	var desk_res := _mode.grid.apply(BuildEdit.place_object(&"checkin_desk", Vector2i(5, 5), 0))
	assert_bool(desk_res.ok).is_true()
	# Dragging a sealed room around the desk's staff spot cuts it off from the entrance.
	var balance := _finances.wallet.balance
	var res := RoomTool.mark(_mode.grid, Rect2i(4, 3, 3, 2), &"kiosk", _finances.wallet)
	assert_bool(res.ok).is_false()
	assert_int(res.reason).is_equal(BuildResult.Reason.STAFF_SPOT)
	assert_array(_mode.grid.room_ids()).is_empty()
	assert_bool(_mode.grid.has_wall(Vector2i(4, 3), NORTH)).is_false()
	assert_int(_finances.wallet.balance).is_equal(balance)
