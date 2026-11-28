class_name TestContextualRoomTray
extends GdUnitTestSuite
## Regression tests for Build Slice B1b: Two Point Contextual Room-Items Tray
## (decisions c221025a, 593876df, 1caf2bb3).

var _port: SubViewport
var _finances: Finances
var _mode: BuildMode
var _menu: BuildMenu
var _selection: BuiltSelection


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
	var edits: Array[BuildEdit] = []
	for y in range(2, 16):
		for x in range(2, 16):
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	_mode.grid.apply_batch(edits)


func after_test() -> void:
	_port.free()


func _at(cell: Vector2i) -> Vector3:
	return _mode.grid.cell_to_world(cell)


func _badge_text(card: Button) -> String:
	var lbl := card.get_node_or_null("RequiredBadge/RequiredBadgeLabel") as Label
	if lbl == null or not lbl.get_parent().visible:
		return ""
	return lbl.text


func _badge_color(card: Button) -> Color:
	var badge := card.get_node_or_null("RequiredBadge") as PanelContainer
	if badge == null:
		return Color.BLACK
	var style := badge.get_theme_stylebox(&"panel") as StyleBoxFlat
	return style.bg_color if style != null else Color.BLACK


func _visible_room_tools() -> Array[BuildMode.Tool]:
	var out: Array[BuildMode.Tool] = []
	for child in _menu.room_context_grid().get_children():
		var btn := child as Button
		if btn == null or not btn.visible:
			continue
		for tool: BuildMode.Tool in BuildMode.Tool.values():
			if _menu.card(tool) == btn:
				out.append(tool)
				break
	return out


func test_room_only_furniture_hidden_from_main_tabs_while_rooms_and_corridor_services_visible(
) -> void:
	for i in BuildMenu.REMOVE_CATEGORY:
		_menu.press_category(i)
		for tool: BuildMode.Tool in BuildMenuCatalog.ROOM_TOOL_OWNERS:
			(
				assert_bool(_menu.card(tool).is_visible_in_tree())
				. override_failure_message("room-only tool %d visible in tab %d" % [tool, i])
				. is_false()
			)
	_menu.press_category(BuildMenu.category_index("facilities"))
	for tool: BuildMode.Tool in [
		BuildMode.Tool.TOILET_ROOM,
		BuildMode.Tool.SHOWER_ROOM,
		BuildMode.Tool.LOUNGE_ROOM,
		BuildMode.Tool.PLAY_AREA_ROOM,
		BuildMode.Tool.ATM,
		BuildMode.Tool.EXCHANGE,
		BuildMode.Tool.NAP_POD,
	]:
		assert_bool(_menu.card(tool).is_visible_in_tree()).is_true()
	_menu.press_category(BuildMenu.category_index("food"))
	for tool: BuildMode.Tool in [
		BuildMode.Tool.CAFE_ROOM,
		BuildMode.Tool.BAR_ROOM,
		BuildMode.Tool.RESTAURANT_ROOM,
		BuildMode.Tool.GRAB_STALL,
	]:
		assert_bool(_menu.card(tool).is_visible_in_tree()).is_true()


