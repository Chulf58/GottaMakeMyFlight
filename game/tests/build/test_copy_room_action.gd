class_name TestCopyRoomAction
extends GdUnitTestSuite
## Slice 3/3 Two Point Build UX: 1-Click Copy Room in BuiltItemActions +
## ephemeral clone paste in TemplatePaste with auto-perimeter plain walls,
## atomic BuildTransaction.commit_composite, 1-step Undo, BuildUnlocks,
## wallet, Career award_trophy cap, keeps_piece()-excluded rooms, and Esc/right-click cancel.

const CAFE_RECT := Rect2i(2, 2, 4, 4)
const COUNTER_CELL := Vector2i(3, 2)
const TABLE_CELL := Vector2i(3, 4)
const NEIGHBOR_SHARED_CENTRE := Vector2i(8, 3)
const BARE_CENTRE := Vector2i(14, 14)

var _port: SubViewport
var _finances: Finances
var _unlocks: BuildUnlocks
var _awards: AirportAwards
var _mode: BuildMode
var _sim: PassengerSim
var _selection: BuiltSelection
var _card: BuiltItemCard
var _actions: BuiltItemActions
var _room := 0


func before_test() -> void:
	_port = SubViewport.new()
	_port.size = Vector2i(1280, 720)
	add_child(_port)
	_finances = Finances.new()
	_finances.wallet.credit(50000, Wallet.Category.GRANT)
	_port.add_child(_finances)
	_unlocks = BuildUnlocks.new()
	_unlocks.rating = AirportRating.new()
	_unlocks.add_child(_unlocks.rating)
	_unlocks.passengers = PassengerSim.new()
	_unlocks.add_child(_unlocks.passengers)
	_unlocks.manual = true
	_set_tier(4)
	_port.add_child(_unlocks)
	_awards = AirportAwards.new()
	_port.add_child(_awards)

	var site := SiteDefinition.new()
	site.grid_size = Vector2i(20, 20)
	site.plot_columns = PackedInt32Array([20])
	site.plot_rows = 1
	site.centre_columns = Vector2i(0, 1)
	site.obstacles = [] as Array[Vector2i]
	_mode = BuildMode.new()
	_mode.site = site
	_mode.finances = _finances
	_mode.unlocks = _unlocks
	_mode.awards = _awards
	_mode.require_unlocks = true
	_port.add_child(_mode)
	LandKit.own_all(_mode.land_tool.land)
	_mode.set_process(false)

	_sim = PassengerSim.new()
	_sim.grid = _mode.grid
	_port.add_child(_sim)

	_selection = BuiltSelection.new()
	_card = BuiltItemCard.new()
	_card.sim = _sim
	_card.selection = _selection
	_card.build_mode = _mode
	_card.visible = true
	_port.add_child(_card)
	_actions = BuiltItemActions.new()
	_actions.card = _card
	_port.add_child(_actions)

	# Floored terminal block covering (1, 1) .. (10, 9); rows 10..19 stay bare ground.
	var floor_edits: Array[BuildEdit] = []
	for y in range(1, 10):
		for x in range(1, 11):
			floor_edits.append(
				BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, BuildMode.TERMINAL_ZONE)
			)
	_mode.grid.apply_batch(floor_edits)
	var mark := RoomTool.mark(_mode.grid, CAFE_RECT, &"cafe", _mode.wallet())
	assert_bool(mark.ok).override_failure_message(mark.reason_text()).is_true()
	_room = mark.room_id
	_commit_one(BuildEdit.place_object(&"cafe_counter", COUNTER_CELL, 0))
	_commit_one(BuildEdit.place_object(&"cafe_table", TABLE_CELL, 0))
	# Add a WallKind.DOOR on the original room's south wall to prove doors are NOT cloned.
	_commit_one(BuildEdit.place_wall(Vector2i(3, 5), BuildGrid.Side.SOUTH, BuildGrid.WallKind.DOOR))
	_mode.set_tool(BuildMode.Tool.NONE)
	_mode.clear_undo()


