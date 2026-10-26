class_name TestRoomGrid
extends GdUnitTestSuite
## Rooms in BuildGrid: a room marks a rectangle of floor cells as a store type.
## Placing and removing one goes through validate/apply like every other edit.


func _floored(area := Rect2i(1, 1, 8, 6)) -> BuildGrid:
	var grid := BuildGrid.new(Vector2i(12, 10))
	var edits: Array[BuildEdit] = []
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	grid.apply_batch(edits)
	return grid


func test_a_room_on_floor_is_placed_and_marks_its_cells() -> void:
	var grid := _floored()
	var result := grid.apply(BuildEdit.place_room(Rect2i(2, 2, 3, 3), &"cafe"))
	assert_bool(result.ok).is_true()
	assert_int(result.room_id).is_equal(1)
	assert_array(grid.room_ids()).is_equal([1])
	assert_int(grid.room_at(Vector2i(2, 2))).is_equal(1)
	assert_int(grid.room_at(Vector2i(4, 4))).is_equal(1)
	assert_int(grid.room_at(Vector2i(5, 4))).is_equal(0)
	assert_int(grid.room_at(Vector2i(-1, 0))).is_equal(0)
	var room := grid.get_room(1)
	assert_str(str(room["type"])).is_equal("cafe")
	assert_that(room["rect"]).is_equal(Rect2i(2, 2, 3, 3))


func test_a_room_needs_floor_on_every_cell() -> void:
	var grid := _floored(Rect2i(1, 1, 3, 3))
	var result := grid.apply(BuildEdit.place_room(Rect2i(1, 1, 4, 3), &"cafe"))
	assert_int(result.reason).is_equal(BuildResult.Reason.NO_FLOOR)
	assert_array(grid.room_ids()).is_empty()


func test_a_room_must_lie_inside_the_grid_and_have_cells() -> void:
	var grid := _floored()
	for rect in [Rect2i(-1, 2, 3, 3), Rect2i(10, 8, 3, 3), Rect2i(2, 2, 0, 3)]:
		var result := grid.validate(BuildEdit.place_room(rect, &"cafe"))
		assert_int(result.reason).is_equal(BuildResult.Reason.OUT_OF_BOUNDS)


func test_an_unknown_room_type_is_refused() -> void:
	var grid := _floored()
	var result := grid.validate(BuildEdit.place_room(Rect2i(2, 2, 3, 3), &"spa"))
	assert_int(result.reason).is_equal(BuildResult.Reason.UNKNOWN_ROOM_TYPE)


func test_rooms_cannot_overlap_but_may_touch() -> void:
	var grid := _floored()
	grid.apply(BuildEdit.place_room(Rect2i(1, 1, 3, 3), &"cafe"))
	var overlap := grid.apply(BuildEdit.place_room(Rect2i(3, 3, 3, 3), &"cafe"))
	assert_int(overlap.reason).is_equal(BuildResult.Reason.ROOM_OVERLAP)
	var beside := grid.apply(BuildEdit.place_room(Rect2i(4, 1, 3, 3), &"cafe"))
	assert_bool(beside.ok).is_true()
	assert_int(beside.room_id).is_equal(2)


func test_a_small_room_is_allowed_by_the_grid() -> void:
	# The minimum size is a readiness rule (RoomRules), not a placement rule.
	var grid := _floored()
	assert_bool(grid.apply(BuildEdit.place_room(Rect2i(2, 2, 1, 2), &"cafe")).ok).is_true()


func test_floor_inside_a_room_cannot_be_removed_until_the_room_goes() -> void:
	var grid := _floored()
	var placed := grid.apply(BuildEdit.place_room(Rect2i(2, 2, 3, 3), &"cafe"))
	var refused := grid.apply(BuildEdit.remove_floor(Vector2i(3, 3)))
	assert_int(refused.reason).is_equal(BuildResult.Reason.IN_ROOM)
	assert_int(grid.floor_at(Vector2i(3, 3))).is_equal(BuildGrid.FLOOR_TILE)
	var removed := grid.apply(BuildEdit.remove_room(placed.room_id))
	assert_bool(removed.ok).is_true()
	assert_int(removed.room_id).is_equal(placed.room_id)
	assert_int(grid.room_at(Vector2i(3, 3))).is_equal(0)
	assert_array(grid.room_ids()).is_empty()
	assert_bool(grid.apply(BuildEdit.remove_floor(Vector2i(3, 3))).ok).is_true()


func test_removing_an_unknown_room_is_refused() -> void:
	var grid := _floored()
	assert_int(grid.apply(BuildEdit.remove_room(7)).reason).is_equal(BuildResult.Reason.NO_ROOM)


func test_room_edits_leave_furniture_and_walkability_alone() -> void:
	var grid := _floored()
	grid.apply(BuildEdit.place_object(&"cafe_counter", Vector2i(3, 3), 0))
	var before := grid.find_path(Vector2i(1, 1), Vector2i(8, 6))
	var placed := grid.apply(BuildEdit.place_room(Rect2i(2, 2, 4, 4), &"cafe"))
	assert_array(placed.dirty_cells).is_empty()
	grid.apply(BuildEdit.remove_room(placed.room_id))
	assert_int(grid.object_ids().size()).is_equal(1)
	assert_array(grid.find_path(Vector2i(1, 1), Vector2i(8, 6))).is_equal(before)


func test_room_edits_emit_edit_applied_but_no_graph_change() -> void:
	var grid := _floored()
	var applied: Array = []
	var graphs: Array = []
	grid.edit_applied.connect(func(e: BuildEdit, _r: BuildResult) -> void: applied.append(e.kind))
	grid.graph_changed.connect(func(cells: Array[Vector2i]) -> void: graphs.append(cells))
	var placed := grid.apply(BuildEdit.place_room(Rect2i(2, 2, 3, 3), &"cafe"))
	grid.apply(BuildEdit.remove_room(placed.room_id))
	assert_array(applied).is_equal([BuildEdit.Kind.PLACE_ROOM, BuildEdit.Kind.REMOVE_ROOM])
	assert_array(graphs).is_empty()


func test_room_ids_are_not_reused_after_a_removal() -> void:
	var grid := _floored()
	var first := grid.apply(BuildEdit.place_room(Rect2i(2, 2, 3, 3), &"cafe"))
	grid.apply(BuildEdit.remove_room(first.room_id))
	var second := grid.apply(BuildEdit.place_room(Rect2i(2, 2, 3, 3), &"cafe"))
	assert_int(second.room_id).is_equal(2)


func test_get_room_returns_a_copy_and_nothing_for_an_unknown_id() -> void:
	var grid := _floored()
	grid.apply(BuildEdit.place_room(Rect2i(2, 2, 3, 3), &"cafe"))
	var room := grid.get_room(1)
	room["rect"] = Rect2i(0, 0, 1, 1)
	assert_that(grid.get_room(1)["rect"]).is_equal(Rect2i(2, 2, 3, 3))
	assert_dict(grid.get_room(9)).is_empty()
