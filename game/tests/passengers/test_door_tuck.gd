class_name TestDoorTuck
extends GdUnitTestSuite
## A pulled roller tucks in line behind its guest through a one-cell doorway
## and swings back out to its side after (board cd4ff4e0, user ruling a-guest-
## pulling-a-roller-through-a-doorway-tucks-it-in-line). A guest walks north
## through a door in an east-west wall of a BuildGrid fixture, a tick at a
## time; each tick PullSide.tuck() is asked for the bag record and the roller
## is put where RollerPull.settle() keeps a straight pull (TRAIL_M behind,
## TRAIL_SIDE_M out, tucked by RollerPull.tuck_weight()). The roller's box (its
## half width either side of the axle, its length toward the guest) is tested
## against the walls as PullSide sees them. The control walk leaves the tuck
## off, as the pull was before: the box then meets a jamb.

const ROLLER := SecurityLooks.Kind.ROLLER
## The wall runs along the north edge of WALL_ROW from WALL_X0 to WALL_X1, with
## a door on the edge of DOOR_X.
const WALL_ROW := 10
const WALL_X0 := 4
const WALL_X1 := 16
const DOOR_X := 10
const START_ROW := 15
const END_ROW := 4
## A second guest walks east along OPEN_ROW, far from every wall.
const OPEN_ROW := 30
const WALK_M := PassengerSim.WALK_MM / 1000.0
const FIRST_TICK := 100.0

var _grid: BuildGrid


func before() -> void:
	_grid = BuildGrid.new()
	var edits: Array[BuildEdit] = []
	for x in range(WALL_X0, WALL_X1):
		edits.append(BuildEdit.place_wall(Vector2i(x, WALL_ROW), BuildGrid.Side.NORTH))
	# A door goes in a wall with a plain wall on each side.
	var door := BuildGrid.WallKind.DOOR
	edits.append(BuildEdit.place_wall(Vector2i(DOOR_X, WALL_ROW), BuildGrid.Side.NORTH, door))
	for result in _grid.apply_batch(edits):
		assert_bool(result.ok).override_failure_message(result.reason_text()).is_true()
	assert_int(_grid.wall_kind(Vector2i(DOOR_X, WALL_ROW), BuildGrid.Side.NORTH)).is_equal(
		BuildGrid.WallKind.DOOR
	)


func after() -> void:
	_grid = null


## The guest walking north through the door, `off` metres east of the door's
## middle, the roller pulled in `hand`; `tucks` false is the control (no
## tuck). Returns per tick: the guest's z, the tuck weight, the roller's axle
## side offset and whether its box meets a wall. With `route_ends` the route
## ends on the cell before the door, as a gate's route ends at its door out to
## the apron, and the guest walks on.
func _walk(hand: int, tucks: bool, off := 0.0, route_ends := false) -> Dictionary:
	var last := _grid.cell_to_world(Vector2i(DOOR_X, WALL_ROW)).z
	var bag := {"kind": ROLLER, "place": (SecurityLooks.Home.HAND * 2 + hand) * 2}
	var x := _grid.cell_to_world(Vector2i(DOOR_X, 0)).x + off
	var z := _grid.cell_to_world(Vector2i(DOOR_X, START_ROW)).z
	var end := _grid.cell_to_world(Vector2i(DOOR_X, END_ROW)).z
	var out := -1.0 if hand == 0 else 1.0
	var rows := {"z": [], "weight": [], "side": [], "hits": []}
	var tick := 0
	while z > end:
		var now := FIRST_TICK + tick
		var frame := Transform3D(Basis(Vector3.UP, PI), Vector3(x, 0.0, z))
		var ahead: Array = []
		for k in range(1, PullSide.AHEAD_CELLS + 1):
			if not route_ends or z - k >= last - 0.001:
				ahead.append(Vector3(x, 0.0, z - k))
		if tucks:
			PullSide.tuck(bag, _grid, frame, ahead, WALK_M, hand, now)
		var w := RollerPull.tuck_weight(bag, now)
		var trail := Vector3(out * RollerPull.TRAIL_SIDE_M, 0.0, -RollerPull.TRAIL_M)
		var axle := RollerPull.settle(trail, hand, w)
		rows["z"].append(z)
		rows["weight"].append(w)
		rows["side"].append(axle.x * out)
		rows["hits"].append(PullSide.blocked(_grid, [frame], _roller_box(axle), false))
		z -= WALK_M
		tick += 1
	return rows


## The roller's box round axle `axle` (the guest's frame), toward the guest.
static func _roller_box(axle: Vector3) -> AABB:
	var size := CarryOnProps.bag_box(ROLLER).size
	var half := size.x * 0.5
	return AABB(Vector3(axle.x - half, 0.0, axle.z), Vector3(half * 2.0, size.z, size.z))


func test_the_untucked_roller_meets_a_jamb_in_the_doorway() -> void:
	# Control: the side offset reaches past the jamb face (0.43 m out).
	for hand in 2:
		var rows := _walk(hand, false)
		var hits := (rows["hits"] as Array).count(true)
		assert_int(hits).override_failure_message("hand %d: no jamb hit" % hand).is_greater(0)


