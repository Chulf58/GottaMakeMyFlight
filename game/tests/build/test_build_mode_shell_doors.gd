class_name TestBuildModeShellDoors
extends GdUnitTestSuite
## BuildMode with the Toon terminal shell: the grid takes the shell's frame,
## the Entrance tool snaps to a landside Toon door and the Exit tool to an
## airside gate door within ShellDefinition.SNAP_RADIUS_M of the cursor, and
## any other spot is refused with DOOR_NOT_AT_SHELL_DOOR (decision
## inside-the-toon-shell-the-entrance-tool-snaps-to-the-toon-la).

const SHELL := preload("res://build/toon_terminal_shell.tres")
## Landside B (Doorway_7) and gate C (Doorway_2), both on column 16.
const LANDSIDE_B := Vector2i(16, 29)
const GATE_C := Vector2i(16, 0)

var _mode: BuildMode


## Floor on columns 12 to 20, every row, so both doors' cells have floor.
func before_test() -> void:
	_mode = BuildMode.new()
	_mode.shell = SHELL
	add_child(_mode)
	for y in SHELL.grid_size.y:
		for x in range(12, 21):
			_mode.grid.apply(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))


func after_test() -> void:
	_mode.free()


## A ground point `offset` metres from the centre of `cell`, on the floor.
func _at(cell: Vector2i, offset := Vector3.ZERO) -> Vector3:
	return _mode.grid.cell_to_world(cell) + offset


func test_the_grid_takes_the_shell_frame() -> void:
	assert_vector(_mode.grid.size).is_equal(SHELL.grid_size)
	assert_vector(_mode.grid.origin).is_equal(SHELL.grid_origin)


func test_entrance_snaps_to_the_landside_door_near_the_cursor() -> void:
	_mode.set_tool(BuildMode.Tool.ENTRANCE)
	# Two cells in and one to the side of the door's cell.
	var edit := _mode.edit_at(_at(LANDSIDE_B, Vector3(1.2, 0.0, -2.0)))
	assert_vector(edit.cell).is_equal(LANDSIDE_B)
	assert_int(edit.facing).is_equal(2)
	var result := _mode.apply_at(_at(LANDSIDE_B, Vector3(1.2, 0.0, -2.0)))
	assert_bool(result.ok).is_true()
	var record := _mode.grid.get_object(result.object_id)
	assert_str(str(record["def"])).is_equal("entrance_door")
	assert_vector(record["anchor"]).is_equal(LANDSIDE_B)


func test_exit_snaps_to_gate_c_and_r_does_not_turn_it() -> void:
	_mode.set_tool(BuildMode.Tool.EXIT)
	_mode.rotate_facing()
	var result := _mode.apply_at(_at(GATE_C, Vector3(-0.8, 0.0, 1.5)))
	assert_bool(result.ok).is_true()
	var record := _mode.grid.get_object(result.object_id)
	assert_vector(record["anchor"]).is_equal(GATE_C)
	assert_int(record["facing"]).is_equal(0)


func test_entrance_by_an_airside_door_is_refused_with_a_hint() -> void:
	_mode.set_tool(BuildMode.Tool.ENTRANCE)
	var result := _mode.apply_at(_at(GATE_C))
	assert_bool(result.ok).is_false()
	assert_int(result.reason).is_equal(BuildResult.Reason.DOOR_NOT_AT_SHELL_DOOR)
	assert_str(_mode.status_text()).contains("landside door")
	assert_int(_mode.grid.object_ids().size()).is_equal(0)


func test_exit_mid_floor_or_on_a_plain_border_cell_is_refused() -> void:
	_mode.set_tool(BuildMode.Tool.EXIT)
	var mid := _mode.apply_at(_at(Vector2i(16, 15)))
	assert_int(mid.reason).is_equal(BuildResult.Reason.DOOR_NOT_AT_SHELL_DOOR)
	assert_str(_mode.status_text()).contains("gate door")
	# A border cell with no Toon door, checked directly so no snap applies.
	var plain := _mode.check(BuildEdit.place_object(&"exit_door", Vector2i(12, 0), 0))
	assert_int(plain.reason).is_equal(BuildResult.Reason.DOOR_NOT_AT_SHELL_DOOR)
	var turned := _mode.check(BuildEdit.place_object(&"exit_door", GATE_C, 1))
	assert_int(turned.reason).is_equal(BuildResult.Reason.DOOR_NOT_AT_SHELL_DOOR)
	assert_int(_mode.grid.object_ids().size()).is_equal(0)


func test_without_a_shell_the_door_rule_is_the_edge_rule() -> void:
	var grid := BuildGrid.new(Vector2i(4, 4))
	for x in 4:
		grid.apply(BuildEdit.paint_floor(Vector2i(x, 0), BuildGrid.FLOOR_TILE, 1))
		grid.apply(BuildEdit.paint_floor(Vector2i(x, 1), BuildGrid.FLOOR_TILE, 1))
	var edit := BuildEdit.place_object(&"exit_door", Vector2i(2, 0), 0)
	assert_bool(DoorPlacement.check(grid, edit).ok).is_true()
	assert_int(DoorPlacement.check(grid, edit, SHELL).reason).is_equal(
		BuildResult.Reason.DOOR_NOT_AT_SHELL_DOOR
	)
