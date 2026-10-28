class_name TestLaneOfficerSpotReach
extends GdUnitTestSuite
## The staff reach rule (staff-spot-reach-rule-an-edit-that-cuts-a-reachable-
## staff-sp) covers a whole security lane's officer spots as it covers a
## desk's or scanner's spot: an edit that cuts a spot staff reach now off from
## every entrance is refused with STAFF_SPOT naming the arch, and the edits
## before it, which leave a way in, pass.
##
## The grid is 12 x 16 and floored, with a RIGHT lane rooted at an arch on
## (5, 6) facing 0 (primary spot (7, 6), helper spot (4, 4)) and the entrance
## at (10, 15), right of the lane.

const ANCHOR := Vector2i(5, 6)
const SIZE := Vector2i(12, 16)
const SPOT := BuildResult.Reason.STAFF_SPOT

var _grid: BuildGrid
var _arch := 0
var _lane := {}


func before_test() -> void:
	_grid = PassengerTestWorld.floored(SIZE)
	_arch = SecurityLaneBuilder.build(_grid, ANCHOR, 0, SecurityLanes.RIGHT)[SecurityLanes.ARCH]
	PassengerTestWorld.place(_grid, &"entrance_door", Vector2i(10, 15), 2)
	_lane = SecurityLaneBuilder.recognise(_grid).lane(_arch)
	assert_bool(_lane.is_empty()).is_false()
	assert_bool(_grid.staff_reach().has(_lane["primary_spot"])).is_true()
	assert_bool(_grid.staff_reach().has(_lane["helper_spot"])).is_true()


## Applies every wall but the last, each accepted, and returns the last's
## result.
func _walls(walls: Array) -> BuildResult:
	for i in walls.size() - 1:
		var wall: Array = walls[i]
		var result := _grid.apply(BuildEdit.place_wall(wall[0], wall[1]))
		print("wall %s: %s" % [wall, result.reason_text()])
		assert_bool(result.ok).is_true()
	var last: Array = walls[walls.size() - 1]
	return _grid.apply(BuildEdit.place_wall(last[0], last[1]))


func _expect_refused(result: BuildResult, spot: Vector2i) -> void:
	print(
		(
			"last wall: %s (%d), blocker %d (arch %d); spot %s still reached %s"
			% [
				result.reason_text(),
				result.reason,
				result.blocking_object_id,
				_arch,
				spot,
				_grid.staff_reach().has(spot)
			]
		)
	)
	assert_bool(result.ok).is_false()
	assert_int(result.reason).is_equal(SPOT)
	assert_int(result.blocking_object_id).is_equal(_arch)
	assert_bool(_grid.staff_reach().has(spot)).is_true()
	assert_bool(SecurityLaneBuilder.recognise(_grid).is_complete(_arch)).is_true()


## Walls the primary spot and the cell beyond it into a pocket: the fifth wall
## closes it.
func test_a_wall_that_pockets_the_primary_spot_is_refused() -> void:
	var spot: Vector2i = _lane["primary_spot"]
	var beyond := spot + Vector2i(1, 0)
	var walls := [
		[spot, BuildGrid.Side.NORTH],
		[spot, BuildGrid.Side.SOUTH],
		[beyond, BuildGrid.Side.NORTH],
		[beyond, BuildGrid.Side.SOUTH],
		[beyond, BuildGrid.Side.EAST],
	]
	_expect_refused(_walls(walls), spot)


## A wall line east of column 5 parts the lane's walk cells, and the helper
## spot with them, from the entrance side; the parts themselves close rows 5
## to 7. The wall on row 0 closes the last gap.
func test_a_wall_that_parts_the_helper_spot_from_the_entrance_is_refused() -> void:
	var spot: Vector2i = _lane["helper_spot"]
	var walls := []
	for y in range(SIZE.y - 1, -1, -1):
		if y < 5 or y > 7:
			walls.append([Vector2i(5, y), BuildGrid.Side.EAST])
	_expect_refused(_walls(walls), spot)
	# The primary spot, on the entrance side, was never cut off.
	assert_bool(_grid.staff_reach().has(_lane["primary_spot"])).is_true()
