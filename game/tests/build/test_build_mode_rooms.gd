class_name TestBuildModeRooms
extends GdUnitTestSuite
## The Cafe room tool and room removal through BuildMode: a drag marks a
## rectangle of floor as a cafe, Remove takes furniture first, then the room,
## then floor, and the room under the pointer is followed for the info panel.

var _mode: BuildMode
var _changes := 0


func before_test() -> void:
	_mode = BuildMode.new()
	_mode.grid_size = Vector2i(20, 20)
	add_child(_mode)
	_changes = 0
	_mode.grid_changed.connect(func() -> void: _changes += 1)
	var edits: Array[BuildEdit] = []
	for y in range(2, 12):
		for x in range(2, 14):
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	_mode.grid.apply_batch(edits)


func after_test() -> void:
	_mode.free()


func _at(cell: Vector2i) -> Vector3:
	return _mode.grid.cell_to_world(cell)


func _drag(from: Vector2i, to: Vector2i) -> void:
	_mode.begin_area(_at(from))
	_mode.move_area(_at(to))
	_mode.finish_area()


func _mark_cafe(rect: Rect2i) -> int:
	_mode.set_tool(BuildMode.Tool.CAFE_ROOM)
	_drag(rect.position, rect.end - Vector2i.ONE)
	return _mode.grid.room_at(rect.position)


func _click(tool: BuildMode.Tool, cell: Vector2i) -> BuildResult:
	_mode.set_tool(tool)
	return _mode.apply_at(_at(cell))


func test_a_cafe_drag_marks_the_rectangle_as_a_cafe() -> void:
	var room_id := _mark_cafe(Rect2i(3, 3, 5, 4))
	assert_int(room_id).is_greater(0)
	var room := _mode.grid.get_room(room_id)
	assert_str(str(room["type"])).is_equal("cafe")
	assert_that(room["rect"]).is_equal(Rect2i(3, 3, 5, 4))
	assert_int(_changes).is_equal(1)
	assert_str(_mode.status_text()).is_equal("Cafe marked: Needs a counter")


func test_the_drag_status_names_the_room_and_its_size() -> void:
	_mode.set_tool(BuildMode.Tool.CAFE_ROOM)
	_mode.begin_area(_at(Vector2i(3, 3)))
	_mode.move_area(_at(Vector2i(6, 5)))
	_mode._update_ghost(_at(Vector2i(6, 5)))
	assert_str(_mode.status_text()).is_equal("Cafe 4 x 3")
	_mode.move_area(_at(Vector2i(15, 5)))
	_mode._update_ghost(_at(Vector2i(15, 5)))
	assert_str(_mode.status_text()).is_equal("Cafe 13 x 3  Needs floor")
	_mode.cancel_area()
	assert_array(_mode.grid.room_ids()).is_empty()


func test_a_cafe_over_bare_ground_is_refused_with_its_reason() -> void:
	_mode.set_tool(BuildMode.Tool.CAFE_ROOM)
	_drag(Vector2i(10, 3), Vector2i(15, 6))
	assert_array(_mode.grid.room_ids()).is_empty()
	assert_str(_mode.status_text()).is_equal("Needs floor")
	assert_int(_changes).is_equal(0)


func test_a_single_click_with_the_cafe_tool_marks_nothing() -> void:
	_mode.set_tool(BuildMode.Tool.CAFE_ROOM)
	_mode.begin_area(_at(Vector2i(4, 4)))
	_mode.finish_area()
	assert_array(_mode.grid.room_ids()).is_empty()
	assert_str(_mode.status_text()).is_equal("Drag to mark a cafe")


func test_counter_and_table_tools_place_the_cafe_pieces() -> void:
	assert_bool(_click(BuildMode.Tool.COUNTER, Vector2i(4, 3)).ok).is_true()
	assert_bool(_click(BuildMode.Tool.TABLE, Vector2i(4, 7)).ok).is_true()
	var defs := []
	for object_id in _mode.grid.object_ids():
		defs.append(str(_mode.grid.get_object(object_id)["def"]))
	defs.sort()
	assert_array(defs).is_equal(["cafe_counter", "cafe_table"])


