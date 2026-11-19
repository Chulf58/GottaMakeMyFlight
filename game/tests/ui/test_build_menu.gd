class_name TestBuildMenu
extends GdUnitTestSuite
## BuildMenu over a BuildMode: six domain tabs + Remove, compact cards picking
## the tool, unbound 1-9/0 number keys, Esc, horizontal scroll + camera wheel
## isolation, and where the status line sits.

const BUILDING := 0
const OPERATIONS := 1
const FACILITIES := 2

var _port: SubViewport
var _mode: BuildMode
var _menu: BuildMenu


func before_test() -> void:
	_port = SubViewport.new()
	_port.size = Vector2i(1536, 864)
	add_child(_port)
	_mode = BuildMode.new()
	_mode.grid_size = Vector2i(20, 20)
	_port.add_child(_mode)
	_menu = BuildMenu.new()
	_menu.build_mode = _mode
	_port.add_child(_menu)


func after_test() -> void:
	_port.free()


func _key(code: Key, pressed := true) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	return event


func _push(event: InputEvent) -> void:
	_port.push_input(event)


func _wheel(button: MouseButton, at: Vector2) -> void:
	for down in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = button
		ev.pressed = down
		ev.position = at
		ev.global_position = at
		_port.push_input(ev)


func _texts(control: Control) -> PackedStringArray:
	var out := PackedStringArray()
	for label in control.find_children("*", "Label", true, false):
		out.append((label as Label).text)
	return out


func _pressed_categories() -> Array[int]:
	var out: Array[int] = []
	for i in BuildMenu.CATEGORIES.size():
		if _menu.category_button(i).button_pressed:
			out.append(i)
	return out


func test_the_menu_starts_on_the_mode_s_tool() -> void:
	assert_int(_mode.tool).is_equal(BuildMode.Tool.FLOOR)
	assert_int(_menu.open_category()).is_equal(BUILDING)
	assert_bool(_menu.is_tray_open()).is_true()
	assert_bool(_menu.card(BuildMode.Tool.FLOOR).button_pressed).is_true()
	assert_array(_pressed_categories()).is_equal([BUILDING])


func test_clicking_a_category_opens_its_tray_and_picks_no_tool() -> void:
	_menu.category_button(OPERATIONS).pressed.emit()
	assert_int(_menu.open_category()).is_equal(OPERATIONS)
	assert_int(_mode.tool).is_equal(BuildMode.Tool.NONE)
	assert_bool(_menu.is_tray_open()).is_true()
	assert_bool(_menu.card(BuildMode.Tool.DESK).is_visible_in_tree()).is_true()
	assert_bool(_menu.card(BuildMode.Tool.FLOOR).is_visible_in_tree()).is_false()
	assert_bool(_menu.card(BuildMode.Tool.FLOOR).button_pressed).is_false()
	assert_array(_pressed_categories()).is_equal([OPERATIONS])


func test_clicking_the_open_category_closes_the_tray() -> void:
	_menu.category_button(OPERATIONS).pressed.emit()
	_menu.category_button(OPERATIONS).pressed.emit()
	assert_int(_menu.open_category()).is_equal(BuildMenu.NO_CATEGORY)
	assert_bool(_menu.is_tray_open()).is_false()
	assert_array(_pressed_categories()).is_empty()


func test_a_card_click_picks_its_tool_and_marks_only_that_card() -> void:
	_menu.category_button(BUILDING).pressed.emit()
	_menu.card(BuildMode.Tool.EXIT).pressed.emit()
	assert_int(_mode.tool).is_equal(BuildMode.Tool.EXIT)
	assert_int(_menu.open_category()).is_equal(BUILDING)
	assert_bool(_menu.card(BuildMode.Tool.EXIT).button_pressed).is_true()
	assert_bool(_menu.card(BuildMode.Tool.ENTRANCE).button_pressed).is_false()
	_menu.card(BuildMode.Tool.ENTRANCE).pressed.emit()
	assert_int(_mode.tool).is_equal(BuildMode.Tool.ENTRANCE)
	assert_bool(_menu.card(BuildMode.Tool.EXIT).button_pressed).is_false()


func test_clicking_the_selected_card_keeps_it_selected() -> void:
	var floor_card := _menu.card(BuildMode.Tool.FLOOR)
	floor_card.button_pressed = false
	floor_card.pressed.emit()
	assert_int(_mode.tool).is_equal(BuildMode.Tool.FLOOR)
	assert_bool(floor_card.button_pressed).is_true()


