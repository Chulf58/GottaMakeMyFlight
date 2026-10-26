class_name TestBuildModeAreaDrag
extends GdUnitTestSuite
## BuildMode's Floor and Remove rectangle drag: press, drag, release, cancel,
## the ghost, the status line and the single click.

var _mode: BuildMode
var _changes := 0


func before_test() -> void:
	_mode = BuildMode.new()
	_mode.grid_size = Vector2i(20, 20)
	add_child(_mode)
	_changes = 0
	_mode.grid_changed.connect(func() -> void: _changes += 1)


func after_test() -> void:
	_mode.free()


func _at(cell: Vector2i) -> Vector3:
	return _mode.grid.cell_to_world(cell)


func _drag(from: Vector2i, to: Vector2i) -> void:
	_mode.begin_area(_at(from))
	_mode.move_area(_at(to))


func _floored(cell: Vector2i) -> bool:
	return _mode.grid.floor_at(cell) == BuildGrid.FLOOR_TILE


func _ghost() -> Node3D:
	return _mode.get_node("Ghost") as Node3D


func _key(action: StringName, pressed := true) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = KEY_ESCAPE
	event.physical_keycode = KEY_ESCAPE
	event.pressed = pressed
	assert_bool(event.is_action(action)).is_true()
	return event


func test_a_floor_drag_fills_the_rectangle_on_release_only() -> void:
	_mode.set_tool(BuildMode.Tool.FLOOR)
	_drag(Vector2i(3, 3), Vector2i(7, 5))
	assert_bool(_floored(Vector2i(4, 4))).is_false()
	var outcome := _mode.finish_area()
	assert_int(outcome.placed).is_equal(15)
	for y in range(3, 6):
		for x in range(3, 8):
			assert_bool(_floored(Vector2i(x, y))).is_true()
	assert_bool(_floored(Vector2i(8, 5))).is_false()
	assert_int(_changes).is_equal(1)
	assert_str(_mode.status_text()).is_equal("Placed 15")


func test_dragging_up_and_left_fills_the_same_rectangle() -> void:
	_mode.set_tool(BuildMode.Tool.FLOOR)
	_drag(Vector2i(7, 5), Vector2i(3, 3))
	_mode.finish_area()
	assert_bool(_floored(Vector2i(3, 3))).is_true()
	assert_bool(_floored(Vector2i(7, 5))).is_true()


func test_the_status_line_shows_the_size_while_dragging() -> void:
	_mode.set_tool(BuildMode.Tool.FLOOR)
	_drag(Vector2i(2, 2), Vector2i(13, 9))
	assert_str(_mode.status_text()).is_equal("")
	_mode._process(0.0)
	assert_str(_mode.status_text()).is_equal("12 x 8")
	assert_int(_ghost().get_child_count()).is_equal(1)
	assert_bool(_ghost().visible).is_true()


func test_the_ghost_is_one_slab_over_the_rectangle() -> void:
	_mode.set_tool(BuildMode.Tool.FLOOR)
	_drag(Vector2i(2, 2), Vector2i(5, 3))
	_mode._process(0.0)
	var slab := _ghost().get_child(0) as MeshInstance3D
	assert_float((slab.mesh as BoxMesh).size.x).is_equal_approx(3.96, 0.001)
	assert_float((slab.mesh as BoxMesh).size.z).is_equal_approx(1.96, 0.001)
	var middle := (_at(Vector2i(2, 2)) + _at(Vector2i(5, 3))) / 2.0
	assert_float(slab.position.x).is_equal_approx(middle.x, 0.001)
	assert_float(slab.position.z).is_equal_approx(middle.z, 0.001)


func test_cancel_applies_nothing_and_the_release_after_it_does_nothing() -> void:
	_mode.set_tool(BuildMode.Tool.FLOOR)
	_drag(Vector2i(3, 3), Vector2i(7, 5))
	_mode.cancel_area()
	assert_object(_mode.finish_area()).is_null()
	assert_bool(_floored(Vector2i(4, 4))).is_false()
	assert_int(_changes).is_equal(0)


func test_escape_cancels_the_drag_and_keeps_the_tool() -> void:
	_mode.set_tool(BuildMode.Tool.FLOOR)
	_drag(Vector2i(3, 3), Vector2i(7, 5))
	_mode._unhandled_input(_key(&"build_tool_none"))
	assert_int(_mode.tool).is_equal(BuildMode.Tool.FLOOR)
	assert_object(_mode.finish_area()).is_null()
	assert_bool(_floored(Vector2i(4, 4))).is_false()


