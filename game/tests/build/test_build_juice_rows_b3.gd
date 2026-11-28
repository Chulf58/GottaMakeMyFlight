class_name TestBuildJuiceRowsB3
extends GdUnitTestSuite
## Regression tests for Build Experience Overhaul Slice B3:
## 1) Repeatable item drag-paint rows (rotated footprint + approach spacing,
##    partial-ok preview/commit, wallet cap, single-click fallback, 1-step Undo).
## 2) Alt+left-click & crisp middle-click Eyedropper (object + facing, wall,
##    room, floor, room-context focus, BuildUnlocks gating, drag-pan guard).
## 3) Exhaustive Furnished Starter Room Kits for every RoomTypes.ids() at all 4
##    rotations, Ready status, exact cost, BuildUnlocks, single Undo, POT check.
## 4) Presentation-only BuildJuice (explicit player_committed only; zero triggers
##    on grid.apply / SaveGame load / ReferenceTerminal / undo; self-freeing
##    pops/puffs/tweens with 0 orphans).

const NORTH := BuildGrid.Side.NORTH
const EAST := BuildGrid.Side.EAST
const SOUTH := BuildGrid.Side.SOUTH
const WEST := BuildGrid.Side.WEST

var _port: SubViewport
var _finances: Finances
var _mode: BuildMode


func before_test() -> void:
	_port = SubViewport.new()
	_port.size = Vector2i(1280, 720)
	add_child(_port)
	_finances = Finances.new()
	_finances.wallet.credit(100000, Wallet.Category.FEES)
	_port.add_child(_finances)
	_mode = BuildMode.new()
	_mode.grid_size = Vector2i(24, 24)
	_mode.initial_tool = BuildMode.Tool.NONE
	_mode.finances = _finances
	_port.add_child(_mode)
	_mode.set_process(false)
	var edits: Array[BuildEdit] = []
	for y in range(2, 20):
		for x in range(2, 20):
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	_mode.grid.apply_batch(edits)


func after_test() -> void:
	_port.free()


func _at(cell: Vector2i) -> Vector3:
	return _mode.grid.cell_to_world(cell)


func _set_balance(amount: int) -> void:
	assert_bool(_finances.wallet.from_snapshot({"balance": str(amount)})).is_true()


func _make_unlocks() -> BuildUnlocks:
	var unlocks := BuildUnlocks.new()
	unlocks.rating = auto_free(AirportRating.new())
	unlocks.passengers = auto_free(PassengerSim.new())
	unlocks.manual = true
	_port.add_child(unlocks)
	return unlocks


func _make_menu() -> BuildMenu:
	var menu := BuildMenu.new()
	menu.build_mode = _mode
	_port.add_child(menu)
	return menu


func test_item_row_step_spacing_respects_rotated_footprint_and_approach() -> void:
	# toilet_stall is 1x2 with interaction_offset (0, 2):
	# facing 0 (south): X step = 1, Y step = 3 (footprint 2 + interaction 1)
	assert_int(ItemRowDrag.step_spacing(&"toilet_stall", 0, Vector2i(1, 0))).is_equal(1)
	assert_int(ItemRowDrag.step_spacing(&"toilet_stall", 0, Vector2i(0, 1))).is_equal(3)
	# facing 1 (90 deg): rotated footprint (-1,0)..(0,0), interaction (-2,0) -> X step = 3, Y step = 1
	assert_int(ItemRowDrag.step_spacing(&"toilet_stall", 1, Vector2i(1, 0))).is_equal(3)
	assert_int(ItemRowDrag.step_spacing(&"toilet_stall", 1, Vector2i(0, 1))).is_equal(1)
	# cafe_table is 3x1 with seat approaches at y+1: X step = 3, Y step = 2
	assert_int(ItemRowDrag.step_spacing(&"cafe_table", 0, Vector2i(1, 0))).is_equal(3)
	assert_int(ItemRowDrag.step_spacing(&"cafe_table", 0, Vector2i(0, 1))).is_equal(2)
	# restaurant_booth is 2x3 with end approaches (-1,y) and (2,y): X step = 3, Y step = 3
	assert_int(ItemRowDrag.step_spacing(&"restaurant_booth", 0, Vector2i(1, 0))).is_equal(3)
	assert_int(ItemRowDrag.step_spacing(&"restaurant_booth", 0, Vector2i(0, 1))).is_equal(3)
	# seat_row is 3x1: facing 0 -> X=3, Y=1; facing 1 -> X=1, Y=3
	assert_int(ItemRowDrag.step_spacing(&"seat_row", 0, Vector2i(1, 0))).is_equal(3)
	assert_int(ItemRowDrag.step_spacing(&"seat_row", 1, Vector2i(0, 1))).is_equal(3)


