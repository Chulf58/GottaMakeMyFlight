class_name TestToiletRoom
extends GdUnitTestSuite
## The toilet room type and its tools (decision toilet-design-queue-free-
## reservable-stalls-per-stall-daily-u, points 1 and 2): a toilet needs a stall
## and a sink, seats nobody and earns nothing; the Toilet room tool drags a
## rectangle like the Cafe tool, the stall and sink tools furnish it, and a
## ready toilet costs PriceTable.TOILET_STALL_UPKEEP per stall per day.

const NEEDS_STALL := "Needs a toilet stall"
const NEEDS_SINK := "Needs a sink"
const NEEDS_OPENING := "Needs a door or open side to the walkway"
const ROOM := Rect2i(3, 3, 3, 3)
const STALL := BuildMode.Tool.TOILET_STALL
const SINK := BuildMode.Tool.TOILET_SINK

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


func _mark_toilet(rect: Rect2i) -> int:
	_mode.set_tool(BuildMode.Tool.TOILET_ROOM)
	_mode.begin_area(_at(rect.position))
	_mode.move_area(_at(rect.end - Vector2i.ONE))
	_mode.finish_area()
	return _mode.grid.room_at(rect.position)


func _click(tool: BuildMode.Tool, cell: Vector2i) -> BuildResult:
	_mode.set_tool(tool)
	return _mode.apply_at(_at(cell))


func _notes(room_id: int) -> Array:
	return Array(RoomRules.status(_mode.grid, room_id).notes)


func test_the_toilet_type_needs_a_stall_and_a_sink_and_seats_nobody() -> void:
	var type := RoomTypes.get_type(&"toilet")
	assert_str(type.display_name).is_equal("Toilet")
	assert_array(type.required).is_equal(
		[[&"toilet_stall", NEEDS_STALL], [&"toilet_sink", NEEDS_SINK]]
	)
	assert_int(type.seats_per_piece).is_equal(0)
	assert_int(type.base_spend).is_equal(0)
	assert_str(str(type.upkeep_piece)).is_equal("toilet_stall")
	assert_int(type.upkeep_per_piece).is_equal(PriceTable.TOILET_STALL_UPKEEP)
	assert_bool(type.fits(Vector2i(2, 3))).is_true()
	assert_bool(type.fits(Vector2i(3, 2))).is_true()
	assert_bool(type.fits(Vector2i(2, 2))).is_false()
	assert_bool(type.fits(Vector2i(1, 4))).is_false()
	assert_array(RoomTypes.ids()).contains([&"cafe", &"bag_room", &"toilet"])


func test_the_other_room_types_cost_no_upkeep() -> void:
	for id in [&"cafe", &"bag_room"]:
		assert_str(str(RoomTypes.get_type(id).upkeep_piece)).is_empty()
		assert_int(RoomTypes.get_type(id).upkeep_per_piece).is_equal(0)


## The stall is 1x2 (door at the front, toilet in the rear cell) and the sink
## 1x1; each keeps the cell in front of it clear, its Mount_Approach.
func test_stall_and_sink_are_priced_pieces_with_an_approach_cell_in_front() -> void:
	var sizes := {&"toilet_stall": Vector2i(1, 2), &"toilet_sink": Vector2i.ONE}
	var approaches := {&"toilet_stall": Vector2i(0, 2), &"toilet_sink": Vector2i(0, 1)}
	for id in sizes:
		var def := BuildCatalog.get_def(id)
		assert_object(def).is_not_null()
		assert_that(def.size).is_equal(sizes[id])
		assert_bool(def.has_interaction).is_true()
		assert_that(def.interaction_offset).is_equal(approaches[id])
		assert_int(PriceTable.price_of_object(id)).is_greater(0)
	assert_str(str(BuildMode.TOOL_OBJECTS[STALL])).is_equal("toilet_stall")
	assert_str(str(BuildMode.TOOL_OBJECTS[SINK])).is_equal("toilet_sink")
	assert_str(str(BuildMode.TOOL_ROOMS[BuildMode.Tool.TOILET_ROOM])).is_equal("toilet")
	assert_bool(BuildMode.AREA_TOOLS.has(BuildMode.Tool.TOILET_ROOM)).is_true()
	for tool in [BuildMode.Tool.TOILET_ROOM, STALL, SINK]:
		assert_bool(BuildMode.ROOM_FOCUS_TOOLS.has(tool)).is_true()


