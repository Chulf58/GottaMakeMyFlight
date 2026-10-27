class_name TestBeltShaper
extends GdUnitTestSuite
## The one Belt tool shapes each belt cell from its neighbours (decision
## baggage-belts-are-one-auto-shaping-belt-tool-one-baggage-tray): straight,
## corner, merge (feed) or end, reshaped when belt next to it changes, with a
## check-in desk outlet as a link and no link through a wall. Every shaped line
## joins port to port (BuildCatalog.belt_ports_join()).

var _mode: BuildMode


func before_test() -> void:
	_mode = BuildMode.new()
	_mode.grid_size = Vector2i(16, 16)
	add_child(_mode)
	var edits: Array[BuildEdit] = []
	for y in 16:
		for x in 16:
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	_mode.grid.apply_batch(edits)
	_mode.set_tool(BuildMode.Tool.BELT)


func after_test() -> void:
	_mode.free()


func _record(cell: Vector2i) -> Dictionary:
	return _mode.grid.get_object(_mode.grid.object_at(cell))


func _def(cell: Vector2i) -> String:
	return str(_record(cell).get("def", ""))


## Whether the pieces on two cells (or a desk and a cell) join port to port.
func _joined(a: Vector2i, b: Vector2i) -> bool:
	var first := _record(a)
	var second := _record(b)
	for mine in BuildCatalog.belt_ports(first["def"], first["anchor"], first["facing"]):
		for theirs in BuildCatalog.belt_ports(second["def"], second["anchor"], second["facing"]):
			if BuildCatalog.belt_ports_join(mine, theirs):
				return true
	return false


func _assert_line_joins(cells: Array[Vector2i]) -> void:
	for i in range(1, cells.size()):
		(
			assert_bool(_joined(cells[i - 1], cells[i]))
			. override_failure_message("%s to %s" % [cells[i - 1], cells[i]])
			. is_true()
		)


func test_the_path_is_an_l_along_the_longer_axis_first() -> void:
	assert_array(BeltShaper.path(Vector2i(2, 2), Vector2i(2, 2))).is_equal([Vector2i(2, 2)])
	assert_array(BeltShaper.path(Vector2i(2, 2), Vector2i(5, 3))).is_equal(
		[Vector2i(2, 2), Vector2i(3, 2), Vector2i(4, 2), Vector2i(5, 2), Vector2i(5, 3)]
	)
	assert_array(BeltShaper.path(Vector2i(2, 2), Vector2i(1, 5))).is_equal(
		[Vector2i(2, 2), Vector2i(2, 3), Vector2i(2, 4), Vector2i(2, 5), Vector2i(1, 5)]
	)
	# A tie goes along x first.
	assert_array(BeltShaper.path(Vector2i(2, 2), Vector2i(3, 3))).is_equal(
		[Vector2i(2, 2), Vector2i(3, 2), Vector2i(3, 3)]
	)


func test_a_straight_run_is_straight_belt_along_the_run() -> void:
	assert_bool(_mode.lay_belt(Vector2i(2, 4), Vector2i(6, 4)).ok).is_true()
	for x in range(2, 7):
		assert_str(_def(Vector2i(x, 4))).is_equal("baggage_belt")
	_assert_line_joins(BeltShaper.path(Vector2i(2, 4), Vector2i(6, 4)))


func test_an_l_line_turns_with_a_corner_that_joins_both_sides() -> void:
	assert_bool(_mode.lay_belt(Vector2i(2, 4), Vector2i(5, 7)).ok).is_true()
	assert_str(_def(Vector2i(5, 4))).is_equal("baggage_belt_corner")
	_assert_line_joins(BeltShaper.path(Vector2i(2, 4), Vector2i(5, 7)))


func test_a_branch_joining_a_line_makes_a_merge_and_reshapes_the_line() -> void:
	_mode.lay_belt(Vector2i(2, 6), Vector2i(8, 6))
	var before := _record(Vector2i(5, 6))
	assert_str(str(before["def"])).is_equal("baggage_belt")
	# A branch from the north meets the line at (5, 6).
	assert_bool(_mode.lay_belt(Vector2i(5, 2), Vector2i(5, 5)).ok).is_true()
	var after := _record(Vector2i(5, 6))
	assert_str(str(after["def"])).is_equal("baggage_belt_feed")
	assert_int(_mode.grid.object_at(Vector2i(5, 6))).is_greater(0)
	for cell in [Vector2i(4, 6), Vector2i(6, 6), Vector2i(5, 5)]:
		assert_bool(_joined(Vector2i(5, 6), cell)).override_failure_message(str(cell)).is_true()
	# The feed's inlet F is the branch: the side opposite the free one.
	var ports := BuildCatalog.belt_ports(after["def"], after["anchor"], after["facing"])
	for port in ports:
		if port["name"] == "F":
			assert_vector(port["side"]).is_equal(Vector2i(0, -1))


