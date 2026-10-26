class_name TestPlaytestEditSignals
extends GdUnitTestSuite
## BuildGrid's edit_applied and edit_refused, which the playtest hook logs:
## one signal per edit through apply_batch(), AreaDrag and BuildMode.apply_at(),
## and never two for the same refusal.

const ZONE := 1

var _applied: Array[BuildEdit] = []
var _refused: Array[BuildResult.Reason] = []
var _graph_changes := 0


func before_test() -> void:
	_applied.clear()
	_refused.clear()
	_graph_changes = 0


func _watch(grid: BuildGrid) -> void:
	grid.edit_applied.connect(func(edit: BuildEdit, _r: BuildResult) -> void: _applied.append(edit))
	grid.edit_refused.connect(
		func(_e: BuildEdit, result: BuildResult) -> void: _refused.append(result.reason)
	)
	grid.graph_changed.connect(func(_cells: Array[Vector2i]) -> void: _graph_changes += 1)


func _floored(size: Vector2i, area: Rect2i) -> BuildGrid:
	var grid := BuildGrid.new(size)
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			grid.apply(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, ZONE))
	return grid


func test_apply_batch_signals_each_edit_and_relinks_once() -> void:
	var grid := BuildGrid.new(Vector2i(8, 8))
	_watch(grid)
	var edits: Array[BuildEdit] = [
		BuildEdit.paint_floor(Vector2i(1, 1), BuildGrid.FLOOR_TILE, ZONE),
		BuildEdit.remove_floor(Vector2i(5, 5)),
		BuildEdit.paint_floor(Vector2i(2, 1), BuildGrid.FLOOR_TILE, ZONE),
	]
	grid.apply_batch(edits)
	assert_int(_applied.size()).is_equal(2)
	assert_that(_applied[1].cell).is_equal(Vector2i(2, 1))
	assert_array(_refused).is_equal([BuildResult.Reason.NO_FLOOR])
	assert_int(_graph_changes).is_equal(1)


func test_a_rectangle_cell_refused_beyond_a_door_is_signalled_once() -> void:
	var grid := _floored(Vector2i(10, 10), Rect2i(5, 5, 1, 2))
	grid.apply(BuildEdit.place_object(&"entrance_door", Vector2i(5, 5), 0))
	_watch(grid)
	var outcome := AreaDrag.fill_floor(grid, Rect2i(4, 3, 3, 3), ZONE)
	assert_int(outcome.skipped).is_equal(1)
	assert_array(_refused).is_equal([BuildResult.Reason.DOOR_NOT_ON_EDGE])
	assert_int(_applied.size()).is_equal(outcome.placed)


func test_a_rectangle_cell_the_grid_refuses_is_signalled_once() -> void:
	var grid := _floored(Vector2i(12, 12), Rect2i(2, 2, 8, 8))
	grid.apply(BuildEdit.place_object(&"checkin_desk", Vector2i(3, 3), 0))
	_watch(grid)
	var outcome := AreaDrag.clear(grid, Rect2i(3, 4, 2, 1))
	assert_int(outcome.skipped).is_equal(1)
	assert_array(_refused).is_equal([BuildResult.Reason.INTERACTION_RESERVED])


func test_a_click_the_rules_refuse_is_signalled_once() -> void:
	var mode: BuildMode = auto_free(BuildMode.new())
	mode.grid_size = Vector2i(8, 8)
	add_child(mode)
	_watch(mode.grid)
	mode.set_tool(BuildMode.Tool.DESK)
	var result := mode.apply_at(mode.grid.cell_to_world(Vector2i(3, 3)))
	assert_bool(result.ok).is_false()
	assert_array(_refused).is_equal([BuildResult.Reason.NO_FLOOR])
	assert_int(_applied.size()).is_equal(0)


func test_a_one_cell_rectangle_the_rules_refuse_is_signalled_once() -> void:
	var mode: BuildMode = auto_free(BuildMode.new())
	mode.grid_size = Vector2i(10, 10)
	add_child(mode)
	var grid := mode.grid
	for cell in [Vector2i(5, 5), Vector2i(5, 6)]:
		grid.apply(BuildEdit.paint_floor(cell, BuildGrid.FLOOR_TILE, ZONE))
	grid.apply(BuildEdit.place_object(&"entrance_door", Vector2i(5, 5), 0))
	_watch(grid)
	mode.set_tool(BuildMode.Tool.FLOOR)
	var beyond := grid.cell_to_world(Vector2i(5, 4))
	mode.begin_area(beyond)
	assert_object(mode.finish_area()).is_null()
	assert_array(_refused).is_equal([BuildResult.Reason.DOOR_NOT_ON_EDGE])