func test_clicking_room_tool_opens_contextual_tray_with_back_header_mandatory_and_optional_items(
) -> void:
	_menu.press_category(BuildMenu.category_index("facilities"))
	_menu.card(BuildMode.Tool.LOUNGE_ROOM).pressed.emit()
	await await_idle_frame()
	assert_bool(_menu.is_tray_open()).is_true()
	assert_bool(_menu.is_room_context()).is_true()
	assert_str(String(_menu.room_context_type())).is_equal("lounge")
	assert_bool(_menu.room_back_button().is_visible_in_tree()).is_true()
	assert_str(_menu.room_back_button().text).is_equal("← Back")
	assert_str(_menu.room_title_label().text).is_equal("Lounge items")
	assert_bool(_menu.room_summary_label().visible).is_false()
	# Mandatory Sofa listed first with ★, then optional items, Door, and Room card.
	var order := _visible_room_tools()
	(
		assert_array(order)
		. is_equal(
			[
				BuildMode.Tool.SOFA,
				BuildMode.Tool.ARMCHAIR,
				BuildMode.Tool.WORK_DESK,
				BuildMode.Tool.DOOR,
				BuildMode.Tool.LOUNGE_ROOM,
			]
		)
	)
	assert_str(_badge_text(_menu.card(BuildMode.Tool.SOFA))).is_equal("★")
	assert_str(_badge_text(_menu.card(BuildMode.Tool.ARMCHAIR))).is_empty()
	assert_str(_badge_text(_menu.card(BuildMode.Tool.WORK_DESK))).is_empty()
	assert_str(_badge_text(_menu.card(BuildMode.Tool.DOOR))).is_empty()
	assert_bool(_menu.card(BuildMode.Tool.LOUNGE_ROOM).button_pressed).is_true()


func test_selecting_built_room_and_picking_furniture_keeps_room_context_persistent() -> void:
	var room_id := _mode.grid.apply(BuildEdit.place_room(Rect2i(3, 3, 4, 4), &"toilet")).room_id
	_selection.clear()
	_selection.kind = BuiltSelection.Kind.ROOM
	_selection.id = room_id
	_selection.changed.emit()
	await await_idle_frame()
	assert_bool(_menu.is_room_context()).is_true()
	assert_int(_menu.room_context_id()).is_equal(room_id)
	assert_str(_menu.room_title_label().text).is_equal("Toilet items")
	assert_bool(_menu.room_summary_label().visible).is_true()
	assert_str(_menu.room_summary_label().text).is_equal("Needs a toilet stall")

	# Clicking a furniture tool keeps room context open even when BuiltSelection clears
	# (clicks_taken) and even when pointer moves over UI (hover room focus = 0).
	_menu.card(BuildMode.Tool.TOILET_STALL).pressed.emit()
	_selection.clear()
	_mode.update_room_focus(null)
	await await_idle_frame()
	assert_int(_mode.tool).is_equal(BuildMode.Tool.TOILET_STALL)
	assert_bool(_menu.is_room_context()).is_true()
	assert_int(_menu.room_context_id()).is_equal(room_id)
	assert_bool(_menu.card(BuildMode.Tool.TOILET_STALL).button_pressed).is_true()


func test_finishing_new_room_drag_binds_contextual_tray_and_live_checkmarks_follow_room_rules(
) -> void:
	_menu.press_category(BuildMenu.category_index("food"))
	_menu.card(BuildMode.Tool.RESTAURANT_ROOM).pressed.emit()
	_mode.begin_area(_at(Vector2i(3, 3)))
	_mode.move_area(_at(Vector2i(7, 7)))
	_mode.finish_area()
	await await_idle_frame()
	var room_id := _mode.grid.room_at(Vector2i(3, 3))
	assert_int(room_id).is_greater(0)
	assert_bool(_menu.is_room_context()).is_true()
	assert_int(_menu.room_context_id()).is_equal(room_id)
	assert_str(_menu.room_title_label().text).is_equal("Restaurant items")
	assert_str(_badge_text(_menu.card(BuildMode.Tool.COUNTER))).is_equal("★")
	assert_str(_badge_text(_menu.card(BuildMode.Tool.DINING_TABLE))).is_equal("★")
	assert_str(_badge_text(_menu.card(BuildMode.Tool.BOOTH))).is_equal("★")

	# Place a Booth (alternative table via RoomTypes.pieces_for(&"restaurant_table")):
	# BOTH Dining table and Booth checkmarks turn green ✓, while Counter stays ★.
	_menu.card(BuildMode.Tool.BOOTH).pressed.emit()
	assert_bool(_mode.apply_at(_at(Vector2i(5, 5))).ok).is_true()
	await await_idle_frame()
	assert_str(_badge_text(_menu.card(BuildMode.Tool.COUNTER))).is_equal("★")
	assert_str(_badge_text(_menu.card(BuildMode.Tool.DINING_TABLE))).is_equal("✓")
	assert_str(_badge_text(_menu.card(BuildMode.Tool.BOOTH))).is_equal("✓")
	assert_float(_badge_color(_menu.card(BuildMode.Tool.BOOTH)).g).is_greater(0.7)

	# Place Counter inside the restaurant -> Counter turns ✓; add door -> Ready!
	_menu.card(BuildMode.Tool.COUNTER).pressed.emit()
	assert_bool(_mode.apply_at(_at(Vector2i(3, 3))).ok).is_true()
	await await_idle_frame()
	assert_str(_badge_text(_menu.card(BuildMode.Tool.COUNTER))).is_equal("✓")
	assert_str(_menu.room_summary_label().text).is_equal(RoomRules.NO_OPENING)
	var door_edit := BuildEdit.place_wall(
		Vector2i(4, 7), BuildGrid.Side.SOUTH, BuildGrid.WallKind.DOOR
	)
	var door_edits := DoorPlacement.edits_for(_mode.grid, door_edit)
	assert_bool(BuildTransaction.commit_plan(_mode.grid, door_edits, _finances.wallet).ok).is_true()
	await await_idle_frame()
	assert_str(_menu.room_summary_label().text).is_equal("Ready")


