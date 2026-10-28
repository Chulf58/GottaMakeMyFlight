class_name TestStaffSpotReach
extends GdUnitTestSuite
## An edit that cuts a staff spot staff can reach from an entrance off from
## every entrance is refused with the staff-spot reason, whether it comes as a
## click, a rectangle drag or a belt line (decision
## desk-belts-run-one-row-back-desk-then-the-agent-row-then-the, v3). An edit
## that leaves the spot reachable passes, and with no entrance on the grid
## nothing is checked.
##
## The grid is 12x12 and floored, with the entrance at (0, 11) and a desk at
## (6, 3) whose spot is (6, 2). Row 5 runs between them.

const DESK := &"checkin_desk"
const SPOT := BuildResult.Reason.STAFF_SPOT
const DESK_SPOT := Vector2i(6, 2)
const ROW := 5
const WIDTH := 12

var _grid: BuildGrid
var _desk := 0


func before_test() -> void:
	_grid = _floored_with_desk(true)


func _floored_with_desk(entrance: bool) -> BuildGrid:
	var grid := PassengerTestWorld.floored(Vector2i(WIDTH, 12))
	_desk = PassengerTestWorld.place(grid, DESK, Vector2i(6, 3), 0)
	if entrance:
		PassengerTestWorld.place(grid, &"entrance_door", Vector2i(0, 11), 2)
	assert_that(StaffSpots.spot_of(grid, _desk)).is_equal(DESK_SPOT)
	assert_bool(grid.staff_reach().has(DESK_SPOT)).is_equal(entrance)
	return grid


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


func _expect_reachable() -> void:
	assert_bool(_grid.staff_reach().has(DESK_SPOT)).is_true()
	assert_bool(StaffSpots.unreachable(_grid, _desk)).is_false()


func test_a_remove_rectangle_skips_the_cell_that_would_cut_the_spot_off() -> void:
	var outcome := AreaDrag.clear(_grid, Rect2i(0, ROW, WIDTH, 1))
	print(
		(
			"row %d: removed %d, skipped %d: %s"
			% [ROW, outcome.placed, outcome.skipped, outcome.first_reason]
		)
	)
	assert_int(outcome.placed).is_equal(WIDTH - 1)
	assert_int(outcome.skipped).is_equal(1)
	assert_str(outcome.first_reason).is_equal(BuildResult.refused(SPOT).reason_text())
	# Cells go in row order, so the last one would have closed the row.
	assert_int(_grid.floor_at(Vector2i(WIDTH - 1, ROW))).is_equal(BuildGrid.FLOOR_TILE)
	_expect_reachable()


func test_a_remove_rectangle_that_leaves_a_way_round_is_all_removed() -> void:
	var outcome := AreaDrag.clear(_grid, Rect2i(0, ROW, WIDTH - 1, 1))
	print("row %d less one: removed %d, skipped %d" % [ROW, outcome.placed, outcome.skipped])
	assert_int(outcome.placed).is_equal(WIDTH - 1)
	assert_int(outcome.skipped).is_equal(0)
	_expect_reachable()


func test_with_no_entrance_the_whole_row_is_removed() -> void:
	_grid = _floored_with_desk(false)
	assert_bool(_grid.staff_reach().is_empty()).is_true()
	var outcome := AreaDrag.clear(_grid, Rect2i(0, ROW, WIDTH, 1))
	print("no entrance: removed %d, skipped %d" % [outcome.placed, outcome.skipped])
	assert_int(outcome.placed).is_equal(WIDTH)
	assert_int(outcome.skipped).is_equal(0)
	# Floor laid back on an open grid is never refused.
	var painted := AreaDrag.fill_floor(_grid, Rect2i(0, ROW, WIDTH, 1), 1)
	assert_int(painted.placed).is_equal(WIDTH)
	assert_bool(StaffSpots.unreachable(_grid, _desk)).is_false()


func test_a_belt_line_that_would_cut_the_spot_off_is_refused() -> void:
	var plan := BeltShaper.plan_line(_grid, Vector2i(0, ROW), Vector2i(WIDTH - 1, ROW), 1)
	_expect_spot_refusal(plan.result)
	assert_int(_grid.object_at(Vector2i(0, ROW))).is_equal(0)
	var shorter := BeltShaper.plan_line(_grid, Vector2i(0, ROW), Vector2i(WIDTH - 2, ROW), 1)
	print("shorter line: %s, %d edits" % [shorter.result.reason_text(), shorter.edits.size()])
	assert_bool(shorter.result.ok).is_true()
	for result in _grid.apply_batch(shorter.edits):
		assert_bool(result.ok).is_true()
	_expect_reachable()


func test_walls_placed_one_by_one_are_refused_at_the_one_that_closes_the_row() -> void:
	for x in WIDTH - 1:
		var placed := _grid.apply(BuildEdit.place_wall(Vector2i(x, ROW), BuildGrid.Side.NORTH))
		assert_bool(placed.ok).is_true()
	var last := Vector2i(WIDTH - 1, ROW)
	_expect_spot_refusal(_grid.apply(BuildEdit.place_wall(last, BuildGrid.Side.NORTH)))
	assert_bool(_grid.has_wall(last, BuildGrid.Side.NORTH)).is_false()
	_expect_reachable()


## A new desk whose own spot lies in a nook its footprint would seal.
func test_a_desk_that_would_seal_its_own_spot_in_is_refused() -> void:
	for cell in [
		Vector2i(8, 0),
		Vector2i(9, 0),
		Vector2i(10, 0),
		Vector2i(11, 0),
		Vector2i(8, 1),
		Vector2i(11, 1)
	]:
		assert_bool(_grid.apply(BuildEdit.remove_floor(cell)).ok).is_true()
	var sealing := _grid.apply(BuildEdit.place_object(DESK, Vector2i(9, 2), 0))
	print("sealing desk: %s, blocker %d" % [sealing.reason_text(), sealing.blocking_object_id])
	assert_bool(sealing.ok).is_false()
	assert_int(sealing.reason).is_equal(SPOT)
	assert_int(_grid.object_at(Vector2i(9, 2))).is_equal(0)
	assert_bool(_grid.staff_reach().has(Vector2i(9, 1))).is_true()


func test_the_reference_terminal_reaches_every_spot() -> void:
	var grid := BuildGrid.new()
	assert_bool(ReferenceTerminal.build(grid)).is_true()
	var ids := ReferenceTerminal.object_ids(grid)
	var start := Time.get_ticks_usec()
	var reach := StaffSpots.reach(grid)
	var usec := Time.get_ticks_usec() - start
	print("reference reach: %d cells in %d usec" % [reach.size(), usec])
	assert_int(reach.size()).is_greater(100)
	for station: int in ids["desks"] + ids["scanners"]:
		assert_bool(StaffSpots.unreachable(grid, station)).is_false()


func test_removing_the_last_entrance_while_a_spot_is_reached_is_refused() -> void:
	var entrance := _grid.object_at(Vector2i(0, 11))
	var result := _grid.apply(BuildEdit.remove_object(entrance))
	print("last entrance: %s, blocker %d" % [result.reason_text(), result.blocking_object_id])
	_expect_spot_refusal(result)
	_expect_reachable()
