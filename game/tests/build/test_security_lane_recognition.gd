class_name TestSecurityLaneRecognition
extends GdUnitTestSuite
## SecurityLanes recognises a lane from separately placed parts (decisions
## security-lane-parts-are-placed-separately-tray-table-x-ray-b and
## security-lane-technical-design-one-station-per-lane-with-int, point 6): at
## every facing and mirror, naming the first missing part in flow order, a
## wrongly turned part, and the first cell of the lane's room that is blocked.

const ANCHOR := Vector2i(6, 6)
const RIGHT := SecurityLanes.RIGHT
const LEFT := SecurityLanes.LEFT
const S := SecurityLanes.Status

var _grid: BuildGrid


func before_test() -> void:
	_grid = PassengerTestWorld.floored(Vector2i(14, 14))


func _status_of(arch: int) -> int:
	var lanes := SecurityLaneBuilder.recognise(_grid)
	print("arch %d: %s (%s)" % [arch, S.keys()[lanes.status(arch)], lanes.status_text(arch)])
	return lanes.status(arch)


func test_a_whole_lane_is_recognised_at_every_facing_and_both_mirrors() -> void:
	for facing in 4:
		for mirror in SecurityLanes.MIRRORS:
			_grid = PassengerTestWorld.floored(Vector2i(14, 14))
			var ids := SecurityLaneBuilder.build(_grid, ANCHOR, facing, mirror)
			var arch: int = ids[SecurityLanes.ARCH]
			var lanes := SecurityLaneBuilder.recognise(_grid)
			var tag := "facing %d mirror %d" % [facing, mirror]
			print("%s: %s" % [tag, S.keys()[lanes.status(arch)]])
			assert_bool(lanes.is_complete(arch)).override_failure_message(tag).is_true()
			assert_int(lanes.status(arch)).is_equal(S.COMPLETE)
			assert_array(lanes.complete_arches()).is_equal([arch])
			var lane := lanes.lane(arch)
			var expected := SecurityLanes.geometry(ANCHOR, facing, mirror)
			for key in expected:
				assert_that(lane[key]).override_failure_message("%s %s" % [tag, key]).is_equal(
					expected[key]
				)
			assert_int(lane["arch_id"]).is_equal(arch)
			assert_dict(lane["parts"]).is_equal(ids)
			for part in ids:
				assert_int(lanes.lane_of_piece(ids[part])).is_equal(arch)


func test_a_lone_arch_needs_a_tray_table_first() -> void:
	var arch := PassengerTestWorld.place(_grid, SecurityLanes.ARCH, ANCHOR, 0)
	assert_int(_status_of(arch)).is_equal(S.NO_TRAY_TABLE)
	var lanes := SecurityLaneBuilder.recognise(_grid)
	assert_bool(lanes.is_complete(arch)).is_false()
	assert_dict(lanes.lane(arch)).is_empty()
	assert_array(lanes.arches).is_equal([arch])
	assert_str(lanes.status_text(arch)).is_equal("Needs a tray table")


func test_each_missing_part_is_named_and_the_first_in_flow_order_wins() -> void:
	var cases := [
		[[SecurityLanes.TRAY_TABLE], S.NO_TRAY_TABLE],
		[[SecurityLanes.XRAY_BELT], S.NO_XRAY_BELT],
		[[SecurityLanes.PICKUP_TABLE], S.NO_PICKUP_TABLE],
		[[SecurityLanes.PICKUP_TABLE, SecurityLanes.XRAY_BELT], S.NO_XRAY_BELT],
		[[SecurityLanes.PICKUP_TABLE, SecurityLanes.TRAY_TABLE], S.NO_TRAY_TABLE],
	]
	for mirror in SecurityLanes.MIRRORS:
		for case in cases:
			_grid = PassengerTestWorld.floored(Vector2i(14, 14))
			var skip: Array[StringName] = []
			skip.assign(case[0])
			var ids := SecurityLaneBuilder.build(_grid, ANCHOR, 2, mirror, skip)
			assert_int(_status_of(ids[SecurityLanes.ARCH])).is_equal(case[1])
	assert_str(SecurityLanes.STATUS_TEXT[S.NO_XRAY_BELT]).is_equal("Needs an X-ray belt")
	assert_str(SecurityLanes.STATUS_TEXT[S.NO_PICKUP_TABLE]).is_equal("Needs a pickup table")


