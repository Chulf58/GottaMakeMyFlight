class_name TestBuildGridBatch
extends GdUnitTestSuite
## BuildGrid.apply_batch(): edits validate and apply one by one, in order, but
## the A* graph is relinked and graph_changed is emitted once, at the end.

var _emitted: Array = []


func _watch(grid: BuildGrid) -> void:
	_emitted.clear()
	grid.graph_changed.connect(func(cells: Array[Vector2i]) -> void: _emitted.append(cells))


func _paints(area: Rect2i) -> Array[BuildEdit]:
	var edits: Array[BuildEdit] = []
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	return edits


func test_a_batch_emits_graph_changed_once_with_every_relinked_cell() -> void:
	var grid := BuildGrid.new(Vector2i(12, 12))
	_watch(grid)
	var results := grid.apply_batch(_paints(Rect2i(2, 2, 3, 2)))
	assert_int(results.size()).is_equal(6)
	assert_int(_emitted.size()).is_equal(1)
	assert_array(_emitted[0]).contains(
		[Vector2i(2, 2), Vector2i(4, 3), Vector2i(1, 1), Vector2i(5, 4)]
	)


func test_later_edits_in_a_batch_see_the_earlier_ones() -> void:
	var grid := BuildGrid.new(Vector2i(12, 12))
	var cell := Vector2i(3, 3)
	var edits: Array[BuildEdit] = [
		BuildEdit.remove_floor(cell),
		BuildEdit.paint_floor(cell, 1, 1),
		BuildEdit.remove_floor(cell),
	]
	var results := grid.apply_batch(edits)
	assert_int(results[0].reason).is_equal(BuildResult.Reason.NO_FLOOR)
	assert_bool(results[1].ok).is_true()
	assert_bool(results[2].ok).is_true()
	assert_int(grid.floor_at(cell)).is_equal(BuildGrid.FLOOR_NONE)


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
	batched.apply_batch(edits)
	for y in range(1, 9):
		for x in range(1, 13):
			var to := Vector2i(x, y)
			assert_array(batched.find_path(Vector2i(1, 1), to)).is_equal(
				single.find_path(Vector2i(1, 1), to)
			)


func test_a_batch_that_changes_nothing_emits_nothing() -> void:
	var grid := BuildGrid.new(Vector2i(8, 8))
	_watch(grid)
	var edits: Array[BuildEdit] = [BuildEdit.remove_floor(Vector2i(3, 3))]
	var results := grid.apply_batch(edits)
	assert_bool(results[0].ok).is_false()
	assert_array(_emitted).is_empty()


func test_an_empty_batch_emits_nothing() -> void:
	var grid := BuildGrid.new(Vector2i(8, 8))
	_watch(grid)
	var edits: Array[BuildEdit] = []
	assert_array(grid.apply_batch(edits)).is_empty()
	assert_array(_emitted).is_empty()


func test_edits_after_a_batch_relink_on_their_own() -> void:
	var grid := BuildGrid.new(Vector2i(8, 8))
	grid.apply_batch(_paints(Rect2i(1, 1, 2, 2)))
	_watch(grid)
	grid.apply(BuildEdit.paint_floor(Vector2i(5, 5), 1, 1))
	assert_int(_emitted.size()).is_equal(1)


func test_back_to_back_batches_relink_only_their_own_cells() -> void:
	var grid := BuildGrid.new(Vector2i(20, 12))
	_watch(grid)
	grid.apply_batch(_paints(Rect2i(1, 1, 2, 2)))
	grid.apply_batch(_paints(Rect2i(15, 8, 2, 2)))
	assert_int(_emitted.size()).is_equal(2)
	assert_array(_emitted[0]).contains([Vector2i(1, 1), Vector2i(2, 2)])
	assert_array(_emitted[0]).not_contains([Vector2i(15, 8), Vector2i(16, 9)])
	assert_array(_emitted[1]).contains([Vector2i(15, 8), Vector2i(16, 9)])
	assert_array(_emitted[1]).not_contains([Vector2i(1, 1), Vector2i(2, 2)])
