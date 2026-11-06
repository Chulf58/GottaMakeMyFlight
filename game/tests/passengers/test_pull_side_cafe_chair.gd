class_name TestPullSideCafeChair
extends GdUnitTestSuite
## PullSide's walking-pull furniture guard sees a cafe chair (board 2fcb8475
## part 1). A cafe_table is one 3x1 piece, a chair in each outer cell; its
## kit piece is one mesh, so PullSide.piece_boxes() gives one box over both
## chairs and the table. A guest faces east with its pulled roller's settled
## right footprint (PullSide.footprint(0, false)) laid over a chair's cell:
## blocked() with furniture finds the piece there, without furniture (no wall)
## it does not, and with no table on the grid it does not either.

const ANCHOR := Vector2i(10, 10)

var _grid: BuildGrid
var _empty: BuildGrid


func before() -> void:
	_grid = BuildGrid.new()
	_empty = BuildGrid.new()
	var edits: Array[BuildEdit] = []
	for x in range(ANCHOR.x - 3, ANCHOR.x + 6):
		for y in range(ANCHOR.y - 3, ANCHOR.y + 4):
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	edits.append(BuildEdit.place_object(&"cafe_table", ANCHOR, 0))
	for result in _grid.apply_batch(edits):
		assert_bool(result.ok).override_failure_message(result.reason_text()).is_true()


func after() -> void:
	_grid = null
	_empty = null


## The guest's pose facing east that puts the middle of `box` (its frame) on
## the middle of `cell` at floor height.
func _pose_over(box: AABB, cell: Vector2i) -> Transform3D:
	var basis := Basis(Vector3.UP, PI / 2.0)
	var under := _grid.cell_to_world(cell)
	var middle := basis * box.get_center()
	return Transform3D(basis, Vector3(under.x - middle.x, under.y, under.z - middle.z))


func test_the_table_has_a_chair_in_each_outer_cell() -> void:
	var id := _grid.object_at(ANCHOR)
	assert_int(id).is_not_equal(0)
	assert_int(_grid.object_at(ANCHOR + Vector2i(2, 0))).is_equal(id)
	var seats: Array = BuildCatalog.get_def(&"cafe_table").seats
	assert_int(seats.size()).is_equal(2)
	assert_vector(seats[0]["cell"] as Vector2i).is_equal(Vector2i(0, 0))
	assert_vector(seats[1]["cell"] as Vector2i).is_equal(Vector2i(2, 0))


func test_the_settled_right_footprint_over_a_chair_is_blocked() -> void:
	var box := PullSide.footprint(0, false)
	for chair: Vector2i in [ANCHOR, ANCHOR + Vector2i(2, 0)]:
		var pose := _pose_over(box, chair)
		var message := "chair %s, guest at %s" % [chair, pose.origin]
		(
			assert_bool(PullSide.blocked(_grid, [pose], box, true))
			. override_failure_message(message)
			. is_true()
		)
		# Controls: no wall there, and no piece there on an empty grid.
		assert_bool(PullSide.blocked(_grid, [pose], box, false)).is_false()
		assert_bool(PullSide.blocked(_empty, [pose], box, true)).is_false()
