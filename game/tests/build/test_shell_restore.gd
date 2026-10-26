class_name TestShellRestore
extends GdUnitTestSuite
## Restoring a saved build grid into BuildMode with the Toon terminal shell:
## a snapshot of the shell's own frame with its doors on the Toon doors loads;
## one from another frame (every save from before the shell, which loads
## centred 64x64 on the forecourt) or with a door off the Toon doors is
## refused and leaves the grid as it was.

const SHELL := preload("res://build/toon_terminal_shell.tres")
const LANDSIDE_B := Vector2i(16, 29)
const GATE_C := Vector2i(16, 0)

var _mode: BuildMode


func before_test() -> void:
	_mode = BuildMode.new()
	_mode.shell = SHELL
	add_child(_mode)


func after_test() -> void:
	_mode.free()


## A shell-frame grid with a floor column on x 15..17 and the given doors.
func _shell_grid(doors: Array) -> BuildGrid:
	var grid := BuildGrid.new(SHELL.grid_size, SHELL.grid_origin)
	for y in SHELL.grid_size.y:
		for x in range(15, 18):
			grid.apply(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	for door in doors:
		assert_bool(grid.apply(BuildEdit.place_object(door[0], door[1], door[2])).ok).is_true()
	return grid


func _floor_count() -> int:
	var count := 0
	for y in _mode.grid.size.y:
		for x in _mode.grid.size.x:
			count += int(_mode.grid.floor_at(Vector2i(x, y)) != BuildGrid.FLOOR_NONE)
	return count


func test_a_shell_snapshot_with_toon_doors_loads() -> void:
	var saved := (
		_shell_grid([[&"entrance_door", LANDSIDE_B, 2], [&"exit_door", GATE_C, 0]]).to_snapshot()
	)
	var loaded := JSON.parse_string(JSON.stringify(saved)) as Dictionary
	assert_bool(_mode.load_snapshot(loaded)).is_true()
	assert_int(_floor_count()).is_equal(3 * 30)
	assert_int(_mode.grid.object_ids().size()).is_equal(2)
	assert_vector(_mode.grid.origin).is_equal(SHELL.grid_origin)


func test_a_save_from_before_the_shell_is_refused() -> void:
	var old := BuildGrid.new()
	old.apply(BuildEdit.paint_floor(Vector2i(3, 3), BuildGrid.FLOOR_TILE, 1))
	var saved := old.to_snapshot()
	saved.erase("origin")
	assert_bool(_mode.load_snapshot(saved)).is_false()
	assert_vector(_mode.grid.size).is_equal(SHELL.grid_size)
	assert_int(_floor_count()).is_equal(0)
	assert_str(SHELL.snapshot_problem(saved)).contains("frame")


func test_the_shell_size_at_another_origin_is_refused() -> void:
	var moved := BuildGrid.new(SHELL.grid_size, SHELL.grid_origin + Vector3(1.0, 0.0, 0.0))
	moved.apply(BuildEdit.paint_floor(Vector2i(3, 3), BuildGrid.FLOOR_TILE, 1))
	assert_bool(_mode.load_snapshot(moved.to_snapshot())).is_false()
	assert_int(_floor_count()).is_equal(0)


func test_a_door_off_the_toon_doors_is_refused() -> void:
	var saved := _shell_grid([[&"entrance_door", Vector2i(15, 29), 2]]).to_snapshot()
	assert_bool(_mode.load_snapshot(saved)).is_false()
	assert_str(SHELL.snapshot_problem(saved)).contains("Toon door")
	assert_int(_floor_count()).is_equal(0)


func test_an_exit_at_a_landside_door_is_refused() -> void:
	var saved := _shell_grid([[&"exit_door", LANDSIDE_B, 2]]).to_snapshot()
	assert_bool(_mode.load_snapshot(saved)).is_false()
	assert_int(_floor_count()).is_equal(0)


func test_a_toon_door_with_a_wall_on_its_way_out_is_refused() -> void:
	var grid := _shell_grid([[&"exit_door", GATE_C, 0]])
	assert_bool(grid.apply(BuildEdit.place_wall(GATE_C, BuildGrid.Side.NORTH)).ok).is_true()
	assert_bool(_mode.load_snapshot(grid.to_snapshot())).is_false()
	assert_int(_floor_count()).is_equal(0)


func test_a_malformed_snapshot_is_refused_before_anything_is_read() -> void:
	assert_str(SHELL.snapshot_problem({"width": 66})).is_not_empty()
	assert_bool(_mode.load_snapshot({"width": 66})).is_false()


func test_a_refused_restore_leaves_a_built_grid_unchanged() -> void:
	var built := _shell_grid([[&"entrance_door", LANDSIDE_B, 2], [&"exit_door", GATE_C, 0]])
	assert_bool(_mode.load_snapshot(built.to_snapshot())).is_true()
	var before := JSON.stringify(_mode.grid.to_snapshot())
	var old := BuildGrid.new()
	old.apply(BuildEdit.paint_floor(Vector2i(3, 3), BuildGrid.FLOOR_TILE, 1))
	var off_door := _shell_grid([[&"entrance_door", Vector2i(15, 29), 2]])
	var walled := _shell_grid([[&"exit_door", GATE_C, 0]])
	walled.apply(BuildEdit.place_wall(GATE_C, BuildGrid.Side.NORTH))
	for refused in [old.to_snapshot(), off_door.to_snapshot(), walled.to_snapshot()]:
		assert_bool(_mode.load_snapshot(refused)).is_false()
		assert_str(JSON.stringify(_mode.grid.to_snapshot())).is_equal(before)
	assert_int(_floor_count()).is_equal(3 * 30)
	assert_int(_mode.grid.object_ids().size()).is_equal(2)
