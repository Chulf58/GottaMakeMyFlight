class_name TestBagRoom
extends GdUnitTestSuite
## The bag room type and the Belt tool (decisions baggage-rides-a-player-
## built-belt-from-check-in-to-a-bag-roo and baggage-belts-are-one-auto-
## shaping-belt-tool-one-baggage-tray): a bag room needs a belt end, the Bag
## room tool drags a rectangle like the Cafe tool, and a belt that dead-ends
## inside the room becomes the end. The end, corner and merge tools are gone,
## so these cases lay belt with the one Belt tool instead.

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


func _lay(from: Vector2i, to: Vector2i) -> BuildResult:
	_mode.set_tool(BuildMode.Tool.BELT)
	return _mode.lay_belt(from, to)


func _def_at(cell: Vector2i) -> String:
	return str(_mode.grid.get_object(_mode.grid.object_at(cell))["def"])


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
	assert_bool(_lay(Vector2i(4, 4), Vector2i(4, 4)).ok).is_true()
	assert_str(_def_at(Vector2i(4, 4))).is_equal("baggage_belt_end")
	var status := RoomRules.status(_mode.grid, room_id)
	assert_bool(status.ok).is_true()
	assert_int(status.pieces.get(&"baggage_belt_end", 0)).is_equal(1)


func test_a_belt_dead_end_outside_the_room_is_a_plain_belt() -> void:
	var room_id := _mark_bag_room(ROOM)
	assert_bool(_lay(Vector2i(8, 8), Vector2i(8, 8)).ok).is_true()
	assert_str(_def_at(Vector2i(8, 8))).is_equal("baggage_belt")
	assert_array(_notes(room_id)).is_equal([NEEDS_END])


func test_a_real_belt_end_outside_the_room_does_not_count() -> void:
	# The Belt tool never makes an end outside a bag room, but a B2a save can
	# hold a hand-placed one: put it on the grid directly, then load it back.
	var room_id := _mark_bag_room(ROOM)
	var end := _mode.grid.apply(BuildEdit.place_object(&"baggage_belt_end", Vector2i(8, 8), 0))
	assert_bool(end.ok).is_true()
	assert_str(_def_at(Vector2i(8, 8))).is_equal("baggage_belt_end")
	assert_array(_notes(room_id)).is_equal([NEEDS_END])
	var saved := _mode.grid.to_snapshot()
	assert_bool(_mode.load_snapshot(saved)).is_true()
	assert_str(_def_at(Vector2i(8, 8))).is_equal("baggage_belt_end")
	assert_array(_notes(_mode.grid.room_at(ROOM.position))).is_equal([NEEDS_END])


func test_belts_a_corner_a_merge_and_a_cart_do_not_stand_in_for_the_end() -> void:
	# A 5x5 room, so a merge and a corner fit inside with no line beside another.
	var room_id := _mark_bag_room(Rect2i(4, 4, 5, 5))
	# A line through the room, then a branch from its middle that turns and
	# leaves: every dead end is outside the room.
	assert_bool(_lay(Vector2i(3, 5), Vector2i(9, 5)).ok).is_true()
	assert_bool(_lay(Vector2i(6, 6), Vector2i(6, 8)).ok).is_true()
	assert_bool(_lay(Vector2i(7, 8), Vector2i(9, 8)).ok).is_true()
	assert_bool(_click(BuildMode.Tool.CART, Vector2i(4, 6)).ok).is_true()
	assert_str(_def_at(Vector2i(6, 5))).is_equal("baggage_belt_feed")
	assert_str(_def_at(Vector2i(6, 8))).is_equal("baggage_belt_corner")
	assert_str(_def_at(Vector2i(5, 5))).is_equal("baggage_belt")
	for cell in [Vector2i(3, 5), Vector2i(9, 5), Vector2i(9, 8)]:
		assert_str(_def_at(cell)).is_equal("baggage_belt")
	var pieces := RoomRules.status(_mode.grid, room_id).pieces
	assert_int(pieces.get(&"baggage_belt_feed", 0)).is_equal(1)
	assert_int(pieces.get(&"baggage_belt_corner", 0)).is_equal(1)
	assert_int(pieces.get(&"baggage_belt_end", 0)).is_equal(0)
	assert_array(_notes(room_id)).is_equal([NEEDS_END])


func test_a_walled_bag_room_needs_an_opening_even_with_an_end() -> void:
	var room_id := _mark_bag_room(ROOM)
	_lay(Vector2i(4, 4), Vector2i(4, 4))
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


func test_a_belt_click_lays_a_plain_belt_and_the_cart_takes_two_cells() -> void:
	assert_bool(BuildMode.TOOL_OBJECTS.has(BuildMode.Tool.BELT)).is_false()
	assert_str(str(BuildMode.TOOL_OBJECTS[BuildMode.Tool.CART])).is_equal("baggage_cart")
	assert_bool(_lay(Vector2i(3, 8), Vector2i(3, 8)).ok).is_true()
	assert_str(_def_at(Vector2i(3, 8))).is_equal("baggage_belt")
	var cart := _click(BuildMode.Tool.CART, Vector2i(11, 8))
	assert_bool(cart.ok).is_true()
	assert_str(str(_mode.grid.get_object(cart.object_id)["def"])).is_equal("baggage_cart")
	assert_int(_mode.grid.object_ids().size()).is_equal(2)
	var cart_cells := BuildCatalog.get_def(&"baggage_cart").footprint(Vector2i(11, 8), 0)
	assert_int(cart_cells.size()).is_equal(2)
	assert_int(_mode.grid.object_at(cart_cells[0])).is_greater(0)
	assert_int(_mode.grid.object_at(cart_cells[1])).is_equal(_mode.grid.object_at(cart_cells[0]))


func test_remove_takes_the_belt_end_before_the_bag_room() -> void:
	var room_id := _mark_bag_room(ROOM)
	_lay(Vector2i(4, 4), Vector2i(4, 4))
	_click(BuildMode.Tool.REMOVE, Vector2i(4, 4))
	assert_int(_mode.grid.room_at(Vector2i(4, 4))).is_equal(room_id)
	assert_array(_mode.grid.object_ids()).is_empty()
	_click(BuildMode.Tool.REMOVE, Vector2i(4, 4))
	assert_array(_mode.grid.room_ids()).is_empty()
