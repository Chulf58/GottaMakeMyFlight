class_name TestBuiltItemActions
extends GdUnitTestSuite
## On the real main scene, the inspect window of a selected built item offers
## Move and Delete (decision built-items-selectable-reuse-the-selection-window-
## move-delete-close-open). Delete starts build mode and removes the item as one
## refunded undo step; Move on a room, or on a piece in one, picks the room tool
## and lifts the room; Move is disabled with a reason for a check-in desk and
## for a lone piece.

const SEED := 6_113_312
const ROOM_SIZE := Vector2i(3, 3)

var _settings_path := SaveTestKit.run_path("built_item_actions_alerts")

var _main: Node
var _hud: PassengerHud
var _mode: BuildMode
var _sim: PassengerSim
var _inspect: PassengerInspect
var _menu: BuildMenu
var _desk := 0
var _room := 0
var _room_area := Rect2i()
var _plain_cell := Vector2i(-1, -1)


func before() -> void:
	_main = load(SaveTestKit.MAIN).instantiate()
	(_main.get_node("SimClock") as SimClock).seed_rng(SEED)
	(_main.get_node("SimClock") as SimClock).set_paused(true)
	(_main.get_node("PassengerHud") as PassengerHud).alert_settings_path = _settings_path
	add_child(_main)
	_hud = _main.get_node("PassengerHud")
	_mode = _main.get_node("BuildMode")
	_sim = _main.get_node("PassengerSim")
	_menu = _main.get_node("BuildMenu")
	(_main.get_node("TycoonCamera") as TycoonCamera).set_process(false)
	_inspect = _hud.find_child("PassengerInspect", true, false) as PassengerInspect
	_hud.press_starter_terminal()
	_desk = _sim.layout.desks[0]
	_find_free_floor()
	var edit := _mode.grid.apply(BuildEdit.place_room(_room_area, &"cafe"))
	assert_bool(edit.ok).is_true()
	_room = _mode.grid.room_at(_room_area.position)


func after() -> void:
	_main.free()
	DirAccess.remove_absolute(_settings_path)


func before_test() -> void:
	_mode.set_tool(BuildMode.Tool.NONE)
	_menu.build_session.set_building(false)
	_selection().clear()
	_hud.refresh()


## The first free ROOM_SIZE block of landside-hall floor for the room, and a free
## cell well clear of it for a lone piece.
func _find_free_floor() -> void:
	var grid := _mode.grid
	var offset := ReferenceTerminal.offset_on(grid)
	var low := Vector2i(ReferenceTerminal.FLOOR_MIN.x + 1, ReferenceTerminal.DIVIDER_Y + 1) + offset
	var high := ReferenceTerminal.FLOOR_MAX + offset - Vector2i.ONE
	for y in range(low.y, high.y - ROOM_SIZE.y + 2):
		for x in range(low.x, high.x - ROOM_SIZE.x + 2):
			var area := Rect2i(Vector2i(x, y), ROOM_SIZE)
			if not _is_free(grid, area.grow(1)):
				continue
			if not _room_area.has_area():
				_room_area = area
			elif not area.intersects(_room_area.grow(3)):
				_plain_cell = area.position + Vector2i.ONE
	assert_bool(_room_area.has_area() and _plain_cell.x >= 0).is_true()


static func _is_free(grid: BuildGrid, area: Rect2i) -> bool:
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var cell := Vector2i(x, y)
			if (
				grid.floor_at(cell) == BuildGrid.FLOOR_NONE
				or grid.object_at(cell) != 0
				or grid.room_at(cell) != 0
			):
				return false
	return true


## An exit door whose back edge holds no wall, so removing it buys one. An
## entrance is skipped: removing the only one is refused for another reason.
func _door_without_back_wall() -> int:
	for object_id in _mode.grid.object_ids():
		var record := _mode.grid.get_object(object_id)
		if record["def"] != &"exit_door":
			continue
		var back := BuildGrid.SIDE_STEP.find(DoorPlacement.back_step(record["facing"]))
		if _mode.grid.wall_kind(record["anchor"], back) == BuildGrid.WallKind.NONE:
			return object_id
	return 0