func test_reshaping_keeps_the_object_id() -> void:
	_mode.lay_belt(Vector2i(2, 6), Vector2i(8, 6))
	var id := _mode.grid.object_at(Vector2i(5, 6))
	_mode.lay_belt(Vector2i(5, 5), Vector2i(5, 5))
	assert_int(_mode.grid.object_at(Vector2i(5, 6))).is_equal(id)
	assert_str(_def(Vector2i(5, 6))).is_equal("baggage_belt_feed")


func test_removing_a_belt_reshapes_its_neighbours() -> void:
	_mode.lay_belt(Vector2i(2, 6), Vector2i(8, 6))
	_mode.lay_belt(Vector2i(5, 3), Vector2i(5, 5))
	assert_str(_def(Vector2i(5, 6))).is_equal("baggage_belt_feed")
	_mode.set_tool(BuildMode.Tool.REMOVE)
	assert_bool(_mode.apply_at(_mode.grid.cell_to_world(Vector2i(6, 6))).ok).is_true()
	# The merge lost its east side: now a corner from the west to the branch.
	assert_str(_def(Vector2i(5, 6))).is_equal("baggage_belt_corner")
	_assert_line_joins([Vector2i(4, 6), Vector2i(5, 6), Vector2i(5, 5)])


func test_a_dead_end_in_a_bag_room_is_the_end_and_outside_it_stays_open() -> void:
	(
		assert_bool(_mode.grid.apply(BuildEdit.place_room(Rect2i(8, 8, 3, 3), &"bag_room")).ok)
		. is_true()
	)
	assert_bool(_mode.lay_belt(Vector2i(4, 9), Vector2i(9, 9)).ok).is_true()
	assert_str(_def(Vector2i(9, 9))).is_equal("baggage_belt_end")
	assert_str(_def(Vector2i(4, 9))).is_equal("baggage_belt")
	assert_bool(_joined(Vector2i(8, 9), Vector2i(9, 9))).is_true()
	# Marking or removing the room reshapes the dead end inside it.
	_mode.set_tool(BuildMode.Tool.REMOVE)
	var room_id := _mode.grid.room_at(Vector2i(10, 10))
	assert_bool(_mode.apply_at(_mode.grid.cell_to_world(Vector2i(10, 10))).ok).is_true()
	assert_int(_mode.grid.room_at(Vector2i(10, 10))).is_not_equal(room_id)
	assert_str(_def(Vector2i(9, 9))).is_equal("baggage_belt")
	_mode.set_tool(BuildMode.Tool.BAG_ROOM)
	_mode.begin_area(_mode.grid.cell_to_world(Vector2i(8, 8)))
	_mode.move_area(_mode.grid.cell_to_world(Vector2i(10, 10)))
	_mode.finish_area()
	assert_str(_def(Vector2i(9, 9))).is_equal("baggage_belt_end")


func test_a_desk_outlet_is_a_link_and_the_line_joins_it() -> void:
	var desk := _mode.grid.apply(BuildEdit.place_object(&"checkin_desk", Vector2i(4, 8), 0))
	assert_bool(desk.ok).is_true()
	# The desk's belt cell is (5, 8); its outlet points north into (5, 7).
	assert_bool(_mode.lay_belt(Vector2i(5, 7), Vector2i(9, 7)).ok).is_true()
	assert_str(_def(Vector2i(5, 7))).is_equal("baggage_belt_corner")
	assert_bool(_joined(Vector2i(4, 8), Vector2i(5, 7))).is_true()
	_assert_line_joins(BeltShaper.path(Vector2i(5, 7), Vector2i(9, 7)))


func test_a_desk_placed_after_the_belt_reshapes_it_to_take_the_outlet() -> void:
	_mode.lay_belt(Vector2i(3, 7), Vector2i(7, 7))
	assert_str(_def(Vector2i(5, 7))).is_equal("baggage_belt")
	_mode.set_tool(BuildMode.Tool.DESK)
	_mode.facing = 0
	assert_bool(_mode.apply_at(_mode.grid.cell_to_world(Vector2i(4, 8))).ok).is_true()
	assert_str(_def(Vector2i(5, 7))).is_equal("baggage_belt_feed")
	assert_bool(_joined(Vector2i(4, 8), Vector2i(5, 7))).is_true()


func test_no_link_through_a_wall_and_no_line_across_one() -> void:
	_mode.grid.apply(BuildEdit.place_wall(Vector2i(5, 4), BuildGrid.Side.EAST))
	var refused := _mode.lay_belt(Vector2i(3, 4), Vector2i(8, 4))
	assert_bool(refused.ok).is_false()
	assert_int(refused.reason).is_equal(BuildResult.Reason.BELT_WALL)
	assert_array(_mode.grid.object_ids()).is_empty()
	assert_bool(_mode.lay_belt(Vector2i(3, 4), Vector2i(5, 4)).ok).is_true()
	assert_bool(_mode.lay_belt(Vector2i(6, 4), Vector2i(8, 4)).ok).is_true()
	# The two open ends meet at the wall, but the wall cuts the link.
	var scene := BeltShaper.Scene.new(_mode.grid)
	assert_array(scene.links(Vector2i(5, 4))).is_equal([Vector2i(-1, 0)])
	assert_array(scene.links(Vector2i(6, 4))).is_equal([Vector2i(1, 0)])
	# Control: with the wall treated as gone they would link.
	scene.open_edges[Vector3i(5, 4, BuildGrid.Side.EAST)] = true
	assert_int(scene.links(Vector2i(5, 4)).size()).is_equal(2)


