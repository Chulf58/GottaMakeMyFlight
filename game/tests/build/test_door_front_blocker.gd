class_name TestDoorFrontBlocker
extends GdUnitTestSuite
## A door whose front cell is taken is refused with the blocker's name (decision
## door-placement-refusal-names-what-blocks-the-spot-in-front); other pieces keep
## the generic "The spot in front is blocked".

const EXIT_CELL := Vector2i(4, 2)

var _mode: BuildMode


## A 10x10 grid with floor on x 2..7, y 2..7. The exit at (4, 2) faces north, so
## its front cell is (4, 3).
func before_test() -> void:
	_mode = BuildMode.new()
	_mode.grid_size = Vector2i(10, 10)
	add_child(_mode)
	_mode.set_process(false)
	var edits: Array[BuildEdit] = []
	for y in range(2, 8):
		for x in range(2, 8):
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	_mode.grid.apply_batch(edits)


func after_test() -> void:
	_mode.free()


func _put(def_id: StringName, cell: Vector2i, turn: int) -> BuildResult:
	var result := _mode.grid.apply(BuildEdit.place_object(def_id, cell, turn))
	assert_bool(result.ok).is_true()
	return result


func _exit_check() -> BuildResult:
	return _mode.check(BuildEdit.place_object(&"exit_door", EXIT_CELL, 0))


func test_a_seat_in_front_of_an_exit_is_named() -> void:
	var seat := _put(&"seat_row", Vector2i(3, 3), 0)
	var result := _exit_check()
	print("exit: reason=%d text='%s'" % [result.reason, result.reason_text()])
	assert_int(result.reason).is_equal(BuildResult.Reason.DOOR_FRONT_BLOCKED)
	assert_int(result.blocking_object_id).is_equal(seat.object_id)
	assert_str(result.reason_text()).is_equal("Something is in front of the door: gate seats")
	var short := GhostReason.short_text(result)
	assert_str(short).is_equal("Gate seats in front")
	assert_int(short.length()).is_less_equal(24)


func test_a_desk_front_keeps_the_generic_text() -> void:
	var anchor := Vector2i(4, 5)
	var front := BuildCatalog.get_def(&"checkin_desk").interaction_cell(anchor, 0)
	_put(&"seat_row", front, 0)
	var result := _mode.check(BuildEdit.place_object(&"checkin_desk", anchor, 0))
	print("desk: reason=%d text='%s'" % [result.reason, result.reason_text()])
	assert_int(result.reason).is_equal(BuildResult.Reason.INTERACTION_BLOCKED)
	assert_str(result.reason_text()).is_equal("The spot in front is blocked")
	assert_str(GhostReason.short_text(result)).is_equal("Front spot blocked")


func test_a_door_with_nothing_in_front_is_not_refused_for_it() -> void:
	assert_int(_exit_check().reason).is_not_equal(BuildResult.Reason.DOOR_FRONT_BLOCKED)


func test_a_blocker_with_a_long_name_falls_back_to_the_generic_short_form() -> void:
	var result := BuildResult.refused(BuildResult.Reason.DOOR_FRONT_BLOCKED)
	result.detail = "security scanner with a long name"
	assert_str(GhostReason.short_text(result)).is_equal("Front spot blocked")
