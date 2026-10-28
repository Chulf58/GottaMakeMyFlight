class_name TestStartView
extends GdUnitTestSuite
## The area the start camera frames: what the player has built, else the
## starter terminal's floor in the shell.

const SHELL_PATH := "res://build/toon_terminal_shell.tres"

var _shell: ShellDefinition


func before() -> void:
	_shell = load(SHELL_PATH)


func _shell_grid() -> BuildGrid:
	return BuildGrid.new(_shell.grid_size, _shell.grid_origin)


func test_an_empty_shell_grid_frames_the_starter_terminal_floor() -> void:
	var grid := _shell_grid()
	var area := StartView.area_for(grid, _shell)
	# The reference terminal's floor, as ReferenceTerminal paints it.
	var low := Vector2i(1000, 1000)
	var high := Vector2i(-1000, -1000)
	for edit in ReferenceTerminal.edits(_shell):
		if edit.kind == BuildEdit.Kind.PAINT_FLOOR:
			low = low.min(edit.cell)
			high = high.max(edit.cell)
	assert_int(high.x - low.x).is_greater(0)
	assert_vector(area.position).is_equal_approx(
		Vector2(grid.origin.x + low.x, grid.origin.z + low.y), Vector2.ONE * 0.001
	)
	assert_vector(area.size).is_equal_approx(
		Vector2(high - low + Vector2i.ONE), Vector2.ONE * 0.001
	)


func test_the_starter_area_is_a_small_part_of_the_shell() -> void:
	var area := StartView.area_for(_shell_grid(), _shell)
	assert_float(area.size.x).is_less(_shell.grid_size.x * 0.5)
	assert_float(area.size.y).is_greater(area.size.x)


func test_a_built_grid_frames_what_is_built_not_the_starter_terminal() -> void:
	var grid := _shell_grid()
	for cell in [Vector2i(4, 5), Vector2i(8, 7)]:
		grid.apply(BuildEdit.paint_floor(cell, BuildGrid.FLOOR_TILE, 1))
	var area := StartView.area_for(grid, _shell)
	assert_vector(area.position).is_equal_approx(
		Vector2(grid.origin.x + 4.0, grid.origin.z + 5.0), Vector2.ONE * 0.001
	)
	assert_vector(area.size).is_equal_approx(Vector2(5.0, 3.0), Vector2.ONE * 0.001)


func test_an_object_on_bare_ground_counts_as_built() -> void:
	var grid := BuildGrid.new(Vector2i(10, 10))
	grid.apply(BuildEdit.paint_floor(Vector2i(2, 2), BuildGrid.FLOOR_TILE, 1))
	grid.apply(BuildEdit.place_object(&"checkin_desk", Vector2i(2, 2), 0))
	var area := StartView.area_for(grid, null)
	assert_vector(area.position).is_equal_approx(
		Vector2(grid.origin.x + 2.0, grid.origin.z + 2.0), Vector2.ONE * 0.001
	)
	assert_float(area.size.x).is_greater_equal(1.0)


func test_without_a_shell_the_default_layout_floor_is_framed_on_a_big_grid() -> void:
	var grid := BuildGrid.new()
	var area := StartView.area_for(grid, null)
	var low := ReferenceTerminal.FLOOR_MIN
	var high := ReferenceTerminal.FLOOR_MAX
	assert_vector(area.position).is_equal_approx(
		Vector2(grid.origin.x + low.x, grid.origin.z + low.y), Vector2.ONE * 0.001
	)
	assert_vector(area.size).is_equal_approx(
		Vector2(high - low + Vector2i.ONE), Vector2.ONE * 0.001
	)


func test_with_nothing_built_and_a_grid_too_small_for_the_starter_the_whole_grid_is_framed(
) -> void:
	var grid := BuildGrid.new(Vector2i(12, 8))
	var area := StartView.area_for(grid, null)
	assert_vector(area.size).is_equal_approx(Vector2(12.0, 8.0), Vector2.ONE * 0.001)
	assert_vector(area.position).is_equal_approx(
		Vector2(grid.origin.x, grid.origin.z), Vector2.ONE * 0.001
	)
