class_name TestBuildModeRemoveTwoPass
extends GdUnitTestSuite
## A Remove rectangle clears in two drags (decision
## remove-rectangle-clears-objects-first-then-floor-and-walls-o): over a
## rectangle that holds objects it takes only the objects; over one with none
## left it takes the floor in it and the walls inside it or on its edge. Each
## drag is one undo step and refunds like any piece.

const NORTH := BuildGrid.Side.NORTH
const WEST := BuildGrid.Side.WEST
## The dragged rectangle: x 3..6, y 3..6.
const AREA := Rect2i(3, 3, 4, 4)
## A wall inside the rectangle, one on its top edge and one beside it.
const INNER_WALL := Vector2i(4, 5)
const EDGE_WALL := Vector2i(5, 3)
const OUTER_WALL := Vector2i(1, 1)

var _mode: BuildMode
var _finances: Finances


## A 12x12 grid with floor on x 1..8, y 1..8, a check-in desk on (3,4) and
## (4,4) with its front on (3,5), and three plain walls.
func before_test() -> void:
	_finances = Finances.new()
	add_child(_finances)
	_mode = BuildMode.new()
	_mode.grid_size = Vector2i(12, 12)
	_mode.finances = _finances
	add_child(_mode)
	_mode.set_tool(BuildMode.Tool.FLOOR)
	_drag(Rect2i(1, 1, 8, 8))
	_mode.set_tool(BuildMode.Tool.DESK)
	assert_bool(_mode.apply_at(_at(Vector2i(3, 4))).ok).is_true()
	_mode.set_tool(BuildMode.Tool.WALL)
	for cell in [INNER_WALL, EDGE_WALL, OUTER_WALL]:
		assert_bool(_mode.apply_at(_near_edge(cell, NORTH)).ok).is_true()
	_mode.set_tool(BuildMode.Tool.REMOVE)


func after_test() -> void:
	_mode.free()
	_finances.free()


func _at(cell: Vector2i) -> Vector3:
	return _mode.grid.cell_to_world(cell)


func _near_edge(cell: Vector2i, side: int) -> Vector3:
	var step := BuildGrid.SIDE_STEP[side]
	return _at(cell) + Vector3(step.x * 0.45, 0.0, step.y * 0.45)


func _drag(area: Rect2i) -> AreaDrag.Outcome:
	_mode.begin_area(_at(area.position))
	_mode.move_area(_at(area.end - Vector2i.ONE))
	return _mode.finish_area()


func _floor_cells_in(area: Rect2i) -> int:
	var count := 0
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			if _mode.grid.floor_at(Vector2i(x, y)) != BuildGrid.FLOOR_NONE:
				count += 1
	return count


func _balance() -> int:
	return _finances.wallet.balance


func test_a_rectangle_holding_an_object_removes_only_the_objects() -> void:
	var outcome := _drag(AREA)
	assert_int(outcome.placed).is_equal(1)
	assert_array(_mode.grid.object_ids()).is_empty()
	assert_int(_floor_cells_in(AREA)).is_equal(16)
	assert_bool(_mode.grid.has_wall(INNER_WALL, NORTH)).is_true()
	assert_bool(_mode.grid.has_wall(EDGE_WALL, NORTH)).is_true()
	assert_bool(_mode.grid.has_wall(OUTER_WALL, NORTH)).is_true()


func test_a_rectangle_with_no_object_removes_the_floor_and_the_inner_and_edge_walls() -> void:
	_drag(AREA)
	var outcome := _drag(AREA)
	# 16 floor cells and the inner and the edge wall.
	assert_int(outcome.placed).is_equal(18)
	assert_int(_floor_cells_in(AREA)).is_equal(0)
	assert_bool(_mode.grid.has_wall(INNER_WALL, NORTH)).is_false()
	assert_bool(_mode.grid.has_wall(EDGE_WALL, NORTH)).is_false()
	# Floor and a wall outside the rectangle are left alone.
	assert_bool(_mode.grid.has_wall(OUTER_WALL, NORTH)).is_true()
	assert_int(_mode.grid.floor_at(Vector2i(2, 3))).is_equal(BuildGrid.FLOOR_TILE)
	assert_int(_mode.grid.floor_at(Vector2i(7, 7))).is_equal(BuildGrid.FLOOR_TILE)


func test_an_object_outside_the_rectangle_does_not_stop_the_second_pass() -> void:
	_mode.set_tool(BuildMode.Tool.SEATS)
	assert_bool(_mode.apply_at(_at(Vector2i(1, 8))).ok).is_true()
	_mode.set_tool(BuildMode.Tool.REMOVE)
	var outcome := _drag(AREA)
	assert_int(outcome.placed).is_equal(1)
	_drag(AREA)
	assert_int(_floor_cells_in(AREA)).is_equal(0)
	assert_int(_mode.grid.object_ids().size()).is_equal(1)


func test_each_drag_is_one_undo_step() -> void:
	var before := _balance()
	_drag(AREA)
	_drag(AREA)
	assert_bool(_mode.undo().ok).is_true()
	assert_int(_floor_cells_in(AREA)).is_equal(16)
	assert_bool(_mode.grid.has_wall(INNER_WALL, NORTH)).is_true()
	assert_bool(_mode.grid.has_wall(EDGE_WALL, NORTH)).is_true()
	assert_array(_mode.grid.object_ids()).is_empty()
	assert_bool(_mode.undo().ok).is_true()
	assert_int(_mode.grid.object_ids().size()).is_equal(1)
	assert_int(_balance()).is_equal(before)


func test_the_drags_refund_at_the_saved_prices() -> void:
	var start := _balance()
	_drag(AREA)
	var desk_refund := PriceTable.refund_of(PriceTable.price_of_object(&"checkin_desk"))
	assert_int(_balance()).is_equal(start + desk_refund)
	var second := _balance()
	_drag(AREA)
	var wall_refund := PriceTable.refund_of(PriceTable.price_of_wall(BuildGrid.WallKind.PLAIN))
	var expected := 16 * PriceTable.refund_of(PriceTable.FLOOR_PRICE) + 2 * wall_refund
	assert_int(_balance()).is_equal(second + expected)
	assert_str(_mode.status_text()).is_equal("Removed 18, refund %d" % expected)


func test_a_rectangle_with_nothing_in_it_removes_nothing() -> void:
	var outcome := _drag(Rect2i(9, 9, 2, 2))
	assert_int(outcome.placed).is_equal(0)
	assert_str(_mode.status_text()).is_equal("Nothing to remove")
