class_name TestAreaDragFillRefusal
extends GdUnitTestSuite
## A Fill rectangle with a cell the door rules refuse: the refusal waits in the
## grid's hold queue behind the signals an outer caller already queued there.

const ZONE := 1

var _grid: BuildGrid
var _events: Array[String] = []


func before_test() -> void:
	_events.clear()
	_grid = BuildGrid.new(Vector2i(20, 20))
	for cell in [Vector2i(5, 5), Vector2i(5, 6)]:
		(
			assert_bool(_grid.apply(BuildEdit.paint_floor(cell, BuildGrid.FLOOR_TILE, ZONE)).ok)
			. is_true()
		)
	(
		assert_bool(_grid.apply(BuildEdit.place_object(&"entrance_door", Vector2i(5, 5), 0)).ok)
		. is_true()
	)
	_grid.edit_applied.connect(
		func(_e: BuildEdit, _r: BuildResult) -> void: _events.append("applied")
	)
	_grid.edit_refused.connect(
		func(_e: BuildEdit, _r: BuildResult) -> void: _events.append("refused")
	)


func test_a_rule_refused_cell_publishes_after_the_edits_queued_before_it() -> void:
	_grid.hold_signals()
	(
		assert_bool(_grid.apply(BuildEdit.paint_floor(Vector2i(9, 9), BuildGrid.FLOOR_TILE, 2)).ok)
		. is_true()
	)
	# The cell beyond the door is refused by the door rules; its neighbours are laid.
	var outcome := AreaDrag.fill_floor(_grid, Rect2i(4, 3, 3, 3), ZONE)
	print("fill under hold: skipped=%d events held=%s" % [outcome.skipped, _events])
	assert_int(outcome.skipped).is_equal(1)
	assert_array(_events).is_empty()
	_grid.release_signals()
	# Published in the order they happened: the queued edit, the refusal, the batch.
	assert_array(_events.slice(0, 2)).is_equal(["applied", "refused"])
	assert_int(_events.count("refused")).is_equal(1)
	assert_int(_events.count("applied")).is_greater(1)
