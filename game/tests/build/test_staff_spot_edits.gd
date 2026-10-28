class_name TestStaffSpotEdits
extends GdUnitTestSuite
## Once a station stands, no edit may block its staff spot: not the floor
## under it, not a rectangle drag, not a wall between it and its station, and
## not an edit that takes its last routable neighbour (decision
## staff-spot-design-a-derived-staff-spot-behind-each-desk-and, point 2).

const DESK := &"checkin_desk"
const SEATS := &"seat_row"
const SPOT := BuildResult.Reason.STAFF_SPOT
## The desk at (3, 3) facing 0 has its spot here.
const DESK_SPOT := Vector2i(3, 2)

var _grid: BuildGrid
var _desk := 0


func before_test() -> void:
	_grid = PassengerTestWorld.floored(Vector2i(12, 10))
	var placed := _grid.apply(BuildEdit.place_object(DESK, Vector2i(3, 3), 0))
	assert_bool(placed.ok).is_true()
	_desk = placed.object_id


func _expect_spot_refusal(result: BuildResult) -> void:
	print(
		(
			"refused: %s (%d), blocker %d"
			% [result.reason_text(), result.reason, result.blocking_object_id]
		)
	)
	assert_bool(result.ok).is_false()
	assert_int(result.reason).is_equal(SPOT)
	assert_int(result.blocking_object_id).is_equal(_desk)


## Leaves (4, 2) as the spot's only routable neighbour.
func _corner_the_spot() -> void:
	for cell in [Vector2i(2, 1), Vector2i(3, 1), Vector2i(4, 1), Vector2i(2, 2)]:
		var result := _grid.apply(BuildEdit.remove_floor(cell))
		assert_bool(result.ok).is_true()
	assert_bool(StaffSpots.blocked(_grid, _desk)).is_false()


func test_removing_the_floor_under_a_spot_is_refused() -> void:
	var before := JSON.stringify(_grid.to_snapshot())
	_expect_spot_refusal(_grid.validate(BuildEdit.remove_floor(DESK_SPOT)))
	assert_str(JSON.stringify(_grid.to_snapshot())).is_equal(before)
	_expect_spot_refusal(_grid.apply(BuildEdit.remove_floor(DESK_SPOT)))
	assert_int(_grid.floor_at(DESK_SPOT)).is_equal(BuildGrid.FLOOR_TILE)


func test_a_remove_rectangle_keeps_the_spot_and_its_last_way_out() -> void:
	# Rows 0 to 2 over the whole width: the desk on row 3 stays.
	var outcome := AreaDrag.clear(_grid, Rect2i(0, 0, 12, 3))
	print(
		(
			"rectangle: removed %d, skipped %d: %s"
			% [outcome.placed, outcome.skipped, outcome.first_reason]
		)
	)
	assert_int(_grid.floor_at(DESK_SPOT)).is_equal(BuildGrid.FLOOR_TILE)
	assert_int(outcome.skipped).is_equal(2)
	assert_str(outcome.first_reason).is_equal(BuildResult.REASON_TEXT[SPOT])
	assert_int(outcome.placed).is_equal(34)
	assert_bool(StaffSpots.blocked(_grid, _desk)).is_false()


func test_a_wall_between_a_spot_and_its_desk_is_refused() -> void:
	_expect_spot_refusal(_grid.apply(BuildEdit.place_wall(DESK_SPOT, BuildGrid.Side.SOUTH)))
	assert_int(_grid.wall_kind(DESK_SPOT, BuildGrid.Side.SOUTH)).is_equal(BuildGrid.WallKind.NONE)
	var glass := BuildEdit.place_wall(
		Vector2i(3, 3), BuildGrid.Side.NORTH, BuildGrid.WallKind.GLASS
	)
	_expect_spot_refusal(_grid.apply(glass))
	# Walls on the spot's other edges leave it a way out.
	assert_bool(_grid.apply(BuildEdit.place_wall(DESK_SPOT, BuildGrid.Side.NORTH)).ok).is_true()
	assert_bool(_grid.apply(BuildEdit.place_wall(DESK_SPOT, BuildGrid.Side.WEST)).ok).is_true()


func test_a_wall_taking_the_last_routable_neighbour_is_refused() -> void:
	_corner_the_spot()
	_expect_spot_refusal(_grid.apply(BuildEdit.place_wall(DESK_SPOT, BuildGrid.Side.EAST)))
	assert_bool(StaffSpots.blocked(_grid, _desk)).is_false()
	# The same wall one cell further east blocks nothing.
	assert_bool(_grid.apply(BuildEdit.place_wall(Vector2i(4, 2), BuildGrid.Side.EAST)).ok).is_true()


func test_an_object_or_floor_edit_taking_the_last_routable_neighbour_is_refused() -> void:
	_corner_the_spot()
	_expect_spot_refusal(_grid.apply(BuildEdit.place_object(SEATS, Vector2i(4, 2), 0)))
	_expect_spot_refusal(_grid.apply(BuildEdit.remove_floor(Vector2i(4, 2))))
	assert_int(_grid.floor_at(Vector2i(4, 2))).is_equal(BuildGrid.FLOOR_TILE)
	assert_bool(_grid.apply(BuildEdit.place_object(SEATS, Vector2i(5, 1), 0)).ok).is_true()


func test_removing_the_desk_frees_its_spot() -> void:
	assert_bool(_grid.apply(BuildEdit.remove_object(_desk)).ok).is_true()
	assert_bool(_grid.apply(BuildEdit.remove_floor(DESK_SPOT)).ok).is_true()