func test_each_wrongly_turned_part_says_parts_face_different_ways() -> void:
	for part in SecurityLaneBuilder.PARTS:
		_grid = PassengerTestWorld.floored(Vector2i(14, 14))
		var turned: Array[StringName] = [part]
		var ids := SecurityLaneBuilder.build(_grid, ANCHOR, 1, RIGHT, [], turned)
		var arch: int = ids[SecurityLanes.ARCH]
		assert_int(_status_of(arch)).is_equal(S.PARTS_FACING)
		var lanes := SecurityLaneBuilder.recognise(_grid)
		assert_str(lanes.status_text(arch)).is_equal("Parts face different ways")
		assert_int(lanes.lane_of_piece(ids[part])).is_equal(0)


func test_a_missing_part_is_named_before_a_turned_one() -> void:
	var skip: Array[StringName] = [SecurityLanes.PICKUP_TABLE]
	var turned: Array[StringName] = [SecurityLanes.TRAY_TABLE]
	var ids := SecurityLaneBuilder.build(_grid, ANCHOR, 0, RIGHT, skip, turned)
	assert_int(_status_of(ids[SecurityLanes.ARCH])).is_equal(S.NO_PICKUP_TABLE)


func test_a_blocked_cell_of_the_lane_names_what_it_is_for() -> void:
	var lane := SecurityLanes.geometry(ANCHOR, 3, LEFT)
	var cases := {
		"pickup": S.NO_PASSAGE,
		"queue_entry": S.NO_QUEUE_ROOM,
		"berth": S.NO_BERTH_ROOM,
		"exit": S.NO_EXIT_ROOM,
		"primary_spot": S.NO_PRIMARY_SPOT,
		"helper_spot": S.NO_HELPER_SPOT,
	}
	for key in cases:
		_grid = PassengerTestWorld.floored(Vector2i(14, 14))
		var ids := SecurityLaneBuilder.build(_grid, ANCHOR, 3, LEFT)
		SecurityLaneBuilder.block(_grid, lane[key])
		print("blocked %s at %s" % [key, lane[key]])
		assert_int(_status_of(ids[SecurityLanes.ARCH])).override_failure_message(key).is_equal(
			cases[key]
		)
	for cell in lane["return_route"]:
		_grid = PassengerTestWorld.floored(Vector2i(14, 14))
		var ids := SecurityLaneBuilder.build(_grid, ANCHOR, 3, LEFT)
		SecurityLaneBuilder.block(_grid, cell)
		assert_int(_status_of(ids[SecurityLanes.ARCH])).is_equal(S.NO_RETURN_ROOM)


func test_a_cell_off_the_floor_or_another_station_spot_blocks_the_lane() -> void:
	var lane := SecurityLanes.geometry(ANCHOR, 0, RIGHT)
	var ids := SecurityLaneBuilder.build(_grid, ANCHOR, 0, RIGHT)
	var arch: int = ids[SecurityLanes.ARCH]
	assert_bool(_grid.apply(BuildEdit.remove_floor(lane["berth"])).ok).is_true()
	assert_int(_status_of(arch)).is_equal(S.NO_BERTH_ROOM)
	var floor_back := BuildEdit.paint_floor(lane["berth"], BuildGrid.FLOOR_TILE, 1)
	assert_bool(_grid.apply(floor_back).ok).is_true()
	assert_int(_status_of(arch)).is_equal(S.COMPLETE)
	# A check-in desk whose staff spot is the lane's primary officer spot.
	var spot: Vector2i = lane["primary_spot"]
	PassengerTestWorld.place(_grid, &"checkin_desk", spot + Vector2i(0, 1), 0)
	assert_that(StaffSpots.cell_of(&"checkin_desk", spot + Vector2i(0, 1), 0)).is_equal(spot)
	assert_int(_status_of(arch)).is_equal(S.NO_PRIMARY_SPOT)


