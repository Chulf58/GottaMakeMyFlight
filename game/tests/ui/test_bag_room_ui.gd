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
	for y in range(3, 12):
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


func _bag_room(with_end: bool, connected := false) -> int:
	var room_id := _mode.grid.apply(BuildEdit.place_room(ROOM, &"bag_room")).room_id
	if with_end:
		(
			assert_bool(
				_mode.grid.apply(BuildEdit.place_object(&"baggage_bay_door", Vector2i(4, 3), 0)).ok
			)
			. is_true()
		)
		PassengerTestWorld.place(_mode.grid, &"baggage_belt_end", ROOM.position, 0)
	if connected:
		PassengerTestWorld.place(_mode.grid, &"checkin_desk", Vector2i(2, 6), 0)
		var plan := BeltShaper.plan_line(_mode.grid, Vector2i(3, 5), ROOM.position, 0)
		assert_bool(plan.result.ok).is_true()
		_mode.grid.apply_batch(plan.edits)
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
	assert_array(texts).contains(
		["Bag room", "Needs a belt dragged inside", "Belt ends 0", "Desks connected: 0"]
	)
	for text in texts:
		assert_bool(text.begins_with("Seats")).override_failure_message(text).is_false()
		assert_bool(text.begins_with("Base spend")).override_failure_message(text).is_false()


func test_the_panel_for_a_bag_room_with_end_but_zero_desks_is_amber_not_ready() -> void:
	_bag_room(true, false)
	var texts := _texts(_menu.room_panel())
	assert_array(texts).contains(
		["Bag room", "Waiting for belt from check-in desk", "Belt ends 1", "Desks connected: 0"]
	)
	assert_array(texts).not_contains(["Ready", "Needs a belt dragged inside"])
	var status_label: Label = null
	for label in _menu.room_panel().find_children("*", "Label", true, false):
		if (label as Label).text == "Waiting for belt from check-in desk":
			status_label = label as Label
	assert_object(status_label).is_not_null()
	assert_str(String(status_label.theme_type_variation)).is_equal("HudAttentionText")


func test_the_panel_for_a_connected_bag_room_says_ready_and_counts_desks() -> void:
	_bag_room(true, true)
	var texts := _texts(_menu.room_panel())
	assert_array(texts).contains(["Bag room", "Ready", "Belt ends 1", "Desks connected: 1"])
	assert_array(texts).not_contains(
		["Needs a belt dragged inside", "Waiting for belt from check-in desk"]
	)
	for text in texts:
		assert_bool(text.begins_with("Seats")).override_failure_message(text).is_false()
		assert_bool(text.begins_with("Base spend")).override_failure_message(text).is_false()


func test_the_panel_warns_when_a_cart_is_placed_with_no_ramp_agent() -> void:
	var staff: StaffSim = auto_free(StaffSim.new())
	_menu.room_panel().staff = staff
	_bag_room(true, true)
	PassengerTestWorld.place(_mode.grid, &"baggage_cart", Vector2i(4, 4), 0)
	_menu.room_panel().show_room(_mode.grid.room_at(Vector2i(4, 4)))
	assert_array(_texts(_menu.room_panel())).contains(["Needs a Ramp Agent (Staff)"])
	staff.hire(StaffMember.Role.RAMP)
	_menu.room_panel().show_room(_mode.grid.room_at(Vector2i(4, 4)))
	assert_array(_texts(_menu.room_panel())).not_contains(["Needs a Ramp Agent (Staff)"])


func test_cart_hover_info_mentions_hiring_a_ramp_agent_in_staff() -> void:
	_menu.press_category(BuildMenu.category_index("operations"))
	var card := _menu.card(BuildMode.Tool.CART) as ItemCardButton
	var tooltip := card._get_tooltip(Vector2.ZERO)
	assert_str(tooltip).contains("Ramp Agent")
	assert_str(tooltip).contains("Staff")


func test_the_cafe_panel_keeps_its_seats_and_base_spend() -> void:
	_mode.grid.apply(BuildEdit.place_room(Rect2i(3, 3, 5, 4), &"cafe"))
	_mode.set_tool(BuildMode.Tool.NONE)
	_mode.update_room_focus(_mode.grid.cell_to_world(Vector2i(4, 4)))
	var spend := "Base spend $%d per visit" % RoomTypes.get_type(&"cafe").base_spend
	assert_array(_texts(_menu.room_panel())).contains(["Seats 0", spend])


func test_the_bag_room_hover_card_says_it_needs_a_belt_end_in_attention_style() -> void:
	_menu.press_category(BuildMenu.category_index("operations"))
	var card := _menu.card(BuildMode.Tool.BAG_ROOM) as ItemCardButton
	var popup: Control = auto_free(card._make_custom_tooltip(card.tooltip_text))
	var need: Label = null
	for label in popup.find_children("*", "Label", true, false):
		if (label as Label).text == "Needs belt end":
			need = label
	assert_object(need).override_failure_message("no belt end chip in hover popup").is_not_null()
	if need == null:
		return
	assert_str(String(need.theme_type_variation)).is_equal("HudAttentionText")
	var face := _texts(card)
	assert_bool(face.is_empty()).is_false()
	for text in face:
		assert_bool(text.to_lower().contains("belt end")).is_false()


func test_the_cafe_card_has_no_belt_end_line() -> void:
	_menu.press_category(BuildMenu.category_index("food"))
	var card := _menu.card(BuildMode.Tool.CAFE_ROOM)
	var face := _texts(card)
	assert_bool(face.is_empty()).is_false()
	for text in face:
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
