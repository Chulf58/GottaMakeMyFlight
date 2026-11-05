class_name TestPullSide
extends GdUnitTestSuite
## The hand a one-bag guest pulls its roller with (PullSide; board 578435a7,
## decision roller-hand-swap-design-a-pulled-roller-keeps-its-hand-while). A
## guest walks east along a row of a BuildGrid fixture, a tick at a time, and
## each tick's hand is what PullSide.pick() answers for the bag record, kept as
## CarryOnProps keeps it (the place and the tick of a change). Walking east the
## right hand is the south side. Rows, each with RUN cells of wall:
##   RIGHT: a wall on the south edge (the pulling side);
##   LEFT: a wall on the north edge only;
##   BOTH: walls on both edges;
##   BIN: a wall on the south edge and a bin on the north cell beside each run
##     cell (its rim reaches over its cell's edge into the row).

const ROLLER := SecurityLooks.Kind.ROLLER
const RIGHT_ROW := 10
const LEFT_ROW := 20
const BOTH_ROW := 30
const BIN_ROW := 40
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
	assert_int(changes.size()).override_failure_message(str(changes)).is_equal(1)
	assert_int(changes[0][2]).is_equal(1)
	var done := int(changes[0][0]) + int(CarryOnProps.TRANSFER_TICKS)
	(
		assert_int(done)
		. override_failure_message(
			"change done at tick %d, right roller meets the wall at %d" % [done, first_hit]
		)
		. is_less_equal(first_hit)
	)


func test_the_hand_stays_left_after_the_run() -> void:
	var walk := _walk(RIGHT_ROW, WALK_M)
	var hands: Array[int] = walk["hands"]
	var xs: Array[float] = walk["xs"]
	var past := _grid.cell_to_world(Vector2i(RUN.y + 3, RIGHT_ROW)).x
	var after := 0
	for t in hands.size():
		if xs[t] > past:
			after += 1
			assert_int(hands[t]).override_failure_message("x %.2f" % xs[t]).is_equal(1)
	# Positive: the walk went on well past the run, both sides clear.
	assert_int(after).is_greater(20)
	assert_int(int(walk["bag"].get("pull_side_swaps", 0))).is_equal(1)


func test_a_left_wall_only_keeps_the_right_hand() -> void:
	var left := _walk(LEFT_ROW, WALK_M)
	assert_array(left["changes"]).is_empty()
	assert_int(int(left["bag"].get("pull_side_both", 0))).is_equal(0)
	# Control in the same fixture: the right wall does make it swap.
	var right := _walk(RIGHT_ROW, WALK_M)
	assert_int((right["changes"] as Array).size()).is_equal(1)


func test_walls_on_both_sides_keep_the_hand_and_are_counted() -> void:
	var walk := _walk(BOTH_ROW, WALK_M)
	assert_array(walk["changes"]).is_empty()
	assert_int(walk["first_hit"]).is_greater(0)
	assert_int(int(walk["bag"].get("pull_side_both", 0))).is_greater(0)


func test_a_running_guest_starts_the_change_early_enough() -> void:
	var run := _walk(RIGHT_ROW, RUN_M)
	var walk := _walk(RIGHT_ROW, WALK_M)
	var changes: Array = run["changes"]
	assert_int(changes.size()).is_equal(1)
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
	assert_int((_walk(RIGHT_ROW, WALK_M)["changes"] as Array).size()).is_equal(1)


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