func test_item_row_drag_partial_ok_preview_wallet_cap_and_single_undo() -> void:
	# Place a blocking bin at (5, 4) so dragging benches/bins across x=3..9 skips (5, 4).
	(
		assert_bool(_mode.grid.apply(BuildEdit.place_object(&"trash_can", Vector2i(5, 4), 0)).ok)
		. is_true()
	)
	_mode.set_tool(BuildMode.Tool.BIN)
	_mode.facing = 0
	var price := PriceTable.price_of_object(&"trash_can")
	# Wallet holds enough for 4 bins (out of 6 unblocked cells: 3,4,6,7,8,9 -> stops at 4!).
	_set_balance(price * 4 + 10)
	var start_bal := _finances.wallet.balance

	_mode.begin_item_row(_at(Vector2i(3, 4)))
	_mode.move_item_row(_at(Vector2i(9, 4)))
	var preview := ItemRowDrag.preview(
		_mode.grid, _mode._item_row.edits(), _mode.check, _finances.wallet
	)
	assert_int(preview.edits.size()).is_equal(7)
	# Index 0 (x=3) ok, 1 (x=4) ok, 2 (x=5 blocked) false, 3 (x=6) ok, 4 (x=7) ok, 5..6 false (afford)
	assert_array(preview.valid).is_equal([true, true, false, true, true, false, false])
	assert_int(preview.cost).is_equal(price * 4)

	var outcome := _mode.finish_item_row()
	assert_object(outcome).is_not_null()
	assert_int(outcome.placed).is_equal(4)
	assert_int(outcome.skipped).is_equal(3)
	assert_int(start_bal - _finances.wallet.balance).is_equal(price * 4)
	assert_int(_finances.wallet.balance).is_equal(10)
	for x in [3, 4, 6, 7]:
		assert_int(_mode.grid.object_at(Vector2i(x, 4))).is_greater(0)
	assert_int(_mode.grid.object_at(Vector2i(8, 4))).is_equal(0)

	# Single Ctrl+Z reverts the entire painted row and refunds exact total.
	assert_bool(_mode.undo().ok).is_true()
	assert_int(_finances.wallet.balance).is_equal(start_bal)
	for x in [3, 4, 6, 7]:
		assert_int(_mode.grid.object_at(Vector2i(x, 4))).is_equal(0)


func test_item_row_single_click_places_one_item_and_rotates_row_step() -> void:
	var start_bal := _finances.wallet.balance
	_mode.set_tool(BuildMode.Tool.BIN)
	_mode.begin_item_row(_at(Vector2i(4, 4)))
	var click_out := _mode.finish_item_row()
	assert_object(click_out).is_null()
	assert_int(_mode.grid.object_at(Vector2i(4, 4))).is_greater(0)
	assert_int(start_bal - _finances.wallet.balance).is_equal(
		PriceTable.price_of_object(&"trash_can")
	)

	# Drag a rotated row of toilet stalls (facing 1, step 3 along X: x=6 and x=9).
	_mode.set_tool(BuildMode.Tool.TOILET_STALL)
	_mode.facing = 1
	_mode.begin_item_row(_at(Vector2i(6, 8)))
	_mode.move_item_row(_at(Vector2i(10, 8)))
	var row_out := _mode.finish_item_row()
	assert_int(row_out.placed).is_equal(2)
	assert_int(_mode.grid.object_at(Vector2i(6, 8))).is_greater(0)
	assert_int(_mode.grid.object_at(Vector2i(9, 8))).is_greater(0)


