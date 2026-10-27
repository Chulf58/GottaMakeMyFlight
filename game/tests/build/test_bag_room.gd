class_name TestBagRoom
extends GdUnitTestSuite
## The bag room type and the belt tools (decision baggage-rides-a-player-
## built-belt-from-check-in-to-a-bag-roo): a bag room needs a belt end, the
## Bag room tool drags a rectangle like the Cafe tool, and each belt tool
## places its piece.

const NEEDS_END := "Needs a belt end"
const NEEDS_OPENING := "Needs a door or open side to the walkway"
const ROOM := Rect2i(3, 3, 3, 3)

var _mode: BuildMode


func before_test() -> void:
	_mode = BuildMode.new()
	_mode.grid_size = Vector2i(20, 20)
	add_child(_mode)
	var edits: Array[BuildEdit] = []
	for y in range(2, 12):
		for x in range(2, 14):
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	_mode.grid.apply_batch(edits)


func after_test() -> void:
	_mode.free()


func _at(cell: Vector2i) -> Vector3:
	return _mode.grid.cell_to_world(cell)


func _mark_bag_room(rect: Rect2i) -> int:
	_mode.set_tool(BuildMode.Tool.BAG_ROOM)
	_mode.begin_area(_at(rect.position))
	_mode.move_area(_at(rect.end - Vector2i.ONE))
	_mode.finish_area()
	return _mode.grid.room_at(rect.position)


func _click(tool: BuildMode.Tool, cell: Vector2i) -> BuildResult:
	_mode.set_tool(tool)
	return _mode.apply_at(_at(cell))


func _notes(room_id: int) -> Array:
	return Array(RoomRules.status(_mode.grid, room_id).notes)


func test_the_bag_room_type_requires_a_belt_end_and_seats_nobody() -> void:
	var type := RoomTypes.get_type(&"bag_room")
	assert_str(type.display_name).is_equal("Bag room")
	assert_array(type.required).is_equal([[&"baggage_belt_end", NEEDS_END]])
	assert_int(type.seats_per_piece).is_equal(0)
	assert_int(type.base_spend).is_equal(0)
	assert_bool(type.fits(Vector2i(2, 2))).is_true()
	assert_bool(type.fits(Vector2i(1, 3))).is_false()
	assert_array(RoomTypes.ids()).contains([&"cafe", &"bag_room"])


func test_a_bag_room_without_an_end_is_not_ready() -> void:
	var room_id := _mark_bag_room(ROOM)
	assert_int(room_id).is_greater(0)
	var status := RoomRules.status(_mode.grid, room_id)
	assert_bool(status.ok).is_false()
	assert_array(_notes(room_id)).is_equal([NEEDS_END])
	assert_str(status.type_name).is_equal("Bag room")
	assert_int(status.seats).is_equal(0)
	assert_str(_mode.status_text()).is_equal("Bag room marked: Needs a belt end")


func test_a_belt_end_inside_makes_the_bag_room_ready() -> void:
	var room_id := _mark_bag_room(ROOM)
	assert_bool(_click(BuildMode.Tool.BELT_END, Vector2i(4, 4)).ok).is_true()
	var status := RoomRules.status(_mode.grid, room_id)
	assert_bool(status.ok).is_true()
	assert_int(status.pieces.get(&"baggage_belt_end", 0)).is_equal(1)


func test_a_belt_end_outside_the_room_does_not_count() -> void:
	var room_id := _mark_bag_room(ROOM)
	assert_bool(_click(BuildMode.Tool.BELT_END, Vector2i(8, 8)).ok).is_true()
	assert_array(_notes(room_id)).is_equal([NEEDS_END])


func test_belts_and_a_cart_do_not_stand_in_for_the_end() -> void:
	var room_id := _mark_bag_room(ROOM)
	assert_bool(_click(BuildMode.Tool.BELT, Vector2i(3, 3)).ok).is_true()
	assert_bool(_click(BuildMode.Tool.BELT_CORNER, Vector2i(3, 4)).ok).is_true()
	assert_bool(_click(BuildMode.Tool.BELT_FEED, Vector2i(3, 5)).ok).is_true()
	assert_bool(_click(BuildMode.Tool.CART, Vector2i(5, 3)).ok).is_true()
	assert_array(_notes(room_id)).is_equal([NEEDS_END])


