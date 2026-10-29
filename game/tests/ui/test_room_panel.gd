class_name TestRoomPanel
extends GdUnitTestSuite
## The Shops category in BuildMenu (Cafe room, counter and table cards) and
## the room info panel that follows the room under the pointer.

var _port: SubViewport
var _mode: BuildMode
var _menu: BuildMenu


func before_test() -> void:
	_port = SubViewport.new()
	_port.size = Vector2i(1280, 720)
	add_child(_port)
	_mode = BuildMode.new()
	_mode.grid_size = Vector2i(20, 20)
	_port.add_child(_mode)
	# The tests point at rooms through update_room_focus(); with processing on,
	# BuildMode would follow the (camera-less) mouse each frame instead.
	_mode.set_process(false)
	_menu = BuildMenu.new()
	_menu.build_mode = _mode
	_port.add_child(_menu)
	var edits: Array[BuildEdit] = []
	for y in range(2, 12):
		for x in range(2, 14):
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	_mode.grid.apply_batch(edits)


func after_test() -> void:
	_port.free()


func _texts(control: Control) -> PackedStringArray:
	var out := PackedStringArray()
	for label in control.find_children("*", "Label", true, false):
		if (label as Label).is_visible_in_tree():
			out.append((label as Label).text)
	return out


func _cafe(rect := Rect2i(3, 3, 5, 4)) -> int:
	return _mode.grid.apply(BuildEdit.place_room(rect, &"cafe")).room_id


func _shops() -> int:
	for i in BuildMenu.CATEGORIES.size():
		if BuildMenu.CATEGORIES[i]["name"] == "Shops":
			return i
	return BuildMenu.NO_CATEGORY


func test_the_shops_category_holds_the_cafe_room_counter_and_table() -> void:
	var shops := _shops()
	assert_int(shops).is_not_equal(BuildMenu.NO_CATEGORY)
	assert_int(shops).is_less(BuildMenu.REMOVE_CATEGORY)
	assert_str(BuildMenu.CATEGORIES[BuildMenu.REMOVE_CATEGORY]["name"]).is_equal("Remove")
	_menu.category_button(shops).pressed.emit()
	for tool in [BuildMode.Tool.CAFE_ROOM, BuildMode.Tool.COUNTER, BuildMode.Tool.TABLE]:
		assert_bool(_menu.card(tool).is_visible_in_tree()).is_true()
	assert_array(Array(_texts(_menu.card(BuildMode.Tool.CAFE_ROOM)))).contains(
		["Cafe", "3x3 min", "Drag"]
	)
	assert_array(Array(_texts(_menu.card(BuildMode.Tool.COUNTER)))).contains(["Counter", "2x1"])
	assert_array(Array(_texts(_menu.card(BuildMode.Tool.TABLE)))).contains(["Table", "3x1"])


func test_the_cafe_card_picks_the_room_tool() -> void:
	_menu.category_button(_shops()).pressed.emit()
	_menu.card(BuildMode.Tool.CAFE_ROOM).pressed.emit()
	assert_int(_mode.tool).is_equal(BuildMode.Tool.CAFE_ROOM)
	assert_int(_menu.open_category()).is_equal(_shops())


func test_the_panel_is_hidden_with_no_room_under_the_pointer() -> void:
	assert_bool(_menu.room_panel().visible).is_false()


func test_the_panel_shows_type_notes_seats_and_spend_of_the_focused_room() -> void:
	var room_id := _cafe()
	_mode.set_tool(BuildMode.Tool.NONE)
	_mode.update_room_focus(_mode.grid.cell_to_world(Vector2i(4, 4)))
	var panel := _menu.room_panel()
	assert_bool(panel.visible).is_true()
	assert_int(panel.room_id()).is_equal(room_id)
	var texts := Array(_texts(panel))
	assert_array(texts).contains(["Cafe", "Needs a counter", "Needs a table", "Seats 0"])
	var spend := "Base spend $%d per visit" % RoomTypes.get_type(&"cafe").base_spend
	assert_array(texts).contains([spend])
	assert_array(texts).not_contains(["Ready"])


func test_the_panel_follows_furniture_placed_while_it_is_open() -> void:
	_cafe()
	_mode.set_tool(BuildMode.Tool.NONE)
	_mode.update_room_focus(_mode.grid.cell_to_world(Vector2i(4, 4)))
	_mode.grid.apply(BuildEdit.place_object(&"cafe_counter", Vector2i(4, 3), 0))
	_mode.grid.apply(BuildEdit.place_object(&"cafe_table", Vector2i(4, 6), 0))
	await get_tree().process_frame
	await get_tree().process_frame
	var texts := Array(_texts(_menu.room_panel()))
	assert_array(texts).contains(["Cafe", "Ready", "Seats 2"])
	assert_array(texts).not_contains(["Needs a counter"])


func test_the_panel_hides_when_the_pointer_leaves_the_room() -> void:
	_cafe()
	_mode.set_tool(BuildMode.Tool.NONE)
	_mode.update_room_focus(_mode.grid.cell_to_world(Vector2i(4, 4)))
	_mode.update_room_focus(_mode.grid.cell_to_world(Vector2i(12, 10)))
	assert_bool(_menu.room_panel().visible).is_false()


func test_the_panel_sits_top_left_below_the_money_slot() -> void:
	_cafe()
	_mode.set_tool(BuildMode.Tool.NONE)
	_mode.update_room_focus(_mode.grid.cell_to_world(Vector2i(4, 4)))
	await get_tree().process_frame
	await get_tree().process_frame
	var rect: Rect2 = _menu.room_panel().get_global_rect()
	var money := (_menu.money_label().get_parent() as Control).get_global_rect()
	print("room panel %s, money slot %s" % [rect, money])
	assert_float(rect.position.x).is_less(200.0)
	assert_float(rect.position.y).is_greater_equal(money.end.y)
	assert_float(rect.end.y).is_less(720.0 - BuildMenu.MARGIN - BuildMenu.BAR_H)
