class_name TestBuildModeFrontWarning
extends GdUnitTestSuite
## An item placed inside a room whose front (interaction) cell falls outside it
## is not counted by the room (FacilitySlots.piece_inside), so the player is
## told on the status line, before and after the purchase (smoke 9 note 3,
## board item 73e15dd7).

## Cells 3..5 on both axes. A toilet stall at facing 0 covers (x, y) and
## (x, y + 1) with its front cell at (x, y + 2).
const ROOM := Rect2i(3, 3, 3, 3)
const STALL := &"toilet_stall"
const FRONT_INSIDE := Vector2i(3, 3)
const FRONT_OUTSIDE := Vector2i(3, 4)

var _mode: BuildMode


func before_test() -> void:
	_mode = BuildMode.new()
	_mode.grid_size = Vector2i(20, 20)
	add_child(_mode)
	_mode.set_process(false)
	var edits: Array[BuildEdit] = []
	for y in range(2, 12):
		for x in range(2, 14):
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	_mode.grid.apply_batch(edits)
	_mode.set_tool(BuildMode.Tool.TOILET_ROOM)
	_mode.begin_area(_at(ROOM.position))
	_mode.move_area(_at(ROOM.end - Vector2i.ONE))
	_mode.finish_area()
	assert_int(_mode.grid.room_at(ROOM.position)).is_greater(0)
	_mode.set_tool(BuildMode.Tool.TOILET_STALL)


func after_test() -> void:
	_mode.free()


func _at(cell: Vector2i) -> Vector3:
	return _mode.grid.cell_to_world(cell)


func _warning(def_id: StringName, cell: Vector2i) -> String:
	return BuildMode.front_warning(_mode.grid, BuildEdit.place_object(def_id, cell, 0))


func test_a_stall_with_its_front_inside_the_room_has_no_warning() -> void:
	assert_str(_warning(STALL, FRONT_INSIDE)).is_empty()


func test_a_stall_with_its_front_outside_the_room_is_warned() -> void:
	assert_str(_warning(STALL, FRONT_OUTSIDE)).is_equal(BuildMode.FRONT_OUTSIDE_ROOM)


func test_a_stall_outside_any_room_has_no_warning() -> void:
	assert_str(_warning(STALL, Vector2i(9, 3))).is_empty()


func test_other_edits_and_a_missing_edit_have_no_warning() -> void:
	assert_str(BuildMode.front_warning(_mode.grid, null)).is_empty()
	var floor_edit := BuildEdit.paint_floor(FRONT_OUTSIDE, BuildGrid.FLOOR_TILE, 1)
	assert_str(BuildMode.front_warning(_mode.grid, floor_edit)).is_empty()


func test_hovering_a_stall_with_its_front_outside_shows_the_warning_with_the_facing() -> void:
	_mode._update_ghost(_at(FRONT_OUTSIDE))
	assert_str(_mode.status_text()).contains(BuildMode.FRONT_OUTSIDE_ROOM)
	assert_str(_mode.status_text()).contains("Facing")


func test_hovering_a_stall_with_its_front_inside_shows_no_warning() -> void:
	_mode._update_ghost(_at(FRONT_INSIDE))
	assert_str(_mode.status_text()).not_contains(BuildMode.FRONT_OUTSIDE_ROOM)


func test_the_warning_leaves_with_the_pointer() -> void:
	_mode._update_ghost(_at(FRONT_OUTSIDE))
	assert_str(_mode.status_text()).contains(BuildMode.FRONT_OUTSIDE_ROOM)
	_mode._update_ghost(null)
	assert_str(_mode.status_text()).not_contains(BuildMode.FRONT_OUTSIDE_ROOM)


func test_a_refused_stall_shows_its_reason_alone() -> void:
	# A second stall on the first one's rear cell is refused; no warning rides along.
	assert_bool(_mode.apply_at(_at(FRONT_OUTSIDE)).ok).is_true()
	var overlap := FRONT_OUTSIDE + Vector2i(0, 1)
	_mode._update_ghost(_at(overlap))
	var result := _mode.check(BuildEdit.place_object(STALL, overlap, _mode.facing))
	assert_bool(result.ok).is_false()
	assert_str(_mode.status_text()).is_equal(result.reason_text())


func test_placing_the_stall_leaves_the_warning_on_the_status_line() -> void:
	var result := _mode.apply_at(_at(FRONT_OUTSIDE))
	assert_bool(result.ok).is_true()
	print("after place: '%s'" % _mode.status_text())
	assert_str(_mode.status_text()).is_equal(BuildMode.FRONT_OUTSIDE_ROOM)


func test_placing_a_stall_with_its_front_inside_leaves_no_warning() -> void:
	assert_bool(_mode.apply_at(_at(FRONT_INSIDE)).ok).is_true()
	assert_str(_mode.status_text()).not_contains(BuildMode.FRONT_OUTSIDE_ROOM)