## The text RoomMove refuses a desk, scanner or lane part with, from its source.
func _unmovable_text() -> String:
	return BuildResult.REASON_TEXT[BuildResult.Reason.MOVE_UNMOVABLE]


func _selection() -> BuiltSelection:
	return _inspect.built_card.selection


func _select_object(object_id: int) -> void:
	_selection().kind = BuiltSelection.Kind.OBJECT
	_selection().id = object_id
	_hud.refresh()


func _select_room(room_id: int) -> void:
	_selection().kind = BuiltSelection.Kind.ROOM
	_selection().id = room_id
	_hud.refresh()


## A statue paid for through the build mode, as a click would place it.
func _place_statue(cell: Vector2i) -> int:
	var placed := _mode.apply_edit(BuildEdit.place_object(&"statue_indoor", cell, 0))
	assert_bool(placed.ok).is_true()
	return placed.object_id


func test_delete_removes_the_item_refunds_it_and_one_undo_restores_it() -> void:
	var statue := _place_statue(_plain_cell)
	var before_balance := _mode.wallet().balance
	var saved_price := int(_mode.grid.get_object(statue)["paid"])
	_mode.clear_undo()
	_select_object(statue)
	var actions := _inspect.actions
	print(
		(
			"window: %s | %s | delete %s"
			% [_inspect.built_card.name_text(), actions.move_text(), actions.delete_text()]
		)
	)
	assert_bool(actions.visible).is_true()
	assert_str(actions.delete_text()).is_equal(BuiltItemActions.DELETE)
	assert_bool(actions.delete_disabled()).is_false()
	assert_object(actions.session).is_same(_menu.build_session)
	assert_bool(_menu.build_session.active).is_false()
	var result := actions.press_delete()
	var paid_back := _mode.wallet().balance - before_balance
	print(
		(
			"delete ok %s, object left %s, balance %d -> %d, session %s, undo steps %d"
			% [
				result.ok,
				_mode.grid.get_object(statue).size(),
				before_balance,
				_mode.wallet().balance,
				_menu.build_session.active,
				_mode.undo_history().size()
			]
		)
	)
	assert_bool(result.ok).is_true()
	assert_bool(_mode.grid.get_object(statue).is_empty()).is_true()
	assert_int(saved_price).is_greater(0)
	assert_int(paid_back).is_equal(PriceTable.refund_of(saved_price))
	assert_bool(_menu.build_session.active).is_true()
	assert_int(_mode.undo_history().size()).is_equal(1)
	# The selection falls away with the item.
	_hud.refresh()
	assert_bool(_selection().is_selected()).is_false()
	var undone := _mode.undo()
	print(
		(
			"undo ok %s, balance %d, object back %s"
			% [undone.ok, _mode.wallet().balance, _mode.grid.object_at(_plain_cell)]
		)
	)
	assert_bool(undone.ok).is_true()
	assert_int(_mode.grid.object_at(_plain_cell)).is_not_equal(0)
	assert_int(_mode.wallet().balance).is_equal(before_balance)
	assert_int(_mode.undo_history().size()).is_equal(0)
	_mode.apply_edit(BuildEdit.remove_object(_mode.grid.object_at(_plain_cell)))


func test_delete_on_a_room_removes_the_whole_room_as_one_step() -> void:
	var area := _room_area
	_mode.clear_undo()
	_select_room(_room)
	var actions := _inspect.actions
	assert_str(actions.delete_text()).is_equal(BuiltItemActions.DELETE_ROOM)
	var result := actions.press_delete()
	print(
		(
			"room delete ok %s, room left %s, undo steps %d"
			% [result.ok, _mode.grid.get_room(_room).size(), _mode.undo_history().size()]
		)
	)
	assert_bool(result.ok).is_true()
	assert_bool(_mode.grid.get_room(_room).is_empty()).is_true()
	assert_int(_mode.undo_history().size()).is_equal(1)
	assert_bool(_mode.undo().ok).is_true()
	assert_bool(_mode.grid.get_room(_mode.grid.room_at(area.position)).is_empty()).is_false()
	_room = _mode.grid.room_at(area.position)


