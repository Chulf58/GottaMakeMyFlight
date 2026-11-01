class_name TestEnclosureGaps
extends GdUnitTestSuite
## Gaps in the outer wall (EnclosureGaps): the open edges where floor that
## walls do not close in meets ground with no floor (decision player-builds-
## the-terminal-floor-outer-walls-auto-roof-land-plots-starter-one-floor,
## point 2: "an open gap is shown on screen"). The subject is a 4x3 box of
## floor at x 2-5, y 2-4 on a 12x10 grid, walled on all four sides.

const BOX := Rect2i(2, 2, 4, 3)

var _grid: BuildGrid


func before_test() -> void:
	_grid = BuildGrid.new(Vector2i(12, 10))
	_paint(BOX)
	assert_int(EnclosureKit.close_floor(_grid)).is_equal(14)


func _paint(area: Rect2i) -> void:
	var edits: Array[BuildEdit] = []
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	for result in _grid.apply_batch(edits):
		assert_bool(result.ok).override_failure_message(result.reason_text()).is_true()


func _apply(edit: BuildEdit) -> BuildResult:
	var result := _grid.apply(edit)
	assert_bool(result.ok).override_failure_message(result.reason_text()).is_true()
	return result


func test_a_closed_box_has_no_gap() -> void:
	assert_bool(EnclosureKit.all_indoor(_grid)).is_true()
	assert_array(EnclosureGaps.gap_edges(_grid)).is_empty()
	assert_array(EnclosureGaps.gap_runs(_grid)).is_empty()


func test_one_missing_wall_is_one_gap_on_that_edge() -> void:
	_apply(BuildEdit.remove_wall(Vector2i(5, 3), BuildGrid.Side.EAST))
	var edges := EnclosureGaps.gap_edges(_grid)
	assert_array(edges).contains_exactly([Vector3i(5, 3, BuildGrid.Side.EAST)])
	var runs := EnclosureGaps.gap_runs(_grid)
	assert_int(runs.size()).is_equal(1)
	assert_that(runs[0].cell).is_equal(Vector2i(5, 3))
	assert_int(runs[0].side).is_equal(BuildGrid.Side.EAST)
	assert_int(runs[0].length).is_equal(1)
	# The marker point is the middle of the open edge, on the floor.
	assert_that(runs[0].centre(_grid)).is_equal(_grid.origin + Vector3(6.0, 0.0, 3.5))


func test_neighbouring_open_edges_on_one_side_are_one_run() -> void:
	for x in [2, 3, 4]:
		_apply(BuildEdit.remove_wall(Vector2i(x, 4), BuildGrid.Side.SOUTH))
	assert_int(EnclosureGaps.gap_edges(_grid).size()).is_equal(3)
	var runs := EnclosureGaps.gap_runs(_grid)
	assert_int(runs.size()).is_equal(1)
	assert_that(runs[0].cell).is_equal(Vector2i(2, 4))
	assert_int(runs[0].length).is_equal(3)
	assert_that(runs[0].centre(_grid)).is_equal(_grid.origin + Vector3(3.5, 0.0, 5.0))


func test_gaps_on_two_sides_are_two_runs() -> void:
	_apply(BuildEdit.remove_wall(Vector2i(2, 2), BuildGrid.Side.NORTH))
	_apply(BuildEdit.remove_wall(Vector2i(2, 2), BuildGrid.Side.WEST))
	assert_array(EnclosureGaps.gap_edges(_grid)).contains_exactly_in_any_order(
		[Vector3i(2, 2, BuildGrid.Side.NORTH), Vector3i(2, 2, BuildGrid.Side.WEST)]
	)
	assert_int(EnclosureGaps.gap_runs(_grid).size()).is_equal(2)


## An entrance stands in the wall line with no wall on its back edge: the door
## object fills that gap, so it is not one. Taking the door away opens it.
func test_a_door_fills_its_back_edge_and_removing_it_opens_a_gap() -> void:
	_apply(BuildEdit.remove_wall(Vector2i(3, 4), BuildGrid.Side.SOUTH))
	assert_int(EnclosureGaps.gap_edges(_grid).size()).is_equal(1)
	var door := _apply(BuildEdit.place_object(&"entrance_door", Vector2i(3, 4), 2)).object_id
	assert_bool(_grid.has_wall(Vector2i(3, 4), BuildGrid.Side.SOUTH)).is_false()
	assert_bool(EnclosureKit.all_indoor(_grid)).is_true()
	assert_array(EnclosureGaps.gap_edges(_grid)).is_empty()
	_apply(BuildEdit.remove_object(door))
	assert_array(EnclosureGaps.gap_edges(_grid)).contains_exactly(
		[Vector3i(3, 4, BuildGrid.Side.SOUTH)]
	)


## Floor painted out through a gap carries the gap to the new floor's open
## edges; the edge between the two floored cells is not a gap.
func test_floor_painted_through_a_gap_moves_the_gap_to_its_open_edges() -> void:
	_apply(BuildEdit.remove_wall(Vector2i(5, 3), BuildGrid.Side.EAST))
	_paint(Rect2i(6, 3, 1, 1))
	(
		assert_array(EnclosureGaps.gap_edges(_grid))
		. contains_exactly_in_any_order(
			[
				Vector3i(6, 3, BuildGrid.Side.NORTH),
				Vector3i(6, 3, BuildGrid.Side.EAST),
				Vector3i(6, 3, BuildGrid.Side.SOUTH),
			]
		)
	)


## Bare floor with no wall anywhere on it is not a building yet, so its edges
## are not gaps in an outer wall.
func test_floor_with_no_wall_at_all_has_no_gap() -> void:
	_paint(Rect2i(8, 6, 2, 2))
	assert_bool(_grid.is_indoor(Vector2i(8, 6))).is_false()
	assert_array(EnclosureGaps.gap_edges(_grid)).is_empty()
	# One wall makes the patch a building with gaps on every other open edge.
	_apply(BuildEdit.place_wall(Vector2i(8, 6), BuildGrid.Side.NORTH))
	assert_int(EnclosureGaps.gap_edges(_grid).size()).is_equal(7)


## A grid edge with floor against it is open ground beyond, unless walled.
func test_floor_at_the_grid_border_counts_the_border_edge() -> void:
	var grid := BuildGrid.new(Vector2i(3, 3))
	_grid = grid
	_paint(Rect2i(0, 0, 1, 1))
	_apply(BuildEdit.place_wall(Vector2i(0, 0), BuildGrid.Side.EAST))
	_apply(BuildEdit.place_wall(Vector2i(0, 0), BuildGrid.Side.SOUTH))
	assert_array(EnclosureGaps.gap_edges(grid)).contains_exactly_in_any_order(
		[Vector3i(0, 0, BuildGrid.Side.NORTH), Vector3i(0, 0, BuildGrid.Side.WEST)]
	)
