class_name TestBuildMenuOffGrid
extends GdUnitTestSuite
## BuildMenu with the pointer over ground outside the grid (smoke playtest of
## 46c5a70: at launch "Cost 25" and "Outside the building area" sat over the
## shell wall): the cost line is empty and the status line is hidden, and a
## grant message still shows.

var _port: SubViewport
var _mode: BuildMode
var _menu: BuildMenu


func before_test() -> void:
	_port = SubViewport.new()
	_port.size = Vector2i(1280, 720)
	add_child(_port)
	var finances := Finances.new()
	_port.add_child(finances)
	_mode = BuildMode.new()
	_mode.grid_size = Vector2i(20, 20)
	_mode.finances = finances
	_port.add_child(_mode)
	_menu = BuildMenu.new()
	_menu.build_mode = _mode
	_port.add_child(_menu)


func after_test() -> void:
	_port.free()


func _at(cell: Vector2i) -> Vector3:
	return _mode.grid.cell_to_world(cell)


func test_the_cost_line_is_empty_over_ground_outside_the_grid() -> void:
	_mode.set_tool(BuildMode.Tool.ENTRANCE)
	_mode._update_ghost(_at(Vector2i(-3, -3)))
	assert_object(_mode.hover_edit()).is_not_null()
	_menu.refresh_preview()
	assert_str(_menu.preview_label().text).is_equal("")
	assert_bool(_menu.preview_label().visible).is_false()


func test_the_status_line_is_hidden_over_ground_outside_the_grid() -> void:
	_mode._update_ghost(_at(Vector2i(-3, -3)))
	assert_str(_mode.status_text()).is_equal(
		BuildResult.refused(BuildResult.Reason.OUT_OF_BOUNDS).reason_text()
	)
	_menu.refresh_preview()
	assert_bool(_menu.status_label().visible).is_false()
	# Back over a cell, the status line is shown again.
	_mode._update_ghost(_at(Vector2i(3, 3)))
	_menu.refresh_preview()
	assert_bool(_menu.status_label().visible).is_true()


func test_the_status_line_is_hidden_when_the_pointer_leaves_the_grid_for_the_hud() -> void:
	_mode.set_tool(BuildMode.Tool.ENTRANCE)
	_mode._update_ghost(_at(Vector2i(3, 3)))
	_menu.refresh_preview()
	assert_str(_mode.status_text()).is_not_equal("")
	assert_bool(_menu.status_label().visible).is_true()
	# Over a HUD Control BuildMode drops the hover but keeps the status text.
	_mode._update_ghost(null)
	assert_object(_mode.hover_edit()).is_null()
	assert_str(_mode.status_text()).is_not_equal("")
	_menu.refresh_preview()
	assert_bool(_menu.status_label().visible).is_false()


func _floor(rect: Rect2i) -> void:
	var edits: Array[BuildEdit] = []
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	_mode.grid.apply_batch(edits)


func test_a_room_tool_hint_shows_over_a_cell_before_the_drag() -> void:
	_mode.set_tool(BuildMode.Tool.CAFE_ROOM)
	_mode._update_ghost(_at(Vector2i(3, 3)))
	# A room tool makes no edit before a drag, but the pointer is over a cell.
	assert_object(_mode.hover_edit()).is_null()
	_menu.refresh_preview()
	assert_str(_menu.status_label().text).is_equal("Drag to mark a cafe")
	assert_bool(_menu.status_label().visible).is_true()


func test_the_room_result_shows_after_a_valid_drag() -> void:
	_floor(Rect2i(2, 2, 8, 6))
	_mode.set_tool(BuildMode.Tool.CAFE_ROOM)
	_mode._update_ghost(_at(Vector2i(3, 3)))
	_mode.begin_area(_at(Vector2i(3, 3)))
	_mode.move_area(_at(Vector2i(6, 5)))
	_mode._update_ghost(_at(Vector2i(6, 5)))
	_menu.refresh_preview()
	assert_bool(_menu.status_label().visible).is_true()
	_mode.finish_area()
	_mode._update_ghost(_at(Vector2i(6, 5)))
	_menu.refresh_preview()
	assert_str(_menu.status_label().text).starts_with("Cafe marked")
	assert_bool(_menu.status_label().visible).is_true()


func test_a_room_tool_hint_is_hidden_when_the_pointer_leaves_the_grid() -> void:
	_mode.set_tool(BuildMode.Tool.CAFE_ROOM)
	_mode._update_ghost(_at(Vector2i(3, 3)))
	_menu.refresh_preview()
	assert_bool(_menu.status_label().visible).is_true()
	_mode._update_ghost(null)
	_menu.refresh_preview()
	assert_bool(_menu.status_label().visible).is_false()
	_mode._update_ghost(_at(Vector2i(-3, -3)))
	_menu.refresh_preview()
	assert_bool(_menu.status_label().visible).is_false()


func test_a_grant_message_shows_even_with_the_pointer_off_the_grid() -> void:
	_mode._update_ghost(_at(Vector2i(-3, -3)))
	_menu._on_granted(100, "Rescue grant")
	_menu.refresh_preview()
	assert_bool(_menu.status_label().visible).is_true()
	assert_str(_menu.status_label().text).is_equal("Rescue grant")
