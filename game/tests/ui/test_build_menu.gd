class_name TestBuildMenu
extends GdUnitTestSuite
## BuildMenu over a BuildMode: seven domain tabs + Templates + Remove + Staff,
## slider-free 9-column wrapping grid with compact 80x96 cards, unbound 1-9/0
## number keys, Esc, camera wheel isolation, and where the status line sits.

const BUILDING := 0
const OPERATIONS := 1
const FACILITIES := 2

var _port: SubViewport
var _mode: BuildMode
var _menu: BuildMenu
var _translation: Translation


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
	if _translation != null:
		TranslationServer.remove_translation(_translation)
		_translation = null
	_port.free()
	PseudoLocale.disable()


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
	assert_array(Array(_texts(_menu.card(BuildMode.Tool.BAG_ROOM)))).is_equal(
		["Bag room", "Free", "Room"]
	)
	assert_array(Array(_texts(_menu.card(BuildMode.Tool.TOILET_STALL)))).is_equal(
		["Toilet stall", "Free"]
	)
	for tool: BuildMode.Tool in BuildMode.Tool.values():
		var card := _menu.card(tool)
		if card == null:
			continue
		var lines := _texts(card)
		var expect_lines := 3 if BuildMenuCatalog.is_room_tool(tool) else 2
		assert_int(lines.size()).override_failure_message("tool %d %s" % [tool, lines]).is_equal(
			expect_lines
		)
		if BuildMenuCatalog.is_room_tool(tool):
			assert_array(Array(lines)).contains(["Room"])
		else:
			assert_array(Array(lines)).not_contains(["Room"])
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


func test_the_status_line_shows_a_refusal_above_the_tray_then_above_the_bar_when_closed() -> void:
	_mode.set_process(false)
	_mode.set_tool(BuildMode.Tool.DOOR)
	_mode._update_ghost(_mode.grid.cell_to_world(Vector2i(4, 4)))
	var result := _mode.apply_at(_mode.grid.cell_to_world(Vector2i(4, 4)))
	assert_bool(result.ok).is_false()
	assert_str(_menu.status_label().text).is_equal(_mode.status_text())
	assert_str(_menu.status_label().text).contains(result.reason_text())
	_menu.refresh_preview()
	await get_tree().process_frame
	assert_bool(_menu.status_card().visible).is_true()
	assert_bool(_menu.status_label().is_visible_in_tree()).is_true()
	var status := _menu.status_label().get_global_rect()
	var open_card := _menu.status_card().get_global_rect()
	var tray := _menu.tray().get_global_rect()
	var bar := _menu.bar().get_global_rect()
	assert_float(open_card.end.y).is_equal(tray.position.y - float(HudLayout.GAP))
	assert_bool(open_card.encloses(status)).is_true()
	assert_float(tray.end.y).is_less_equal(bar.position.y)
	_menu._on_wages_paid(60, 0)
	_push(_key(KEY_ESCAPE))
	_menu.refresh_preview()
	await get_tree().process_frame
	assert_bool(_menu.is_tray_open()).is_false()
	assert_bool(_menu.status_card().visible).is_true()
	assert_bool(_menu.status_label().is_visible_in_tree()).is_true()
	var closed_card := _menu.status_card().get_global_rect()
	var closed_status := _menu.status_label().get_global_rect()
	assert_float(closed_card.end.y).is_equal(bar.position.y - float(HudLayout.GAP))
	assert_bool(closed_card.encloses(closed_status)).is_true()
	assert_float(closed_card.size.x).is_equal(open_card.size.x)
	assert_float(closed_status.size.y).is_greater(0.0)


func test_every_tray_fits_its_reserved_space_and_expected_height() -> void:
	var expected_rows := {
		"building": 1,
		"operations": 2,
		"facilities": 3,
		"food": 2,
		"shops": 2,
		"decor": 2,
		"landside": 1,
	}
	_mode.set_tool(BuildMode.Tool.NONE)
	for i in BuildMenu.CATEGORIES.size():
		if i == BuildMenu.REMOVE_CATEGORY:
			continue
		_menu.category_button(i).pressed.emit()
		await get_tree().process_frame
		await get_tree().process_frame
		var cat_id := BuildMenu.category_id(i)
		var want_h := BuildMenu.tray_height_for_rows(int(expected_rows[cat_id]))
		assert_float(_menu.tray_height()).override_failure_message(cat_id).is_equal(want_h)
		var need := _menu.tray().get_combined_minimum_size()
		var rect := _menu.tray().get_global_rect()
		assert_float(need.y).is_less_equal(want_h)
		assert_float(rect.size.y).is_equal(want_h)
		assert_float(rect.size.x).is_less_equal(832.0)
		assert_float(need.x).is_less_equal(BuildMenu.COLUMN_W)
		assert_float(need.x).is_greater(BuildMenu.CARD_SIZE.x)
		for scroller in _menu.tray().find_children("*", "ScrollContainer", true, false):
			assert_bool((scroller as Control).is_visible_in_tree()).is_false()


