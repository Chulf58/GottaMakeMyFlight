class_name TestPullSide
extends GdUnitTestSuite
## The hand a one-bag guest pulls its roller with (PullSide; board 578435a7,
## decision roller-hand-swap-design-a-pulled-roller-keeps-its-hand-while as
## amended by pullside-amendment-the-roller-goes-back-to-the-right-hand-on). A
## guest walks east along a row of a BuildGrid fixture, a tick at a time, and
## each tick's hand is what PullSide.pick() answers for the bag record, kept as
## CarryOnProps keeps it (the place, the tick of a change and the drawn axle
## TRAIL_M behind on the pulling side). Walking east the
## right hand is the south side. Rows, each with RUN cells of wall:
##   RIGHT: a wall on the south edge (the pulling side);
##   LEFT: a wall on the north edge only;
##   BOTH: walls on both edges;
##   BIN: a wall on the south edge and a bin on the north cell beside each run
##     cell (its rim reaches over its cell's edge into the row);
##   FURNITURE: a bin on the south cell beside each run cell, no wall;
##   OPEN: nothing.

const ROLLER := SecurityLooks.Kind.ROLLER
const RIGHT_ROW := 10
const LEFT_ROW := 20
const BOTH_ROW := 30
const BIN_ROW := 40
const FURNITURE_ROW := 50
const OPEN_ROW := 60
const RUN := Vector2i(18, 24)
const START_X := 10
const END_X := 32
const WALK_M := PassengerSim.WALK_MM / 1000.0
const RUN_M := PassengerSim.RUN_MM / 1000.0
const FIRST_TICK := 100.0

var _grid: BuildGrid


func before() -> void:
	_grid = BuildGrid.new()
	var edits: Array[BuildEdit] = []
	for x in range(RUN.x, RUN.y):
		edits.append(BuildEdit.place_wall(Vector2i(x, RIGHT_ROW), BuildGrid.Side.SOUTH))
		edits.append(BuildEdit.place_wall(Vector2i(x, LEFT_ROW), BuildGrid.Side.NORTH))
		edits.append(BuildEdit.place_wall(Vector2i(x, BOTH_ROW), BuildGrid.Side.NORTH))
		edits.append(BuildEdit.place_wall(Vector2i(x, BOTH_ROW), BuildGrid.Side.SOUTH))
		edits.append(BuildEdit.place_wall(Vector2i(x, BIN_ROW), BuildGrid.Side.SOUTH))
		edits.append(BuildEdit.paint_floor(Vector2i(x, BIN_ROW - 1), BuildGrid.FLOOR_TILE, 1))
		edits.append(BuildEdit.place_object(&"trash_can", Vector2i(x, BIN_ROW - 1), 0))
		edits.append(BuildEdit.paint_floor(Vector2i(x, FURNITURE_ROW + 1), BuildGrid.FLOOR_TILE, 1))
		edits.append(BuildEdit.place_object(&"trash_can", Vector2i(x, FURNITURE_ROW + 1), 0))
	for result in _grid.apply_batch(edits):
		assert_bool(result.ok).override_failure_message(result.reason_text()).is_true()


func after() -> void:
	_grid = null


## The place CarryOnProps gives a roller pulled in `hand`.
static func _place(hand: int) -> int:
	return (SecurityLooks.Home.HAND * 2 + hand) * 2


## The guest's pose at `x` (world) on `row`, facing east.
func _pose(row: int, x: float) -> Transform3D:
	var at := _grid.cell_to_world(Vector2i(0, row))
	return Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(x, at.y, at.z))


## The route cells ahead of `x` on `row`, as world points (PullSide.resolve()).
func _ahead(row: int, x: float) -> Array:
	var out: Array = []
	for cx in range(START_X, END_X + 1):
		var at := _grid.cell_to_world(Vector2i(cx, row))
		if at.x > x + 0.001 and out.size() < PullSide.AHEAD_CELLS:
			out.append(at)
	return out


