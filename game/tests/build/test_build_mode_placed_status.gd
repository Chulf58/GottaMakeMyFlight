class_name TestBuildModePlacedStatus
extends GdUnitTestSuite
## The status line after a successful place says what was placed, not the
## refusal the ghost under the pointer now shows (the piece just placed
## overlaps itself), until the pointer moves to another cell.

var _mode: BuildMode


## A 10x10 grid with floor on x 2..7, y 2..7 and no floor around it.
func before_test() -> void:
	_mode = BuildMode.new()
	_mode.grid_size = Vector2i(10, 10)
	add_child(_mode)
	_mode.set_tool(BuildMode.Tool.FLOOR)
	for y in range(2, 8):
		for x in range(2, 8):
			_mode.apply_at(_at(Vector2i(x, y)))


func after_test() -> void:
	_mode.free()


func _at(cell: Vector2i) -> Vector3:
	return _mode.grid.cell_to_world(cell)


func test_the_status_after_an_entrance_is_placed_says_so() -> void:
	_mode.set_tool(BuildMode.Tool.ENTRANCE)
	var point := _at(Vector2i(4, 2))
	assert_bool(_mode.apply_at(point).ok).is_true()
	assert_str(_mode.status_text()).is_equal("Entrance placed")
	# The pointer has not moved; the ghost re-checks the cell the door now fills.
	_mode._update_ghost(point)
	assert_str(_mode.status_text()).is_equal("Entrance placed")


func test_the_status_names_the_piece_that_was_placed() -> void:
	_mode.set_tool(BuildMode.Tool.EXIT)
	var point := _at(Vector2i(7, 4))
	assert_bool(_mode.apply_at(point).ok).is_true()
	_mode._update_ghost(point)
	assert_str(_mode.status_text()).is_equal("Exit to the plane placed")


func test_the_note_goes_when_the_pointer_moves_to_another_cell() -> void:
	_mode.set_tool(BuildMode.Tool.ENTRANCE)
	var point := _at(Vector2i(4, 2))
	_mode.apply_at(point)
	_mode._update_ghost(_at(Vector2i(5, 2)))
	assert_str(_mode.status_text()).is_not_equal("Entrance placed")
	_mode._update_ghost(point)
	assert_str(_mode.status_text()).is_equal(BuildResult.REASON_TEXT[BuildResult.Reason.OVERLAP])


func test_a_refused_place_keeps_its_reason() -> void:
	_mode.set_tool(BuildMode.Tool.ENTRANCE)
	var point := _at(Vector2i(4, 4))
	var result := _mode.apply_at(point)
	assert_int(result.reason).is_equal(BuildResult.Reason.DOOR_NOT_ON_EDGE)
	assert_str(_mode.status_text()).is_equal("Put the entrance on the outside edge of the floor")
