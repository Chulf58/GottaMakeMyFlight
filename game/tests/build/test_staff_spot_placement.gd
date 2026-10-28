class_name TestStaffSpotPlacement
extends GdUnitTestSuite
## Placing a station needs a free staff spot behind a desk or beside a
## scanner, and nothing may be placed on a spot (decision
## staff-spot-design-a-derived-staff-spot-behind-each-desk-and, point 2).

const DESK := &"checkin_desk"
const SCANNER := &"security_scanner"
const SEATS := &"seat_row"
const SPOT := BuildResult.Reason.STAFF_SPOT

var _grid: BuildGrid


func before_test() -> void:
	_grid = PassengerTestWorld.floored(Vector2i(12, 10))


func _place(def_id: StringName, anchor: Vector2i, facing := 0) -> BuildResult:
	return _grid.apply(BuildEdit.place_object(def_id, anchor, facing))


func _expect_spot_refusal(result: BuildResult, blocker := -1) -> void:
	print(
		(
			"refused: %s (%d), blocker %d"
			% [result.reason_text(), result.reason, result.blocking_object_id]
		)
	)
	assert_bool(result.ok).is_false()
	assert_int(result.reason).is_equal(SPOT)
	if blocker >= 0:
		assert_int(result.blocking_object_id).is_equal(blocker)


func test_the_spot_is_behind_the_desk_and_beside_the_scanner_at_every_facing() -> void:
	for facing in 4:
		var desk := StaffSpots.cell_of(DESK, Vector2i(5, 5), facing)
		var scanner := StaffSpots.cell_of(SCANNER, Vector2i(5, 5), facing)
		assert_that(desk).is_equal(
			Vector2i(5, 5) + BuildObjectDef.rotate_offset(Vector2i(0, -1), facing)
		)
		assert_that(scanner).is_equal(
			Vector2i(5, 5) + BuildObjectDef.rotate_offset(Vector2i(1, 1), facing)
		)
	assert_that(StaffSpots.cell_of(SEATS, Vector2i(5, 5), 0)).is_equal(BuildObjectDef.NO_CELL)
	var id := _place(DESK, Vector2i(3, 3)).object_id
	assert_that(StaffSpots.spot_of(_grid, id)).is_equal(Vector2i(3, 2))


func test_the_refusal_has_its_own_player_text() -> void:
	var text := BuildResult.REASON_TEXT[SPOT] as String
	print("STAFF_SPOT text: %s" % text)
	assert_str(text).is_not_empty()
	for other in BuildResult.REASON_TEXT:
		if other != SPOT:
			assert_str(BuildResult.REASON_TEXT[other]).is_not_equal(text)


func test_a_desk_whose_spot_is_off_the_grid_is_refused() -> void:
	_expect_spot_refusal(_place(DESK, Vector2i(3, 0)))
	assert_int(_grid.object_at(Vector2i(3, 0))).is_equal(0)


func test_a_desk_whose_spot_has_no_floor_is_refused() -> void:
	assert_bool(_grid.apply(BuildEdit.remove_floor(Vector2i(3, 2))).ok).is_true()
	_expect_spot_refusal(_place(DESK, Vector2i(3, 3)))


func test_a_desk_whose_spot_is_under_an_object_is_refused() -> void:
	var seats := _place(SEATS, Vector2i(2, 2)).object_id
	_expect_spot_refusal(_place(DESK, Vector2i(3, 3)), seats)


func test_a_desk_whose_spot_is_another_station_interaction_cell_is_refused() -> void:
	var first := _place(DESK, Vector2i(6, 1)).object_id
	assert_that(_grid.interaction_cell(first)).is_equal(Vector2i(6, 2))
	_expect_spot_refusal(_place(DESK, Vector2i(6, 3)), first)


func test_a_station_whose_spot_is_another_station_spot_is_refused() -> void:
	var desk := _place(DESK, Vector2i(3, 3)).object_id
	# A scanner at (2, 1) facing 0 would stand its officer on (3, 2) as well.
	assert_that(StaffSpots.cell_of(SCANNER, Vector2i(2, 1), 0)).is_equal(Vector2i(3, 2))
	_expect_spot_refusal(_place(SCANNER, Vector2i(2, 1)), desk)


func test_a_desk_walled_off_from_its_spot_is_refused() -> void:
	var wall := BuildEdit.place_wall(Vector2i(3, 2), BuildGrid.Side.SOUTH)
	assert_bool(_grid.apply(wall).ok).is_true()
	_expect_spot_refusal(_place(DESK, Vector2i(3, 3)))
	# A door on that edge leaves the agent a way to its desk.
	var open := PassengerTestWorld.floored(Vector2i(12, 10))
	for x in [2, 4]:
		open.apply(BuildEdit.place_wall(Vector2i(x, 2), BuildGrid.Side.SOUTH))
	(
		assert_bool(open.apply(BuildEdit.place_wall(Vector2i(3, 2), BuildGrid.Side.SOUTH, 3)).ok)
		. is_true()
	)
	assert_bool(open.apply(BuildEdit.place_object(DESK, Vector2i(3, 3), 0)).ok).is_true()


func test_a_footprint_on_a_spot_is_refused() -> void:
	var desk := _place(DESK, Vector2i(3, 3)).object_id
	_expect_spot_refusal(_place(SEATS, Vector2i(2, 2)), desk)
	assert_int(_grid.object_at(Vector2i(3, 2))).is_equal(0)


func test_an_interaction_cell_on_a_spot_is_refused() -> void:
	var desk := _place(DESK, Vector2i(3, 3)).object_id
	# A desk at (3, 1) facing 0 has its interaction cell on (3, 2).
	_expect_spot_refusal(_place(DESK, Vector2i(3, 1)), desk)


func test_back_to_back_desks_are_refused() -> void:
	var desk := _place(DESK, Vector2i(3, 3)).object_id
	# Facing 2 the footprint runs (4, 2), (3, 2): its back against the first desk's.
	_expect_spot_refusal(_place(DESK, Vector2i(4, 2), 2), desk)


func test_same_facing_scanners_side_by_side_need_a_gap_column() -> void:
	var first := _place(SCANNER, Vector2i(3, 3)).object_id
	assert_that(StaffSpots.spot_of(_grid, first)).is_equal(Vector2i(4, 4))
	_expect_spot_refusal(_place(SCANNER, Vector2i(4, 3)), first)
	var spaced := _place(SCANNER, Vector2i(5, 3))
	print("scanner with a gap column: ok=%s" % spaced.ok)
	assert_bool(spaced.ok).is_true()
