class_name TestBuildModeGridOrigin
extends GdUnitTestSuite
## BuildMode, BuildView and the door tools on the shell grid: 66x30 at
## (-33.5, 0.3, -94.8). Picking meets the floor at y 0.3, the view draws in
## that frame, and an entrance placed by a click paths into the room.

const SHELL_SIZE := Vector2i(66, 30)
const SHELL_ORIGIN := Vector3(-33.5, 0.3, -94.8)
const FLOOR_Y := 0.3
const ROOM_MIN := Vector2i(4, 2)
const ROOM_MAX := Vector2i(9, 6)

var _mode: BuildMode


## Floor on x 4..9, y 2..6 of the shell grid, painted by clicks.
func before_test() -> void:
	_mode = BuildMode.new()
	_mode.grid_size = SHELL_SIZE
	_mode.grid_centred = false
	_mode.grid_origin = SHELL_ORIGIN
	add_child(_mode)
	_mode.set_tool(BuildMode.Tool.FLOOR)
	for y in range(ROOM_MIN.y, ROOM_MAX.y + 1):
		for x in range(ROOM_MIN.x, ROOM_MAX.x + 1):
			_mode.apply_at(_mode.grid.cell_to_world(Vector2i(x, y)))


func after_test() -> void:
	_mode.free()


func _view() -> BuildView:
	return _mode.get_node("BuildView") as BuildView


func test_the_mode_builds_its_grid_at_the_set_origin() -> void:
	assert_that(_mode.grid.size).is_equal(SHELL_SIZE)
	assert_that(_mode.grid.origin).is_equal(SHELL_ORIGIN)
	assert_int(_mode.grid.floor_at(ROOM_MAX)).is_equal(BuildGrid.FLOOR_TILE)


func test_a_default_mode_stays_centred_at_floor_height_zero() -> void:
	var plain := auto_free(BuildMode.new()) as BuildMode
	plain.grid_size = Vector2i(10, 10)
	add_child(plain)
	assert_that(plain.grid.origin).is_equal(Vector3(-5, 0, -5))


## A ray falling at 45 degrees toward +x crosses y 0.3 at x fraction 0.9 of
## cell (30, 20) and would reach y 0 in cell (31, 20).
func test_picking_meets_the_floor_at_the_grid_height() -> void:
	var grid := _mode.grid
	var target := SHELL_ORIGIN + Vector3(30.9, 0.0, 20.5)
	var direction := Vector3(1, -1, 0).normalized()
	var from := target + Vector3(-10, 10, 0)
	var hit: Variant = _mode.grid_point(from, direction)
	assert_that(hit).is_not_null()
	assert_float((hit as Vector3).y).is_equal_approx(FLOOR_Y, 0.0001)
	assert_that(grid.world_to_cell(hit)).is_equal(Vector2i(30, 20))
	var at_zero: Variant = BuildMode.ground_point(from, direction)
	assert_that(grid.world_to_cell(at_zero)).is_equal(Vector2i(31, 20))
	assert_bool(_mode.apply_at(hit).ok).is_true()
	assert_int(grid.floor_at(Vector2i(30, 20))).is_equal(BuildGrid.FLOOR_TILE)
	assert_int(grid.floor_at(Vector2i(31, 20))).is_equal(BuildGrid.FLOOR_NONE)


func test_the_view_draws_in_the_grid_frame() -> void:
	var grid := _mode.grid
	var area := _view().get_node("BuildArea") as MeshInstance3D
	var area_at := SHELL_ORIGIN + Vector3(33, BuildView.AREA_Y, 15)
	assert_vector(area.position).is_equal_approx(area_at, Vector3.ONE * 0.0001)
	var floors := _view().piece_transforms("floor_tile")
	assert_int(floors.size()).is_equal(30)
	for at in floors:
		assert_float(at.origin.y).is_equal_approx(FLOOR_Y, 0.0001)
		assert_int(grid.floor_at(grid.world_to_cell(at.origin))).is_equal(BuildGrid.FLOOR_TILE)
	_mode.set_tool(BuildMode.Tool.WALL)
	var north_of := grid.cell_to_world(Vector2i(6, 2)) + Vector3(0, 0, -0.45)
	assert_bool(_mode.apply_at(north_of).ok).is_true()
	var walls := _view().piece_transforms("wall")
	assert_int(walls.size()).is_greater(0)
	for at in walls:
		assert_float(at.origin.y).is_equal_approx(FLOOR_Y, 0.0001)
		assert_float(at.origin.z).is_equal_approx(SHELL_ORIGIN.z + 2.0, 0.0001)
	var posts := _view().piece_transforms("wall_post")
	assert_int(posts.size()).is_greater(0)
	for at in posts:
		assert_float(at.origin.y).is_equal_approx(FLOOR_Y, 0.0001)


func test_an_entrance_clicked_on_the_edge_paths_into_the_room() -> void:
	var grid := _mode.grid
	var cell := Vector2i(6, ROOM_MIN.y)
	_mode.set_tool(BuildMode.Tool.ENTRANCE)
	var point := grid.cell_to_world(cell) + Vector3(0.1, 0, -0.45)
	assert_bool(_mode.apply_at(point).ok).is_true()
	var door := grid.object_at(cell)
	assert_int(door).is_greater(0)
	assert_int(grid.get_object(door)["facing"]).is_equal(0)
	var layout := TerminalLayout.new()
	layout.rebuild(grid)
	assert_bool(layout.is_exit_open(grid, door)).is_true()
	var start := layout.door_cell(grid, door)
	assert_bool(grid.in_bounds(start)).is_true()
	var path := grid.find_path(start, ROOM_MAX)
	assert_array(path).is_not_empty()
	assert_that(path[path.size() - 1]).is_equal(ROOM_MAX)