func test_number_keys_are_unbound_and_do_not_pick_build_tools() -> void:
	assert_array(BuildMode.TOOL_ACTIONS.keys()).is_equal([&"build_tool_none"])
	for action in [
		&"build_tool_floor",
		&"build_tool_wall",
		&"build_tool_desk",
		&"build_tool_scanner",
		&"build_tool_seats",
		&"build_tool_remove",
		&"build_tool_glass",
		&"build_tool_door",
		&"build_tool_entrance",
		&"build_tool_exit",
	]:
		assert_bool(InputMap.has_action(action)).is_false()
	_mode.set_tool(BuildMode.Tool.NONE)
	for code: Key in [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9, KEY_0]:
		_push(_key(code, true))
		_push(_key(code, false))
		assert_int(_mode.tool).is_equal(BuildMode.Tool.NONE)


func test_cards_show_only_thumbnail_name_and_price_on_face() -> void:
	assert_array(Array(_texts(_menu.card(BuildMode.Tool.DESK)))).is_equal(["Check-in desk", "Free"])
	assert_array(Array(_texts(_menu.card(BuildMode.Tool.FLOOR)))).is_equal(["Floor", "Free"])
	assert_array(Array(_texts(_menu.card(BuildMode.Tool.BAG_ROOM)))).is_equal(["Bag room", "Free"])
	assert_array(Array(_texts(_menu.card(BuildMode.Tool.TOILET_STALL)))).is_equal(
		["Toilet stall", "Free"]
	)
	for tool: BuildMode.Tool in BuildMode.Tool.values():
		var card := _menu.card(tool)
		if card == null:
			continue
		var lines := _texts(card)
		assert_int(lines.size()).is_equal(2)
		for line in lines:
			assert_bool(line.begins_with("Key ")).is_false()
			assert_str(line).is_not_equal("Click")
			assert_str(line).is_not_equal("Drag")
			assert_bool(line.begins_with("Upkeep ")).is_false()
			assert_str(line).is_not_equal("Needs belt end")
	var scanner_pic := (
		_menu.card(BuildMode.Tool.SCANNER).find_children("*", "TextureRect", true, false)[0]
		as TextureRect
	)
	assert_object(scanner_pic.texture).is_not_null()


func test_esc_deselects_and_closes_the_tray() -> void:
	_mode.set_tool(BuildMode.Tool.SCANNER)
	assert_bool(_menu.is_tray_open()).is_true()
	_push(_key(KEY_ESCAPE))
	assert_int(_mode.tool).is_equal(BuildMode.Tool.NONE)
	assert_bool(_menu.is_tray_open()).is_false()
	assert_bool(_menu.card(BuildMode.Tool.SCANNER).button_pressed).is_false()
	assert_array(_pressed_categories()).is_empty()


func test_esc_closes_a_tray_opened_for_browsing() -> void:
	_menu.category_button(OPERATIONS).pressed.emit()
	_push(_key(KEY_ESCAPE))
	assert_bool(_menu.is_tray_open()).is_false()


func test_remove_is_one_button_with_no_tray() -> void:
	_menu.category_button(BuildMenu.REMOVE_CATEGORY).pressed.emit()
	assert_int(_mode.tool).is_equal(BuildMode.Tool.REMOVE)
	assert_bool(_menu.is_tray_open()).is_false()
	assert_array(_pressed_categories()).is_equal([BuildMenu.REMOVE_CATEGORY])


func test_the_status_line_shows_a_refusal_above_the_tray_and_never_moves() -> void:
	_mode.set_tool(BuildMode.Tool.DESK)
	var result := _mode.apply_at(_mode.grid.cell_to_world(Vector2i(4, 4)))
	assert_bool(result.ok).is_false()
	assert_bool(RotateHint.applies(_mode)).is_true()
	assert_str(_menu.status_label().text).is_equal(_mode.status_text())
	assert_str(_menu.status_label().text).contains(result.reason_text())
	await get_tree().process_frame
	var status := _menu.status_label().get_global_rect()
	var tray := _menu.tray().get_global_rect()
	assert_float(status.end.y).is_less_equal(tray.position.y)
	assert_float(tray.end.y).is_less_equal(_menu.bar().get_global_rect().position.y)
	_push(_key(KEY_ESCAPE))
	await get_tree().process_frame
	assert_bool(_menu.is_tray_open()).is_false()
	assert_that(_menu.status_label().get_global_rect()).is_equal(status)


func test_every_tray_fits_its_reserved_space_and_constant_height() -> void:
	_mode.set_tool(BuildMode.Tool.NONE)
	for i in BuildMenu.CATEGORIES.size():
		if i == BuildMenu.REMOVE_CATEGORY:
			continue
		_menu.category_button(i).pressed.emit()
		await get_tree().process_frame
		await get_tree().process_frame
		var need := _menu.tray().get_combined_minimum_size()
		var rect := _menu.tray().get_global_rect()
		assert_float(need.y).is_less_equal(BuildMenu.TRAY_H)
		assert_float(rect.size.y).is_equal(BuildMenu.TRAY_H)
		assert_float(need.x).is_less_equal(BuildMenu.COLUMN_W)
		assert_float(need.x).is_greater(BuildMenu.CARD_SIZE.x)


