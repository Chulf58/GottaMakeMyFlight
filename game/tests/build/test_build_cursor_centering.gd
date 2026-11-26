class_name TestBuildCursorCentering
extends GdUnitTestSuite

var _mode: BuildMode


func before_test() -> void:
	_mode = BuildMode.new()
	_mode.grid_size = Vector2i(20, 20)
	_mode.initial_tool = BuildMode.Tool.NONE
	add_child(_mode)
	_mode.set_process(false)
	var edits: Array[BuildEdit] = []
	for y in range(2, 18):
		for x in range(2, 18):
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	_mode.grid.apply_batch(edits)


func after_test() -> void:
	_mode.free()


func _at(cell: Vector2i) -> Vector3:
	return _mode.grid.cell_to_world(cell)


func _footprint_center(def_id: StringName, anchor: Vector2i, turn: int) -> Vector3:
	var def := BuildCatalog.get_def(def_id)
	var cells := def.footprint(anchor, turn)
	var sum := Vector3.ZERO
	for c in cells:
		sum += _mode.grid.cell_to_world(c)
	return sum / float(cells.size())


func _sorted_cells(cells: Array[Vector2i]) -> Array[Vector2i]:
	var copy := cells.duplicate()
	copy.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y if a.y != b.y else a.x < b.x
	)
	return copy


func test_odd_multitile_object_centers_on_cursor_across_all_facings() -> void:
	_mode.set_tool(BuildMode.Tool.SEATS)
	var cursor_cell := Vector2i(9, 9)
	var point := _at(cursor_cell)
	for turn in 4:
		_mode.facing = turn
		var edit := _mode.edit_at(point)
		assert_object(edit).is_not_null()
		var center := _footprint_center(&"seat_row", edit.cell, edit.facing)
		(
			assert_float(center.distance_to(point))
			. override_failure_message("facing %d center %s != %s" % [turn, center, point])
			. is_less(0.001)
		)
		var def := BuildCatalog.get_def(&"seat_row")
		var footprint := _sorted_cells(def.footprint(edit.cell, edit.facing))
		assert_bool(footprint.has(cursor_cell)).is_true()


func test_even_multitile_objects_center_within_half_cell_and_rotate_in_place() -> void:
	# 2x1 checkin_desk slightly off cell center: all 4 facings stay within +/-0.5 m
	# and 180-degree opposite pairs (0/2 and 1/3) share exact footprints.
	_mode.set_tool(BuildMode.Tool.DESK)
	var desk_pt := _at(Vector2i(9, 9)) + Vector3(-0.2, 0.0, -0.2)
	var desk_def := BuildCatalog.get_def(&"checkin_desk")
	var footprints := {}
	for turn in 4:
		_mode.facing = turn
		var edit := _mode.edit_at(desk_pt)
		footprints[turn] = _sorted_cells(desk_def.footprint(edit.cell, edit.facing))
		var desk_center := _footprint_center(&"checkin_desk", edit.cell, edit.facing)
		(
			assert_float(absf(desk_center.x - desk_pt.x))
			. override_failure_message("desk facing %d x" % turn)
			. is_less_equal(0.5)
		)
		(
			assert_float(absf(desk_center.z - desk_pt.z))
			. override_failure_message("desk facing %d z" % turn)
			. is_less_equal(0.5)
		)
	assert_array(footprints[2]).is_equal(footprints[0])
	assert_array(footprints[3]).is_equal(footprints[1])

	# 2x2 bar_counter: all 4 facings occupy the exact same 2x2 cells around the cursor.
	_mode.set_tool(BuildMode.Tool.BAR_COUNTER)
	var bar_pt := _at(Vector2i(10, 10)) + Vector3(0.2, 0.0, 0.2)
	var bar_def := BuildCatalog.get_def(&"bar_counter")
	var expected_bar: Array[Vector2i] = [
		Vector2i(10, 10), Vector2i(11, 10), Vector2i(10, 11), Vector2i(11, 11)
	]
	for turn in 4:
		_mode.facing = turn
		var edit := _mode.edit_at(bar_pt)
		var foot := _sorted_cells(bar_def.footprint(edit.cell, edit.facing))
		assert_array(foot).override_failure_message("bar facing %d" % turn).is_equal(expected_bar)


func test_one_by_one_and_doors_preserve_wall_line_snapping() -> void:
	# Floor exists on x 2..17, y 2..17; east outer wall line is x = 18.0 (between x=17 and x=18).
	var east_line := _at(Vector2i(17, 6)) + Vector3(0.5, 0.0, 0.0)
	for t in [BuildMode.Tool.BIN, BuildMode.Tool.ENTRANCE, BuildMode.Tool.EXIT]:
		_mode.set_tool(t)
		var edit := _mode.edit_at(east_line)
		assert_vector(edit.cell).override_failure_message("tool %d" % t).is_equal(Vector2i(17, 6))