func test_wrapping_grid_shows_all_cards_with_no_subfilters_and_shrinks_on_tab_switch() -> void:
	assert_object(_menu.find_child("FilterScroll", true, false)).is_null()
	assert_object(_menu.find_child("FilterBar", true, false)).is_null()
	assert_object(_menu.find_child("TrayScroll", true, false)).is_null()
	assert_int(_menu.tray().find_children("*", "VSeparator", true, false).size()).is_equal(0)
	_menu.press_category(FACILITIES)
	await get_tree().process_frame
	await get_tree().process_frame
	var facilities_grid := _menu.card(BuildMode.Tool.TOILET_ROOM).get_parent() as GridContainer
	assert_object(facilities_grid).is_instanceof(GridContainer)
	assert_int(facilities_grid.columns).is_equal(9)
	assert_float(_menu.tray_height()).is_equal(BuildMenu.tray_height_for_rows(3))
	assert_float(_menu.tray().size.y).is_equal(BuildMenu.tray_height_for_rows(3))
	for tool: BuildMode.Tool in BuildMenu.CATEGORIES[FACILITIES]["tools"]:
		assert_bool(_menu.card(tool).is_visible_in_tree()).is_true()
	# Switching from 3-row Facilities (310 px) back to 1-row Building (106 px) shrinks
	# PanelContainer.size.y immediately (anti-pattern 1caf2bb3).
	_menu.press_category(BUILDING)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_float(_menu.tray_height()).is_equal(BuildMenu.TRAY_H)
	assert_float(_menu.tray().size.y).is_equal(BuildMenu.TRAY_H)
	assert_float(_menu.tray().size.x).is_equal(7.0 * 80.0 + 6.0 * 6.0 + 24.0)


func test_mouse_wheel_over_tray_never_zooms_camera_and_has_no_horizontal_slider() -> void:
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
	# Positive control: a wheel event over open world outside the tray zooms the camera.
	var initial_dist := camera.target_distance
	var world_pt := Vector2(200.0, 200.0)
	assert_bool(_menu.tray().get_global_rect().has_point(world_pt)).is_false()
	_wheel(MOUSE_BUTTON_WHEEL_UP, world_pt)
	assert_float(camera.target_distance).is_not_equal(initial_dist)
	var start_dist := camera.target_distance
	var tray_rect := _menu.tray().get_global_rect()
	var card_pt := _menu.card(BuildMode.Tool.BUSH).get_global_rect().get_center()
	var pad_pt := tray_rect.position + Vector2(6.0, 6.0)
	for pt in [card_pt, pad_pt]:
		_wheel(MOUSE_BUTTON_WHEEL_UP, pt)
		_wheel(MOUSE_BUTTON_WHEEL_DOWN, pt)
		_wheel(MOUSE_BUTTON_WHEEL_LEFT, pt)
		_wheel(MOUSE_BUTTON_WHEEL_RIGHT, pt)
	assert_float(camera.target_distance).is_equal(start_dist)
	DirAccess.remove_absolute(camera.settings_path)


func test_arming_last_card_tool_on_closed_menu_shows_card_in_wrapping_grid() -> void:
	_mode.set_tool(BuildMode.Tool.NONE)
	assert_bool(_menu.is_tray_open()).is_false()
	_mode.set_tool(BuildMode.Tool.PLAY_SLIDE)
	await get_tree().process_frame
	await get_tree().process_frame
	var slide_card := _menu.card(BuildMode.Tool.PLAY_SLIDE)
	var tray_rect := _menu.tray().get_global_rect()
	var card_rect := slide_card.get_global_rect()
	assert_int(_menu.open_category()).is_equal(BuildMenu.category_index("facilities"))
	assert_bool(slide_card.is_visible_in_tree()).is_true()
	assert_float(tray_rect.size.x).is_less_equal(832.0)
	assert_bool(tray_rect.encloses(card_rect)).is_true()


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


func test_wrapping_grid_stays_rail_clear_under_pseudolocale_and_clamps_narrow_viewport() -> void:
	PseudoLocale.enable(0.4)
	var port := SubViewport.new()
	port.size = Vector2i(1536, 864)
	port.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	add_child(port)
	var mode := BuildMode.new()
	mode.grid_size = Vector2i(20, 20)
	port.add_child(mode)
	mode.set_process(false)
	var menu := BuildMenu.new()
	menu.build_mode = mode
	port.add_child(menu)
	menu.press_category(FACILITIES)
	await get_tree().process_frame
	await get_tree().process_frame
	var tray_rect := menu.tray().get_global_rect()
	assert_float(tray_rect.size.x).is_equal_approx(BuildMenu.COLUMN_W, 0.5)
	assert_float(tray_rect.size.x).is_less_equal(832.0)
	assert_float(tray_rect.size.y).is_equal_approx(BuildMenu.tray_height_for_rows(3), 0.5)
	assert_float(tray_rect.position.x).is_greater_equal(
		float(HudLayout.MARGIN + HudLayout.LIST_W + HudLayout.GROUP_GAP)
	)
	assert_float(tray_rect.end.x).is_less_equal(
		1536.0 - float(HudLayout.MARGIN + HudLayout.RAIL_W + HudLayout.GROUP_GAP)
	)
	for tool: BuildMode.Tool in BuildMenu.CATEGORIES[FACILITIES]["tools"]:
		var card := menu.card(tool)
		assert_bool(tray_rect.grow(0.5).encloses(card.get_global_rect())).is_true()
	# Narrow viewport (< 792 + 2 * MARGIN): columns reduce dynamically so the tray never clips.
	port.size = Vector2i(700, 720)
	await get_tree().process_frame
	await get_tree().process_frame
	tray_rect = menu.tray().get_global_rect()
	assert_int(menu.tray_columns()).is_equal(7)
	assert_bool(Rect2(Vector2.ZERO, Vector2(700.0, 720.0)).encloses(tray_rect)).is_true()
	assert_float(tray_rect.size.x).is_less_equal(700.0 - 2.0 * float(HudLayout.MARGIN) + 0.5)
	port.free()