func test_piece_with_front_outside_room_does_not_tick_mandatory_checkmark() -> void:
	var room_id := _mode.grid.apply(BuildEdit.place_room(Rect2i(4, 4, 3, 3), &"toilet")).room_id
	_menu.enter_room_context(&"toilet", room_id)
	await await_idle_frame()
	# Place sink at (4, 6) facing south (facing=0, interaction cell at (4, 7), outside room).
	_mode.set_tool(BuildMode.Tool.TOILET_SINK)
	_mode.facing = 0
	assert_bool(_mode.apply_at(_at(Vector2i(4, 6))).ok).is_true()
	await await_idle_frame()
	assert_str(_badge_text(_menu.card(BuildMode.Tool.TOILET_SINK))).is_equal("★")
	# Place sink wholly inside (5, 5) facing south (interaction cell (5, 6), inside room).
	assert_bool(_mode.apply_at(_at(Vector2i(5, 5))).ok).is_true()
	await await_idle_frame()
	assert_str(_badge_text(_menu.card(BuildMode.Tool.TOILET_SINK))).is_equal("✓")


func test_bag_room_context_ticks_belt_when_belt_end_is_inside_and_keeps_cart_optional() -> void:
	var room_id := _mode.grid.apply(BuildEdit.place_room(Rect2i(8, 2, 3, 3), &"bag_room")).room_id
	_menu.enter_room_context(&"bag_room", room_id)
	await await_idle_frame()
	(
		assert_array(_visible_room_tools())
		. is_equal(
			[
				BuildMode.Tool.BAY_DOOR,
				BuildMode.Tool.BELT,
				BuildMode.Tool.CART,
				BuildMode.Tool.DOOR,
				BuildMode.Tool.BAG_ROOM,
			]
		)
	)
	assert_str(_badge_text(_menu.card(BuildMode.Tool.BAY_DOOR))).is_equal("★")
	assert_str(_badge_text(_menu.card(BuildMode.Tool.BELT))).is_equal("★")
	assert_str(_badge_text(_menu.card(BuildMode.Tool.CART))).is_empty()
	_menu.card(BuildMode.Tool.BAY_DOOR).pressed.emit()
	_mode.facing = 0
	assert_bool(_mode.apply_at(_at(Vector2i(9, 2))).ok).is_true()
	await await_idle_frame()
	assert_str(_badge_text(_menu.card(BuildMode.Tool.BAY_DOOR))).is_equal("✓")
	_menu.card(BuildMode.Tool.BELT).pressed.emit()
	assert_bool(_mode.lay_belt(Vector2i(6, 3), Vector2i(9, 3)).ok).is_true()
	await await_idle_frame()
	assert_str(_badge_text(_menu.card(BuildMode.Tool.BELT))).is_equal("✓")
	assert_str(_menu.room_summary_label().text).is_equal("Ready")


