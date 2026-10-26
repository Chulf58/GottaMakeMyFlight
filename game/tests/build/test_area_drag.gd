class_name TestAreaDrag
extends GdUnitTestSuite
## AreaDrag on a bare grid: the rectangle a drag makes and what filling or
## clearing it does cell by cell.

const ZONE := 1
## Stall guards, set between the measured time (see the printed AREA_DRAG lines)
## and the per-cell relink this replaced (about 200 ms and 880 ms to fill).
const FILL_30_LIMIT_MS := 150.0
const CLEAR_30_LIMIT_MS := 100.0
const FILL_64_LIMIT_MS := 500.0
const CLEAR_64_LIMIT_MS := 250.0

var _grid: BuildGrid
var _drag: AreaDrag


func before_test() -> void:
	_grid = BuildGrid.new(Vector2i(20, 20))
	_drag = AreaDrag.new()


func _paint(cell: Vector2i) -> void:
	assert_bool(_grid.apply(BuildEdit.paint_floor(cell, BuildGrid.FLOOR_TILE, ZONE)).ok).is_true()


func _paint_rect(area: Rect2i) -> void:
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			_paint(Vector2i(x, y))


func test_the_rectangle_runs_from_the_start_cell_to_the_current_cell_either_way() -> void:
	_drag.begin(Vector2i(5, 5), Vector3.ZERO, _grid.size)
	assert_bool(_drag.move(Vector2i(8, 7))).is_true()
	assert_that(_drag.rect()).is_equal(Rect2i(5, 5, 4, 3))
	_drag.move(Vector2i(2, 3))
	assert_that(_drag.rect()).is_equal(Rect2i(2, 3, 4, 3))
	_drag.move(Vector2i(9, 1))
	assert_that(_drag.rect()).is_equal(Rect2i(5, 1, 5, 5))


func test_moving_inside_the_same_cell_changes_nothing() -> void:
	_drag.begin(Vector2i(5, 5), Vector3.ZERO, _grid.size)
	_drag.move(Vector2i(7, 6))
	assert_bool(_drag.move(Vector2i(7, 6))).is_false()


func test_the_size_label_counts_cells_both_ways() -> void:
	_drag.begin(Vector2i(2, 2), Vector3.ZERO, _grid.size)
	_drag.move(Vector2i(13, 9))
	assert_str(_drag.size_label()).is_equal("12 x 8")
	_drag.move(Vector2i(2, 2))
	assert_str(_drag.size_label()).is_equal("1 x 1")


func test_the_rectangle_stops_at_the_edge_of_the_grid() -> void:
	_drag.begin(Vector2i(5, 5), Vector3.ZERO, _grid.size)
	_drag.move(Vector2i(40, -9))
	assert_that(_drag.rect()).is_equal(Rect2i(5, 0, 15, 6))


func test_a_drag_that_stays_on_the_start_cell_is_a_single_click() -> void:
	var press := Vector3(1.2, 0.0, 3.4)
	_drag.begin(Vector2i(1, 3), press, _grid.size)
	assert_bool(_drag.is_single_cell()).is_true()
	assert_that(_drag.press_point).is_equal(press)
	_drag.move(Vector2i(2, 3))
	assert_bool(_drag.is_single_cell()).is_false()


func test_cancel_ends_the_drag() -> void:
	_drag.begin(Vector2i(5, 5), Vector3.ZERO, _grid.size)
	_drag.cancel()
	assert_bool(_drag.active).is_false()


func test_fill_floor_paints_every_cell_of_the_rectangle() -> void:
	var outcome := AreaDrag.fill_floor(_grid, Rect2i(3, 4, 4, 3), ZONE)
	assert_int(outcome.placed).is_equal(12)
	assert_int(outcome.skipped).is_equal(0)
	assert_str(outcome.message()).is_equal("Placed 12")
	for y in range(4, 7):
		for x in range(3, 7):
			assert_int(_grid.floor_at(Vector2i(x, y))).is_equal(BuildGrid.FLOOR_TILE)
			assert_int(_grid.zone_at(Vector2i(x, y))).is_equal(ZONE)
	assert_int(_grid.floor_at(Vector2i(7, 4))).is_equal(BuildGrid.FLOOR_NONE)


func test_fill_floor_counts_floored_cells_as_unchanged_not_refused() -> void:
	_paint_rect(Rect2i(3, 4, 2, 3))
	var outcome := AreaDrag.fill_floor(_grid, Rect2i(3, 4, 4, 3), ZONE)
	assert_int(outcome.placed).is_equal(6)
	assert_int(outcome.unchanged).is_equal(6)
	assert_int(outcome.skipped).is_equal(0)
	assert_str(outcome.message()).is_equal("Placed 6")
	var again := AreaDrag.fill_floor(_grid, Rect2i(3, 4, 4, 3), ZONE)
	assert_str(again.message()).is_equal("Nothing to place")


