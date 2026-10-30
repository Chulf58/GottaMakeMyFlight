class_name TestRoomResize
extends GdUnitTestSuite
## Resizing a built room by dragging an edge with its room tool (decision
## resize-rooms-first-drag-a-room-s-edge-to-grow-or-shrink-it-f): grow and
## shrink keep the room's id and type, furniture stays where it is, a blocked
## resize is refused whole with its reason, and each resize is one undo step.
##
## The grid is 20x20 with floor on columns 2 to 13 and rows 2 to 11. The cafe
## under test covers columns 3 to 7 and rows 3 to 6.

const CAFE := Rect2i(3, 3, 5, 4)

var _mode: BuildMode
var _finances: Finances
var _room := 0


func before_test() -> void:
	_finances = Finances.new()
	add_child(_finances)
	_mode = BuildMode.new()
	_mode.grid_size = Vector2i(20, 20)
	_mode.finances = _finances
	add_child(_mode)
	var edits: Array[BuildEdit] = []
	for y in range(2, 12):
		for x in range(2, 14):
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	_mode.grid.apply_batch(edits)
	_room = _mark(BuildMode.Tool.CAFE_ROOM, CAFE)


func after_test() -> void:
	_mode.free()
	_finances.free()


func _at(cell: Vector2i) -> Vector3:
	return _mode.grid.cell_to_world(cell)


func _mark(tool: BuildMode.Tool, rect: Rect2i) -> int:
	_mode.set_tool(tool)
	_mode.begin_area(_at(rect.position))
	_mode.move_area(_at(rect.end - Vector2i.ONE))
	_mode.finish_area()
	return _mode.grid.room_at(rect.position)


## A point on grid line `line` of the x axis (axis 0) or the y axis (axis 1),
## at the middle of cell `across` along the other axis.
func _on_line(axis: int, line: int, across: int) -> Vector3:
	if axis == 0:
		return _at(Vector2i(line, across)) - Vector3(0.5, 0.0, 0.0)
	return _at(Vector2i(across, line)) - Vector3(0.0, 0.0, 0.5)


## A press 0.1 m inside the cafe's east or north edge.
func _press(side: int) -> Vector3:
	if side == BuildGrid.Side.EAST:
		return _on_line(0, CAFE.end.x, 4) - Vector3(0.1, 0.0, 0.0)
	return _on_line(1, CAFE.position.y, 4) + Vector3(0.0, 0.0, 0.1)


## Presses the east or north edge, drags it to grid line `line` and releases.
func _resize(side: int, line: int) -> void:
	_mode.set_tool(BuildMode.Tool.CAFE_ROOM)
	_mode.begin_area(_press(side))
	var axis := 0 if side == BuildGrid.Side.EAST else 1
	_mode.move_area(_on_line(axis, line, 4))
	_mode.finish_area()


func _rect() -> Rect2i:
	return _mode.grid.get_room(_room)["rect"]


func test_dragging_the_east_edge_out_grows_the_room_and_keeps_its_id() -> void:
	_resize(BuildGrid.Side.EAST, 10)
	assert_that(_rect()).is_equal(Rect2i(3, 3, 7, 4))
	assert_int(_mode.grid.room_at(Vector2i(9, 4))).is_equal(_room)
	assert_str(str(_mode.grid.get_room(_room)["type"])).is_equal("cafe")
	assert_array(_mode.grid.room_ids()).is_equal([_room])
	assert_str(_mode.status_text()).starts_with("Cafe resized to 7 x 4: ")


func test_dragging_the_east_edge_in_shrinks_the_room() -> void:
	_resize(BuildGrid.Side.EAST, 6)
	assert_that(_rect()).is_equal(Rect2i(3, 3, 3, 4))
	assert_int(_mode.grid.room_at(Vector2i(7, 4))).is_equal(0)
	assert_int(_mode.grid.floor_at(Vector2i(7, 4))).is_equal(BuildGrid.FLOOR_TILE)


