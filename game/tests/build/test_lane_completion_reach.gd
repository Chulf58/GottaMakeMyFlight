class_name TestLaneCompletionReach
extends GdUnitTestSuite
## The staff reach rule treats the officer spots of a lane an edit completes
## like the spot of a desk or scanner it places: a placement that completes a
## lane and cuts its own officer spot off from every entrance is refused with
## STAFF_SPOT, alone or in a batch, and one that leaves the spot reachable
## passes.
##
## The grid is 12 x 16 and floored, with the entrance at (5, 15) and a RIGHT
## lane rooted at an arch on (5, 6) facing 0 with every part but the pickup
## table. Walls close the cells right of the parts (x 7 and 8, rows 5 to 7,
## holding the primary spot (7, 6)) on every side but the pickup table's cell
## (6, 5), so placing the pickup table seals them in.

const ANCHOR := Vector2i(5, 6)
const PRIMARY := Vector2i(7, 6)
const SPOT := BuildResult.Reason.STAFF_SPOT

var _grid: BuildGrid
var _lane := {}
var _arch := 0


func before_test() -> void:
	_grid = PassengerTestWorld.floored(Vector2i(12, 16))
	PassengerTestWorld.place(_grid, &"entrance_door", Vector2i(5, 15), 2)
	_lane = SecurityLanes.geometry(ANCHOR, 0, SecurityLanes.RIGHT)
	assert_that(_lane["primary_spot"]).is_equal(PRIMARY)
	_arch = PassengerTestWorld.place(_grid, SecurityLanes.ARCH, ANCHOR, 0)


## The walls around the primary spot's pocket; `open_top` leaves (8, 5)'s
## north edge open, so the pocket keeps a way out past the pickup table.
func _pocket(open_top: bool) -> void:
	var walls := [
		[Vector2i(7, 5), BuildGrid.Side.NORTH],
		[Vector2i(8, 5), BuildGrid.Side.EAST],
		[Vector2i(8, 6), BuildGrid.Side.EAST],
		[Vector2i(8, 7), BuildGrid.Side.EAST],
		[Vector2i(7, 7), BuildGrid.Side.SOUTH],
		[Vector2i(8, 7), BuildGrid.Side.SOUTH],
	]
	if not open_top:
		walls.append([Vector2i(8, 5), BuildGrid.Side.NORTH])
	for wall: Array in walls:
		assert_bool(_grid.apply(BuildEdit.place_wall(wall[0], wall[1])).ok).is_true()


func _part(def_id: StringName) -> BuildEdit:
	return BuildEdit.place_object(def_id, _lane[def_id], 0)


func _place_side_parts() -> void:
	for def_id in [SecurityLanes.TRAY_TABLE, SecurityLanes.XRAY_BELT]:
		assert_bool(_grid.apply(_part(def_id)).ok).is_true()


func _report(label: String, result: BuildResult) -> void:
	var lanes := SecurityLaneBuilder.recognise(_grid)
	print(
		(
			"%s: ok %s, %s (%d), blocker %d; lane whole %s; primary spot reached %s"
			% [
				label,
				result.ok,
				result.reason_text(),
				result.reason,
				result.blocking_object_id,
				lanes.is_complete(_arch),
				_grid.staff_reach().has(PRIMARY)
			]
		)
	)


func test_a_last_part_that_seals_its_own_primary_spot_is_refused() -> void:
	_pocket(false)
	_place_side_parts()
	assert_bool(_grid.staff_reach().has(PRIMARY)).is_true()
	var result := _grid.apply(_part(SecurityLanes.PICKUP_TABLE))
	_report("last part", result)
	assert_bool(result.ok).is_false()
	assert_int(result.reason).is_equal(SPOT)
	assert_int(result.blocking_object_id).is_equal(_arch)
	assert_bool(_grid.staff_reach().has(PRIMARY)).is_true()
	# The lane is still missing its pickup table.
	assert_bool(SecurityLaneBuilder.recognise(_grid).is_complete(_arch)).is_false()


func test_a_batch_whose_last_part_seals_the_primary_spot_stops_at_that_part() -> void:
	_pocket(false)
	var edits: Array[BuildEdit] = [
		_part(SecurityLanes.TRAY_TABLE),
		_part(SecurityLanes.XRAY_BELT),
		_part(SecurityLanes.PICKUP_TABLE),
	]
	var results := _grid.apply_batch(edits)
	_report("batch last part", results[2])
	assert_bool(results[0].ok).is_true()
	assert_bool(results[1].ok).is_true()
	assert_bool(results[2].ok).is_false()
	assert_int(results[2].reason).is_equal(SPOT)
	assert_bool(_grid.staff_reach().has(PRIMARY)).is_true()


func test_a_last_part_that_leaves_the_primary_spot_a_way_in_passes() -> void:
	_pocket(true)
	_place_side_parts()
	var result := _grid.apply(_part(SecurityLanes.PICKUP_TABLE))
	_report("control", result)
	assert_bool(result.ok).is_true()
	assert_bool(SecurityLaneBuilder.recognise(_grid).is_complete(_arch)).is_true()
	assert_bool(_grid.staff_reach().has(PRIMARY)).is_true()
