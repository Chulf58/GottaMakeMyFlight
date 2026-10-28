class_name TestSecurityLaneNeighbours
extends GdUnitTestSuite
## Lanes side by side and in a row: a part or a cell belongs to at most one
## lane, lanes claim in arch-id order, an incomplete arch claims nothing, and
## the removal policy (SecurityLanes.broken()) names every lane an edit
## stopped (decisions each-security-lane-owns-its-parts-no-tray-or-pickup-
## table-is and security-lane-technical-design-one-station-per-lane-with-int,
## point 6).

const RIGHT := SecurityLanes.RIGHT
const LEFT := SecurityLanes.LEFT
const S := SecurityLanes.Status
## Two lanes in a row, facing 0: the front lane's queue entry (4, 10) is the
## back lane's exit.
const FRONT_ARCH := Vector2i(4, 8)
const BACK_ARCH := Vector2i(4, 12)

var _grid: BuildGrid


func before_test() -> void:
	_grid = PassengerTestWorld.floored(Vector2i(12, 18))


func _recognise() -> SecurityLanes:
	return SecurityLaneBuilder.recognise(_grid)


func _remove(object_id: int) -> void:
	assert_bool(_grid.apply(BuildEdit.remove_object(object_id)).ok).is_true()


func test_two_lanes_wanting_one_cell_go_to_the_lower_arch_id() -> void:
	var front: int = SecurityLaneBuilder.build(_grid, FRONT_ARCH, 0, RIGHT)[SecurityLanes.ARCH]
	var back: int = SecurityLaneBuilder.build(_grid, BACK_ARCH, 0, RIGHT)[SecurityLanes.ARCH]
	var shared: Vector2i = SecurityLanes.geometry(FRONT_ARCH, 0, RIGHT)["queue_entry"]
	assert_that(SecurityLanes.geometry(BACK_ARCH, 0, RIGHT)["exit"]).is_equal(shared)
	var lanes := _recognise()
	print("front %s, back %s" % [S.keys()[lanes.status(front)], S.keys()[lanes.status(back)]])
	assert_array(lanes.complete_arches()).is_equal([front])
	assert_int(lanes.status(back)).is_equal(S.NO_EXIT_ROOM)
	assert_int(lanes.lane_at(shared)).is_equal(front)


func test_the_same_two_lanes_built_the_other_way_round_go_to_the_back_lane() -> void:
	var back: int = SecurityLaneBuilder.build(_grid, BACK_ARCH, 0, RIGHT)[SecurityLanes.ARCH]
	var front: int = SecurityLaneBuilder.build(_grid, FRONT_ARCH, 0, RIGHT)[SecurityLanes.ARCH]
	var lanes := _recognise()
	assert_array(lanes.complete_arches()).is_equal([back])
	assert_int(lanes.status(front)).is_equal(S.NO_QUEUE_ROOM)


func test_removing_the_winner_hands_the_cell_to_the_other_lane_at_once() -> void:
	var front_ids := SecurityLaneBuilder.build(_grid, FRONT_ARCH, 0, RIGHT)
	var back: int = SecurityLaneBuilder.build(_grid, BACK_ARCH, 0, RIGHT)[SecurityLanes.ARCH]
	var before := _recognise()
	_remove(front_ids[SecurityLanes.TRAY_TABLE])
	var after := _recognise()
	assert_array(after.complete_arches()).is_equal([back])
	assert_int(after.status(front_ids[SecurityLanes.ARCH])).is_equal(S.NO_TRAY_TABLE)
	assert_array(SecurityLanes.broken(before, after)).is_equal([front_ids[SecurityLanes.ARCH]])


func test_two_arches_across_one_set_of_tables_share_nothing() -> void:
	# The tables at x = 5 fit the left arch's right side and the right arch's
	# left side, and each arch stands on the other's officer spot.
	var ids := SecurityLaneBuilder.build(_grid, Vector2i(4, 6), 0, RIGHT)
	var other := PassengerTestWorld.place(_grid, SecurityLanes.ARCH, Vector2i(6, 6), 0)
	var lanes := _recognise()
	var arch: int = ids[SecurityLanes.ARCH]
	print("arches %d %d: %s %s" % [arch, other, lanes.status_text(arch), lanes.status_text(other)])
	assert_array(lanes.complete_arches()).is_empty()
	assert_int(lanes.status(arch)).is_equal(S.NO_PRIMARY_SPOT)
	assert_int(lanes.status(other)).is_equal(S.NO_PRIMARY_SPOT)
	assert_int(lanes.candidate(other)["mirror"]).is_equal(LEFT)
	for part in ids:
		assert_int(lanes.lane_of_piece(ids[part])).is_equal(0)
	# Moving the second arch out leaves the first a whole lane.
	_remove(other)
	assert_array(_recognise().complete_arches()).is_equal([arch])


