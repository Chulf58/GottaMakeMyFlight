class_name TestBuildSmartRoomsUiB2
extends GdUnitTestSuite
## UI regression tests for Build Slice B2:
## - Always-on resize handles in Tool.NONE (BuiltOutline + BuiltSelection.Kind.ROOM)
## - Starter Toilet & Starter Cafe 1-click kit cards in Contextual Room-Items Tray
## - RoomPanel localized "Needs entrance" note on enclosed rooms

var _port: SubViewport
var _finances: Finances
var _mode: BuildMode
var _menu: BuildMenu
var _selection: BuiltSelection
var _outline: BuiltOutline


func before_test() -> void:
	_port = SubViewport.new()
	_port.size = Vector2i(1280, 720)
	add_child(_port)
	_finances = Finances.new()
	_finances.wallet.credit(50000, Wallet.Category.FEES)
	_port.add_child(_finances)
	_mode = BuildMode.new()
	_mode.grid_size = Vector2i(20, 20)
	_mode.initial_tool = BuildMode.Tool.NONE
	_mode.finances = _finances
	_port.add_child(_mode)
	_mode.set_process(false)
	_selection = BuiltSelection.new()
	_menu = BuildMenu.new()
	_menu.build_mode = _mode
	_port.add_child(_menu)
	_menu.watch_selection(_selection)
	_outline = BuiltOutline.new()
	_outline.selection = _selection
	_outline.build_mode = _mode
	_port.add_child(_outline)
	var edits: Array[BuildEdit] = []
	for y in range(2, 16):
		for x in range(2, 16):
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	_mode.grid.apply_batch(edits)


func after_test() -> void:
	_port.free()


func _at(cell: Vector2i) -> Vector3:
	return _mode.grid.cell_to_world(cell)


func test_always_on_resize_handles_appear_when_room_selected_in_tool_none() -> void:
	_mode.set_tool(BuildMode.Tool.TOILET_ROOM)
	_mode.begin_area(_at(Vector2i(4, 4)))
	_mode.move_area(_at(Vector2i(6, 6)))
	_mode.finish_area()
	var room_id := _mode.grid.room_at(Vector2i(4, 4))
	assert_int(room_id).is_greater(0)

	# With a non-NONE tool, handles stay hidden.
	_selection.kind = BuiltSelection.Kind.ROOM
	_selection.id = room_id
	_selection.changed.emit()
	_outline.refresh()
	assert_bool(_outline.handles_visible()).is_false()

	# Switching to Tool.NONE immediately reveals 4 resize handles with no mode toggle.
	_mode.set_tool(BuildMode.Tool.NONE)
	_outline.refresh()
	assert_bool(_outline.handles_visible()).is_true()
	assert_int(_outline.handle_positions().size()).is_equal(4)

	# Selecting an object hides room resize handles.
	var obj := _mode.grid.apply(BuildEdit.place_object(&"trash_can", Vector2i(10, 10), 0)).object_id
	_selection.select_object(obj)
	_outline.refresh()
	assert_bool(_outline.handles_visible()).is_false()


func test_starter_kit_cards_appear_in_toilet_and_cafe_contextual_trays_and_arm() -> void:
	_menu.enter_room_context(&"toilet", 0)
	await await_idle_frame()
	var toilet_kit := _menu.starter_kit_card(&"toilet")
	assert_object(toilet_kit).is_not_null()
	assert_bool(toilet_kit.is_visible_in_tree()).is_true()
	toilet_kit.pressed.emit()
	await await_idle_frame()
	assert_str(String(_mode.starter_kit.armed)).is_equal("toilet")
	assert_bool(RotateHint.applies(_mode)).is_true()
	assert_bool(BuiltSelection.clicks_taken(_mode)).is_true()
	# Clearing selection (e.g. PassengerHud._settle_built_selection) keeps tray + kit armed.
	_selection.clear()
	await await_idle_frame()
	assert_bool(_menu.is_room_context()).is_true()
	assert_bool(_mode.starter_kit.is_active()).is_true()
	_mode.starter_kit.disarm()
	assert_bool(BuiltSelection.clicks_taken(_mode)).is_false()

	_menu.enter_room_context(&"cafe", 0)
	await await_idle_frame()
	var cafe_kit := _menu.starter_kit_card(&"cafe")
	assert_object(cafe_kit).is_not_null()
	assert_bool(cafe_kit.is_visible_in_tree()).is_true()
	cafe_kit.pressed.emit()
	await await_idle_frame()
	assert_str(String(_mode.starter_kit.armed)).is_equal("cafe")

	# Lounge has a starter kit as of B3.
	_menu.enter_room_context(&"lounge", 0)
	await await_idle_frame()
	var lounge_kit := _menu.starter_kit_card(&"lounge")
	assert_object(lounge_kit).is_not_null()
	assert_bool(lounge_kit.is_visible_in_tree()).is_true()


func test_enclosed_room_surfaces_localized_needs_entrance_note_in_room_panel() -> void:
	_mode.set_tool(BuildMode.Tool.TOILET_ROOM)
	_mode.begin_area(_at(Vector2i(4, 4)))
	_mode.move_area(_at(Vector2i(6, 6)))
	_mode.finish_area()
	var room_id := _mode.grid.room_at(Vector2i(4, 4))
	_mode.set_tool(BuildMode.Tool.NONE)
	_mode.update_room_focus(_at(Vector2i(5, 5)))
	var lines: Array[String] = []
	for lbl in _menu.room_panel().find_children("*", "Label", true, false):
		lines.append((lbl as Label).text)
	assert_array(lines).contains([RoomRules.NO_OPENING])
	# Placing a door clears "Needs entrance" on RoomPanel.
	var door_edit := BuildEdit.place_wall(
		Vector2i(5, 6), BuildGrid.Side.SOUTH, BuildGrid.WallKind.DOOR
	)
	_mode.grid.apply(door_edit)
	_menu.room_panel().show_room(room_id)
	lines.clear()
	for lbl in _menu.room_panel().find_children("*", "Label", true, false):
		lines.append((lbl as Label).text)
	assert_array(lines).not_contains([RoomRules.NO_OPENING])