func test_eyedropper_picks_objects_with_facing_walls_rooms_floor_and_unlocks() -> void:
	var menu := _make_menu()
	var place_rest := BuildEdit.place_room(Rect2i(3, 3, 5, 5), &"restaurant")
	assert_bool(_mode.grid.apply(place_rest).ok).is_true()
	var rest_id := _mode.grid.room_at(Vector2i(3, 3))
	var place_cnt := BuildEdit.place_object(&"cafe_counter", Vector2i(5, 5), 2)
	assert_bool(_mode.grid.apply(place_cnt).ok).is_true()
	var place_stall := BuildEdit.place_object(&"toilet_stall", Vector2i(12, 5), 3)
	assert_bool(_mode.grid.apply(place_stall).ok).is_true()
	var place_glass := BuildEdit.place_wall(Vector2i(10, 4), NORTH, BuildGrid.WallKind.GLASS)
	assert_bool(_mode.grid.apply(place_glass).ok).is_true()

	# Picking cafe_counter inside restaurant opens restaurant tray + copies facing!
	assert_bool(_mode.pick_eyedropper_at(_at(Vector2i(5, 5)))).is_true()
	assert_int(_mode.tool).is_equal(BuildMode.Tool.COUNTER)
	assert_int(_mode.facing).is_equal(2)
	assert_bool(menu.is_room_context()).is_true()
	assert_str(String(menu.room_context_type())).is_equal("restaurant")
	assert_int(menu.room_context_id()).is_equal(rest_id)

	# Picking toilet_stall opens toilet Contextual Room-Items tray + copies facing 3!
	assert_bool(_mode.pick_eyedropper_at(_at(Vector2i(12, 5)))).is_true()
	assert_int(_mode.tool).is_equal(BuildMode.Tool.TOILET_STALL)
	assert_int(_mode.facing).is_equal(3)
	assert_bool(menu.is_room_context()).is_true()
	assert_str(String(menu.room_context_type())).is_equal("toilet")

	# Picking glass wall picks Tool.GLASS.
	var glass_pt := _at(Vector2i(10, 4)) + Vector3(0.0, 0.0, -0.45)
	assert_bool(_mode.pick_eyedropper_at(glass_pt)).is_true()
	assert_int(_mode.tool).is_equal(BuildMode.Tool.GLASS)

	# Picking restaurant room floor picks Tool.RESTAURANT_ROOM.
	assert_bool(_mode.pick_eyedropper_at(_at(Vector2i(3, 3)))).is_true()
	assert_int(_mode.tool).is_equal(BuildMode.Tool.RESTAURANT_ROOM)

	# Picking plain floor picks Tool.FLOOR.
	assert_bool(_mode.pick_eyedropper_at(_at(Vector2i(15, 15)))).is_true()
	assert_int(_mode.tool).is_equal(BuildMode.Tool.FLOOR)

	# Unlocks check: Tier 1 cannot eyedrop Tier 2 cafe_table -> refused via set_tool().
	var place_tbl := BuildEdit.place_object(&"cafe_table", Vector2i(14, 10), 1)
	assert_bool(_mode.grid.apply(place_tbl).ok).is_true()
	var unlocks := _make_unlocks()
	_mode.unlocks = unlocks
	_mode.require_unlocks = true
	_mode.set_tool(BuildMode.Tool.FLOOR)
	assert_bool(_mode.pick_eyedropper_at(_at(Vector2i(14, 10)))).is_true()
	assert_int(_mode.tool).is_equal(BuildMode.Tool.FLOOR)
	assert_bool(_mode.status_is_refusal).is_true()
	assert_str(_mode.status_text()).contains("Unlocks at")

	# Middle-mouse drag (>= CLICK_SLOP_PX) must NOT trigger Eyedropper; crisp middle-click DOES.
	_mode.require_unlocks = false
	_mode.set_tool(BuildMode.Tool.NONE)
	_mode.pointer_override = Vector2(100, 100)
	var mid_down := InputEventMouseButton.new()
	mid_down.button_index = MOUSE_BUTTON_MIDDLE
	mid_down.pressed = true
	mid_down.position = Vector2(100, 100)
	_mode._unhandled_input(mid_down)
	var mid_drag_up := InputEventMouseButton.new()
	mid_drag_up.button_index = MOUSE_BUTTON_MIDDLE
	mid_drag_up.pressed = false
	mid_drag_up.position = Vector2(125, 100)
	_mode._unhandled_input(mid_drag_up)
	assert_int(_mode.tool).is_equal(BuildMode.Tool.NONE)
	_mode.pointer_override = Vector2(-1, -1)