func test_item_row_drag_starts_at_centered_anchor_with_zero_jump() -> void:
	_mode.set_tool(BuildMode.Tool.SEATS)
	_mode.facing = 0
	var start_pt := _at(Vector2i(5, 8))
	var single := _mode.edit_at(start_pt)
	_mode.begin_item_row(start_pt)
	assert_vector(_mode._item_row.start_cell()).is_equal(single.cell)
	# Moving to cursor cell 7 (centered anchor 6, dist 2 < stride 3) keeps 1 edit;
	# raw world_to_cell(7, 8) would regress to 2 edits.
	_mode.move_item_row(_at(Vector2i(7, 8)))
	assert_int(_mode._item_row.edits().size()).is_equal(1)
	assert_vector(_mode._item_row.edits()[0].cell).is_equal(single.cell)
	_mode.move_item_row(_at(Vector2i(8, 8)))
	var edits := _mode._item_row.edits()
	assert_int(edits.size()).is_equal(2)
	assert_vector(edits[0].cell).is_equal(single.cell)
	assert_vector(edits[1].cell).is_equal(Vector2i(7, 8))
	var out := _mode.finish_item_row()
	assert_int(out.placed).is_equal(2)
	assert_vector(_mode._note_cell).is_equal(Vector2i(8, 8))

	# Rotated even-width repeatable item (toilet_stall 1x2 at facing 1 -> 2x1 along X, stride 3).
	_mode.set_tool(BuildMode.Tool.TOILET_STALL)
	_mode.facing = 1
	var stall_start := _at(Vector2i(5, 12))
	var stall_single := _mode.edit_at(stall_start)
	assert_vector(stall_single.cell).is_equal(Vector2i(6, 12))
	_mode.begin_item_row(stall_start)
	assert_vector(_mode._item_row.start_cell()).is_equal(stall_single.cell)
	_mode.move_item_row(_at(Vector2i(8, 12)) + Vector3(-0.2, 0.0, 0.0))
	assert_int(_mode._item_row.edits().size()).is_equal(1)
	_mode.move_item_row(_at(Vector2i(8, 12)) + Vector3(0.2, 0.0, 0.0))
	var stall_edits := _mode._item_row.edits()
	assert_int(stall_edits.size()).is_equal(2)
	assert_vector(stall_edits[0].cell).is_equal(Vector2i(6, 12))
	assert_vector(stall_edits[1].cell).is_equal(Vector2i(9, 12))
	var stall_out := _mode.finish_item_row()
	assert_int(stall_out.placed).is_equal(2)
	assert_vector(_mode._note_cell).is_equal(Vector2i(8, 12))


func test_security_lane_stamp_centers_and_aligns_preview_click_and_clearance() -> void:
	_mode.set_tool(BuildMode.Tool.SECURITY_LANE)
	var pt := _at(Vector2i(10, 10))
	var rects_by_facing := {}
	for turn in 4:
		_mode.facing = turn
		_mode._pointer_on_grid = true
		_mode._update_ghost(pt)
		var clearance := BuildGhost.clearance_target(_mode)
		assert_bool(clearance["active"]).is_true()
		var res := _mode.apply_at(pt)
		(
			assert_bool(res.ok)
			. override_failure_message("lane facing %d: %s" % [turn, res.reason_text()])
			. is_true()
		)
		var placed_cells: Array[Vector2i] = []
		for oid in _mode.grid.object_ids():
			placed_cells.append(_mode.grid.get_object(oid)["anchor"])
		assert_int(placed_cells.size()).is_equal(4)
		var box := Rect2i(placed_cells[0], Vector2i.ONE)
		for i in range(1, placed_cells.size()):
			box = box.merge(Rect2i(placed_cells[i], Vector2i.ONE))
		rects_by_facing[turn] = box
		var bounds: Rect2 = clearance["bounds"]
		var expected_bounds := Rect2(
			Vector2(_mode.grid.origin.x + box.position.x, _mode.grid.origin.z + box.position.y),
			Vector2(box.size),
		)
		assert_that(bounds).is_equal(expected_bounds)
		var box_center := bounds.get_center()
		assert_float(absf(box_center.x - pt.x)).is_less_equal(0.5)
		assert_float(absf(box_center.y - pt.z)).is_less_equal(0.5)
		assert_bool(_mode.undo().ok).is_true()
	# 180-degree opposite facings cover the exact same 2x3 bounding box.
	assert_that(rects_by_facing[2]).is_equal(rects_by_facing[0])
	assert_that(rects_by_facing[3]).is_equal(rects_by_facing[1])