func test_move_on_a_room_picks_the_room_tool_and_lifts_the_room() -> void:
	_select_room(_room)
	var actions := _inspect.actions
	print(
		(
			"room window: %s | move %s disabled %s | %s"
			% [
				_inspect.built_card.name_text(),
				actions.move_text(),
				actions.move_disabled(),
				actions.reason_text()
			]
		)
	)
	assert_str(actions.move_text()).is_equal(BuiltItemActions.MOVE_ROOM)
	assert_bool(actions.move_disabled()).is_false()
	assert_bool(_mode.room_mover.active).is_false()
	assert_bool(actions.press_move()).is_true()
	print(
		(
			"tool %d, mover active %s, room %d (wanted %d)"
			% [_mode.tool, _mode.room_mover.active, _mode.room_mover.room_id, _room]
		)
	)
	assert_int(_mode.tool).is_equal(BuildMode.Tool.CAFE_ROOM)
	assert_bool(_mode.room_mover.active).is_true()
	assert_int(_mode.room_mover.room_id).is_equal(_room)
	# The window yields to the move: the next refresh clears the selection.
	_hud.refresh()
	assert_bool(_selection().is_selected()).is_false()
	_mode.set_tool(BuildMode.Tool.NONE)
	assert_bool(_mode.room_mover.active).is_false()


func test_move_on_a_piece_in_a_room_lifts_that_room() -> void:
	var cell := _room_area.position + Vector2i.ONE
	var statue := _place_statue(cell)
	_select_object(statue)
	var actions := _inspect.actions
	assert_str(actions.move_text()).is_equal(BuiltItemActions.MOVE_ROOM)
	assert_bool(actions.move_disabled()).is_false()
	assert_bool(actions.press_move()).is_true()
	assert_bool(_mode.room_mover.active).is_true()
	assert_int(_mode.room_mover.room_id).is_equal(_room)
	_mode.set_tool(BuildMode.Tool.NONE)
	_mode.apply_edit(BuildEdit.remove_object(statue))


func test_move_is_disabled_with_a_reason_for_a_check_in_desk() -> void:
	_select_object(_desk)
	var actions := _inspect.actions
	print("desk window: move disabled %s | %s" % [actions.move_disabled(), actions.reason_text()])
	assert_bool(actions.visible).is_true()
	assert_bool(actions.move_disabled()).is_true()
	assert_str(actions.reason_text()).contains(_unmovable_text())
	assert_bool(actions.press_move()).is_false()
	assert_int(_mode.tool).is_equal(BuildMode.Tool.NONE)
	assert_bool(_mode.room_mover.active).is_false()


func test_move_is_disabled_with_the_rooms_reason_for_a_scanner_and_a_lane_part() -> void:
	var cell := _room_area.position + Vector2i.ONE
	for def_id: StringName in [&"security_scanner", SecurityLanes.TRAY_TABLE]:
		var placed := _mode.grid.apply(BuildEdit.place_object(def_id, cell, 0))
		assert_bool(placed.ok).is_true()
		_select_object(placed.object_id)
		var actions := _inspect.actions
		print(
			(
				"%s window: move disabled %s | %s"
				% [def_id, actions.move_disabled(), actions.reason_text()]
			)
		)
		assert_bool(actions.move_disabled()).is_true()
		assert_str(actions.reason_text()).contains(_unmovable_text())
		assert_bool(actions.press_move()).is_false()
		assert_bool(_mode.room_mover.active).is_false()
		_selection().clear()
		_mode.grid.apply(BuildEdit.remove_object(placed.object_id))