func test_focus_tool_on_room_only_furniture_opens_room_context_and_pulses() -> void:
	assert_bool(_menu.focus_tool(BuildMode.Tool.TOILET_STALL)).is_true()
	assert_bool(_menu.is_room_context()).is_true()
	assert_str(String(_menu.room_context_type())).is_equal("toilet")
	assert_int(_menu.pulsed_tool()).is_equal(BuildMode.Tool.TOILET_STALL)
	assert_bool(_menu.card(BuildMode.Tool.TOILET_STALL).is_visible_in_tree()).is_true()


func test_back_button_and_tab_switch_exit_room_context_and_shrink_tray_via_reset_size() -> void:
	_menu.press_category(BuildMenu.category_index("facilities"))
	await await_idle_frame()
	var facilities_h := _menu.tray().size.y
	assert_float(facilities_h).is_equal(BuildMenu.TRAY_H)
	_menu.card(BuildMode.Tool.TOILET_ROOM).pressed.emit()
	await await_idle_frame()
	await await_idle_frame()
	var context_h := _menu.tray().size.y
	assert_float(context_h).is_greater(facilities_h)

	# Clicking "← Back" exits room context and shrinks tray back to Facilities 106 px height.
	_menu.room_back_button().pressed.emit()
	await await_idle_frame()
	await await_idle_frame()
	assert_bool(_menu.is_room_context()).is_false()
	assert_int(_menu.open_category()).is_equal(BuildMenu.category_index("facilities"))
	assert_int(_mode.tool).is_equal(BuildMode.Tool.NONE)
	assert_float(_menu.tray().size.y).is_equal(BuildMenu.TRAY_H)

	# Re-enter room context, then click another bottom-bar tab -> exits room context and shrinks.
	_menu.enter_room_context(&"toilet", 0)
	await await_idle_frame()
	assert_float(_menu.tray().size.y).is_greater(BuildMenu.TRAY_H)
	_menu.category_button(BuildMenu.category_index("building")).pressed.emit()
	await await_idle_frame()
	await await_idle_frame()
	assert_bool(_menu.is_room_context()).is_false()
	assert_int(_menu.open_category()).is_equal(BuildMenu.category_index("building"))
	assert_float(_menu.tray().size.y).is_equal(BuildMenu.TRAY_H)


