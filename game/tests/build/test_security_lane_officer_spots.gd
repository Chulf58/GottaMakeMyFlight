class_name TestSecurityLaneOfficerSpots
extends GdUnitTestSuite
## Once a lane is whole, BuildGrid refuses an edit that would block one of
## its officer spots (SecurityLanes.officer_spot_problem()), as it refuses one
## that blocks a desk's or scanner's staff spot: an object on the spot, a
## station whose own staff spot is the officer spot, a wall between the spot
## and the part or berth it works beside, or the floor taken from under it.
## The refusal is STAFF_SPOT and names the arch. Removing a lane part is
## allowed (the lane ends), and the spot is then free to build on.

const ANCHOR := Vector2i(5, 6)
const RIGHT := SecurityLanes.RIGHT
const STAFF_SPOT := BuildResult.Reason.STAFF_SPOT

var _grid: BuildGrid
var _ids := {}
var _lane := {}


func before_test() -> void:
	_grid = PassengerTestWorld.floored(Vector2i(14, 14))
	_ids = SecurityLaneBuilder.build(_grid, ANCHOR, 0, RIGHT)
	_lane = SecurityLanes.geometry(ANCHOR, 0, RIGHT)
	assert_bool(SecurityLaneBuilder.recognise(_grid).is_complete(_arch())).is_true()


func _arch() -> int:
	return _ids[SecurityLanes.ARCH]


func _assert_refused(edit: BuildEdit, what: String) -> void:
	var result := _grid.apply(edit)
	print(
		(
			"%s: ok %s reason '%s' blocker %d"
			% [what, result.ok, result.reason_text(), result.blocking_object_id]
		)
	)
	assert_bool(result.ok).override_failure_message(what).is_false()
	assert_int(result.reason).override_failure_message(what).is_equal(STAFF_SPOT)
	assert_int(result.blocking_object_id).override_failure_message(what).is_equal(_arch())
	assert_bool(SecurityLaneBuilder.recognise(_grid).is_complete(_arch())).is_true()


func test_an_object_on_either_officer_spot_is_refused() -> void:
	for key in ["primary_spot", "helper_spot"]:
		_assert_refused(BuildEdit.place_object(SecurityLaneBuilder.BLOCKER, _lane[key], 0), key)
	# Control: the same piece one cell further out is accepted.
	var out: Vector2i = _lane["primary_spot"] + Vector2i(1, 0)
	(
		assert_bool(_grid.apply(BuildEdit.place_object(SecurityLaneBuilder.BLOCKER, out, 0)).ok)
		. is_true()
	)


func test_a_desk_whose_staff_spot_is_an_officer_spot_is_refused() -> void:
	var spot: Vector2i = _lane["primary_spot"]
	var anchor := spot + Vector2i(0, 1)
	assert_that(StaffSpots.cell_of(&"checkin_desk", anchor, 0)).is_equal(spot)
	_assert_refused(BuildEdit.place_object(&"checkin_desk", anchor, 0), "desk")


func test_a_wall_between_an_officer_spot_and_its_part_is_refused() -> void:
	# The primary spot (7, 6) works the X-ray belt (6, 6) to its west; the
	# helper spot (4, 4) works the berth (4, 5) to its south.
	_assert_refused(
		BuildEdit.place_wall(_lane["primary_spot"], BuildGrid.Side.WEST), "primary wall"
	)
	_assert_refused(BuildEdit.place_wall(_lane["berth"], BuildGrid.Side.NORTH), "helper wall")
	var glass := BuildEdit.place_wall(_lane["primary_spot"], BuildGrid.Side.WEST)
	glass.wall_kind = BuildGrid.WallKind.GLASS
	_assert_refused(glass, "glass wall")
	# Control: a wall on the spot's far side is accepted.
	var far := BuildEdit.place_wall(_lane["primary_spot"], BuildGrid.Side.EAST)
	assert_bool(_grid.apply(far).ok).is_true()


func test_taking_the_floor_from_under_an_officer_spot_is_refused() -> void:
	_assert_refused(BuildEdit.remove_floor(_lane["helper_spot"]), "floor")


func test_removing_a_lane_part_frees_the_spot() -> void:
	assert_bool(_grid.apply(BuildEdit.remove_object(_ids[SecurityLanes.PICKUP_TABLE])).ok).is_true()
	assert_bool(SecurityLaneBuilder.recognise(_grid).is_complete(_arch())).is_false()
	var result := _grid.apply(
		BuildEdit.place_object(SecurityLaneBuilder.BLOCKER, _lane["helper_spot"], 0)
	)
	assert_bool(result.ok).is_true()