func after_test() -> void:
	_port.free()


func _set_tier(t: int) -> void:
	(
		assert_bool(
			_unlocks.from_snapshot(
				{"tier": t, "made": 600 if t >= 4 else 0, "shown": [], "seen": [], "firsts": []}
			)
		)
		. is_true()
	)


func _commit_one(edit: BuildEdit) -> BuildResult:
	var plan: Array[BuildEdit] = [edit]
	var res := BuildTransaction.commit_plan(_mode.grid, plan, _mode.wallet())
	assert_bool(res.ok).override_failure_message(res.reason_text()).is_true()
	return res


func _select_room(room_id: int) -> void:
	_selection.kind = BuiltSelection.Kind.ROOM
	_selection.id = room_id
	_card.refresh()
	_actions.refresh()


func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	return event


func _pieces_in(rect: Rect2i) -> Dictionary:
	var out := {}
	for oid in _mode.grid.object_ids():
		var rec := _mode.grid.get_object(oid)
		if rect.has_point(rec["anchor"]):
			var cells := BuildCatalog.get_def(rec["def"]).footprint(rec["anchor"], rec["facing"])
			cells.sort()
			out[rec["def"]] = [cells, rec["facing"]]
	return out


func test_selecting_furnished_room_exposes_copy_room_and_hides_for_objects() -> void:
	_select_room(_room)
	assert_bool(_actions.visible).is_true()
	assert_str(_actions.move_text()).is_equal(BuiltItemActions.MOVE_ROOM)
	assert_str(_actions.copy_text()).is_equal(BuiltItemActions.COPY_ROOM)
	assert_str(_actions.delete_text()).is_equal(BuiltItemActions.DELETE_ROOM)
	assert_bool(_actions.copy_visible()).is_true()
	assert_bool(_actions.copy_disabled()).is_false()
	assert_int(_mode.templates.library.size()).is_equal(0)

	# Selecting a plain object hides Copy room.
	var table_id := _mode.grid.object_at(TABLE_CELL)
	_selection.select_object(table_id)
	_card.refresh()
	_actions.refresh()
	assert_bool(_actions.copy_visible()).is_false()