## Walks `row` east at `step_m` a tick from START_X to END_X, starting in
## `hand`. Returns {"bag", "hands" (one a tick), "xs", "first_hit" (the first
## tick the right roller's settled footprint meets a wall where the guest is,
## -1 for none), "changes" ([tick, x, hand] each)}.
func _walk(row: int, step_m: float, hand := 0) -> Dictionary:
	var bag := {"kind": ROLLER, "place": _place(hand)}
	var hands: Array[int] = []
	var xs: Array[float] = []
	var changes: Array = []
	var first_hit := -1
	var x := _grid.cell_to_world(Vector2i(START_X, row)).x
	var end := _grid.cell_to_world(Vector2i(END_X, row)).x
	var tick := 0
	while x < end:
		var now := FIRST_TICK + tick
		var frame := _pose(row, x)
		var picked := PullSide.pick(bag, _grid, frame, _ahead(row, x), step_m, hand, now)
		if picked != CarryLead.hand_of(bag["place"]):
			bag["place"] = _place(picked)
			bag["changed"] = now
			changes.append([tick, x, picked])
		var out := -1.0 if picked == 0 else 1.0
		bag["drawn_axle"] = (
			frame * Vector3(out * CarryOnProps.TRAIL_SIDE_M, 0.0, -CarryOnProps.TRAIL_M)
		)
		hands.append(picked)
		xs.append(x)
		var right := PullSide.footprint(0, false)
		if first_hit < 0 and PullSide.blocked(_grid, [frame], right, false):
			first_hit = tick
		x += step_m
		tick += 1
	return {"bag": bag, "hands": hands, "xs": xs, "first_hit": first_hit, "changes": changes}


func test_a_right_wall_ahead_swaps_to_the_left_before_the_roller_reaches_it() -> void:
	var walk := _walk(RIGHT_ROW, WALK_M)
	var changes: Array = walk["changes"]
	var first_hit: int = walk["first_hit"]
	# Control: the right roller would meet the wall on this walk.
	assert_int(first_hit).override_failure_message("no wall on the walk").is_greater(0)
	assert_int(changes.size()).override_failure_message(str(changes)).is_equal(2)
	assert_int(changes[0][2]).is_equal(1)
	var done := int(changes[0][0]) + int(CarryOnProps.TRANSFER_TICKS)
	(
		assert_int(done)
		. override_failure_message(
			"change done at tick %d, right roller meets the wall at %d" % [done, first_hit]
		)
		. is_less_equal(first_hit)
	)


func test_the_roller_goes_back_to_the_right_once_past_the_wall() -> void:
	var walk := _walk(RIGHT_ROW, WALK_M)
	var changes: Array = walk["changes"]
	var hands: Array[int] = walk["hands"]
	var xs: Array[float] = walk["xs"]
	assert_int(changes.size()).override_failure_message(str(changes)).is_equal(2)
	assert_int(changes[0][2]).is_equal(1)
	assert_int(changes[1][2]).is_equal(0)
	assert_int(int(walk["bag"].get("pull_side_returns", 0))).is_equal(1)
	# The wall's east end, and where the guest was when the roller went back.
	var wall_end := _grid.cell_to_world(Vector2i(RUN.y, RIGHT_ROW)).x - 0.5
	var back_x: float = changes[1][1]
	(
		assert_float(back_x - wall_end)
		. override_failure_message("went back %.2f m past the wall's end" % (back_x - wall_end))
		. is_greater(CarryOnProps.TRAIL_M)
	)
	# On the left the whole run, and the right's reach footprint meets no wall
	# from the tick it went back to the end of the walk.
	var right := PullSide.footprint(0, true)
	var after := 0
	for t in hands.size():
		var x := xs[t]
		if x > wall_end - 1.0 and x < back_x - 0.001:
			assert_int(hands[t]).override_failure_message("x %.2f" % x).is_equal(1)
		if x >= back_x:
			after += 1
			assert_int(hands[t]).is_equal(0)
			assert_bool(PullSide.blocked(_grid, [_pose(RIGHT_ROW, x)], right, true)).is_false()
	assert_int(after).is_greater(5)


func test_the_left_hand_holds_for_the_minimum_hold() -> void:
	var x := _grid.cell_to_world(Vector2i(RUN.x + 2, OPEN_ROW)).x
	var frame := _pose(OPEN_ROW, x)
	var ahead := _ahead(OPEN_ROW, x)
	var now := FIRST_TICK + 50.0
	var left := {"kind": ROLLER, "place": _place(1)}
	left["drawn_axle"] = frame * Vector3(CarryOnProps.TRAIL_SIDE_M, 0.0, -CarryOnProps.TRAIL_M)
	left["changed"] = now - PullSide.HOLD_TICKS + 1.0
	assert_int(PullSide.pick(left, _grid, frame, ahead, WALK_M, 0, now)).is_equal(1)
	# Past the hold it goes back to the right on the same open floor.
	left["changed"] = now - PullSide.HOLD_TICKS
	assert_int(PullSide.pick(left, _grid, frame, ahead, WALK_M, 0, now)).is_equal(0)
	assert_int(int(left.get("pull_side_returns", 0))).is_equal(1)
	# Not while SecurityLooks.hand_of() finds the right closed beside the guest.
	var closed := {"kind": ROLLER, "place": _place(1), "changed": now - 100.0}
	assert_int(PullSide.pick(closed, _grid, frame, ahead, WALK_M, 1, now)).is_equal(1)
	# The hold is longer than the probe's 12-tick swap-back window.
	assert_float(PullSide.HOLD_TICKS).is_greater(12.0)