func test_a_fourth_link_is_refused_and_changes_nothing() -> void:
	_mode.lay_belt(Vector2i(2, 6), Vector2i(8, 6))
	_mode.lay_belt(Vector2i(5, 3), Vector2i(5, 5))
	var objects := _mode.grid.object_ids().size()
	var refused := _mode.lay_belt(Vector2i(5, 7), Vector2i(5, 9))
	assert_bool(refused.ok).is_false()
	assert_int(refused.reason).is_equal(BuildResult.Reason.BELT_CROSSING)
	assert_int(_mode.grid.object_ids().size()).is_equal(objects)
	assert_str(_def(Vector2i(5, 6))).is_equal("baggage_belt_feed")


func test_a_desk_or_a_wall_removal_that_makes_a_fourth_link_is_refused() -> void:
	_mode.lay_belt(Vector2i(2, 6), Vector2i(8, 6))
	_mode.lay_belt(Vector2i(5, 3), Vector2i(5, 5))
	# A desk whose outlet would point into the merge from the south.
	var desk := BuildEdit.place_object(&"checkin_desk", Vector2i(4, 7), 0)
	assert_int(_mode.check(desk).reason).is_equal(BuildResult.Reason.BELT_CROSSING)
	# The click is refused the same way and places nothing.
	var objects := _mode.grid.object_ids().size()
	_mode.set_tool(BuildMode.Tool.DESK)
	_mode.facing = 0
	var clicked := _mode.apply_at(_mode.grid.cell_to_world(Vector2i(4, 7)))
	assert_int(clicked.reason).is_equal(BuildResult.Reason.BELT_CROSSING)
	assert_int(_mode.grid.object_ids().size()).is_equal(objects)
	_mode.set_tool(BuildMode.Tool.BELT)
	# A belt south of the merge behind a wall, then the wall taken away.
	_mode.grid.apply(BuildEdit.place_wall(Vector2i(5, 6), BuildGrid.Side.SOUTH))
	assert_bool(_mode.lay_belt(Vector2i(5, 7), Vector2i(5, 7)).ok).is_true()
	var wall_out := BuildEdit.remove_wall(Vector2i(5, 6), BuildGrid.Side.SOUTH)
	assert_int(_mode.check(wall_out).reason).is_equal(BuildResult.Reason.BELT_CROSSING)
	# Control: taking away a wall between two lone belts is fine.
	_mode.lay_belt(Vector2i(10, 10), Vector2i(10, 10))
	_mode.grid.apply(BuildEdit.place_wall(Vector2i(10, 10), BuildGrid.Side.EAST))
	_mode.lay_belt(Vector2i(11, 10), Vector2i(11, 10))
	(
		assert_bool(_mode.check(BuildEdit.remove_wall(Vector2i(10, 10), BuildGrid.Side.EAST)).ok)
		. is_true()
	)


func test_a_rectangle_taking_a_desk_reshapes_the_belt_at_its_outlet() -> void:
	_mode.grid.apply(BuildEdit.place_object(&"checkin_desk", Vector2i(4, 8), 0))
	_mode.lay_belt(Vector2i(3, 7), Vector2i(7, 7))
	assert_str(_def(Vector2i(5, 7))).is_equal("baggage_belt_feed")
	# The rectangle covers only the desk's left cell, which takes the whole desk.
	_mode.set_tool(BuildMode.Tool.REMOVE)
	_mode.begin_area(_mode.grid.cell_to_world(Vector2i(3, 8)))
	_mode.move_area(_mode.grid.cell_to_world(Vector2i(4, 9)))
	_mode.finish_area()
	assert_int(_mode.grid.object_at(Vector2i(5, 8))).is_equal(0)
	assert_str(_def(Vector2i(5, 7))).is_equal("baggage_belt")


func test_dragging_the_belt_tool_lays_the_l_line_and_a_cancelled_drag_nothing() -> void:
	_mode.begin_area(_mode.grid.cell_to_world(Vector2i(2, 2)))
	_mode.move_area(_mode.grid.cell_to_world(Vector2i(6, 4)))
	_mode._update_ghost(_mode.grid.cell_to_world(Vector2i(6, 4)))
	assert_str(_mode.status_text()).is_equal("Belt 7 cells")
	assert_int(_mode.belt_cells_to_buy()).is_equal(7)
	# Right-click cancels the drag, as it does a rectangle.
	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	assert_bool(_mode._cancels_area(right)).is_true()
	_mode.cancel_area()
	assert_array(_mode.grid.object_ids()).is_empty()
	_mode.begin_area(_mode.grid.cell_to_world(Vector2i(2, 2)))
	_mode.move_area(_mode.grid.cell_to_world(Vector2i(6, 4)))
	_mode.finish_area()
	assert_int(_mode.grid.object_ids().size()).is_equal(7)
	assert_str(_def(Vector2i(6, 2))).is_equal("baggage_belt_corner")
