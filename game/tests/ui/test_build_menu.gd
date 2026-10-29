class_name TestBuildMenu
extends GdUnitTestSuite
## BuildMenu over a BuildMode: category and tray switching, cards picking the
## tool, number keys, Esc, Remove, and where the status line sits.

const STRUCTURE := 0
const DOORS := 1
const CHECKIN := 2

## The menu and mode live in a 1280x720 SubViewport so layout and pushed
## input see a real screen size, not the headless window.
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
	assert_int(_menu.open_category()).is_equal(STRUCTURE)
	assert_bool(_menu.is_tray_open()).is_true()
	assert_bool(_menu.card(BuildMode.Tool.FLOOR).button_pressed).is_true()
	assert_array(_pressed_categories()).is_equal([STRUCTURE])


func test_clicking_a_category_opens_its_tray_and_picks_no_tool() -> void:
	_menu.category_button(CHECKIN).pressed.emit()
	assert_int(_menu.open_category()).is_equal(CHECKIN)
	assert_int(_mode.tool).is_equal(BuildMode.Tool.NONE)
	assert_bool(_menu.is_tray_open()).is_true()
	assert_bool(_menu.card(BuildMode.Tool.DESK).is_visible_in_tree()).is_true()
	assert_bool(_menu.card(BuildMode.Tool.FLOOR).is_visible_in_tree()).is_false()
	assert_bool(_menu.card(BuildMode.Tool.FLOOR).button_pressed).is_false()
	assert_array(_pressed_categories()).is_equal([CHECKIN])


func test_clicking_the_open_category_closes_the_tray() -> void:
	_menu.category_button(DOORS).pressed.emit()
	_menu.category_button(DOORS).pressed.emit()
	assert_int(_menu.open_category()).is_equal(BuildMenu.NO_CATEGORY)
	assert_bool(_menu.is_tray_open()).is_false()
	assert_array(_pressed_categories()).is_empty()


func test_a_card_click_picks_its_tool_and_marks_only_that_card() -> void:
	_menu.category_button(DOORS).pressed.emit()
	_menu.card(BuildMode.Tool.EXIT).pressed.emit()
	assert_int(_mode.tool).is_equal(BuildMode.Tool.EXIT)
	assert_int(_menu.open_category()).is_equal(DOORS)
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


func test_a_number_key_picks_the_tool_and_opens_its_category() -> void:
	_push(_key(KEY_3))
	assert_int(_mode.tool).is_equal(BuildMode.Tool.DESK)
	assert_int(_menu.open_category()).is_equal(CHECKIN)
	assert_bool(_menu.card(BuildMode.Tool.DESK).button_pressed).is_true()
	assert_array(_pressed_categories()).is_equal([CHECKIN])
	_push(_key(KEY_2))
	assert_int(_mode.tool).is_equal(BuildMode.Tool.WALL)
	assert_int(_menu.open_category()).is_equal(STRUCTURE)


func test_cards_show_their_key_size_and_price() -> void:
	assert_array(Array(_texts(_menu.card(BuildMode.Tool.DESK)))).contains(["Key 3", "2x1", "Free"])
	assert_array(Array(_texts(_menu.card(BuildMode.Tool.FLOOR)))).contains(["Key 1", "1x1 tile"])
	assert_array(Array(_texts(_menu.card(BuildMode.Tool.GLASS)))).contains(["Key 7", "1 m edge"])
	assert_array(Array(_texts(_menu.card(BuildMode.Tool.SEATS)))).contains(["Key 5", "3x1"])
	(
		assert_object(
			(
				(
					_menu
					. card(BuildMode.Tool.SCANNER)
					. find_children("*", "TextureRect", true, false)[0]
				)
				. texture
			)
		)
		. is_not_null()
	)


func test_esc_deselects_and_closes_the_tray() -> void:
	_mode.set_tool(BuildMode.Tool.SCANNER)
	assert_bool(_menu.is_tray_open()).is_true()
	_push(_key(KEY_ESCAPE))
	assert_int(_mode.tool).is_equal(BuildMode.Tool.NONE)
	assert_bool(_menu.is_tray_open()).is_false()
	assert_bool(_menu.card(BuildMode.Tool.SCANNER).button_pressed).is_false()
	assert_array(_pressed_categories()).is_empty()