func test_copy_arms_clone_rotates_shares_neighbor_walls_commits_and_undoes() -> void:
	var committed_events: Array[Dictionary] = []
	_mode.player_committed.connect(func(info: Dictionary) -> void: committed_events.append(info))
	_select_room(_room)

	assert_bool(_actions.press_copy()).is_true()
	assert_bool(_selection.is_selected()).is_false()
	assert_bool(_mode.templates.is_active()).is_true()
	assert_object(_mode.templates.active_template()).is_not_null()
	assert_int(_mode.templates.armed).is_equal(-1)
	assert_int(_mode.templates.library.size()).is_equal(0)

	# BuildGhost.clearance_target and RotateHint track the active ephemeral clone.
	_mode._pointer_on_grid = true
	_mode._hover_point = _mode.grid.cell_to_world(NEIGHBOR_SHARED_CENTRE)
	var clearance := BuildGhost.clearance_target(_mode)
	assert_bool(clearance.get("active", false)).is_true()
	assert_bool(RotateHint.applies(_mode)).is_true()

	# R key rotates the clone without rotating BuildMode.facing.
	var facing_before := _mode.facing
	var press_r := InputEventAction.new()
	press_r.action = &"build_rotate"
	press_r.pressed = true
	_port.push_input(press_r)
	assert_int(_mode.templates.turns).is_equal(1)
	assert_int(_mode.facing).is_equal(facing_before)

	# Rotate back to 0 turns and check preview cost adjacent to original room's east wall.
	for _i in 3:
		_mode.templates.rotate_cw()
	assert_int(_mode.templates.turns).is_equal(0)

	# CAFE_RECT is (2, 2, 4, 4) -> east edge at x=5.
	# At NEIGHBOR_SHARED_CENTRE (8, 3), rect is (7, 2, 4, 4) -> west edge at x=7 (1 cell gap)
	# unless we paste at (7, 3) -> rect (6, 2, 4, 4) sharing x=5/x=6 wall!
	var adjacent_centre := Vector2i(7, 3)
	var adj_rect := _mode.templates.active_template().rect_at(adjacent_centre, 0)
	assert_that(adj_rect).is_equal(Rect2i(6, 2, 4, 4))
	# All 16 cells are floored, 4 west perimeter edges are shared with CAFE_RECT -> 12 new plain walls.
	var expected_cost := (
		12 * PriceTable.price_of_wall(BuildGrid.WallKind.PLAIN)
		+ PriceTable.price_of_object(&"cafe_counter")
		+ PriceTable.price_of_object(&"cafe_table")
	)
	var quoted := _mode.templates.preview_price_at(adjacent_centre)
	assert_that(quoted).is_equal(Vector2i(expected_cost, expected_cost))

	var cam := Camera3D.new()
	cam.position = _mode.grid.cell_to_world(adjacent_centre) + Vector3(0.0, 10.0, 0.0)
	cam.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	_port.add_child(cam)
	cam.make_current()
	_mode.pointer_override = Vector2(_port.size) * 0.5
	var menu := BuildMenu.new()
	menu.build_mode = _mode
	_port.add_child(menu)
	assert_that(BuildMenuPrices.preview_price(menu)).is_equal(
		Vector2i(expected_cost, expected_cost)
	)
	_port.remove_child(menu)
	menu.free()
	_mode.pointer_override = Vector2(-1.0, -1.0)
	_port.remove_child(cam)
	cam.free()

	var balance_before := _mode.wallet().balance
	var result := _mode.templates.paste_at(adjacent_centre)
	assert_bool(result.ok).override_failure_message(result.reason_text()).is_true()
	assert_int(_mode.wallet().balance).is_equal(balance_before - expected_cost)
	assert_int(_mode.undo_history().size()).is_equal(1)
	assert_int(_mode.templates.library.size()).is_equal(0)
	assert_int(committed_events.size()).is_equal(1)
	assert_that(committed_events[0]["kind"]).is_equal(&"template")

	# Verify copied room has auto-perimeter plain walls, NO doors, and kept interior pieces.
	var copied_id := _mode.grid.room_at(adj_rect.position)
	assert_int(copied_id).is_greater(0)
	assert_int(copied_id).is_not_equal(_room)
	assert_that(_mode.grid.get_room(copied_id)["rect"]).is_equal(adj_rect)
	for edge in RoomTool.perimeter_edges(adj_rect):
		assert_int(_mode.grid.wall_kind(edge[0], edge[1])).is_equal(BuildGrid.WallKind.PLAIN)
	var copied_pieces := _pieces_in(adj_rect)
	assert_int(copied_pieces.size()).is_equal(2)
	assert_bool(copied_pieces.has(&"cafe_counter")).is_true()
	assert_bool(copied_pieces.has(&"cafe_table")).is_true()
	assert_bool(copied_pieces.has(&"door")).is_false()

	# 1 Undo removes room, walls, and pieces and refunds the exact cost.
	assert_bool(_mode.undo().ok).is_true()
	assert_int(_mode.grid.room_at(adj_rect.position)).is_equal(0)
	assert_int(_mode.wallet().balance).is_equal(balance_before)
	assert_int(_mode.undo_history().size()).is_equal(0)
	for edge in RoomTool.perimeter_edges(adj_rect):
		var c: Vector2i = edge[0]
		var s: int = edge[1]
		if c.x == 6 and s == BuildGrid.Side.WEST:
			assert_int(_mode.grid.wall_kind(c, s)).is_equal(BuildGrid.WallKind.PLAIN)
		else:
			assert_int(_mode.grid.wall_kind(c, s)).is_equal(BuildGrid.WallKind.NONE)