func test_mouse_wheel_over_tray_scrolls_horizontally_and_never_zooms_camera() -> void:
	var camera := TycoonCamera.new()
	camera.settings_path = SaveTestKit.run_path("build_menu_wheel_cam")
	var eye := Camera3D.new()
	eye.name = "Camera3D"
	camera.add_child(eye)
	_port.add_child(camera)
	var decor := BuildMenu.category_index("decor")
	_menu.press_category(decor)
	await get_tree().process_frame
	await get_tree().process_frame
	var start_dist := camera.target_distance
	var center := _menu.tray().get_global_rect().get_center()
	assert_int(_menu.tray_scroll().scroll_horizontal).is_equal(0)
	# At left scroll end: wheel up does not zoom camera.
	_wheel(MOUSE_BUTTON_WHEEL_UP, center)
	assert_float(camera.target_distance).is_equal(start_dist)
	# Wheel down scrolls right without zooming camera.
	for _i in 4:
		_wheel(MOUSE_BUTTON_WHEEL_DOWN, center)
	assert_int(_menu.tray_scroll().scroll_horizontal).is_greater(0)
	assert_float(camera.target_distance).is_equal(start_dist)
	# Scroll all the way past right end: still never zooms camera.
	for _i in 40:
		_wheel(MOUSE_BUTTON_WHEEL_DOWN, center)
	assert_float(camera.target_distance).is_equal(start_dist)
	# Switching tabs resets scroll_horizontal to 0; short non-overflowing tab never zooms either.
	var unlocks := BuildUnlocks.new()
	unlocks.manual = true
	unlocks.rating = auto_free(AirportRating.new())
	unlocks.passengers = auto_free(PassengerSim.new())
	_port.add_child(unlocks)
	_mode.unlocks = unlocks
	_mode.require_unlocks = true
	_menu._refresh_cards()
	_menu.press_category(FACILITIES)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_int(_menu.tray_scroll().scroll_horizontal).is_equal(0)
	assert_float(_menu.tray().get_global_rect().size.x).is_less(BuildMenu.COLUMN_W)
	var short_center := _menu.tray().get_global_rect().get_center()
	_wheel(MOUSE_BUTTON_WHEEL_UP, short_center)
	_wheel(MOUSE_BUTTON_WHEEL_DOWN, short_center)
	_wheel(MOUSE_BUTTON_WHEEL_LEFT, short_center)
	_wheel(MOUSE_BUTTON_WHEEL_RIGHT, short_center)
	assert_float(camera.target_distance).is_equal(start_dist)
	DirAccess.remove_absolute(camera.settings_path)


func test_a_rectangle_released_over_the_tray_is_still_applied() -> void:
	await get_tree().process_frame
	var world := MouseButton.MOUSE_BUTTON_LEFT
	var press := InputEventMouseButton.new()
	press.button_index = world
	press.pressed = true
	press.position = Vector2(640.0, 200.0)
	_push(press)
	assert_bool(_menu.tray().get_global_rect().has_point(press.position)).is_false()
	_mode.begin_area(_mode.grid.cell_to_world(Vector2i(2, 2)))
	_mode.move_area(_mode.grid.cell_to_world(Vector2i(5, 4)))
	var release := InputEventMouseButton.new()
	release.button_index = world
	release.pressed = false
	release.position = _menu.card(BuildMode.Tool.WALL).get_global_rect().get_center()
	assert_bool(_menu.card(BuildMode.Tool.WALL).is_visible_in_tree()).is_true()
	_push(release)
	assert_str(_mode.status_text()).is_equal("Placed 12")
	assert_int(_mode.grid.floor_at(Vector2i(5, 4))).is_equal(BuildGrid.FLOOR_TILE)
	assert_int(_mode.tool).is_equal(BuildMode.Tool.FLOOR)


func test_the_cafe_room_counter_and_table_cards_show_their_renders() -> void:
	for tool in [BuildMode.Tool.CAFE_ROOM, BuildMode.Tool.COUNTER, BuildMode.Tool.TABLE]:
		var thumb_name: String = BuildMenu.item(tool)[1]
		var card := _menu.card(tool)
		var picture := card.find_children("*", "TextureRect", true, false)[0] as TextureRect
		assert_bool(BuildMenu.PLACEHOLDER_THUMBNAILS.has(thumb_name)).is_false()
		assert_object(picture.texture).override_failure_message(thumb_name).is_not_null()
		assert_str(picture.texture.resource_path).is_equal(BuildMenu.THUMBNAIL_DIR % thumb_name)
		assert_int(picture.find_children("*", "ColorRect", true, false).size()).is_equal(0)
