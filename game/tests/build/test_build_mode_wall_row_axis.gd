class_name TestBuildModeWallRowAxis
extends GdUnitTestSuite
## BuildMode's Wall tool: the drag axis, not the pressed edge, decides whether
## the row is a vertical or a horizontal wall (decision
## wall-and-glass-drag-a-row-placed-on-release-one-undo-remove-picks-walls-by-sight).

const NORTH := BuildGrid.Side.NORTH
const WEST := BuildGrid.Side.WEST
const PORT_SIZE := Vector2i(1280, 720)

var _mode: BuildMode
var _finances: Finances
var _port: SubViewport


func before_test() -> void:
	_finances = Finances.new()
	add_child(_finances)
	_port = SubViewport.new()
	_port.size = PORT_SIZE
	add_child(_port)
	_mode = BuildMode.new()
	_mode.grid_size = Vector2i(12, 12)
	_mode.grid_centred = false
	_mode.finances = _finances
	_port.add_child(_mode)
	_mode.set_tool(BuildMode.Tool.WALL)


func after_test() -> void:
	_port.free()
	_finances.free()


func _at(cell: Vector2i) -> Vector3:
	return _mode.grid.cell_to_world(cell)


## A ground point 0.45 m from the middle of `cell` toward `side`.
func _near_edge(cell: Vector2i, side: int) -> Vector3:
	var step := BuildGrid.SIDE_STEP[side]
	return _at(cell) + Vector3(step.x * 0.45, 0.0, step.y * 0.45)


func _drag(from: Vector2i, to: Vector2i, side := NORTH) -> void:
	_mode.begin_row(_near_edge(from, side))
	_mode.move_row(_near_edge(to, side))


func _walls_on(row: Array[Vector2i], side := NORTH) -> int:
	var count := 0
	for cell in row:
		if _mode.grid.has_wall(cell, side):
			count += 1
	return count


func _cells_x(from: int, to: int, y: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for x in range(from, to + 1):
		cells.append(Vector2i(x, y))
	return cells


func _cells_z(x: int, from: int, to: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in range(from, to + 1):
		cells.append(Vector2i(x, y))
	return cells


func test_a_horizontal_press_dragged_up_the_grid_lays_a_vertical_wall() -> void:
	_drag(Vector2i(4, 2), Vector2i(5, 7))
	var outcome := _mode.finish_row()
	assert_int(outcome.placed).is_equal(6)
	assert_int(_walls_on(_cells_z(4, 2, 7), WEST)).is_equal(6)
	assert_int(_walls_on(_cells_z(4, 2, 7))).is_equal(0)
	assert_int(_mode.undo_history().size()).is_equal(1)


func test_a_vertical_press_dragged_across_the_grid_lays_a_horizontal_wall() -> void:
	_drag(Vector2i(2, 4), Vector2i(7, 5), WEST)
	var outcome := _mode.finish_row()
	assert_int(outcome.placed).is_equal(6)
	assert_int(_walls_on(_cells_x(2, 7, 4))).is_equal(6)
	assert_int(_walls_on(_cells_x(2, 7, 4), WEST)).is_equal(0)
	assert_bool(_mode.undo().ok).is_true()
	assert_int(_walls_on(_cells_x(2, 7, 4))).is_equal(0)
