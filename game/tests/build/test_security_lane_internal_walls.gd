class_name TestSecurityLaneInternalWalls
extends GdUnitTestSuite
## A wall on either conveyor edge of a lane, tray table to X-ray belt or X-ray
## belt to pickup table, breaks the lane with WALL_IN_LANE at every facing and
## both mirrors: the conveyor ends would stick into it and trays could not pass
## (board item a064072b, found by the Security 3/8 asset lane).

const ANCHOR := Vector2i(6, 6)
const S := SecurityLanes.Status
## The two conveyor edges as pairs of lane keys.
const EDGES := [
	[&"tray_table", &"xray_belt"],
	[&"xray_belt", &"pickup_table"],
]

var _grid: BuildGrid


func before_test() -> void:
	_grid = PassengerTestWorld.floored(Vector2i(14, 14))


func _edge_wall(a: Vector2i, b: Vector2i, kind: int) -> BuildEdit:
	return BuildEdit.place_wall(a, BuildGrid.SIDE_STEP.find(b - a), kind)


func test_a_valid_lane_with_no_internal_wall_is_still_accepted() -> void:
	for facing in 4:
		for mirror in SecurityLanes.MIRRORS:
			_grid = PassengerTestWorld.floored(Vector2i(14, 14))
			var ids := SecurityLaneBuilder.build(_grid, ANCHOR, facing, mirror)
			var lanes := SecurityLaneBuilder.recognise(_grid)
			var arch: int = ids[SecurityLanes.ARCH]
			print("facing %d mirror %d: %s" % [facing, mirror, S.keys()[lanes.status(arch)]])
			assert_int(lanes.status(arch)).is_equal(S.COMPLETE)
			assert_bool(lanes.is_complete(arch)).is_true()


func test_a_wall_on_a_conveyor_edge_breaks_the_lane_at_every_facing_and_mirror() -> void:
	for facing in 4:
		for mirror in SecurityLanes.MIRRORS:
			var lane := SecurityLanes.geometry(ANCHOR, facing, mirror)
			for edge in EDGES:
				for kind in [BuildGrid.WallKind.PLAIN, BuildGrid.WallKind.GLASS]:
					_grid = PassengerTestWorld.floored(Vector2i(14, 14))
					var ids := SecurityLaneBuilder.build(_grid, ANCHOR, facing, mirror)
					var arch: int = ids[SecurityLanes.ARCH]
					var tag := "facing %d mirror %d %s kind %d" % [facing, mirror, edge, kind]
					var wall := _edge_wall(lane[edge[0]], lane[edge[1]], kind)
					var applied := _grid.apply(wall)
					assert_bool(applied.ok).override_failure_message("place " + tag).is_true()
					var lanes := SecurityLaneBuilder.recognise(_grid)
					print("%s: %s" % [tag, S.keys()[lanes.status(arch)]])
					assert_int(lanes.status(arch)).override_failure_message(tag).is_equal(
						S.WALL_IN_LANE
					)
					assert_bool(lanes.is_complete(arch)).override_failure_message(tag).is_false()


func test_removing_the_conveyor_edge_wall_makes_the_lane_whole_again() -> void:
	var lane := SecurityLanes.geometry(ANCHOR, 2, SecurityLanes.LEFT)
	var ids := SecurityLaneBuilder.build(_grid, ANCHOR, 2, SecurityLanes.LEFT)
	var arch: int = ids[SecurityLanes.ARCH]
	for edge in EDGES:
		var a: Vector2i = lane[edge[0]]
		var b: Vector2i = lane[edge[1]]
		var side := BuildGrid.SIDE_STEP.find(b - a)
		assert_bool(_grid.apply(BuildEdit.place_wall(a, side)).ok).is_true()
		assert_int(SecurityLaneBuilder.recognise(_grid).status(arch)).is_equal(S.WALL_IN_LANE)
		assert_bool(_grid.apply(BuildEdit.remove_wall(a, side)).ok).is_true()
		assert_int(SecurityLaneBuilder.recognise(_grid).status(arch)).is_equal(S.COMPLETE)
