class_name TestSecurityLaneLayout
extends GdUnitTestSuite
## TerminalLayout lists a whole security lane as one station keyed by its
## arch, and leaves an incomplete arch out (decision security-lane-technical-
## design-one-station-per-lane-with-int, points 1 and 6). The basic scanner
## is unchanged beside it.

const ANCHOR := Vector2i(5, 6)
const S := SecurityLanes.Status

var _grid: BuildGrid
var _layout: TerminalLayout


func before_test() -> void:
	_grid = PassengerTestWorld.floored(Vector2i(14, 14))
	_layout = TerminalLayout.new()


## Builds the lane at ANCHOR, facing 0, mirror RIGHT, and returns its arch.
func _arch(skip: Array[StringName] = []) -> int:
	return SecurityLaneBuilder.build(_grid, ANCHOR, 0, SecurityLanes.RIGHT, skip)[
		SecurityLanes.ARCH
	]


func test_a_whole_lane_is_one_usable_station_keyed_by_its_arch() -> void:
	var arch := _arch()
	_layout.rebuild(_grid)
	var lane := _layout.security_lanes.lane(arch)
	var shown := [_layout.scanners, _layout.lanes.get(arch), _layout.passages.get(arch)]
	print("scanners %s, lane %s, passage %s" % shown)
	assert_array(_layout.scanners).is_equal([arch])
	assert_bool(_layout.is_usable(arch)).is_true()
	assert_array(_layout.passages[arch]).is_equal(lane["passage"])
	var queue: Array = _layout.lanes[arch]
	assert_that(queue[0]).is_equal(lane["unpack"])
	assert_that(queue[1]).is_equal(lane["queue_entry"])
	assert_int(queue.size()).is_equal(TerminalLayout.LANE_SLOTS)


func test_an_incomplete_arch_is_not_a_station() -> void:
	var skip: Array[StringName] = [SecurityLanes.XRAY_BELT]
	var arch := _arch(skip)
	_layout.rebuild(_grid)
	assert_array(_layout.scanners).is_empty()
	assert_bool(_layout.is_usable(arch)).is_false()
	assert_bool(_layout.lanes.has(arch)).is_false()
	assert_bool(_layout.passages.has(arch)).is_false()
	assert_int(_layout.security_lanes.status(arch)).is_equal(S.NO_XRAY_BELT)


func test_a_basic_scanner_beside_a_lane_keeps_its_own_queue_and_passage() -> void:
	var scanner := PassengerTestWorld.place(_grid, &"security_scanner", Vector2i(11, 5), 0)
	var arch := _arch()
	_layout.rebuild(_grid)
	assert_array(_layout.scanners).is_equal([scanner, arch])
	assert_bool(_layout.is_usable(scanner)).is_true()
	assert_array(_layout.passages[scanner]).is_equal(_grid.passage_cells(scanner))
	assert_that(_layout.lanes[scanner][0]).is_equal(Vector2i(11, 7))


func test_another_station_queue_stops_before_the_lane_room() -> void:
	# The lane's helper spot is (4, 4); the desk's queue runs down x = 4.
	var desk := PassengerTestWorld.place(_grid, &"checkin_desk", Vector2i(4, 1), 0)
	SecurityLaneBuilder.build(_grid, ANCHOR, 0, SecurityLanes.RIGHT)
	_layout.rebuild(_grid)
	assert_that(SecurityLanes.geometry(ANCHOR, 0, SecurityLanes.RIGHT)["helper_spot"]).is_equal(
		Vector2i(4, 4)
	)
	assert_array(_layout.lanes[desk]).is_equal([Vector2i(4, 2), Vector2i(4, 3)])


func test_each_rebuild_makes_a_new_recognition_so_a_caller_can_compare() -> void:
	var ids := SecurityLaneBuilder.build(_grid, ANCHOR, 0, SecurityLanes.RIGHT)
	_layout.rebuild(_grid)
	var before := _layout.security_lanes
	assert_bool(_grid.apply(BuildEdit.remove_object(ids[SecurityLanes.TRAY_TABLE])).ok).is_true()
	_layout.rebuild(_grid)
	assert_object(_layout.security_lanes).is_not_same(before)
	assert_array(SecurityLanes.broken(before, _layout.security_lanes)).is_equal(
		[ids[SecurityLanes.ARCH]]
	)
	assert_array(_layout.scanners).is_empty()
