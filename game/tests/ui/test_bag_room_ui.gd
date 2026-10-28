class_name TestBagRoomUi
extends GdUnitTestSuite
## The bag room in the HUD (smoke playtest 3 notes 6, 7 and 12): the info panel
## shows bag room facts instead of shop figures, the tray card says the room
## needs a belt end, and Esc closes the panel without breaking the tool cancel.

const ROOM := Rect2i(3, 3, 3, 3)

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


func _texts(control: Control) -> Array:
	var out := []
	for label in control.find_children("*", "Label", true, false):
		if (label as Label).is_visible_in_tree():
			out.append((label as Label).text)
	return out


func _bag_room(with_end: bool) -> int:
	var room_id := _mode.grid.apply(BuildEdit.place_room(ROOM, &"bag_room")).room_id
	if with_end:
		PassengerTestWorld.place(_mode.grid, &"baggage_belt_end", ROOM.position, 0)
	_mode.set_tool(BuildMode.Tool.NONE)
	_mode.update_room_focus(_mode.grid.cell_to_world(Vector2i(4, 4)))
	return room_id


func _key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	return event


func test_the_panel_for_an_unfinished_bag_room_names_what_it_needs_and_no_shop_figures() -> void:
	_bag_room(false)
	var texts := _texts(_menu.room_panel())
	assert_array(texts).contains(["Bag room", "Needs a belt end"])
	for text in texts:
		assert_bool(text.begins_with("Seats")).override_failure_message(text).is_false()
		assert_bool(text.begins_with("Base spend")).override_failure_message(text).is_false()


func test_the_panel_for_a_ready_bag_room_says_ready_and_counts_its_belt_ends() -> void:
	_bag_room(true)
	var texts := _texts(_menu.room_panel())
	assert_array(texts).contains(["Bag room", "Ready", "Belt ends 1"])
	assert_array(texts).not_contains(["Needs a belt end"])
	for text in texts:
		assert_bool(text.begins_with("Seats")).override_failure_message(text).is_false()
		assert_bool(text.begins_with("Base spend")).override_failure_message(text).is_false()


func test_the_cafe_panel_keeps_its_seats_and_base_spend() -> void:
	_mode.grid.apply(BuildEdit.place_room(Rect2i(3, 3, 5, 4), &"cafe"))
	_mode.set_tool(BuildMode.Tool.NONE)
	_mode.update_room_focus(_mode.grid.cell_to_world(Vector2i(4, 4)))
	var spend := "Base spend $%d per visit" % RoomTypes.get_type(&"cafe").base_spend
	assert_array(_texts(_menu.room_panel())).contains(["Seats 0", spend])


func test_the_bag_room_card_says_it_needs_a_belt_end_inside_the_card() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var card := _menu.card(BuildMode.Tool.BAG_ROOM)
	var need: Label = null
	for label in card.find_children("*", "Label", true, false):
		if (label as Label).text.to_lower().contains("belt end"):
			need = label
	assert_object(need).override_failure_message("no belt end line on the card").is_not_null()
	if need == null:
		return
	assert_str(need.theme_type_variation).is_equal("HudAttentionText")
	var column := need.get_parent() as Control
	var inner := card.size - Vector2(12.0, 12.0)
	assert_float(column.get_combined_minimum_size().y).is_less_equal(inner.y)
	var font := need.get_theme_font("font")
	var width := font.get_string_size(
		need.text, HORIZONTAL_ALIGNMENT_LEFT, -1, need.get_theme_font_size("font_size")
	)
	assert_float(width.x).is_less_equal(inner.x)


func test_the_cafe_card_has_no_belt_end_line() -> void:
	var card := _menu.card(BuildMode.Tool.CAFE_ROOM)
	for text in _texts(card):
		assert_bool(text.to_lower().contains("belt end")).is_false()


func test_esc_closes_the_open_bag_room_panel_and_is_handled() -> void:
	_bag_room(false)
	assert_bool(_menu.room_panel().visible).is_true()
	_port.push_input(_key(KEY_ESCAPE))
	assert_bool(_menu.room_panel().visible).is_false()
	assert_int(_menu.room_panel().room_id()).is_equal(0)


func test_esc_with_the_panel_open_leaves_a_selected_room_tool_selected() -> void:
	_bag_room(false)
	_mode.set_tool(BuildMode.Tool.BAG_ROOM)
	_mode.update_room_focus(_mode.grid.cell_to_world(Vector2i(4, 4)))
	assert_bool(_menu.room_panel().visible).is_true()
	_port.push_input(_key(KEY_ESCAPE))
	assert_bool(_menu.room_panel().visible).is_false()
	assert_int(_mode.tool).is_equal(BuildMode.Tool.BAG_ROOM)


func test_esc_with_the_panel_closed_still_drops_the_tool() -> void:
	_mode.set_tool(BuildMode.Tool.WALL)
	_port.push_input(_key(KEY_ESCAPE))
	assert_int(_mode.tool).is_equal(BuildMode.Tool.NONE)


func test_the_panel_comes_back_when_the_pointer_enters_a_room_again() -> void:
	_bag_room(false)
	_port.push_input(_key(KEY_ESCAPE))
	_mode.update_room_focus(_mode.grid.cell_to_world(Vector2i(12, 10)))
	_mode.update_room_focus(_mode.grid.cell_to_world(Vector2i(4, 4)))
	assert_bool(_menu.room_panel().visible).is_true()
