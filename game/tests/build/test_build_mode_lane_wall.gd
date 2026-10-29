class_name TestBuildModeLaneWall
extends GdUnitTestSuite
## A security lane part that would cross a wall is refused with text saying
## the wall is in the way, and no wall edge is removed for it (decision
## a-security-lane-part-placed-across-the-security-divider-wall). Smoke
## playtest 8: a lane built beside the starter scanner sat behind the divider
## wall and stayed incomplete until two of its edges were removed by hand.
## The terminal is ReferenceTerminal's: its divider runs along the north edge
## of row 9, the landside hall is below it (y 10-17) and the airside above.

const DIVIDER_ROW := ReferenceTerminal.DIVIDER_Y
## An arch in the landside hall just below the divider, at x 13 where the
## divider has no scanner gap and the grid accepts an arch. Facing 0 puts the
## queue on the landside. The lane's pickup cell (13, 9) is landside, but its
## exit (13, 8) is across the wall, and the helper officer's spot ((12, 8) on
## a RIGHT lane, (14, 8) on a LEFT one) is too.
const ACROSS := Vector2i(13, 10)
## A free spot in the landside hall, clear of every wall.
const HALL := Vector2i(19, 14)

var _mode: BuildMode


func before_test() -> void:
	_mode = BuildMode.new()
	add_child(_mode)
	assert_bool(ReferenceTerminal.build(_mode.grid)).is_true()


func after_test() -> void:
	_mode.free()


func _place(def_id: StringName, cell: Vector2i) -> BuildResult:
	return _mode.check(BuildEdit.place_object(def_id, cell, 0))


func _wall(cell: Vector2i, side: int) -> void:
	assert_bool(_mode.grid.apply(BuildEdit.place_wall(cell, side)).ok).is_true()


func test_the_terminal_has_the_divider_the_lane_would_cross() -> void:
	assert_bool(_mode.grid.has_wall(Vector2i(13, DIVIDER_ROW), BuildGrid.Side.NORTH)).is_true()
	assert_bool(_mode.grid.has_wall(Vector2i(17, DIVIDER_ROW), BuildGrid.Side.NORTH)).is_false()


func test_an_arch_across_the_divider_is_refused_naming_the_wall() -> void:
	var result := _place(SecurityLanes.ARCH, ACROSS)
	print("arch across the divider: ok=%s reason=%d" % [result.ok, result.reason])
	assert_bool(result.ok).is_false()
	assert_int(result.reason).is_equal(BuildResult.Reason.LANE_WALL)
	assert_str(result.reason_text()).contains("wall")


func test_clicking_it_shows_the_text_builds_nothing_and_keeps_the_wall() -> void:
	var before := _mode.grid.object_ids().size()
	_mode.set_tool(BuildMode.Tool.ARCH)
	var result := _mode.apply_at(_mode.grid.cell_to_world(ACROSS))
	assert_bool(result.ok).is_false()
	assert_int(_mode.grid.object_ids().size()).is_equal(before)
	assert_str(_mode.status_text()).contains("wall")
	assert_bool(_mode.grid.has_wall(Vector2i(13, DIVIDER_ROW), BuildGrid.Side.NORTH)).is_true()


func test_an_arch_in_the_clear_is_accepted() -> void:
	assert_bool(_place(SecurityLanes.ARCH, HALL).ok).is_true()


func test_a_part_across_a_wall_beside_its_arch_is_refused() -> void:
	assert_bool(_mode.grid.apply(BuildEdit.place_object(SecurityLanes.ARCH, HALL, 0)).ok).is_true()
	# A wall on the north edge of (20, 15) is across the conveyor between the
	# tray table (20, 15) and the X-ray belt (20, 14).
	_wall(Vector2i(20, 15), BuildGrid.Side.NORTH)
	var tray := _place(SecurityLanes.TRAY_TABLE, Vector2i(20, 15))
	var belt := _place(SecurityLanes.XRAY_BELT, Vector2i(20, 14))
	print("tray reason=%d belt reason=%d" % [tray.reason, belt.reason])
	assert_int(tray.reason).is_equal(BuildResult.Reason.LANE_WALL)
	assert_int(belt.reason).is_equal(BuildResult.Reason.LANE_WALL)
	assert_bool(_mode.grid.has_wall(Vector2i(20, 15), BuildGrid.Side.NORTH)).is_true()


func test_a_part_whose_edges_are_clear_is_accepted_beside_a_walled_one() -> void:
	assert_bool(_mode.grid.apply(BuildEdit.place_object(SecurityLanes.ARCH, HALL, 0)).ok).is_true()
	_wall(Vector2i(20, 15), BuildGrid.Side.NORTH)
	assert_bool(_place(SecurityLanes.PICKUP_TABLE, Vector2i(20, 13)).ok).is_true()


## The tray table (20, 15) beside the arch at HALL: a wall west of it is across
## the RIGHT lane of that arch (the unpack cell is (19, 15)), but the tray also
## belongs to a clear LEFT lane whose arch can still go at (21, 14).
func test_a_part_with_a_clear_lane_of_its_own_is_accepted_beside_a_walled_arch() -> void:
	assert_bool(_mode.grid.apply(BuildEdit.place_object(SecurityLanes.ARCH, HALL, 0)).ok).is_true()
	_wall(Vector2i(20, 15), BuildGrid.Side.WEST)
	assert_bool(_place(SecurityLanes.TRAY_TABLE, Vector2i(20, 15)).ok).is_true()


func test_a_part_with_a_clear_lane_not_yet_built_is_accepted_with_no_arch() -> void:
	_wall(Vector2i(20, 15), BuildGrid.Side.WEST)
	assert_bool(_place(SecurityLanes.TRAY_TABLE, Vector2i(20, 15)).ok).is_true()


func test_a_part_walled_in_every_lane_it_could_join_is_refused_with_no_arch() -> void:
	# A wall north of the tray table is across its conveyor step to the X-ray
	# belt, in a RIGHT lane and in a LEFT one.
	_wall(Vector2i(20, 15), BuildGrid.Side.NORTH)
	var result := _place(SecurityLanes.TRAY_TABLE, Vector2i(20, 15))
	assert_int(result.reason).is_equal(BuildResult.Reason.LANE_WALL)


func test_taking_the_wall_edges_down_by_hand_lets_the_arch_in() -> void:
	# Smoke playtest 8 needed two edges down: the exit's (x 13) and the helper
	# spot's on the RIGHT lane (x 12).
	assert_bool(_place(SecurityLanes.ARCH, ACROSS).ok).is_false()
	for x in [12, 13]:
		var cell := Vector2i(x, DIVIDER_ROW)
		(
			assert_bool(_mode.grid.apply(BuildEdit.remove_wall(cell, BuildGrid.Side.NORTH)).ok)
			. is_true()
		)
	assert_bool(_place(SecurityLanes.ARCH, ACROSS).ok).is_true()