## Taking a door off puts its back wall back at the wall's price
## (DoorPlacement.edits_for), so with an empty wallet BuildMode.check() refuses
## the delete (CANT_AFFORD) and nothing may change.
func test_a_refused_delete_changes_nothing_and_says_why() -> void:
	var door := _door_without_back_wall()
	assert_int(door).is_not_equal(0)
	var kept := _mode.wallet().balance
	# The control: with the money the same removal is accepted.
	assert_bool(_mode.check(BuildEdit.remove_object(door)).ok).is_true()
	assert_bool(_mode.wallet().spend(kept, Wallet.Category.BUILD)).is_true()
	_mode.clear_undo()
	_select_object(door)
	var actions := _inspect.actions
	var refusal := _mode.check(BuildEdit.remove_object(door))
	assert_bool(refusal.ok).is_false()
	assert_int(refusal.reason).is_equal(BuildResult.Reason.CANT_AFFORD)
	assert_bool(_menu.build_session.active).is_false()
	var result := actions.press_delete()
	print("refused delete ok %s | %s" % [result.ok, actions.reason_text()])
	var left := _mode.grid.get_object(door).is_empty()
	var session_on := _menu.build_session.active
	var undo_steps := _mode.undo_history().size()
	var shown := actions.reason_text()
	var restored := _mode.wallet().credit(kept, Wallet.Category.BUILD)
	assert_bool(restored).is_true()
	assert_int(_mode.wallet().balance).is_equal(kept)
	assert_bool(result.ok).is_false()
	assert_bool(left).is_false()
	assert_bool(session_on).is_false()
	assert_int(undo_steps).is_equal(0)
	assert_str(shown).contains(BuiltItemActions.DELETE_REFUSED % refusal.reason_text())
	assert_str(shown).contains("Can't delete: ")


func test_move_is_disabled_with_a_reason_for_a_lone_piece() -> void:
	var statue := _place_statue(_plain_cell)
	_select_object(statue)
	var actions := _inspect.actions
	print(
		(
			"lone piece window: move disabled %s delete disabled %s | %s"
			% [actions.move_disabled(), actions.delete_disabled(), actions.reason_text()]
		)
	)
	assert_bool(actions.move_disabled()).is_true()
	assert_str(actions.reason_text()).contains(BuiltItemActions.NO_LOOSE_PIECE)
	assert_bool(actions.delete_disabled()).is_false()
	assert_bool(actions.press_move()).is_false()
	assert_bool(_mode.room_mover.active).is_false()
	_mode.apply_edit(BuildEdit.remove_object(statue))


func test_move_on_a_room_holding_a_security_piece_is_disabled_with_the_rooms_reason() -> void:
	# The control: the plain room's Move is live (the room-move test above).
	assert_object(RoomMoveTool.never_moves_refusal(_mode.grid, _room)).is_null()
	var arch := _mode.grid.apply(
		BuildEdit.place_object(&"security_arch", _room_area.position + Vector2i.ONE, 2)
	)
	assert_bool(arch.ok).is_true()
	_select_room(_room)
	var actions := _inspect.actions
	var reason := BuildResult.REASON_TEXT[BuildResult.Reason.MOVE_UNMOVABLE]
	print(
		"room with arch: move disabled %s | %s" % [actions.move_disabled(), actions.reason_text()]
	)
	assert_bool(actions.move_disabled()).is_true()
	assert_str(actions.reason_text()).contains(reason)
	assert_bool(actions.press_move()).is_false()
	assert_bool(_mode.room_mover.active).is_false()
	_mode.grid.apply(BuildEdit.remove_object(arch.object_id))


func test_the_buttons_hide_with_no_item_selected() -> void:
	_select_object(_desk)
	assert_bool(_inspect.actions.visible).is_true()
	_selection().clear()
	_hud.refresh()
	assert_bool(_inspect.actions.visible).is_false()
