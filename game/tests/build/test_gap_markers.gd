class_name TestGapMarkers
extends GdUnitTestSuite
## Gap markers (GapMarkers): a strip on every open edge of the outer wall and
## one sign per run of them (EnclosureGaps), redrawn when the grid changes.
## The subject is a closed 4x3 box of floor at x 2-5, y 2-4 on a 12x10 grid.

const BOX := Rect2i(2, 2, 4, 3)

var _grid: BuildGrid
var _markers: GapMarkers


func before_test() -> void:
	_grid = BuildGrid.new(Vector2i(12, 10))
	var edits: Array[BuildEdit] = []
	for y in range(BOX.position.y, BOX.end.y):
		for x in range(BOX.position.x, BOX.end.x):
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	for result in _grid.apply_batch(edits):
		assert_bool(result.ok).is_true()
	EnclosureKit.close_floor(_grid)
	_markers = auto_free(GapMarkers.new())
	add_child(_markers)
	_markers.bind(_grid)


func _remove(cell: Vector2i, side: int) -> void:
	assert_bool(_grid.apply(BuildEdit.remove_wall(cell, side)).ok).is_true()


func test_a_closed_box_shows_no_marker() -> void:
	assert_int(_markers.strip_count()).is_equal(0)
	assert_int(_markers.sign_count()).is_equal(0)


func test_open_edges_get_a_strip_each_and_a_sign_per_run() -> void:
	for x in [2, 3, 4]:
		_remove(Vector2i(x, 4), BuildGrid.Side.SOUTH)
	_remove(Vector2i(5, 2), BuildGrid.Side.EAST)
	assert_int(_markers.strip_count()).is_equal(4)
	assert_int(_markers.sign_count()).is_equal(2)
	# The south run's sign stands over the middle of its three edges.
	var at := _markers.sign_positions()
	var south := _grid.origin + Vector3(3.5, GapMarkers.SIGN_LIFT_M, 5.0)
	assert_bool(at.any(func(p: Vector3) -> bool: return p.is_equal_approx(south))).is_true()


func test_closing_the_gap_clears_the_markers() -> void:
	_remove(Vector2i(5, 2), BuildGrid.Side.EAST)
	assert_int(_markers.sign_count()).is_equal(1)
	assert_bool(_grid.apply(BuildEdit.place_wall(Vector2i(5, 2), BuildGrid.Side.EAST)).ok).is_true()
	assert_int(_markers.strip_count()).is_equal(0)
	assert_int(_markers.sign_count()).is_equal(0)