func test_the_tucked_roller_clears_the_jambs() -> void:
	for hand in 2:
		for off in [0.0, 0.05, -0.05]:
			var rows := _walk(hand, true, off)
			var hits := (rows["hits"] as Array).count(true)
			(
				assert_int(hits)
				. override_failure_message(
					"hand %d off %.2f: %d ticks in a jamb" % [hand, off, hits]
				)
				. is_equal(0)
			)


func test_a_route_ending_at_the_door_still_tucks_in_time() -> void:
	for hand in 2:
		var control := (_walk(hand, false, 0.0, true)["hits"] as Array).count(true)
		assert_int(control).override_failure_message("no jamb hit").is_greater(0)
		var hits := (_walk(hand, true, 0.0, true)["hits"] as Array).count(true)
		(
			assert_int(hits)
			. override_failure_message("hand %d: %d ticks in a jamb" % [hand, hits])
			. is_equal(0)
		)


func test_the_roller_tucks_in_line_and_swings_back_out_after() -> void:
	var rows := _walk(0, true)
	var weights: Array = rows["weight"]
	var sides: Array = rows["side"]
	# Out at its side before the door, in line through it, out again after.
	assert_float(weights[0]).is_equal(0.0)
	assert_float(weights.max()).is_equal(1.0)
	assert_float(weights[-1]).is_equal(0.0)
	assert_float(sides[0]).is_equal_approx(RollerPull.TRAIL_SIDE_M, 0.001)
	assert_float(sides.min()).is_equal_approx(RollerPull.TUCK_SIDE_M, 0.001)
	assert_float(sides[-1]).is_equal_approx(RollerPull.TRAIL_SIDE_M, 0.001)
	# One tuck, not on and off at each jamb.
	var ups := 0
	for k in range(1, weights.size()):
		ups += int(weights[k] > weights[k - 1] and weights[k - 1] == 0.0)
	assert_int(ups).is_equal(1)


func test_the_tuck_eases_in_and_out_with_no_jump() -> void:
	var sides: Array = _walk(1, true)["side"]
	var most := 0.0
	for k in range(1, sides.size()):
		most = maxf(most, absf(float(sides[k]) - float(sides[k - 1])))
	# smoothstep's steepest slope is 1.5 a tick over TUCK_TICKS.
	var limit := (
		(RollerPull.TRAIL_SIDE_M - RollerPull.TUCK_SIDE_M) * 1.5 / RollerPull.TUCK_TICKS + 0.001
	)
	assert_float(most).is_greater(0.0)
	assert_float(most).is_less_equal(limit)


func test_an_open_walk_never_tucks() -> void:
	var bag := {"kind": ROLLER, "place": (SecurityLooks.Home.HAND * 2) * 2}
	var at := _grid.cell_to_world(Vector2i(4, OPEN_ROW))
	for tick in 40:
		var x := at.x + tick * WALK_M
		var frame := Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(x, 0.0, at.z))
		var ahead: Array = [Vector3(x + 1.0, 0.0, at.z), Vector3(x + 2.0, 0.0, at.z)]
		PullSide.tuck(bag, _grid, frame, ahead, WALK_M, 0, FIRST_TICK + tick)
		assert_float(RollerPull.tuck_weight(bag, FIRST_TICK + tick)).is_equal(0.0)


func test_standing_still_keeps_the_tuck() -> void:
	var bag := {"kind": ROLLER, "place": (SecurityLooks.Home.HAND * 2) * 2}
	RollerPull.tuck(bag, true, FIRST_TICK)
	var at := _grid.cell_to_world(Vector2i(4, OPEN_ROW))
	var frame := Transform3D(Basis(Vector3.UP, PI / 2.0), at)
	PullSide.tuck(bag, _grid, frame, [], 0.0, 0, FIRST_TICK + 20.0)
	assert_float(RollerPull.tuck_weight(bag, FIRST_TICK + 20.0)).is_equal(1.0)


func test_hand_of_does_not_take_a_tucked_roller_across() -> void:
	# hand_of() says left (a wall beside the guest on the right) while the
	# roller is tucked on the right: it stays on the right.
	var at := _grid.cell_to_world(Vector2i(DOOR_X, WALL_ROW))
	var frame := Transform3D(Basis(Vector3.UP, PI), at)
	var ahead: Array = [at + Vector3(0, 0, -1), at + Vector3(0, 0, -2)]
	var bag := {"kind": ROLLER, "place": (SecurityLooks.Home.HAND * 2) * 2}
	var told := PullSide.pick(bag.duplicate(), _grid, frame, ahead, WALK_M, 1, FIRST_TICK)
	assert_int(told).override_failure_message("control: hand_of() moves it").is_equal(1)
	RollerPull.tuck(bag, true, FIRST_TICK - 10.0)
	assert_int(PullSide.pick(bag, _grid, frame, ahead, WALK_M, 1, FIRST_TICK)).is_equal(0)