func test_the_north_edge_resizes_up_and_down() -> void:
	_resize(BuildGrid.Side.NORTH, 2)
	assert_that(_rect()).is_equal(Rect2i(3, 2, 5, 5))
	_mode.begin_area(_on_line(1, 2, 4) + Vector3(0.0, 0.0, 0.1))
	_mode.move_area(_on_line(1, 4, 4))
	_mode.finish_area()
	assert_that(_rect()).is_equal(Rect2i(3, 4, 5, 3))


func test_the_edge_never_crosses_the_far_edge() -> void:
	_resize(BuildGrid.Side.EAST, 1)
	assert_that(_rect()).is_equal(Rect2i(3, 3, 1, 4))


func test_the_drag_shows_the_new_size_and_the_reason_it_would_be_refused() -> void:
	_mark(BuildMode.Tool.TOILET_ROOM, Rect2i(9, 3, 3, 4))
	_mode.set_tool(BuildMode.Tool.CAFE_ROOM)
	_mode.begin_area(_press(BuildGrid.Side.EAST))
	assert_bool(_mode.is_dragging()).is_true()
	_mode.move_area(_on_line(0, 8, 4))
	_mode._update_ghost(_on_line(0, 8, 4))
	assert_str(_mode.status_text()).is_equal("Cafe 5 x 4")
	_mode.move_area(_on_line(0, 10, 4))
	_mode._update_ghost(_on_line(0, 10, 4))
	assert_str(_mode.status_text()).is_equal("Cafe 7 x 4  Overlaps another room")
	_mode.cancel_area()
	assert_bool(_mode.is_dragging()).is_false()
	assert_that(_rect()).is_equal(CAFE)


func test_a_resize_into_another_room_is_refused_whole_with_its_reason() -> void:
	var other := _mark(BuildMode.Tool.TOILET_ROOM, Rect2i(9, 3, 3, 4))
	var steps := _mode.undo_history().size()
	_resize(BuildGrid.Side.EAST, 10)
	assert_that(_rect()).is_equal(CAFE)
	assert_that(_mode.grid.get_room(other)["rect"]).is_equal(Rect2i(9, 3, 3, 4))
	assert_str(_mode.status_text()).is_equal("Overlaps another room")
	assert_int(_mode.undo_history().size()).is_equal(steps)


func test_a_resize_onto_bare_ground_is_refused_with_its_reason() -> void:
	_resize(BuildGrid.Side.EAST, 15)
	assert_that(_rect()).is_equal(CAFE)
	assert_str(_mode.status_text()).is_equal("Needs floor")


func test_a_resize_across_a_wall_is_refused_with_its_reason() -> void:
	# A wall on grid line x = 9, one edge long, between columns 8 and 9.
	_mode.grid.apply(BuildEdit.place_wall(Vector2i(8, 5), BuildGrid.Side.EAST))
	_resize(BuildGrid.Side.EAST, 11)
	assert_that(_rect()).is_equal(CAFE)
	assert_str(_mode.status_text()).is_equal("A wall is in the way of the room")


func test_the_room_may_grow_up_to_a_wall_but_not_on_through_it() -> void:
	_mode.grid.apply(BuildEdit.place_wall(Vector2i(8, 5), BuildGrid.Side.EAST))
	_resize(BuildGrid.Side.EAST, 9)
	assert_that(_rect()).is_equal(Rect2i(3, 3, 6, 4))
	_mode.begin_area(_on_line(0, 9, 4) - Vector3(0.1, 0.0, 0.0))
	_mode.move_area(_on_line(0, 10, 4))
	_mode.finish_area()
	assert_that(_rect()).is_equal(Rect2i(3, 3, 6, 4))
	assert_str(_mode.status_text()).is_equal("A wall is in the way of the room")