func test_furniture_on_the_pulling_side_swaps_to_the_left() -> void:
	var walk := _walk(FURNITURE_ROW, WALK_M)
	var changes: Array = walk["changes"]
	# Control: the bins, not a wall, are in the right roller's reach footprint.
	var frame := _pose(FURNITURE_ROW, _grid.cell_to_world(Vector2i(RUN.x + 2, FURNITURE_ROW)).x)
	var right := PullSide.footprint(0, true)
	assert_bool(PullSide.blocked(_grid, [frame], right, true)).is_true()
	assert_bool(PullSide.blocked(_grid, [frame], right, false)).is_false()
	assert_int(changes.size()).override_failure_message(str(changes)).is_greater_equal(1)
	assert_int(changes[0][2]).is_equal(1)
	var first_bin := _grid.cell_to_world(Vector2i(RUN.x, FURNITURE_ROW)).x - 0.5
	assert_float(changes[0][1]).is_less(first_bin)


func test_a_change_of_hand_starts_the_trail_behind_on_the_new_side() -> void:
	var x := _grid.cell_to_world(Vector2i(RUN.x + 2, RIGHT_ROW)).x
	var frame := _pose(RIGHT_ROW, x)
	var now := FIRST_TICK + 50.0
	var bag := {"kind": ROLLER, "place": _place(0), "changed": now - 20.0}
	# The right side's walked line, as CarryOnProps._trail() keeps it.
	var walked: Array = []
	for k in 11:
		walked.append(frame * Vector3(-CarryOnProps.TRAIL_SIDE_M, 0.0, -2.0 + k * 0.2))
	bag["walked"] = walked
	var right_axle := frame * Vector3(-CarryOnProps.TRAIL_SIDE_M, 0.0, -CarryOnProps.TRAIL_M)
	bag["drawn_axle"] = right_axle
	var picked := PullSide.pick(bag, _grid, frame, _ahead(RIGHT_ROW, x), WALK_M, 0, now)
	assert_int(picked).is_equal(1)
	# The next trail step (CarryOnProps._trail()): the left line's point now on
	# what is left of the walked line, kept on the left and behind.
	var line: Array = bag.get("walked", [])
	line.append(frame * Vector3(CarryOnProps.TRAIL_SIDE_M, 0.0, 0.0))
	var local := frame.affine_inverse() * CarryOnProps.trail(line, frame.basis * Vector3.FORWARD)
	local.x = clampf(local.x, CarryOnProps.TRAIL_SIDE_MIN_M, CarryOnProps.TRAIL_SIDE_MAX_M)
	local.z = minf(local.z, -CarryOnProps.TRAIL_BEHIND_MIN_M)
	# Straight behind on the left's own line, not pulled in to the clamps by
	# the jump across the legs at the end of the right's line.
	assert_float(local.x).is_equal_approx(CarryOnProps.TRAIL_SIDE_M, 0.01)
	assert_float(-local.z).is_equal_approx(CarryOnProps.TRAIL_M, 0.01)
	# The drawn axle swings across to it (CarryOnProps.follow()) behind the
	# legs: wherever it is nearer the centre line than TRAIL_SIDE_MIN_M it is
	# at least TRAIL_BEHIND_MIN_M behind, and it gets there.
	var at := frame.affine_inverse() * right_axle
	var crossed := 0
	for step in 30:
		at = CarryOnProps.follow(at, local, 1.0 / 3.0, 1)
		if absf(at.x) < CarryOnProps.TRAIL_SIDE_MIN_M:
			crossed += 1
			assert_float(-at.z).is_greater_equal(CarryOnProps.TRAIL_BEHIND_MIN_M)
	assert_int(crossed).is_greater(0)
	assert_float(at.x).is_equal_approx(local.x, 0.01)