func test_remove_takes_the_furniture_then_the_room_then_the_floor() -> void:
	var room_id := _mark_cafe(Rect2i(3, 3, 5, 4))
	_click(BuildMode.Tool.COUNTER, Vector2i(4, 3))
	var counter := _mode.grid.object_at(Vector2i(4, 3))
	var first := _click(BuildMode.Tool.REMOVE, Vector2i(4, 3))
	assert_int(first.object_id).is_equal(counter)
	assert_int(_mode.grid.room_at(Vector2i(4, 3))).is_equal(room_id)
	var second := _click(BuildMode.Tool.REMOVE, Vector2i(4, 3))
	assert_bool(second.ok).is_true()
	assert_int(second.room_id).is_equal(room_id)
	assert_array(_mode.grid.room_ids()).is_empty()
	assert_int(_mode.grid.floor_at(Vector2i(4, 3))).is_equal(BuildGrid.FLOOR_TILE)
	_click(BuildMode.Tool.REMOVE, Vector2i(4, 3))
	assert_int(_mode.grid.floor_at(Vector2i(4, 3))).is_equal(BuildGrid.FLOOR_NONE)


func test_a_remove_drag_over_a_room_takes_the_room_and_furniture_but_keeps_floor() -> void:
	_mark_cafe(Rect2i(3, 3, 5, 4))
	_click(BuildMode.Tool.COUNTER, Vector2i(4, 3))
	_mode.set_tool(BuildMode.Tool.REMOVE)
	_drag(Vector2i(2, 2), Vector2i(8, 7))
	assert_array(_mode.grid.room_ids()).is_empty()
	assert_array(_mode.grid.object_ids()).is_empty()
	assert_int(_mode.grid.floor_at(Vector2i(5, 5))).is_equal(BuildGrid.FLOOR_TILE)
	# Outside the room the same drag cleared the floor, as it always did.
	assert_int(_mode.grid.floor_at(Vector2i(2, 2))).is_equal(BuildGrid.FLOOR_NONE)
	_drag(Vector2i(2, 2), Vector2i(8, 7))
	assert_int(_mode.grid.floor_at(Vector2i(5, 5))).is_equal(BuildGrid.FLOOR_NONE)


func test_a_remove_drag_over_only_furniture_keeps_the_room() -> void:
	var room_id := _mark_cafe(Rect2i(3, 3, 5, 4))
	_click(BuildMode.Tool.TABLE, Vector2i(4, 5))
	_mode.set_tool(BuildMode.Tool.REMOVE)
	_drag(Vector2i(4, 5), Vector2i(6, 5))
	assert_array(_mode.grid.object_ids()).is_empty()
	assert_array(_mode.grid.room_ids()).is_equal([room_id])


func test_the_room_under_the_pointer_is_followed() -> void:
	var room_id := _mark_cafe(Rect2i(3, 3, 5, 4))
	var seen: Array[int] = []
	_mode.room_focus_changed.connect(func(id: int) -> void: seen.append(id))
	_mode.set_tool(BuildMode.Tool.NONE)
	_mode.update_room_focus(_at(Vector2i(4, 4)))
	_mode.update_room_focus(_at(Vector2i(5, 5)))
	assert_int(_mode.focused_room()).is_equal(room_id)
	_mode.update_room_focus(_at(Vector2i(10, 10)))
	_mode.update_room_focus(null)
	assert_array(seen).is_equal([room_id, 0])
	assert_int(_mode.focused_room()).is_equal(0)


func test_focus_clears_when_the_room_is_removed() -> void:
	var room_id := _mark_cafe(Rect2i(3, 3, 5, 4))
	_mode.set_tool(BuildMode.Tool.NONE)
	_mode.update_room_focus(_at(Vector2i(4, 4)))
	_mode.grid.apply(BuildEdit.remove_room(room_id))
	_mode.update_room_focus(_at(Vector2i(4, 4)))
	assert_int(_mode.focused_room()).is_equal(0)


func test_floor_and_wall_tools_do_not_follow_rooms() -> void:
	_mark_cafe(Rect2i(3, 3, 5, 4))
	_mode.set_tool(BuildMode.Tool.FLOOR)
	_mode.update_room_focus(_at(Vector2i(4, 4)))
	assert_int(_mode.focused_room()).is_equal(0)