func test_rotated_clone_on_bare_ground_lays_floor_walls_room_and_pieces_and_undoes() -> void:
	_select_room(_room)
	assert_bool(_actions.press_copy()).is_true()
	_mode.templates.rotate_cw()
	var rect := _mode.templates.active_template().rect_at(BARE_CENTRE, 1)
	var expected_cost := (
		16 * PriceTable.price_of_floor()
		+ 16 * PriceTable.price_of_wall(BuildGrid.WallKind.PLAIN)
		+ PriceTable.price_of_object(&"cafe_counter")
		+ PriceTable.price_of_object(&"cafe_table")
	)
	assert_that(_mode.templates.preview_price_at(BARE_CENTRE)).is_equal(
		Vector2i(expected_cost, expected_cost)
	)
	var balance_before := _mode.wallet().balance
	var res := _mode.templates.paste_at(BARE_CENTRE)
	assert_bool(res.ok).override_failure_message(res.reason_text()).is_true()
	assert_int(_mode.wallet().balance).is_equal(balance_before - expected_cost)
	var copied := _mode.grid.room_at(rect.position)
	assert_int(copied).is_greater(0)
	assert_int(_mode.grid.floor_at(rect.position)).is_equal(BuildGrid.FLOOR_TILE)
	var pieces := _pieces_in(rect)
	assert_int(pieces.size()).is_equal(2)
	assert_int(pieces[&"cafe_counter"][1]).is_equal(1)
	assert_int(pieces[&"cafe_table"][1]).is_equal(1)

	assert_bool(_mode.undo().ok).is_true()
	assert_int(_mode.grid.room_at(rect.position)).is_equal(0)
	assert_int(_mode.grid.floor_at(rect.position)).is_equal(BuildGrid.FLOOR_NONE)
	assert_int(_mode.wallet().balance).is_equal(balance_before)