func test_fill_floor_skips_the_cell_beyond_a_door_and_names_why() -> void:
	_paint(Vector2i(5, 5))
	_paint(Vector2i(5, 6))
	(
		assert_bool(_grid.apply(BuildEdit.place_object(&"entrance_door", Vector2i(5, 5), 0)).ok)
		. is_true()
	)
	var outcome := AreaDrag.fill_floor(_grid, Rect2i(4, 3, 3, 3), ZONE)
	assert_int(outcome.placed).is_equal(7)
	assert_int(outcome.skipped).is_equal(1)
	assert_int(outcome.unchanged).is_equal(1)
	var why := BuildResult.REASON_TEXT[BuildResult.Reason.DOOR_NOT_ON_EDGE]
	assert_str(outcome.message()).is_equal("Placed 7, skipped 1: " + why)
	assert_int(_grid.floor_at(Vector2i(5, 4))).is_equal(BuildGrid.FLOOR_NONE)


func test_fill_floor_skips_cells_outside_the_grid() -> void:
	var outcome := AreaDrag.fill_floor(_grid, Rect2i(18, 18, 4, 4), ZONE)
	assert_int(outcome.placed).is_equal(4)
	assert_int(outcome.skipped).is_equal(12)
	assert_str(outcome.first_reason).is_equal(
		BuildResult.REASON_TEXT[BuildResult.Reason.OUT_OF_BOUNDS]
	)


func test_clear_removes_floor_and_whole_objects_but_not_walls() -> void:
	_paint_rect(Rect2i(2, 2, 8, 8))
	(
		assert_bool(_grid.apply(BuildEdit.place_object(&"checkin_desk", Vector2i(3, 3), 0)).ok)
		. is_true()
	)
	(
		assert_bool(_grid.apply(BuildEdit.place_wall(Vector2i(6, 6), BuildGrid.Side.NORTH)).ok)
		. is_true()
	)
	# The rectangle holds only the desk's left cell, but the desk goes whole.
	var outcome := AreaDrag.clear(_grid, Rect2i(3, 3, 1, 1))
	assert_int(outcome.placed).is_equal(1)
	assert_array(_grid.object_ids()).is_empty()
	assert_int(_grid.floor_at(Vector2i(3, 3))).is_equal(BuildGrid.FLOOR_TILE)
	assert_str(outcome.message()).is_equal("Removed 1")
	var floors := AreaDrag.clear(_grid, Rect2i(5, 5, 3, 3))
	assert_int(floors.placed).is_equal(9)
	assert_int(_grid.floor_at(Vector2i(6, 6))).is_equal(BuildGrid.FLOOR_NONE)
	assert_bool(_grid.has_wall(Vector2i(6, 6), BuildGrid.Side.NORTH)).is_true()


func test_clear_takes_an_object_before_the_floor_it_reserved() -> void:
	_paint_rect(Rect2i(2, 2, 8, 8))
	(
		assert_bool(_grid.apply(BuildEdit.place_object(&"checkin_desk", Vector2i(3, 3), 0)).ok)
		. is_true()
	)
	# The desk stands on (3,3) and (4,3); (3,4) is its spot in front.
	var outcome := AreaDrag.clear(_grid, Rect2i(3, 3, 1, 2))
	assert_int(outcome.placed).is_equal(2)
	assert_int(outcome.skipped).is_equal(0)
	assert_array(_grid.object_ids()).is_empty()
	assert_int(_grid.floor_at(Vector2i(3, 4))).is_equal(BuildGrid.FLOOR_NONE)
	assert_int(_grid.floor_at(Vector2i(3, 3))).is_equal(BuildGrid.FLOOR_TILE)


func test_clear_refuses_the_spot_in_front_of_an_object_it_leaves_standing() -> void:
	_paint_rect(Rect2i(2, 2, 8, 8))
	(
		assert_bool(_grid.apply(BuildEdit.place_object(&"checkin_desk", Vector2i(3, 3), 0)).ok)
		. is_true()
	)
	var outcome := AreaDrag.clear(_grid, Rect2i(3, 4, 2, 1))
	assert_int(outcome.placed).is_equal(1)
	assert_int(outcome.skipped).is_equal(1)
	var why := BuildResult.REASON_TEXT[BuildResult.Reason.INTERACTION_RESERVED]
	assert_str(outcome.message()).is_equal("Removed 1, skipped 1: " + why)
	assert_int(_grid.floor_at(Vector2i(4, 4))).is_equal(BuildGrid.FLOOR_NONE)


