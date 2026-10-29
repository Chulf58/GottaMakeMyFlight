class_name TestBuildMenuCardHint
extends GdUnitTestSuite
## The last line of a keyless item card says how the tool is used (smoke 9 note
## 1, board item 73e15dd7): a rectangle or line tool is drawn by dragging, any
## other is a click. A drag held by the pointer being over the HUD keeps the
## status line visible, because the line says why the rectangle stopped (note 2).

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


func after_test() -> void:
	_port.free()


func _last_line(tool: BuildMode.Tool) -> String:
	var labels := _menu.card(tool).find_children("*", "Label", true, false)
	return (labels[labels.size() - 1] as Label).text


func test_every_keyless_area_tool_card_says_drag() -> void:
	var checked := 0
	for tool in BuildMode.AREA_TOOLS:
		if BuildMenu.key_hint(tool) != "" or _menu.card(tool) == null:
			continue
		if BuildMenu.CARD_NEEDS.has(tool) or BuildMenu.CARD_RUNNING_COSTS.has(tool):
			continue
		assert_str(_last_line(tool)).override_failure_message("tool %d" % tool).is_equal("Drag")
		checked += 1
	print("keyless area tools with a hint line: %d" % checked)
	# Belt and Toilet room are two of them.
	assert_int(checked).is_greater_equal(2)
	assert_str(_last_line(BuildMode.Tool.TOILET_ROOM)).is_equal("Drag")
	assert_str(_last_line(BuildMode.Tool.BELT)).is_equal("Drag")


func test_a_keyless_placed_item_card_still_says_click() -> void:
	assert_str(_last_line(BuildMode.Tool.TOILET_SINK)).is_equal("Click")


func test_a_card_with_a_key_shows_the_key() -> void:
	assert_str(_last_line(BuildMode.Tool.DESK)).is_equal("Key 3")


func test_the_status_line_stays_visible_while_the_hud_holds_a_drag() -> void:
	_mode.set_tool(BuildMode.Tool.FLOOR)
	_mode.begin_area(_mode.grid.cell_to_world(Vector2i(3, 3)))
	_mode.move_area(_mode.grid.cell_to_world(Vector2i(8, 8)))
	_mode._area_over_ui = true
	_mode._hide_area_ghost()
	_menu.refresh_preview()
	assert_str(_menu.status_label().text).is_equal(BuildMode.DRAG_OVER_UI)
	assert_bool(_menu.status_label().visible).is_true()
	_mode._area_over_ui = false
	_mode.cancel_area()
	_menu.refresh_preview()
	assert_bool(_menu.status_label().visible).is_false()