func test_refusals_locked_tier_wallet_trophy_cap_and_excluded_pieces() -> void:
	# 1. Locked tier refusal (Cafe is Tier 2; drop unlocks to Tier 1).
	_set_tier(1)
	_select_room(_room)
	assert_bool(_actions.press_copy()).is_true()
	var bal := _mode.wallet().balance
	var lock_res := _mode.templates.paste_at(BARE_CENTRE)
	assert_bool(lock_res.ok).is_false()
	assert_int(lock_res.reason).is_equal(BuildResult.Reason.LOCKED)
	assert_int(_mode.grid.room_at(BARE_CENTRE)).is_equal(0)
	assert_int(_mode.wallet().balance).is_equal(bal)
	assert_int(_mode.undo_history().size()).is_equal(0)
	_mode.templates.disarm()
	_set_tier(4)

	# 2. Unaffordable wallet refusal.
	_select_room(_room)
	assert_bool(_actions.press_copy()).is_true()
	var needed := _mode.templates.preview_price_at(BARE_CENTRE).x
	var spend_amt := _mode.wallet().balance - (needed - 1)
	assert_bool(_mode.wallet().spend(spend_amt, Wallet.Category.BUILD)).is_true()
	var bal_short := _mode.wallet().balance
	var poor_res := _mode.templates.paste_at(BARE_CENTRE)
	assert_bool(poor_res.ok).is_false()
	assert_int(poor_res.reason).is_equal(BuildResult.Reason.CANT_AFFORD)
	assert_int(_mode.grid.room_at(BARE_CENTRE)).is_equal(0)
	assert_int(_mode.wallet().balance).is_equal(bal_short)
	assert_bool(_mode.wallet().credit(50000, Wallet.Category.GRANT)).is_true()
	_mode.templates.disarm()

	# 3. Career award_trophy cap enforcement.
	var snap: Dictionary = _awards.to_save_dict()
	snap["trophies_earned"] = 1
	assert_bool(_awards.from_save_dict(snap)).is_true()
	_commit_one(BuildEdit.place_object(AirportAwards.TROPHY_DEF_ID, Vector2i(2, 4), 0))
	assert_int(_awards.trophies_available(_mode.grid)).is_equal(0)
	_select_room(_room)
	assert_bool(_actions.press_copy()).is_true()
	var cap_res := _mode.templates.paste_at(BARE_CENTRE)
	assert_bool(cap_res.ok).is_false()
	assert_int(cap_res.reason).is_equal(BuildResult.Reason.LOCKED)
	assert_str(cap_res.reason_text()).contains("No award trophies available")
	assert_int(_mode.grid.room_at(BARE_CENTRE)).is_equal(0)
	_mode.templates.disarm()

	# Granting a 2nd trophy allows cloning the trophy room cleanly.
	snap["trophies_earned"] = 2
	assert_bool(_awards.from_save_dict(snap)).is_true()
	assert_int(_awards.trophies_available(_mode.grid)).is_equal(1)
	_select_room(_room)
	assert_bool(_actions.press_copy()).is_true()
	assert_bool(_mode.templates.paste_at(BARE_CENTRE).ok).is_true()
	_mode.undo()
	_mode.templates.disarm()

	# 4. Room whose interior pieces are ALL excluded by keeps_piece() disables Copy with reason.
	var unkept_rect := Rect2i(6, 5, 4, 4)
	assert_bool(RoomTool.mark(_mode.grid, unkept_rect, &"cafe", _mode.wallet()).ok).is_true()
	var unkept_room := _mode.grid.room_at(unkept_rect.position)
	_commit_one(BuildEdit.place_object(&"security_scanner", Vector2i(7, 6), 0))
	_select_room(unkept_room)
	assert_bool(_actions.copy_visible()).is_true()
	assert_bool(_actions.copy_disabled()).is_true()
	assert_str(_actions.reason_text()).contains(BuiltItemActions.COPY_PIECES_UNCOPIABLE)
	assert_str(_actions.copy_button().tooltip_text).contains(
		BuiltItemActions.COPY_PIECES_UNCOPIABLE
	)
	assert_bool(_actions.copy_room()).is_false()
	assert_bool(_mode.templates.is_active()).is_false()


func test_empty_room_is_copyable_and_esc_or_right_click_disarms_without_library_mutation() -> void:
	var empty_rect := Rect2i(7, 6, 3, 3)
	assert_bool(RoomTool.mark(_mode.grid, empty_rect, &"toilet", _mode.wallet()).ok).is_true()
	var empty_room := _mode.grid.room_at(empty_rect.position)
	_select_room(empty_room)
	assert_bool(_actions.copy_visible()).is_true()
	assert_bool(_actions.copy_disabled()).is_false()
	assert_bool(_actions.copy_room()).is_true()
	assert_bool(_mode.templates.is_active()).is_true()
	assert_int(_mode.templates.library.size()).is_equal(0)

	# Esc disarms cleanly without adding to library.
	var esc := InputEventAction.new()
	esc.action = &"build_tool_none"
	esc.pressed = true
	_port.push_input(esc)
	assert_bool(_mode.templates.is_active()).is_false()
	assert_int(_mode.tool).is_equal(BuildMode.Tool.NONE)
	assert_int(_mode.templates.library.size()).is_equal(0)

	# Right-click also disarms cleanly.
	_select_room(empty_room)
	assert_bool(_actions.press_copy()).is_true()
	assert_bool(_mode.templates.is_active()).is_true()
	assert_bool(_mode._cancel_or_deselect_on_right_click()).is_true()
	assert_bool(_mode.templates.is_active()).is_false()
	assert_int(_mode.tool).is_equal(BuildMode.Tool.NONE)
	assert_int(_mode.templates.library.size()).is_equal(0)