func test_undo_restores_the_old_rect_and_the_same_room_id_in_one_step() -> void:
	var steps := _mode.undo_history().size()
	_resize(BuildGrid.Side.EAST, 10)
	assert_int(_mode.undo_history().size()).is_equal(steps + 1)
	assert_bool(_mode.undo().ok).is_true()
	assert_that(_rect()).is_equal(CAFE)
	assert_array(_mode.grid.room_ids()).is_equal([_room])
	assert_int(_mode.grid.room_at(Vector2i(8, 4))).is_equal(0)
	assert_int(_mode.undo_history().size()).is_equal(steps)
	_resize(BuildGrid.Side.EAST, 5)
	assert_that(_rect()).is_equal(Rect2i(3, 3, 2, 4))
	assert_bool(_mode.undo().ok).is_true()
	assert_that(_rect()).is_equal(CAFE)
	assert_int(_mode.grid.room_at(Vector2i(7, 4))).is_equal(_room)


func test_a_resize_costs_nothing() -> void:
	var balance := _finances.wallet.balance
	_resize(BuildGrid.Side.EAST, 10)
	assert_int(_finances.wallet.balance).is_equal(balance)
	assert_that(_rect()).is_equal(Rect2i(3, 3, 7, 4))


func test_a_drag_that_never_moves_the_edge_does_nothing() -> void:
	var steps := _mode.undo_history().size()
	_resize(BuildGrid.Side.EAST, CAFE.end.x)
	assert_that(_rect()).is_equal(CAFE)
	assert_int(_mode.undo_history().size()).is_equal(steps)


func test_a_piece_left_outside_makes_the_room_not_ready_and_stays_put() -> void:
	_mode.set_tool(BuildMode.Tool.COUNTER)
	_mode.apply_at(_at(Vector2i(4, 3)))
	_mode.set_tool(BuildMode.Tool.TABLE)
	_mode.apply_at(_at(Vector2i(4, 5)))
	assert_bool(RoomRules.status(_mode.grid, _room).ok).is_true()
	var counter := _mode.grid.object_at(Vector2i(4, 3))
	assert_int(counter).is_greater(0)
	_resize(BuildGrid.Side.NORTH, 4)
	assert_that(_rect()).is_equal(Rect2i(3, 4, 5, 3))
	assert_int(_mode.grid.object_at(Vector2i(4, 3))).is_equal(counter)
	var status := RoomRules.status(_mode.grid, _room)
	assert_bool(status.ok).is_false()
	assert_str(status.headline()).is_equal("Needs a counter")
	assert_str(_mode.status_text()).is_equal("Cafe resized to 5 x 3: Needs a counter")


func test_a_press_in_the_middle_or_with_another_rooms_tool_draws_instead() -> void:
	_mode.set_tool(BuildMode.Tool.CAFE_ROOM)
	_mode.begin_area(_at(Vector2i(5, 5)))
	assert_that(_mode.dragged_area()).is_equal(Rect2i(5, 5, 1, 1))
	_mode.cancel_area()
	_mode.set_tool(BuildMode.Tool.TOILET_ROOM)
	_mode.begin_area(_press(BuildGrid.Side.EAST))
	assert_that(_mode.dragged_area()).is_equal(Rect2i(7, 4, 1, 1))
	_mode.cancel_area()
	assert_that(_rect()).is_equal(CAFE)


func test_the_resize_edit_follows_the_grid_rules_on_its_own() -> void:
	var grid := _mode.grid
	assert_bool(grid.validate(BuildEdit.resize_room(_room, Rect2i(3, 3, 6, 4))).ok).is_true()
	var missing := grid.validate(BuildEdit.resize_room(99, CAFE))
	assert_int(missing.reason).is_equal(BuildResult.Reason.NO_ROOM)
	var empty := grid.validate(BuildEdit.resize_room(_room, Rect2i(3, 3, 0, 4)))
	assert_int(empty.reason).is_equal(BuildResult.Reason.OUT_OF_BOUNDS)