func test_every_room_type_has_valid_rotatable_starter_kit_and_pot_entry() -> void:
	var pot := PotEntries.parse(FileAccess.get_file_as_string("res://locale/messages.pot"))
	var room_ids := RoomTypes.ids()
	assert_int(room_ids.size()).is_equal(14)
	var centre := Vector2i(10, 10)
	var bag_centres := {0: Vector2i(10, 3), 1: Vector2i(18, 10), 3: Vector2i(3, 10)}
	for room_type: StringName in room_ids:
		(
			assert_bool(StarterRoomKits.has_kit(room_type))
			. override_failure_message("Missing kit for %s" % room_type)
			. is_true()
		)
		var kit_name := StarterRoomKits.display_name(room_type)
		(
			assert_int(PotEntries.complete(pot, "build menu", kit_name))
			. override_failure_message("Missing POT entry for %s" % kit_name)
			. is_equal(1)
		)
		for turns in 4:
			if room_type == &"bag_room" and turns == 2:
				_mode.starter_kit.arm(room_type)
				_mode.starter_kit.turns = turns
				var south_refusal := _mode.starter_kit.place_at(Vector2i(10, 18))
				assert_bool(south_refusal.ok).is_false()
				assert_int(south_refusal.reason).is_equal(BuildResult.Reason.KIT_NEEDS_APRON_WALL)
				continue
			var kit_centre: Vector2i = bag_centres[turns] if room_type == &"bag_room" else centre
			var before_bal := _finances.wallet.balance
			_mode.starter_kit.arm(room_type)
			_mode.starter_kit.turns = turns
			var preview := _mode.starter_kit.preview_price_at(kit_centre)
			assert_int(preview.x).is_greater(0)
			var res := _mode.starter_kit.place_at(kit_centre)
			var tag := "%s turn=%d" % [room_type, turns]
			(
				assert_bool(res.ok)
				. override_failure_message("%s failed: %s" % [tag, res.reason_text()])
				. is_true()
			)
			(
				assert_int(before_bal - _finances.wallet.balance)
				. override_failure_message(tag)
				. is_equal(preview.x)
			)
			var status := RoomRules.status(_mode.grid, res.room_id)
			assert_object(status).is_not_null()
			(
				assert_bool(status.ok)
				. override_failure_message("%s not Ready: %s" % [tag, str(status.notes)])
				. is_true()
			)
			assert_str(status.headline()).is_equal(RoomRules.READY)
			assert_bool(_mode.undo().ok).override_failure_message(tag).is_true()
			assert_array(_mode.grid.room_ids()).is_empty()
			assert_array(_mode.grid.object_ids()).is_empty()
			assert_int(_finances.wallet.balance).is_equal(before_bal)

	# BuildUnlocks gating check on a Tier 4 kit (duty_free).
	var unlocks := _make_unlocks()
	_mode.unlocks = unlocks
	_mode.require_unlocks = true
	assert_bool(_mode.starter_kit.try_arm(&"duty_free")).is_false()
	assert_str(_mode.starter_kit.status_text()).contains("Unlocks at")


func test_build_juice_fires_only_on_player_commits_and_cleans_up_zero_orphans() -> void:
	var juice := _mode.get_node("BuildJuice") as BuildJuice
	assert_object(juice).is_not_null()
	var events: Array[Dictionary] = []
	_mode.player_committed.connect(func(info: Dictionary) -> void: events.append(info))

	# Direct grid edits, ReferenceTerminal, and SaveGame loads MUST NOT trigger BuildJuice!
	var bin_edit := BuildEdit.place_object(&"trash_can", Vector2i(3, 3), 0)
	assert_bool(_mode.grid.apply(bin_edit).ok).is_true()
	assert_int(juice.commit_count).is_equal(0)
	assert_int(juice.active_pop_count()).is_equal(0)
	assert_int(juice.active_puff_count()).is_equal(0)

	var snap := _mode.grid.to_snapshot()
	assert_bool(_mode.load_snapshot(snap)).is_true()
	assert_int(juice.commit_count).is_equal(0)

	var ref_grid := BuildGrid.new(Vector2i(40, 26))
	assert_bool(ReferenceTerminal.build(ref_grid)).is_true()
	assert_int(juice.commit_count).is_equal(0)

	# Player placement via BuildMode triggers BuildJuice pop-in, cost pop, and dust puff.
	_mode.set_tool(BuildMode.Tool.BIN)
	var placed := _mode.apply_at(_at(Vector2i(6, 6)))
	assert_bool(placed.ok).is_true()
	assert_int(juice.commit_count).is_equal(1)
	assert_int(events.size()).is_equal(1)
	assert_int(int(events[0]["net_cost"])).is_equal(PriceTable.price_of_object(&"trash_can"))
	assert_int(juice.active_pop_count()).is_equal(1)
	assert_int(juice.active_puff_count()).is_equal(1)
	var obj_node := _mode.object_node(placed.object_id)
	assert_object(obj_node).is_not_null()
	assert_bool(obj_node.scale.x < 1.0).is_true()

	# Undo does NOT trigger BuildJuice.
	assert_bool(_mode.undo().ok).is_true()
	assert_int(juice.commit_count).is_equal(1)

	# Advancing past duration frees all pop and puff nodes cleanly.
	juice.advance(1.0)
	await await_idle_frame()
	assert_int(juice.active_pop_count()).is_equal(0)
	assert_int(juice.active_puff_count()).is_equal(0)