func test_an_incomplete_lower_arch_never_takes_a_complete_lane_part() -> void:
	# This arch faces the other way, and its tray table cell is the lane's
	# tray table: it is placed first, so it is evaluated first.
	var stray := PassengerTestWorld.place(_grid, SecurityLanes.ARCH, Vector2i(5, 8), 2)
	var ids := SecurityLaneBuilder.build(_grid, Vector2i(3, 6), 0, RIGHT)
	var tray_cell: Vector2i = SecurityLanes.geometry(Vector2i(5, 8), 2, RIGHT)["tray_table"]
	assert_that(tray_cell).is_equal(SecurityLanes.geometry(Vector2i(3, 6), 0, RIGHT)["tray_table"])
	var lanes := _recognise()
	var arch: int = ids[SecurityLanes.ARCH]
	assert_array(lanes.complete_arches()).is_equal([arch])
	assert_int(lanes.lane_of_piece(ids[SecurityLanes.TRAY_TABLE])).is_equal(arch)
	# Its tray table is turned and its X-ray belt is missing: the missing part
	# is named first.
	assert_int(lanes.status(stray)).is_equal(S.NO_XRAY_BELT)


func test_a_part_a_lane_owns_reads_as_missing_to_a_later_arch() -> void:
	var ids := SecurityLaneBuilder.build(_grid, Vector2i(3, 6), 0, RIGHT)
	var stray := PassengerTestWorld.place(_grid, SecurityLanes.ARCH, Vector2i(5, 8), 2)
	var lanes := _recognise()
	assert_array(lanes.complete_arches()).is_equal([ids[SecurityLanes.ARCH]])
	assert_int(lanes.status(stray)).is_equal(S.NO_TRAY_TABLE)


func test_a_complete_lane_beside_an_incomplete_arch() -> void:
	var ids := SecurityLaneBuilder.build(_grid, Vector2i(3, 6), 0, RIGHT)
	var skip: Array[StringName] = [SecurityLanes.XRAY_BELT, SecurityLanes.PICKUP_TABLE]
	var half := SecurityLaneBuilder.build(_grid, Vector2i(8, 6), 0, RIGHT, skip)
	var lanes := _recognise()
	var arch: int = ids[SecurityLanes.ARCH]
	assert_array(lanes.arches).is_equal([arch, half[SecurityLanes.ARCH]])
	assert_array(lanes.complete_arches()).is_equal([arch])
	assert_int(lanes.status(half[SecurityLanes.ARCH])).is_equal(S.NO_XRAY_BELT)
	assert_int(lanes.lane_of_piece(half[SecurityLanes.TRAY_TABLE])).is_equal(0)
	for cell in SecurityLanes.lane_cells(lanes.lane(arch)):
		assert_int(lanes.lane_at(cell)).is_equal(arch)


func test_mirrored_lanes_back_to_back_are_both_whole() -> void:
	var left := SecurityLaneBuilder.build(_grid, Vector2i(2, 6), 0, RIGHT)
	var right := SecurityLaneBuilder.build(_grid, Vector2i(7, 6), 0, LEFT)
	var lanes := _recognise()
	assert_array(lanes.complete_arches()).is_equal(
		[left[SecurityLanes.ARCH], right[SecurityLanes.ARCH]]
	)


func test_removal_policy_names_every_lane_an_edit_stopped() -> void:
	var ids := SecurityLaneBuilder.build(_grid, FRONT_ARCH, 0, RIGHT)
	var arch: int = ids[SecurityLanes.ARCH]
	var whole := _recognise()
	assert_array(SecurityLanes.broken(null, whole)).is_empty()
	assert_array(SecurityLanes.broken(whole, _recognise())).is_empty()
	_remove(ids[SecurityLanes.PICKUP_TABLE])
	var gone := _recognise()
	assert_array(SecurityLanes.broken(whole, gone)).is_equal([arch])
	assert_int(gone.status(arch)).is_equal(S.NO_PICKUP_TABLE)
	var lane := SecurityLanes.geometry(FRONT_ARCH, 0, RIGHT)
	PassengerTestWorld.place(_grid, SecurityLanes.PICKUP_TABLE, lane["pickup_table"], 0)
	var again := _recognise()
	assert_bool(again.is_complete(arch)).is_true()
	assert_array(SecurityLanes.broken(gone, again)).is_empty()
	# A part replaced between two rebuilds is a new lane: the old one stopped.
	assert_array(SecurityLanes.broken(whole, again)).is_equal([arch])
	# A cell of its room blocked stops it too.
	var seat := SecurityLaneBuilder.block(_grid, lane["berth"])
	var blocked := _recognise()
	assert_array(SecurityLanes.broken(again, blocked)).is_equal([arch])
	_remove(seat)
	_remove(arch)
	var no_arch := _recognise()
	assert_array(no_arch.arches).is_empty()
	assert_array(SecurityLanes.broken(again, no_arch)).is_equal([arch])