func test_an_empty_toilet_needs_a_stall_then_a_sink() -> void:
	var room_id := _mark_toilet(ROOM)
	assert_int(room_id).is_greater(0)
	assert_str(str(_mode.grid.get_room(room_id)["type"])).is_equal("toilet")
	var status := RoomRules.status(_mode.grid, room_id)
	assert_bool(status.ok).is_false()
	assert_array(_notes(room_id)).is_equal([NEEDS_STALL, NEEDS_SINK])
	assert_str(status.type_name).is_equal("Toilet")
	assert_int(status.seats).is_equal(0)
	assert_str(_mode.status_text()).is_equal("Toilet marked: Needs a toilet stall")


func test_a_stall_alone_still_needs_a_sink() -> void:
	var room_id := _mark_toilet(ROOM)
	assert_bool(_click(STALL, Vector2i(3, 3)).ok).is_true()
	assert_array(_notes(room_id)).is_equal([NEEDS_SINK])


func test_a_stall_and_a_sink_make_the_toilet_ready() -> void:
	var room_id := _mark_toilet(ROOM)
	assert_bool(_click(STALL, Vector2i(3, 3)).ok).is_true()
	assert_bool(_click(SINK, Vector2i(5, 3)).ok).is_true()
	var status := RoomRules.status(_mode.grid, room_id)
	print("toilet notes %s pieces %s" % [status.notes, status.pieces])
	assert_bool(status.ok).is_true()
	assert_str(status.headline()).is_equal("Ready")
	assert_int(status.pieces.get(&"toilet_stall", 0)).is_equal(1)
	assert_int(status.pieces.get(&"toilet_sink", 0)).is_equal(1)


func test_the_smallest_toilet_holds_a_stall_and_a_sink_with_their_approaches() -> void:
	var room_id := _mark_toilet(Rect2i(3, 3, 2, 3))
	assert_bool(_click(STALL, Vector2i(3, 3)).ok).is_true()
	assert_bool(_click(SINK, Vector2i(4, 3)).ok).is_true()
	assert_array(_notes(room_id)).is_empty()


func test_a_toilet_one_cell_wide_is_too_small() -> void:
	var room_id := _mark_toilet(Rect2i(3, 3, 1, 4))
	assert_int(room_id).is_greater(0)
	assert_str(_notes(room_id)[0]).is_equal("Too small: a toilet needs at least 2x3")


func test_a_stall_whose_approach_is_outside_the_toilet_does_not_count() -> void:
	var room_id := _mark_toilet(ROOM)
	_click(SINK, Vector2i(5, 3))
	# Rows 4 and 5 are the room's last two; the approach cell (3, 6) is not in it.
	assert_bool(_click(STALL, Vector2i(3, 4)).ok).is_true()
	assert_array(_notes(room_id)).is_equal([NEEDS_STALL])


func test_a_walled_toilet_needs_an_opening() -> void:
	var room_id := _mark_toilet(ROOM)
	_click(STALL, Vector2i(3, 3))
	_click(SINK, Vector2i(5, 3))
	for x in range(ROOM.position.x, ROOM.end.x):
		_mode.grid.apply(BuildEdit.place_wall(Vector2i(x, ROOM.position.y), BuildGrid.Side.NORTH))
		_mode.grid.apply(BuildEdit.place_wall(Vector2i(x, ROOM.end.y - 1), BuildGrid.Side.SOUTH))
	for y in range(ROOM.position.y, ROOM.end.y):
		_mode.grid.apply(BuildEdit.place_wall(Vector2i(ROOM.position.x, y), BuildGrid.Side.WEST))
		_mode.grid.apply(BuildEdit.place_wall(Vector2i(ROOM.end.x - 1, y), BuildGrid.Side.EAST))
	assert_array(_notes(room_id)).is_equal([NEEDS_OPENING])