func test_right_click_cancels_the_drag() -> void:
	_mode.set_tool(BuildMode.Tool.REMOVE)
	_drag(Vector2i(3, 3), Vector2i(7, 5))
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_RIGHT
	click.pressed = true
	_mode._unhandled_input(click)
	assert_object(_mode.finish_area()).is_null()
	assert_int(_changes).is_equal(0)


func test_picking_another_tool_mid_drag_drops_the_rectangle() -> void:
	_mode.set_tool(BuildMode.Tool.FLOOR)
	_drag(Vector2i(3, 3), Vector2i(7, 5))
	_mode.set_tool(BuildMode.Tool.WALL)
	assert_object(_mode.finish_area()).is_null()
	assert_bool(_floored(Vector2i(4, 4))).is_false()


func test_a_press_and_release_on_one_cell_is_the_old_click() -> void:
	_mode.set_tool(BuildMode.Tool.FLOOR)
	_mode.begin_area(_at(Vector2i(4, 6)) + Vector3(0.3, 0.0, -0.2))
	assert_object(_mode.finish_area()).is_null()
	assert_bool(_floored(Vector2i(4, 6))).is_true()
	assert_int(_mode.grid.zone_at(Vector2i(4, 6))).is_equal(BuildMode.TERMINAL_ZONE)
	assert_int(_changes).is_equal(1)


func test_a_single_remove_click_still_takes_a_wall_near_the_edge() -> void:
	_mode.set_tool(BuildMode.Tool.FLOOR)
	_drag(Vector2i(2, 2), Vector2i(6, 6))
	_mode.finish_area()
	_mode.grid.apply(BuildEdit.place_wall(Vector2i(3, 3), BuildGrid.Side.NORTH))
	_mode.set_tool(BuildMode.Tool.REMOVE)
	_mode.begin_area(_at(Vector2i(3, 3)) + Vector3(0.0, 0.0, -0.4))
	_mode.finish_area()
	assert_bool(_mode.grid.has_wall(Vector2i(3, 3), BuildGrid.Side.NORTH)).is_false()
	assert_bool(_floored(Vector2i(3, 3))).is_true()


func test_a_press_outside_the_grid_is_refused_as_a_click() -> void:
	_mode.set_tool(BuildMode.Tool.FLOOR)
	_mode.begin_area(_at(Vector2i(-3, 4)))
	assert_object(_mode.finish_area()).is_null()
	assert_str(_mode.status_text()).is_equal(
		BuildResult.REASON_TEXT[BuildResult.Reason.OUT_OF_BOUNDS]
	)


func test_a_remove_drag_clears_floor_and_the_object_it_touches() -> void:
	_mode.set_tool(BuildMode.Tool.FLOOR)
	_drag(Vector2i(2, 2), Vector2i(9, 9))
	_mode.finish_area()
	_mode.set_tool(BuildMode.Tool.DESK)
	assert_bool(_mode.apply_at(_at(Vector2i(4, 4))).ok).is_true()
	_mode.set_tool(BuildMode.Tool.REMOVE)
	_drag(Vector2i(4, 4), Vector2i(4, 5))
	var outcome := _mode.finish_area()
	assert_int(outcome.placed).is_equal(2)
	assert_array(_mode.grid.object_ids()).is_empty()
	assert_bool(_floored(Vector2i(4, 4))).is_true()
	assert_bool(_floored(Vector2i(4, 5))).is_false()
	assert_str(_mode.status_text()).is_equal("Removed 2")


func test_the_summary_stays_on_the_status_line_until_the_pointer_leaves_the_cell() -> void:
	_mode.set_tool(BuildMode.Tool.FLOOR)
	# The far corner is outside the grid, so the rectangle stops at its edge.
	_drag(Vector2i(17, 3), Vector2i(23, 4))
	var outcome := _mode.finish_area()
	assert_int(outcome.placed).is_equal(6)
	assert_str(_mode.status_text()).is_equal("Placed 6")
	_mode.set_tool(BuildMode.Tool.REMOVE)
	_drag(Vector2i(0, 0), Vector2i(1, 1))
	_mode.finish_area()
	assert_str(_mode.status_text()).is_equal("Nothing to remove")
	_mode._process(0.0)
	assert_str(_mode.status_text()).is_equal("")