func test_a_left_wall_only_keeps_the_right_hand() -> void:
	var left := _walk(LEFT_ROW, WALK_M)
	assert_array(left["changes"]).is_empty()
	assert_int(int(left["bag"].get("pull_side_both", 0))).is_equal(0)
	# Control in the same fixture: the right wall does make it swap.
	var right := _walk(RIGHT_ROW, WALK_M)
	assert_int((right["changes"] as Array).size()).is_equal(2)


func test_walls_on_both_sides_keep_the_hand_and_are_counted() -> void:
	var walk := _walk(BOTH_ROW, WALK_M)
	assert_array(walk["changes"]).is_empty()
	assert_int(walk["first_hit"]).is_greater(0)
	assert_int(int(walk["bag"].get("pull_side_both", 0))).is_greater(0)


func test_a_running_guest_starts_the_change_early_enough() -> void:
	var run := _walk(RIGHT_ROW, RUN_M)
	var walk := _walk(RIGHT_ROW, WALK_M)
	var changes: Array = run["changes"]
	assert_int(changes.size()).is_equal(2)
	var done := int(changes[0][0]) + int(CarryOnProps.TRANSFER_TICKS)
	assert_int(run["first_hit"]).is_greater(0)
	(
		assert_int(done)
		. override_failure_message(
			"running: change done at %d, roller meets the wall at %d" % [done, run["first_hit"]]
		)
		. is_less_equal(run["first_hit"])
	)
	# The look-ahead scales with speed: the runner starts further from the wall.
	var run_x: float = changes[0][1]
	var walk_x: float = walk["changes"][0][1]
	(
		assert_float(walk_x - run_x)
		. override_failure_message("started at x %.2f running, %.2f walking" % [run_x, walk_x])
		. is_greater(0.3)
	)


func test_furniture_on_the_destination_side_vetoes_the_swap() -> void:
	var walk := _walk(BIN_ROW, WALK_M)
	# The bins' rims are in the left roller's settled footprint, and no wall is.
	var frame := _pose(BIN_ROW, _grid.cell_to_world(Vector2i(RUN.x + 2, BIN_ROW)).x)
	var left := PullSide.footprint(1, false)
	assert_bool(PullSide.blocked(_grid, [frame], left, true)).is_true()
	assert_bool(PullSide.blocked(_grid, [frame], left, false)).is_false()
	assert_array(walk["changes"]).is_empty()
	assert_int(int(walk["bag"].get("pull_side_both", 0))).is_greater(0)
	# Control: the same wall without the bins swaps.
	assert_int((_walk(RIGHT_ROW, WALK_M)["changes"] as Array).size()).is_equal(2)


func test_the_hand_holds_mid_transfer_mid_park_and_standing_still() -> void:
	var x := _grid.cell_to_world(Vector2i(RUN.x + 2, RIGHT_ROW)).x
	var frame := _pose(RIGHT_ROW, x)
	var ahead := _ahead(RIGHT_ROW, x)
	var now := FIRST_TICK + 50.0
	# Control: settled, by the wall, it goes to the left.
	var settled := {"kind": ROLLER, "place": _place(0), "changed": now - 20.0}
	assert_int(PullSide.pick(settled, _grid, frame, ahead, WALK_M, 0, now)).is_equal(1)
	var moving := {"kind": ROLLER, "place": _place(0), "changed": now - 2.0}
	assert_int(PullSide.pick(moving, _grid, frame, ahead, WALK_M, 0, now)).is_equal(0)
	var parking := {
		"kind": ROLLER, "place": _place(0), "changed": now - 20.0, "park": true, "since": now - 1.0
	}
	assert_int(PullSide.pick(parking, _grid, frame, ahead, WALK_M, 0, now)).is_equal(0)
	var still := {"kind": ROLLER, "place": _place(0), "changed": now - 20.0}
	assert_int(PullSide.pick(still, _grid, frame, ahead, 0.0, 0, now)).is_equal(0)
	for bag in [moving, parking, still]:
		assert_int(int(bag.get("pull_side_swaps", 0))).is_equal(0)


