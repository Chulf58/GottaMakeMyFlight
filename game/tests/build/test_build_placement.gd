class_name TestBuildPlacement
extends GdUnitTestSuite

const DESK := &"checkin_desk"
const SCANNER := &"security_scanner"
const SEATS := &"seat_row"


func _floored_grid(size := Vector2i(12, 10)) -> BuildGrid:
	var grid := BuildGrid.new(size)
	for y in size.y:
		for x in size.x:
			var result := grid.apply(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
			assert_bool(result.ok).is_true()
	return grid


func _cells_of(grid: BuildGrid, object_id: int) -> Array[Vector2i]:
	var record := grid.get_object(object_id)
	var def := BuildCatalog.get_def(record["def"])
	return def.footprint(record["anchor"], record["facing"])


func test_place_desk_occupies_its_footprint_and_reserves_its_interaction_cell() -> void:
	var grid := _floored_grid()
	var result := grid.apply(BuildEdit.place_object(DESK, Vector2i(3, 3), 0))
	assert_bool(result.ok).is_true()
	assert_int(result.reason).is_equal(BuildResult.Reason.NONE)
	assert_int(result.object_id).is_greater(0)
	assert_int(grid.object_at(Vector2i(3, 3))).is_equal(result.object_id)
	assert_int(grid.object_at(Vector2i(4, 3))).is_equal(result.object_id)
	assert_int(grid.object_at(Vector2i(5, 3))).is_equal(0)
	assert_bool(grid.is_walkable(Vector2i(3, 3))).is_false()
	assert_that(grid.interaction_cell(result.object_id)).is_equal(Vector2i(3, 4))
	assert_bool(grid.is_walkable(Vector2i(3, 4))).is_true()


func test_validate_reports_without_changing_the_grid() -> void:
	var grid := _floored_grid()
	var before := JSON.stringify(grid.to_snapshot())
	var result := grid.validate(BuildEdit.place_object(DESK, Vector2i(3, 3), 0))
	assert_bool(result.ok).is_true()
	assert_int(grid.object_at(Vector2i(3, 3))).is_equal(0)
	assert_str(JSON.stringify(grid.to_snapshot())).is_equal(before)


func test_overlap_is_refused_with_the_blocking_object_named() -> void:
	var grid := _floored_grid()
	var first := grid.apply(BuildEdit.place_object(SEATS, Vector2i(2, 2), 0))
	assert_bool(first.ok).is_true()
	var second := grid.apply(BuildEdit.place_object(DESK, Vector2i(4, 2), 0))
	assert_bool(second.ok).is_false()
	assert_int(second.reason).is_equal(BuildResult.Reason.OVERLAP)
	assert_int(second.blocking_object_id).is_equal(first.object_id)
	assert_str(second.reason_text()).is_not_empty()
	assert_int(grid.object_at(Vector2i(5, 2))).is_equal(0)


func test_out_of_bounds_is_refused() -> void:
	var grid := _floored_grid()
	var past_edge := grid.apply(BuildEdit.place_object(DESK, Vector2i(11, 0), 0))
	assert_bool(past_edge.ok).is_false()
	assert_int(past_edge.reason).is_equal(BuildResult.Reason.OUT_OF_BOUNDS)
	var negative := grid.apply(BuildEdit.paint_floor(Vector2i(-1, 0), BuildGrid.FLOOR_TILE, 1))
	assert_int(negative.reason).is_equal(BuildResult.Reason.OUT_OF_BOUNDS)
	var wall := grid.apply(BuildEdit.place_wall(Vector2i(0, 10), BuildGrid.Side.NORTH))
	assert_int(wall.reason).is_equal(BuildResult.Reason.OUT_OF_BOUNDS)
	assert_int(grid.object_at(Vector2i(11, 0))).is_equal(0)


func test_no_floor_is_refused() -> void:
	var grid := BuildGrid.new(Vector2i(8, 8))
	var result := grid.apply(BuildEdit.place_object(SEATS, Vector2i(1, 1), 0))
	assert_int(result.reason).is_equal(BuildResult.Reason.NO_FLOOR)


func test_rotation_turns_footprint_and_interaction_cell() -> void:
	var desk := BuildCatalog.get_def(DESK)
	var anchor := Vector2i(5, 5)
	var expected := {
		0: [[Vector2i(5, 5), Vector2i(6, 5)], Vector2i(5, 6)],
		1: [[Vector2i(5, 5), Vector2i(5, 6)], Vector2i(4, 5)],
		2: [[Vector2i(5, 5), Vector2i(4, 5)], Vector2i(5, 4)],
		3: [[Vector2i(5, 5), Vector2i(5, 4)], Vector2i(6, 5)],
	}
	for facing in 4:
		var cells := desk.footprint(anchor, facing)
		assert_array(cells).contains_exactly_in_any_order(expected[facing][0])
		assert_that(desk.interaction_cell(anchor, facing)).is_equal(expected[facing][1])


func test_rotated_placement_occupies_the_rotated_cells() -> void:
	var grid := _floored_grid()
	var result := grid.apply(BuildEdit.place_object(SEATS, Vector2i(5, 5), 1))
	assert_bool(result.ok).is_true()
	var cells := _cells_of(grid, result.object_id)
	assert_array(cells).contains_exactly_in_any_order(
		[Vector2i(5, 5), Vector2i(5, 6), Vector2i(5, 7)]
	)
	for cell in cells:
		assert_int(grid.object_at(cell)).is_equal(result.object_id)
	assert_int(grid.object_at(Vector2i(6, 5))).is_equal(0)


func test_bad_facing_and_unknown_object_are_refused() -> void:
	var grid := _floored_grid()
	var facing := grid.apply(BuildEdit.place_object(DESK, Vector2i(3, 3), 4))
	assert_int(facing.reason).is_equal(BuildResult.Reason.BAD_FACING)
	var unknown := grid.apply(BuildEdit.place_object(&"rocket", Vector2i(3, 3), 0))
	assert_int(unknown.reason).is_equal(BuildResult.Reason.UNKNOWN_OBJECT)


func test_object_on_another_desks_interaction_cell_is_refused() -> void:
	var grid := _floored_grid()
	var desk := grid.apply(BuildEdit.place_object(DESK, Vector2i(3, 3), 0))
	var seats := grid.apply(BuildEdit.place_object(SEATS, Vector2i(2, 4), 0))
	assert_bool(seats.ok).is_false()
	assert_int(seats.reason).is_equal(BuildResult.Reason.INTERACTION_RESERVED)
	assert_int(seats.blocking_object_id).is_equal(desk.object_id)


func test_desk_whose_interaction_cell_is_blocked_is_refused() -> void:
	var grid := _floored_grid()
	assert_bool(grid.apply(BuildEdit.place_object(SEATS, Vector2i(3, 4), 0)).ok).is_true()
	var desk := grid.apply(BuildEdit.place_object(DESK, Vector2i(3, 3), 0))
	assert_int(desk.reason).is_equal(BuildResult.Reason.INTERACTION_BLOCKED)
	var walled := _floored_grid()
	walled.apply(BuildEdit.place_wall(Vector2i(3, 4), BuildGrid.Side.NORTH))
	var behind_wall := walled.apply(BuildEdit.place_object(DESK, Vector2i(3, 3), 0))
	assert_int(behind_wall.reason).is_equal(BuildResult.Reason.INTERACTION_BLOCKED)


func test_wall_inside_a_footprint_is_refused_both_ways() -> void:
	var grid := _floored_grid()
	var desk := grid.apply(BuildEdit.place_object(DESK, Vector2i(3, 3), 0))
	var split := grid.apply(BuildEdit.place_wall(Vector2i(3, 3), BuildGrid.Side.EAST))
	assert_int(split.reason).is_equal(BuildResult.Reason.WALL_IN_FOOTPRINT)
	var cut_off := grid.apply(BuildEdit.place_wall(Vector2i(3, 3), BuildGrid.Side.SOUTH))
	assert_int(cut_off.reason).is_equal(BuildResult.Reason.INTERACTION_BLOCKED)
	grid.apply(BuildEdit.remove_object(desk.object_id))
	grid.apply(BuildEdit.place_wall(Vector2i(3, 3), BuildGrid.Side.EAST))
	var over_wall := grid.apply(BuildEdit.place_object(DESK, Vector2i(3, 3), 0))
	assert_int(over_wall.reason).is_equal(BuildResult.Reason.WALL_IN_FOOTPRINT)


func test_removal_frees_footprint_and_reservation() -> void:
	var grid := _floored_grid()
	var desk := grid.apply(BuildEdit.place_object(DESK, Vector2i(3, 3), 0))
	var removed := grid.apply(BuildEdit.remove_object(desk.object_id))
	assert_bool(removed.ok).is_true()
	assert_int(grid.object_at(Vector2i(3, 3))).is_equal(0)
	assert_int(grid.object_at(Vector2i(4, 3))).is_equal(0)
	assert_bool(grid.is_walkable(Vector2i(3, 3))).is_true()
	assert_dict(grid.get_object(desk.object_id)).is_empty()
	assert_bool(grid.apply(BuildEdit.place_object(SEATS, Vector2i(2, 4), 0)).ok).is_true()
	assert_bool(grid.apply(BuildEdit.place_object(DESK, Vector2i(3, 3), 0)).ok).is_false()
	assert_bool(grid.apply(BuildEdit.place_object(DESK, Vector2i(3, 2), 2)).ok).is_true()
	var again := grid.apply(BuildEdit.remove_object(desk.object_id))
	assert_int(again.reason).is_equal(BuildResult.Reason.NO_OBJECT)


func test_floor_under_an_object_cannot_be_removed() -> void:
	var grid := _floored_grid()
	grid.apply(BuildEdit.place_object(DESK, Vector2i(3, 3), 0))
	var under := grid.apply(BuildEdit.remove_floor(Vector2i(4, 3)))
	assert_int(under.reason).is_equal(BuildResult.Reason.OCCUPIED)
	var queue_spot := grid.apply(BuildEdit.remove_floor(Vector2i(3, 4)))
	assert_int(queue_spot.reason).is_equal(BuildResult.Reason.INTERACTION_RESERVED)
	var free := grid.apply(BuildEdit.remove_floor(Vector2i(8, 8)))
	assert_bool(free.ok).is_true()
	assert_int(grid.floor_at(Vector2i(8, 8))).is_equal(BuildGrid.FLOOR_NONE)
	var twice := grid.apply(BuildEdit.remove_floor(Vector2i(8, 8)))
	assert_int(twice.reason).is_equal(BuildResult.Reason.NO_FLOOR)


func test_floor_paint_sets_type_and_zone() -> void:
	var grid := BuildGrid.new(Vector2i(4, 4))
	var result := grid.apply(BuildEdit.paint_floor(Vector2i(1, 2), BuildGrid.FLOOR_TILE, 7))
	assert_bool(result.ok).is_true()
	assert_int(grid.floor_at(Vector2i(1, 2))).is_equal(BuildGrid.FLOOR_TILE)
	assert_int(grid.zone_at(Vector2i(1, 2))).is_equal(7)
	var bad := grid.apply(BuildEdit.paint_floor(Vector2i(1, 2), 99, 1))
	assert_int(bad.reason).is_equal(BuildResult.Reason.BAD_FLOOR_TYPE)


func test_walls_place_on_shared_edges_and_refuse_duplicates() -> void:
	var grid := _floored_grid()
	assert_bool(grid.apply(BuildEdit.place_wall(Vector2i(2, 2), BuildGrid.Side.EAST)).ok).is_true()
	assert_bool(grid.has_wall(Vector2i(3, 2), BuildGrid.Side.WEST)).is_true()
	var dup := grid.apply(BuildEdit.place_wall(Vector2i(3, 2), BuildGrid.Side.WEST))
	assert_int(dup.reason).is_equal(BuildResult.Reason.WALL_EXISTS)
	assert_bool(grid.apply(BuildEdit.remove_wall(Vector2i(3, 2), BuildGrid.Side.WEST)).ok).is_true()
	assert_bool(grid.has_wall(Vector2i(2, 2), BuildGrid.Side.EAST)).is_false()
	var none := grid.apply(BuildEdit.remove_wall(Vector2i(2, 2), BuildGrid.Side.EAST))
	assert_int(none.reason).is_equal(BuildResult.Reason.NO_WALL)
	assert_bool(grid.apply(BuildEdit.place_wall(Vector2i(0, 0), BuildGrid.Side.NORTH)).ok).is_true()
	assert_bool(grid.apply(BuildEdit.place_wall(Vector2i(11, 9), BuildGrid.Side.EAST)).ok).is_true()