func test_contextual_room_tray_includes_door_card_and_arms_door_without_leaving_room_context(
) -> void:
	_menu.press_category(BuildMenu.category_index("facilities"))
	_menu.card(BuildMode.Tool.TOILET_ROOM).pressed.emit()
	_mode.begin_area(_at(Vector2i(4, 4)))
	_mode.move_area(_at(Vector2i(6, 7)))
	_mode.finish_area()
	await await_idle_frame()
	var room_id := _mode.grid.room_at(Vector2i(4, 4))
	assert_int(room_id).is_greater(0)
	assert_bool(_menu.is_room_context()).is_true()

	var door_card := _menu.card(BuildMode.Tool.DOOR)
	assert_object(door_card).is_not_null()
	assert_bool(door_card.is_visible_in_tree()).is_true()
	assert_str(_menu.card_price_text(BuildMode.Tool.DOOR)).is_equal(
		str(PriceTable.price_of_wall(BuildGrid.WallKind.DOOR))
	)
	assert_str(_badge_text(door_card)).is_empty()

	# Place required stall and sink so only "Needs entrance" remains.
	_menu.card(BuildMode.Tool.TOILET_STALL).pressed.emit()
	assert_bool(_mode.apply_at(_at(Vector2i(4, 4))).ok).is_true()
	_menu.card(BuildMode.Tool.TOILET_SINK).pressed.emit()
	assert_bool(_mode.apply_at(_at(Vector2i(6, 4))).ok).is_true()
	await await_idle_frame()
	assert_str(_menu.room_summary_label().text).is_equal(RoomRules.NO_OPENING)

	# Clicking Door inside the room tray arms Tool.DOOR without leaving the room tray.
	door_card.pressed.emit()
	await await_idle_frame()
	assert_int(_mode.tool).is_equal(BuildMode.Tool.DOOR)
	assert_bool(_menu.is_room_context()).is_true()
	assert_int(_menu.room_context_id()).is_equal(room_id)
	assert_bool(door_card.button_pressed).is_true()

	# Placing the door clears "Needs entrance" -> "Ready".
	var door_edit := BuildEdit.place_wall(
		Vector2i(5, 7), BuildGrid.Side.SOUTH, BuildGrid.WallKind.DOOR
	)
	var door_edits := DoorPlacement.edits_for(_mode.grid, door_edit)
	assert_bool(BuildTransaction.commit_plan(_mode.grid, door_edits, _finances.wallet).ok).is_true()
	await await_idle_frame()
	assert_str(_menu.room_summary_label().text).is_equal("Ready")

	# Door remains available in the Building tab as well.
	_menu.press_category(BuildMenu.category_index("building"))
	await await_idle_frame()
	assert_bool(_menu.is_room_context()).is_false()
	assert_bool(_menu.card(BuildMode.Tool.DOOR).is_visible_in_tree()).is_true()


func test_break_room_contextual_tray_offers_indoor_seating_and_room_panel_counts_all_seating(
) -> void:
	assert_str(BuildMenuCatalog.room_thumbnail(&"break_room")).is_equal("lounge_sofa")
	var room_id := _mode.grid.apply(BuildEdit.place_room(Rect2i(3, 3, 5, 5), &"break_room")).room_id
	_menu.enter_room_context(&"break_room", room_id)
	await await_idle_frame()
	(
		assert_array(_visible_room_tools())
		. is_equal(
			[
				BuildMode.Tool.SOFA,
				BuildMode.Tool.ARMCHAIR,
				BuildMode.Tool.BENCH,
				BuildMode.Tool.DOOR,
				BuildMode.Tool.BREAK_ROOM,
			]
		)
	)
	assert_str(_badge_text(_menu.card(BuildMode.Tool.SOFA))).is_equal("★")
	assert_str(_badge_text(_menu.card(BuildMode.Tool.ARMCHAIR))).is_equal("★")
	assert_str(_badge_text(_menu.card(BuildMode.Tool.BENCH))).is_equal("★")

	_menu.card(BuildMode.Tool.SOFA).pressed.emit()
	assert_bool(_mode.apply_at(_at(Vector2i(4, 4))).ok).is_true()
	_menu.card(BuildMode.Tool.ARMCHAIR).pressed.emit()
	assert_bool(_mode.apply_at(_at(Vector2i(4, 6))).ok).is_true()
	await await_idle_frame()
	assert_str(_badge_text(_menu.card(BuildMode.Tool.SOFA))).is_equal("✓")
	assert_str(_badge_text(_menu.card(BuildMode.Tool.ARMCHAIR))).is_equal("✓")
	assert_str(_badge_text(_menu.card(BuildMode.Tool.BENCH))).is_equal("✓")

	_mode.set_tool(BuildMode.Tool.NONE)
	_mode.update_room_focus(_at(Vector2i(4, 4)))
	var panel := _menu.room_panel()
	var texts: Array[String] = []
	for lbl in panel.find_children("*", "Label", true, false):
		if (lbl as Label).is_visible_in_tree():
			texts.append((lbl as Label).text)
	assert_array(texts).contains(["Break Room", "Seating 2"])