func test_a_wall_inside_the_lane_or_by_an_officer_spot_breaks_it() -> void:
	var lane := SecurityLanes.geometry(ANCHOR, 0, RIGHT)
	var ids := SecurityLaneBuilder.build(_grid, ANCHOR, 0, RIGHT)
	var arch: int = ids[SecurityLanes.ARCH]
	# Tray table (7, 7) is east of the unpack cell (6, 7).
	var wall := BuildEdit.place_wall(lane["unpack"], BuildGrid.Side.EAST)
	assert_bool(_grid.apply(wall).ok).is_true()
	assert_int(_status_of(arch)).is_equal(S.WALL_IN_LANE)
	(
		assert_bool(_grid.apply(BuildEdit.remove_wall(lane["unpack"], BuildGrid.Side.EAST)).ok)
		. is_true()
	)
	assert_int(_status_of(arch)).is_equal(S.COMPLETE)
	# The helper spot (5, 4) is north of the berth (5, 5).
	assert_bool(_grid.apply(BuildEdit.place_wall(lane["berth"], BuildGrid.Side.NORTH)).ok).is_true()
	assert_int(_status_of(arch)).is_equal(S.NO_HELPER_SPOT)


func test_the_report_follows_the_side_with_more_parts() -> void:
	var skip: Array[StringName] = [SecurityLanes.PICKUP_TABLE]
	var ids := SecurityLaneBuilder.build(_grid, ANCHOR, 0, LEFT, skip)
	var arch: int = ids[SecurityLanes.ARCH]
	var lanes := SecurityLaneBuilder.recognise(_grid)
	assert_int(lanes.status(arch)).is_equal(S.NO_PICKUP_TABLE)
	assert_int(lanes.candidate(arch)["mirror"]).is_equal(LEFT)
	# With nothing on either side the preferred mirror is reported.
	var lone := PassengerTestWorld.place(_grid, SecurityLanes.ARCH, Vector2i(2, 11), 0)
	lanes = SecurityLaneBuilder.recognise(_grid)
	assert_int(lanes.candidate(lone)["mirror"]).is_equal(RIGHT)
	assert_that(lanes.candidate(lone)["arch"]).is_equal(Vector2i(2, 11))


func test_parts_on_both_sides_fill_each_other_and_the_preferred_side_is_reported() -> void:
	var ids := SecurityLaneBuilder.build(_grid, ANCHOR, 0, RIGHT)
	var arch: int = ids[SecurityLanes.ARCH]
	var left := SecurityLanes.geometry(ANCHOR, 0, LEFT)
	for part in SecurityLaneBuilder.PARTS:
		PassengerTestWorld.place(_grid, part, left[part], 0)
	var lanes := SecurityLaneBuilder.recognise(_grid)
	# The left pickup table stands on the right lane's berth, and the right
	# one on the left lane's: neither side has room, and the tie goes right.
	assert_int(lanes.status(arch)).is_equal(S.NO_BERTH_ROOM)
	assert_int(lanes.candidate(arch)["mirror"]).is_equal(RIGHT)
	assert_bool(lanes.is_complete(arch)).is_false()


func test_a_whole_left_lane_is_taken_when_the_right_side_is_empty() -> void:
	var ids := SecurityLaneBuilder.build(_grid, ANCHOR, 2, LEFT)
	var lanes := SecurityLaneBuilder.recognise(_grid)
	var arch: int = ids[SecurityLanes.ARCH]
	assert_bool(lanes.is_complete(arch)).is_true()
	assert_int(lanes.lane(arch)["mirror"]).is_equal(LEFT)


func test_status_of_an_object_that_is_no_arch_is_no_arch() -> void:
	var desk := PassengerTestWorld.place(_grid, &"checkin_desk", Vector2i(2, 2), 0)
	var lanes := SecurityLaneBuilder.recognise(_grid)
	assert_int(lanes.status(desk)).is_equal(S.NO_ARCH)
	assert_int(lanes.status(999)).is_equal(S.NO_ARCH)
	assert_dict(lanes.candidate(desk)).is_empty()