func test_the_toilet_drag_is_labelled_and_a_click_marks_nothing() -> void:
	_mode.set_tool(BuildMode.Tool.TOILET_ROOM)
	_mode.begin_area(_at(Vector2i(3, 3)))
	_mode.move_area(_at(Vector2i(5, 4)))
	_mode._update_ghost(_at(Vector2i(5, 4)))
	assert_str(_mode.status_text()).is_equal("Toilet 3 x 2")
	_mode.cancel_area()
	_mode.begin_area(_at(Vector2i(4, 4)))
	_mode.finish_area()
	assert_array(_mode.grid.room_ids()).is_empty()
	assert_str(_mode.status_text()).is_equal("Drag to mark a toilet")


func test_remove_takes_the_pieces_before_the_toilet() -> void:
	var room_id := _mark_toilet(ROOM)
	_click(STALL, Vector2i(3, 3))
	_click(SINK, Vector2i(5, 3))
	assert_int(_mode.grid.object_ids().size()).is_equal(2)
	_click(BuildMode.Tool.REMOVE, Vector2i(3, 3))
	_click(BuildMode.Tool.REMOVE, Vector2i(5, 3))
	assert_int(_mode.grid.room_at(Vector2i(3, 3))).is_equal(room_id)
	assert_array(_mode.grid.object_ids()).is_empty()
	_click(BuildMode.Tool.REMOVE, Vector2i(3, 3))
	assert_array(_mode.grid.room_ids()).is_empty()


func test_a_ready_toilet_costs_its_stall_rate_per_stall_per_day() -> void:
	var room_id := _mark_toilet(Rect2i(3, 3, 4, 3))
	_click(STALL, Vector2i(3, 3))
	_click(STALL, Vector2i(4, 3))
	_click(STALL, Vector2i(5, 3))
	_click(SINK, Vector2i(6, 3))
	var status := RoomRules.status(_mode.grid, room_id)
	print("ready %s upkeep %d" % [status.ok, RoomRules.daily_upkeep(_mode.grid, room_id)])
	assert_bool(status.ok).is_true()
	assert_int(status.upkeep).is_equal(3 * PriceTable.TOILET_STALL_UPKEEP)
	assert_int(RoomRules.daily_upkeep(_mode.grid, room_id)).is_equal(
		3 * PriceTable.TOILET_STALL_UPKEEP
	)


func test_a_toilet_that_is_not_ready_costs_nothing() -> void:
	var room_id := _mark_toilet(ROOM)
	_click(STALL, Vector2i(3, 3))
	assert_bool(RoomRules.status(_mode.grid, room_id).ok).is_false()
	assert_int(RoomRules.daily_upkeep(_mode.grid, room_id)).is_equal(0)
	assert_int(RoomRules.daily_upkeep(_mode.grid, 999)).is_equal(0)


func test_a_stall_outside_the_toilet_is_not_charged() -> void:
	var room_id := _mark_toilet(ROOM)
	_click(STALL, Vector2i(3, 3))
	_click(SINK, Vector2i(5, 3))
	assert_bool(_click(STALL, Vector2i(10, 8)).ok).is_true()
	assert_int(_mode.grid.object_ids().size()).is_equal(3)
	assert_int(RoomRules.daily_upkeep(_mode.grid, room_id)).is_equal(PriceTable.TOILET_STALL_UPKEEP)


func test_a_cafe_costs_no_upkeep_when_ready() -> void:
	_mode.set_tool(BuildMode.Tool.CAFE_ROOM)
	_mode.begin_area(_at(Vector2i(3, 3)))
	_mode.move_area(_at(Vector2i(7, 6)))
	_mode.finish_area()
	var room_id := _mode.grid.room_at(Vector2i(3, 3))
	_click(BuildMode.Tool.COUNTER, Vector2i(3, 3))
	_click(BuildMode.Tool.TABLE, Vector2i(4, 5))
	assert_bool(RoomRules.status(_mode.grid, room_id).ok).is_true()
	assert_int(RoomRules.daily_upkeep(_mode.grid, room_id)).is_equal(0)
