class_name TestBuildModeRefusalStatus
extends GdUnitTestSuite
## The status line when a placement is refused (smoke playtest 5 note f): it
## shows the reason alone. The "Facing" prefix is for an item that can be placed
## and rotated, so a refusal such as "Facing 0  Keep the staff spot ..." read as
## debug text.

var _mode: BuildMode


func before_test() -> void:
	_mode = BuildMode.new()
	_mode.grid_size = Vector2i(10, 10)
	add_child(_mode)


func after_test() -> void:
	_mode.free()


func _bare_cell() -> Vector3:
	return _mode.grid.cell_to_world(Vector2i(4, 4))


func test_a_refused_item_shows_the_reason_without_facing() -> void:
	_mode.set_tool(BuildMode.Tool.DESK)
	var result := _mode.apply_at(_bare_cell())
	assert_bool(result.ok).is_false()
	assert_str(_mode.status_text()).is_equal(result.reason_text())
	assert_str(_mode.status_text()).not_contains("Facing")


func test_a_rotated_refused_item_shows_the_reason_without_facing() -> void:
	_mode.set_tool(BuildMode.Tool.DESK)
	_mode.rotate_facing()
	var result := _mode.apply_at(_bare_cell())
	assert_bool(result.ok).is_false()
	assert_str(_mode.status_text()).is_equal(result.reason_text())


func test_the_staff_spot_refusal_reads_as_the_reason_alone() -> void:
	assert_str(BuildResult.refused(BuildResult.Reason.STAFF_SPOT).reason_text()).is_equal(
		(
			"Keep the staff spot behind a desk, beside a scanner or at a lane officer's post"
			+ " free, with a way in"
		)
	)


func test_an_item_that_can_be_placed_still_shows_its_facing() -> void:
	for y in range(2, 7):
		for x in range(2, 7):
			assert_bool(_mode.apply_at(_mode.grid.cell_to_world(Vector2i(x, y))).ok).is_true()
	_mode.set_tool(BuildMode.Tool.DESK)
	var point := _bare_cell()
	_mode._update_ghost(point)
	assert_str(_mode.status_text()).is_equal("Facing 0")
	_mode.rotate_facing()
	_mode._update_ghost(point)
	assert_str(_mode.status_text()).is_equal("Facing 1")
