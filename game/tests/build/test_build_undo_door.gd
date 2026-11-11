class_name TestBuildUndoDoor
extends GdUnitTestSuite
## Ctrl+Z after a door placement (board 095d80eb: the player pressed it and
## nothing came back). A door put on the terminal's plain wall is one action
## that removes the wall and places the door; undo must take the door away,
## put the wall back and refund the price, and frames running after the click
## must not empty the history.
##
## The grid is 12x12 with floor on rows 2 to 9 and a plain wall round the
## floor, so its north wall is the terminal edge.

const NORTH := BuildGrid.Side.NORTH
const DOOR := Vector2i(5, 2)

var _mode: BuildMode
var _finances: Finances


func before_test() -> void:
	_finances = Finances.new()
	add_child(_finances)
	_mode = BuildMode.new()
	_mode.grid_size = Vector2i(12, 12)
	_mode.finances = _finances
	add_child(_mode)
	var edits: Array[BuildEdit] = []
	for y in range(2, 10):
		for x in range(2, 10):
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	for x in range(2, 10):
		edits.append(BuildEdit.place_wall(Vector2i(x, 2), NORTH, BuildGrid.WallKind.PLAIN))
	_mode.grid.apply_batch(edits)


func after_test() -> void:
	_mode.free()
	_finances.free()


## A point on the wall line of DOOR's north edge, where a click picks that wall.
func _on_north_wall() -> Vector3:
	return _mode.grid.cell_to_world(DOOR) + Vector3(0.0, 0.0, -0.5)


func _place_door() -> BuildResult:
	_mode.set_tool(BuildMode.Tool.EXIT)
	return _mode.apply_at(_on_north_wall())


func test_a_door_placed_over_a_wall_is_one_undo_step_that_restores_the_wall() -> void:
	var balance := _finances.wallet.balance
	var layout := _mode.grid.to_snapshot()
	var placed := _place_door()
	assert_bool(placed.ok).override_failure_message("placed: " + placed.reason_text()).is_true()
	assert_int(_mode.grid.wall_kind(DOOR, NORTH)).is_equal(BuildGrid.WallKind.NONE)
	assert_int(_mode.undo_history().size()).is_equal(1)
	var undone := _mode.undo()
	assert_bool(undone.ok).override_failure_message("undo: " + undone.reason_text()).is_true()
	assert_int(_mode.grid.wall_kind(DOOR, NORTH)).is_equal(BuildGrid.WallKind.PLAIN)
	assert_int(_finances.wallet.balance).is_equal(balance)
	var after := _mode.grid.to_snapshot()
	layout.erase("next_object_id")
	after.erase("next_object_id")
	assert_dict(after).is_equal(layout)


func test_frames_after_a_door_placement_keep_the_history() -> void:
	assert_bool(_place_door().ok).is_true()
	for i in 5:
		await get_tree().process_frame
	var steps := _mode.undo_history().size()
	assert_int(steps).override_failure_message("history after frames: %d" % steps).is_equal(1)
