class_name TestBuildModeLaneHint
extends GdUnitTestSuite
## The status line while the pointer is over a lane part: an incomplete arch
## names the first thing missing (SecurityLanes.status_text), a part that
## belongs to no arch reads "Not part of a lane".

const ANCHOR := Vector2i(5, 6)
const S := SecurityLanes.Status
const ELSEWHERE := Vector2i(1, 1)

var _mode: BuildMode


func before_test() -> void:
	_mode = BuildMode.new()
	_mode.grid_size = Vector2i(14, 14)
	add_child(_mode)
	for y in 14:
		for x in 14:
			_mode.grid.apply(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))


func after_test() -> void:
	_mode.free()


func _hover(cell: Vector2i) -> String:
	_mode._update_ghost(_mode.grid.cell_to_world(cell))
	return _mode.status_text()


func _lane(skip: Array[StringName] = []) -> Dictionary:
	return SecurityLaneBuilder.build(_mode.grid, ANCHOR, 0, SecurityLanes.RIGHT, skip)


func test_an_incomplete_arch_shows_the_first_missing_part() -> void:
	_mode.set_tool(BuildMode.Tool.NONE)
	_lane([SecurityLanes.XRAY_BELT])
	assert_str(_hover(ANCHOR)).is_equal(SecurityLanes.STATUS_TEXT[S.NO_XRAY_BELT])


func test_each_missing_part_has_its_own_hint() -> void:
	_mode.set_tool(BuildMode.Tool.NONE)
	var wanted := {
		SecurityLanes.TRAY_TABLE: S.NO_TRAY_TABLE,
		SecurityLanes.XRAY_BELT: S.NO_XRAY_BELT,
		SecurityLanes.PICKUP_TABLE: S.NO_PICKUP_TABLE,
	}
	for part: StringName in wanted:
		var skip: Array[StringName] = [part]
		var ids := _lane(skip)
		assert_str(_hover(ANCHOR)).is_equal(SecurityLanes.STATUS_TEXT[wanted[part]])
		for id: int in ids.values():
			assert_bool(_mode.grid.apply(BuildEdit.remove_object(id)).ok).is_true()
		assert_str(_hover(ELSEWHERE)).is_empty()


func test_turned_parts_show_the_facing_hint() -> void:
	_mode.set_tool(BuildMode.Tool.NONE)
	var turned: Array[StringName] = [SecurityLanes.TRAY_TABLE]
	SecurityLaneBuilder.build(_mode.grid, ANCHOR, 0, SecurityLanes.RIGHT, [], turned)
	assert_str(_hover(ANCHOR)).is_equal(SecurityLanes.STATUS_TEXT[S.PARTS_FACING])


func test_the_hint_joins_a_tool_that_has_its_own_status() -> void:
	_lane([SecurityLanes.PICKUP_TABLE])
	_mode.set_tool(BuildMode.Tool.DESK)
	assert_str(_hover(ANCHOR)).contains(SecurityLanes.STATUS_TEXT[S.NO_PICKUP_TABLE])


func test_a_part_of_an_incomplete_lane_shows_the_arch_hint() -> void:
	_mode.set_tool(BuildMode.Tool.NONE)
	var ids := _lane([SecurityLanes.XRAY_BELT])
	var tray: Vector2i = SecurityLanes.geometry(ANCHOR, 0, SecurityLanes.RIGHT)["tray_table"]
	assert_int(_mode.grid.object_at(tray)).is_equal(ids[SecurityLanes.TRAY_TABLE])
	assert_str(_hover(tray)).is_equal(SecurityLanes.STATUS_TEXT[S.NO_XRAY_BELT])


func test_a_part_with_no_arch_reads_not_part_of_a_lane() -> void:
	_mode.set_tool(BuildMode.Tool.NONE)
	PassengerTestWorld.place(_mode.grid, SecurityLanes.XRAY_BELT, Vector2i(2, 2), 0)
	assert_str(_hover(Vector2i(2, 2))).is_equal("Not part of a lane")


func test_a_whole_lane_and_empty_floor_add_no_hint() -> void:
	_mode.set_tool(BuildMode.Tool.NONE)
	_lane()
	assert_str(_hover(ANCHOR)).is_empty()
	assert_str(_hover(ELSEWHERE)).is_empty()


func test_the_hint_goes_when_the_pointer_leaves() -> void:
	_mode.set_tool(BuildMode.Tool.NONE)
	_lane([SecurityLanes.XRAY_BELT])
	assert_str(_hover(ANCHOR)).is_not_empty()
	assert_str(_hover(ELSEWHERE)).is_empty()


func test_another_object_adds_no_hint() -> void:
	_mode.set_tool(BuildMode.Tool.NONE)
	PassengerTestWorld.place(_mode.grid, &"checkin_desk", Vector2i(2, 2), 0)
	assert_str(_hover(Vector2i(2, 2))).is_empty()


func test_a_resting_pointer_does_not_recognise_the_lanes_again() -> void:
	_mode.set_tool(BuildMode.Tool.NONE)
	_lane([SecurityLanes.XRAY_BELT])
	var before := _mode.lane_hint_scans
	for i in 5:
		assert_str(_hover(ANCHOR)).is_equal(SecurityLanes.STATUS_TEXT[S.NO_XRAY_BELT])
	assert_int(_mode.lane_hint_scans).is_equal(before + 1)
	# An edit drops the cached hint: the next frame works it out again.
	var belt: Vector2i = SecurityLanes.geometry(ANCHOR, 0, SecurityLanes.RIGHT)["xray_belt"]
	PassengerTestWorld.place(_mode.grid, SecurityLanes.XRAY_BELT, belt, 0)
	assert_str(_hover(ANCHOR)).is_empty()
	assert_int(_mode.lane_hint_scans).is_equal(before + 2)
	# Moving to another cell works that cell's hint out.
	assert_str(_hover(ELSEWHERE)).is_empty()
	assert_int(_mode.lane_hint_scans).is_equal(before + 3)