func test_in_a_queue_the_roller_is_in_hand_ofs_hand() -> void:
	# Walking up to its cafe queue spot or standing at it, the roller is in
	# SecurityLooks.hand_of()'s hand, either way and with no hold after a change
	# of hand, so it is stood up (RollerPark.queue_stand()) where hand_of()
	# puts it, as before PullSide.
	var x := _grid.cell_to_world(Vector2i(RUN.x + 2, OPEN_ROW)).x
	var frame := _pose(OPEN_ROW, x)
	var ahead := _ahead(OPEN_ROW, x)
	var now := FIRST_TICK + 50.0
	var since := now - CarryOnProps.TRANSFER_TICKS - 1.0
	for step_m in [WALK_M, 0.0]:
		var left := {"kind": ROLLER, "place": _place(1), "was": _place(0), "changed": since}
		assert_int(PullSide.pick(left, _grid, frame, ahead, step_m, 0, now, true)).is_equal(0)
		var right := {"kind": ROLLER, "place": _place(0), "was": _place(1), "changed": since}
		assert_int(PullSide.pick(right, _grid, frame, ahead, step_m, 1, now, true)).is_equal(1)
		assert_int(int(right.get("pull_side_queue", 0))).is_equal(1)
	# Not while its move is under way.
	var moving := {"kind": ROLLER, "place": _place(1), "was": _place(0), "changed": now - 1.0}
	assert_int(PullSide.pick(moving, _grid, frame, ahead, 0.0, 0, now, true)).is_equal(1)
	# Control: out of a queue, standing still it holds and walking it keeps
	# the left for the hold after a change of hand.
	for step_m in [WALK_M, 0.0]:
		var out := {"kind": ROLLER, "place": _place(1), "was": _place(0), "changed": since}
		assert_int(PullSide.pick(out, _grid, frame, ahead, step_m, 0, now)).is_equal(1)


func test_a_roller_stood_up_in_a_queue_leaves_it_in_hand_ofs_hand() -> void:
	# Stood up on the left at a cafe queue spot, the guest turns out of the
	# queue to its seat with hand_of() on the right: the change of hand carries
	# the roller round, as before PullSide, where kept on the left its trail
	# swung into a cafe table.
	var x := _grid.cell_to_world(Vector2i(RUN.x + 2, OPEN_ROW)).x
	var frame := _pose(OPEN_ROW, x)
	var ahead := _ahead(OPEN_ROW, x)
	var now := FIRST_TICK + 50.0
	var ticks := 20.0
	var stand := {"kind": ROLLER, "place": _place(1), "was": _place(1), "park": true}
	stand.merge({"queue": true, "ticks": ticks, "since": now - ticks - 1.0, "changed": now - 30.0})
	assert_bool(PullSide.holds(stand, now)).is_false()
	assert_bool(PullSide.stood(stand, now)).is_true()
	assert_int(PullSide.pick(stand.duplicate(), _grid, frame, ahead, WALK_M, 0, now)).is_equal(0)
	# Control: once LOOK_TICKS past the stand's end the roller keeps its hand.
	var later := now + PullSide.LOOK_TICKS
	assert_bool(PullSide.stood(stand, later)).is_false()
	stand["changed"] = later - PullSide.HOLD_TICKS + 1.0
	assert_int(PullSide.pick(stand, _grid, frame, ahead, WALK_M, 0, later)).is_equal(1)


func test_hand_of_moves_a_set_down_roller_without_the_hold() -> void:
	# A new guest's roller is set down in hand_of()'s hand before its route is
	# walked (the right); a tick later hand_of() says left. Held on the right,
	# it swung behind the legs as the guest turned left onto its route.
	var x := _grid.cell_to_world(Vector2i(RUN.x + 2, OPEN_ROW)).x
	var frame := _pose(OPEN_ROW, x)
	var ahead := _ahead(OPEN_ROW, x)
	var now := FIRST_TICK + 50.0
	var since := now - CarryOnProps.TRANSFER_TICKS - 2.0
	assert_float(now - since).is_less(PullSide.HOLD_TICKS)
	var set_down := {"kind": ROLLER, "place": _place(0), "was": -1, "changed": since}
	assert_bool(PullSide.swapped(set_down)).is_false()
	assert_int(PullSide.pick(set_down, _grid, frame, ahead, WALK_M, 1, now)).is_equal(1)
	# After PullSide's own change to the right the hold stands.
	var swapped := {"kind": ROLLER, "place": _place(0), "was": _place(1), "changed": since}
	assert_bool(PullSide.swapped(swapped)).is_true()
	assert_int(PullSide.pick(swapped, _grid, frame, ahead, WALK_M, 1, now)).is_equal(0)
	swapped["changed"] = now - PullSide.HOLD_TICKS
	assert_int(PullSide.pick(swapped, _grid, frame, ahead, WALK_M, 1, now)).is_equal(1)