func test_esc_closes_a_tray_opened_for_browsing() -> void:
	_menu.category_button(CHECKIN).pressed.emit()
	_push(_key(KEY_ESCAPE))
	assert_bool(_menu.is_tray_open()).is_false()


func test_remove_is_one_button_with_no_tray() -> void:
	_menu.category_button(BuildMenu.REMOVE_CATEGORY).pressed.emit()
	assert_int(_mode.tool).is_equal(BuildMode.Tool.REMOVE)
	assert_bool(_menu.is_tray_open()).is_false()
	assert_array(_pressed_categories()).is_equal([BuildMenu.REMOVE_CATEGORY])
	_push(_key(KEY_1))
	assert_array(_pressed_categories()).is_equal([STRUCTURE])


func test_the_status_line_shows_a_refusal_above_the_tray_and_never_moves() -> void:
	_mode.set_tool(BuildMode.Tool.DESK)
	var result := _mode.apply_at(_mode.grid.cell_to_world(Vector2i(4, 4)))
	assert_bool(result.ok).is_false()
	assert_str(_menu.status_label().text).is_equal(_mode.status_text())
	assert_str(_menu.status_label().text).contains(result.reason_text())
	await get_tree().process_frame
	var status := _menu.status_label().get_global_rect()
	var tray := _menu.tray().get_global_rect()
	print("status=%s tray=%s bar=%s" % [status, tray, _menu.bar().get_global_rect()])
	assert_float(status.end.y).is_less_equal(tray.position.y)
	assert_float(tray.end.y).is_less_equal(_menu.bar().get_global_rect().position.y)
	_push(_key(KEY_ESCAPE))
	await get_tree().process_frame
	assert_bool(_menu.is_tray_open()).is_false()
	assert_that(_menu.status_label().get_global_rect()).is_equal(status)


func test_every_tray_fits_its_reserved_space() -> void:
	_mode.set_tool(BuildMode.Tool.NONE)
	for i in BuildMenu.CATEGORIES.size():
		if i == BuildMenu.REMOVE_CATEGORY:
			continue
		_menu.category_button(i).pressed.emit()
		var need := _menu.tray().get_combined_minimum_size()
		print("category %d tray needs %s" % [i, need])
		assert_float(need.y).is_less_equal(BuildMenu.TRAY_H)
		assert_float(need.x).is_less_equal(BuildMenu.COLUMN_W)
		assert_float(need.x).is_greater(BuildMenu.CARD_SIZE.x)


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


func _assert_key_picks(code: Key, tool: BuildMode.Tool, category: int, hint: String) -> void:
	_mode.set_tool(BuildMode.Tool.NONE)
	_push(_key(code))
	assert_int(_mode.tool).is_equal(tool)
	assert_int(_menu.open_category()).is_equal(category)
	assert_bool(_menu.card(tool).button_pressed).is_true()
	assert_array(Array(_texts(_menu.card(tool)))).contains([hint])


func test_key_7_picks_glass() -> void:
	_assert_key_picks(KEY_7, BuildMode.Tool.GLASS, STRUCTURE, "Key 7")


func test_key_8_picks_door() -> void:
	_assert_key_picks(KEY_8, BuildMode.Tool.DOOR, STRUCTURE, "Key 8")


func test_key_9_picks_entrance() -> void:
	_assert_key_picks(KEY_9, BuildMode.Tool.ENTRANCE, DOORS, "Key 9")


func test_key_0_picks_exit() -> void:
	_assert_key_picks(KEY_0, BuildMode.Tool.EXIT, DOORS, "Key 0")


func test_the_cafe_room_counter_and_table_cards_show_their_renders() -> void:
	for tool in [BuildMode.Tool.CAFE_ROOM, BuildMode.Tool.COUNTER, BuildMode.Tool.TABLE]:
		var name: String = BuildMenu.item(tool)[1]
		var card := _menu.card(tool)
		var picture := card.find_children("*", "TextureRect", true, false)[0] as TextureRect
		assert_bool(BuildMenu.PLACEHOLDER_THUMBNAILS.has(name)).is_false()
		assert_object(picture.texture).override_failure_message(name).is_not_null()
		assert_str(picture.texture.resource_path).is_equal(BuildMenu.THUMBNAIL_DIR % name)
		assert_int(picture.find_children("*", "ColorRect", true, false).size()).is_equal(0)
