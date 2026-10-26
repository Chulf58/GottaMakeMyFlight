class_name TestBuildGridBatch
extends GdUnitTestSuite
## BuildGrid's batch: edits validate and apply one by one, in order, but the
## A* graph is relinked and graph_changed is emitted once, at the end.

var _emitted: Array = []


func _watch(grid: BuildGrid) -> void:
	_emitted.clear()
	grid.graph_changed.connect(func(cells: Array[Vector2i]) -> void: _emitted.append(cells))


func _paint(grid: BuildGrid, area: Rect2i) -> void:
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			grid.apply(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))


func test_a_batch_emits_graph_changed_once_with_every_relinked_cell() -> void:
	var grid := BuildGrid.new(Vector2i(12, 12))
	_watch(grid)
	grid.begin_batch()
	_paint(grid, Rect2i(2, 2, 3, 2))
	assert_array(_emitted).is_empty()
	var relinked := grid.end_batch()
	assert_int(_emitted.size()).is_equal(1)
	assert_array(_emitted[0]).contains_exactly_in_any_order(relinked)
	assert_array(relinked).contains(
		[Vector2i(2, 2), Vector2i(4, 3), Vector2i(1, 1), Vector2i(5, 4)]
	)


func test_later_edits_in_a_batch_see_the_earlier_ones() -> void:
	var grid := BuildGrid.new(Vector2i(12, 12))
	grid.begin_batch()
	assert_int(grid.apply(BuildEdit.remove_floor(Vector2i(3, 3))).reason).is_equal(
		BuildResult.Reason.NO_FLOOR
	)
	assert_bool(grid.apply(BuildEdit.paint_floor(Vector2i(3, 3), 1, 1)).ok).is_true()
	assert_bool(grid.apply(BuildEdit.remove_floor(Vector2i(3, 3))).ok).is_true()
	grid.end_batch()
	assert_int(grid.floor_at(Vector2i(3, 3))).is_equal(BuildGrid.FLOOR_NONE)


func test_a_batch_leaves_the_same_routes_as_edits_one_at_a_time() -> void:
	var single := BuildGrid.new(Vector2i(14, 10))
	var batched := BuildGrid.new(Vector2i(14, 10))
	var edits: Array[BuildEdit] = []
	for y in range(1, 9):
		for x in range(1, 13):
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), 1, 1))
	edits.append(BuildEdit.place_wall(Vector2i(6, 4), BuildGrid.Side.NORTH))
	edits.append(BuildEdit.place_object(&"checkin_desk", Vector2i(3, 3), 0))
	edits.append(BuildEdit.remove_floor(Vector2i(10, 6)))
	for edit in edits:
		single.apply(edit)
	batched.begin_batch()
	for edit in edits:
		batched.apply(edit)
	batched.end_batch()
	for y in range(1, 9):
		for x in range(1, 13):
			var to := Vector2i(x, y)
			assert_array(batched.find_path(Vector2i(1, 1), to)).is_equal(
				single.find_path(Vector2i(1, 1), to)
			)


func test_a_batch_that_changes_nothing_emits_nothing() -> void:
	var grid := BuildGrid.new(Vector2i(8, 8))
	_watch(grid)
	grid.begin_batch()
	grid.apply(BuildEdit.remove_floor(Vector2i(3, 3)))
	assert_array(grid.end_batch()).is_empty()
	assert_array(_emitted).is_empty()


func test_edits_after_a_batch_relink_on_their_own() -> void:
	var grid := BuildGrid.new(Vector2i(8, 8))
	grid.begin_batch()
	grid.end_batch()
	_watch(grid)
	grid.apply(BuildEdit.paint_floor(Vector2i(3, 3), 1, 1))
	assert_int(_emitted.size()).is_equal(1)