func test_a_walled_bag_room_needs_an_opening_even_with_an_end() -> void:
	var room_id := _mark_bag_room(ROOM)
	_click(BuildMode.Tool.BELT_END, Vector2i(4, 4))
	for x in range(ROOM.position.x, ROOM.end.x):
		_mode.grid.apply(BuildEdit.place_wall(Vector2i(x, ROOM.position.y), BuildGrid.Side.NORTH))
		_mode.grid.apply(BuildEdit.place_wall(Vector2i(x, ROOM.end.y - 1), BuildGrid.Side.SOUTH))
	for y in range(ROOM.position.y, ROOM.end.y):
		_mode.grid.apply(BuildEdit.place_wall(Vector2i(ROOM.position.x, y), BuildGrid.Side.WEST))
		_mode.grid.apply(BuildEdit.place_wall(Vector2i(ROOM.end.x - 1, y), BuildGrid.Side.EAST))
	assert_array(_notes(room_id)).is_equal([NEEDS_OPENING])


func test_the_bag_room_drag_is_labelled_and_a_click_marks_nothing() -> void:
	_mode.set_tool(BuildMode.Tool.BAG_ROOM)
	_mode.begin_area(_at(Vector2i(3, 3)))
	_mode.move_area(_at(Vector2i(5, 4)))
	_mode._update_ghost(_at(Vector2i(5, 4)))
	assert_str(_mode.status_text()).is_equal("Bag room 3 x 2")
	_mode.cancel_area()
	_mode.begin_area(_at(Vector2i(4, 4)))
	_mode.finish_area()
	assert_array(_mode.grid.room_ids()).is_empty()
	assert_str(_mode.status_text()).is_equal("Drag to mark a bag room")


func test_a_bag_room_one_cell_wide_is_too_small() -> void:
	var room_id := _mark_bag_room(Rect2i(3, 3, 1, 4))
	assert_int(room_id).is_greater(0)
	assert_str(_notes(room_id)[0]).is_equal("Too small: a bag room needs at least 2x2")


func test_each_belt_tool_places_its_piece_and_the_cart_takes_two_cells() -> void:
	var tools := {
		BuildMode.Tool.BELT: &"baggage_belt",
		BuildMode.Tool.BELT_CORNER: &"baggage_belt_corner",
		BuildMode.Tool.BELT_FEED: &"baggage_belt_feed",
		BuildMode.Tool.BELT_END: &"baggage_belt_end",
		BuildMode.Tool.CART: &"baggage_cart",
	}
	var x := 3
	for tool in tools:
		assert_str(str(BuildMode.TOOL_OBJECTS[tool])).is_equal(str(tools[tool]))
		var result := _click(tool, Vector2i(x, 8))
		assert_bool(result.ok).is_true()
		assert_str(str(_mode.grid.get_object(result.object_id)["def"])).is_equal(str(tools[tool]))
		x += 2
	assert_int(_mode.grid.object_ids().size()).is_equal(5)
	var cart_cells := BuildCatalog.get_def(&"baggage_cart").footprint(Vector2i(11, 8), 0)
	assert_int(cart_cells.size()).is_equal(2)
	assert_int(_mode.grid.object_at(cart_cells[0])).is_greater(0)
	assert_int(_mode.grid.object_at(cart_cells[1])).is_equal(_mode.grid.object_at(cart_cells[0]))


func test_remove_takes_the_belt_end_before_the_bag_room() -> void:
	var room_id := _mark_bag_room(ROOM)
	_click(BuildMode.Tool.BELT_END, Vector2i(4, 4))
	_click(BuildMode.Tool.REMOVE, Vector2i(4, 4))
	assert_int(_mode.grid.room_at(Vector2i(4, 4))).is_equal(room_id)
	assert_array(_mode.grid.object_ids()).is_empty()
	_click(BuildMode.Tool.REMOVE, Vector2i(4, 4))
	assert_array(_mode.grid.room_ids()).is_empty()