func test_clear_counts_cells_without_floor_as_unchanged_not_refused() -> void:
	_paint_rect(Rect2i(2, 2, 2, 2))
	var outcome := AreaDrag.clear(_grid, Rect2i(1, 1, 4, 4))
	assert_int(outcome.placed).is_equal(4)
	assert_int(outcome.unchanged).is_equal(12)
	assert_int(outcome.skipped).is_equal(0)
	assert_str(AreaDrag.clear(_grid, Rect2i(1, 1, 4, 4)).message()).is_equal("Nothing to remove")


func test_clear_over_both_cells_of_a_desk_removes_it_and_keeps_the_floor_under_it() -> void:
	_paint_rect(Rect2i(2, 2, 8, 8))
	(
		assert_bool(_grid.apply(BuildEdit.place_object(&"checkin_desk", Vector2i(3, 3), 0)).ok)
		. is_true()
	)
	var outcome := AreaDrag.clear(_grid, Rect2i(3, 3, 2, 1))
	assert_int(outcome.placed).is_equal(1)
	assert_int(outcome.skipped).is_equal(0)
	assert_array(_grid.object_ids()).is_empty()
	assert_int(_grid.floor_at(Vector2i(3, 3))).is_equal(BuildGrid.FLOOR_TILE)
	assert_int(_grid.floor_at(Vector2i(4, 3))).is_equal(BuildGrid.FLOOR_TILE)


func test_fill_floor_leaves_floor_of_another_zone_alone() -> void:
	_grid.apply(BuildEdit.paint_floor(Vector2i(4, 4), BuildGrid.FLOOR_TILE, 2))
	var outcome := AreaDrag.fill_floor(_grid, Rect2i(3, 4, 3, 1), ZONE)
	assert_int(outcome.placed).is_equal(2)
	assert_int(outcome.unchanged).is_equal(1)
	assert_int(_grid.zone_at(Vector2i(4, 4))).is_equal(2)


func test_a_rectangle_relinks_the_graph_once() -> void:
	var emitted := []
	_grid.graph_changed.connect(func(cells: Array[Vector2i]) -> void: emitted.append(cells))
	AreaDrag.fill_floor(_grid, Rect2i(3, 3, 5, 5), ZONE)
	assert_int(emitted.size()).is_equal(1)
	AreaDrag.clear(_grid, Rect2i(3, 3, 5, 5))
	assert_int(emitted.size()).is_equal(2)


func test_a_30_by_30_rectangle_applies_without_a_stall() -> void:
	var big := BuildGrid.new(Vector2i(40, 40))
	var world := PassengerTestWorld.make(big, FlightSim.schedule_starts(0))
	var started := Time.get_ticks_usec()
	var filled := AreaDrag.fill_floor(big, Rect2i(5, 5, 30, 30), ZONE)
	var fill_ms := (Time.get_ticks_usec() - started) / 1000.0
	started = Time.get_ticks_usec()
	var cleared := AreaDrag.clear(big, Rect2i(5, 5, 30, 30))
	var clear_ms := (Time.get_ticks_usec() - started) / 1000.0
	print("AREA_DRAG 30x30 fill=%.1f ms clear=%.1f ms (passenger sim bound)" % [fill_ms, clear_ms])
	assert_int(filled.placed).is_equal(900)
	assert_int(cleared.placed).is_equal(900)
	assert_float(fill_ms).is_less(FILL_30_LIMIT_MS)
	assert_float(clear_ms).is_less(CLEAR_30_LIMIT_MS)
	world.free_all()


func test_a_full_64_by_64_grid_fills_and_clears_without_a_stall() -> void:
	var big := BuildGrid.new()
	var world := PassengerTestWorld.make(big, FlightSim.schedule_starts(0))
	var whole := Rect2i(Vector2i.ZERO, big.size)
	var started := Time.get_ticks_usec()
	var filled := AreaDrag.fill_floor(big, whole, ZONE)
	var fill_ms := (Time.get_ticks_usec() - started) / 1000.0
	started = Time.get_ticks_usec()
	var cleared := AreaDrag.clear(big, whole)
	var clear_ms := (Time.get_ticks_usec() - started) / 1000.0
	print("AREA_DRAG 64x64 fill=%.1f ms clear=%.1f ms (passenger sim bound)" % [fill_ms, clear_ms])
	assert_int(filled.placed).is_equal(4096)
	assert_int(cleared.placed).is_equal(4096)
	assert_float(fill_ms).is_less(FILL_64_LIMIT_MS)
	assert_float(clear_ms).is_less(CLEAR_64_LIMIT_MS)
	world.free_all()
