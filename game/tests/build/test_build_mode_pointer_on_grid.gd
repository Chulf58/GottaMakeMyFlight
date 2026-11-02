class_name TestBuildModePointerOnGrid
extends GdUnitTestSuite
## pointer_on_grid() is true for a point anywhere over the grid, its far east and
## south edge lines included. The cell under a point is floor(), which puts a
## point exactly on the far edge line in a cell outside the grid.

var _mode: BuildMode


func before_test() -> void:
	_mode = BuildMode.new()
	_mode.grid_size = Vector2i(10, 8)
	add_child(_mode)
	_mode.set_tool(BuildMode.Tool.FLOOR)


func after_test() -> void:
	_mode.free()


func _on_grid_at(local: Vector2) -> bool:
	_mode._update_ghost(_mode.grid.origin + Vector3(local.x, 0.0, local.y))
	return _mode.pointer_on_grid()


func test_a_point_inside_the_grid_is_on_the_grid() -> void:
	assert_bool(_on_grid_at(Vector2(4.5, 3.5))).is_true()


func test_a_point_on_the_near_corner_is_on_the_grid() -> void:
	assert_bool(_on_grid_at(Vector2(0.0, 0.0))).is_true()


func test_a_point_on_the_far_east_edge_is_on_the_grid() -> void:
	assert_bool(_on_grid_at(Vector2(10.0, 3.5))).is_true()


func test_a_point_on_the_far_south_edge_is_on_the_grid() -> void:
	assert_bool(_on_grid_at(Vector2(4.5, 8.0))).is_true()


func test_a_point_on_the_far_corner_is_on_the_grid() -> void:
	assert_bool(_on_grid_at(Vector2(10.0, 8.0))).is_true()


func test_a_point_past_the_far_edge_is_off_the_grid() -> void:
	assert_bool(_on_grid_at(Vector2(10.05, 3.5))).is_false()
	assert_bool(_on_grid_at(Vector2(4.5, 8.05))).is_false()


func test_a_point_before_the_near_edge_is_off_the_grid() -> void:
	assert_bool(_on_grid_at(Vector2(-0.05, 3.5))).is_false()
	assert_bool(_on_grid_at(Vector2(4.5, -0.05))).is_false()
