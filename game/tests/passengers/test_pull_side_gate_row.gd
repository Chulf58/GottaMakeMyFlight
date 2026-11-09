class_name TestPullSideGateRow
extends GdUnitTestSuite
## A guest walking along a row of gate chair fronts to its own chair pulls its
## roller in the hand ParkSide stamped for that chair, with no change of hand
## on the way (board 3c591192). Walking along the row, the chairs on the
## guest's side reach into the pulled roller's REACH footprint
## (PullSide.footprint(hand, true)) and PullSide changed hands away from them,
## then laid the roller down from the wrong hand onto the stamped side. The
## reference terminal's seat row at fronts (11..16, 4), seats one cell north:
## pair1_a of the windowed gate_chair_roller_probe (seed 4242) walks west from
## (17, 4) to its front (14, 4), the chairs on its right. The stamp gives way
## where the stamped side's SETTLED footprint meets a wall or a piece: a bin
## grid has a bin on the south cell beside each cell of BIN_ROW, the right
## side walking east.

const ROLLER := SecurityLooks.Kind.ROLLER
const WALK_M := PassengerSim.WALK_MM / 1000.0
const FIRST_TICK := 100.0
const FRONT := Vector2i(14, 4)
const START := Vector2i(17, 4)
const BIN_ROW := 10
const BIN_RUN := Vector2i(8, 16)
## A row with a bin on the north cell beside each cell: the left walking east.
const LEFT_BIN_ROW := 20

var _world: PassengerTestWorld
var _views: PassengerViews
var _grid: BuildGrid
var _bins: BuildGrid
var _seat: Dictionary = {}


func before() -> void:
	PassengerTestWorld.tracker = self
	_world = PassengerTestWorld.reference_world()
	_world.run_to(10)
	_grid = _world.sim.grid
	_views = PassengerTestWorld.views()
	_views.clock = _world.clock
	_views.sim = _world.sim
	add_child(_views)
	for s: Dictionary in _world.sim.layout.seats:
		if s["front"] == FRONT:
			_seat = s
	_bins = BuildGrid.new()
	var edits: Array[BuildEdit] = []
	for x in range(BIN_RUN.x, BIN_RUN.y):
		edits.append(BuildEdit.paint_floor(Vector2i(x, BIN_ROW + 1), BuildGrid.FLOOR_TILE, 1))
		edits.append(BuildEdit.place_object(&"trash_can", Vector2i(x, BIN_ROW + 1), 0))
		edits.append(BuildEdit.paint_floor(Vector2i(x, LEFT_BIN_ROW - 1), BuildGrid.FLOOR_TILE, 1))
		edits.append(BuildEdit.place_object(&"trash_can", Vector2i(x, LEFT_BIN_ROW - 1), 0))
	for result in _bins.apply_batch(edits):
		assert_bool(result.ok).override_failure_message(result.reason_text()).is_true()


func after() -> void:
	_views.free()
	_world.free_all()
	_world = null
	_grid = null
	_bins = null
	PassengerTestWorld.tracker = null


## A new one-bag roller guest bound for the seat at FRONT (TO_GATE), at `at`,
## its path from `at` to the front.
func _bound_guest(at: Vector2i) -> Passenger:
	var p: Passenger = null
	for attempt in 400:
		p = _world.passenger(_world.sim.spawn_now(PassengerTestWorld.FLIGHT))
		if SecurityLooks.bag_kind(p, 0) == ROLLER:
			break
		p.carry_on = 0
	ToiletTestLayout.calm(p)
	p.carry_on = 1
	p.cleared = true
	p.stage = Passenger.Stage.TO_GATE
	p.seat_object = _seat["object_id"]
	p.seat_cell = _seat["cell"]
	p.seat_front = _seat["front"]
	p.at = at
	var path: Array[Vector2i] = []
	for x in range(at.x, FRONT.x - 1, -1):
		path.append(Vector2i(x, FRONT.y))
	p.set_path(path)
	return p


## The place CarryOnProps gives a roller pulled in `hand`.
static func _place(hand: int) -> int:
	return (SecurityLooks.Home.HAND * 2 + hand) * 2


## Walks from START west to FRONT at WALK_M a tick in the right hand, the
## stamped hand (first) the right, PullSide.pick() each tick with `parked`,
## kept as CarryOnProps keeps the record. Returns {"changes" ([dist, hand]
## each), "threatened" (ticks the right's REACH footprint met furniture),
## "settled" (ticks the right's SETTLED footprint met a wall or furniture)}.
func _walk(parked: bool) -> Dictionary:
	var bag := {"kind": ROLLER, "place": _place(0)}
	var front := _grid.cell_to_world(FRONT)
	var start := _grid.cell_to_world(START)
	var way := (front - start).normalized()
	var basis := Basis(Vector3.UP, atan2(way.x, way.z))
	var changes: Array = []
	var threatened := 0
	var settled := 0
	var at := start
	var tick := 0
	while (front - at).dot(way) > 0.001:
		var now := FIRST_TICK + tick
		var frame := Transform3D(basis, at)
		var ahead: Array = []
		for n in range(1, PullSide.AHEAD_CELLS + 1):
			var cell := _grid.world_to_cell(at) + Vector2i(roundi(way.x), roundi(way.z)) * n
			if (front - _grid.cell_to_world(cell)).dot(way) >= -0.001:
				ahead.append(_grid.cell_to_world(cell))
		var poses := PullSide.walk_poses(frame, ahead, WALK_M * PullSide.LOOK_TICKS)
		threatened += int(PullSide.blocked(_grid, poses, PullSide.footprint(0, true), true))
		settled += int(PullSide.blocked(_grid, [frame], PullSide.footprint(0, false), true))
		var picked := PullSide.pick(bag, _grid, frame, ahead, WALK_M, 0, now, false, parked)
		if picked != CarryLead.hand_of(bag["place"]):
			bag["was"] = bag["place"]
			bag["place"] = _place(picked)
			bag["changed"] = now
			changes.append([snappedf(front.distance_to(at), 0.01), picked])
		var out := -1.0 if picked == 0 else 1.0
		bag["drawn_axle"] = frame * Vector3(out * RollerPull.TRAIL_SIDE_M, 0.0, -RollerPull.TRAIL_M)
		at += way * WALK_M
		tick += 1
	return {"changes": changes, "threatened": threatened, "settled": settled}


func test_the_row_is_a_row_of_chairs_on_the_walkers_right() -> void:
	for x in range(11, 17):
		assert_int(_grid.object_at(Vector2i(x, FRONT.y - 1))).is_not_equal(0)
		assert_int(_grid.object_at(Vector2i(x, FRONT.y))).is_equal(0)


func test_bound_for_its_stamped_chair_the_roller_keeps_the_stamped_hand() -> void:
	var walk := _walk(true)
	print("GATE_ROW parked %s" % walk)
	# Control: the chairs threaten the right's reach on this walk, and without
	# the stamp PullSide changes hands away from them.
	assert_int(int(walk["threatened"])).is_greater(0)
	var free := _walk(false)
	print("GATE_ROW not parked %s" % free)
	assert_int((free["changes"] as Array).size()).is_greater(0)
	assert_int(int((free["changes"] as Array)[0][1])).is_equal(1)
	assert_array(walk["changes"] as Array).is_empty()
	# The right roller pulled straight (its settled footprint) meets no chair:
	# keeping it there does not run it into the row.
	assert_int(int(walk["settled"])).is_equal(0)


func test_a_roller_in_the_other_hand_goes_to_the_stamped_hand() -> void:
	var front := _grid.cell_to_world(FRONT)
	var frame := Transform3D(Basis(Vector3.UP, -PI / 2.0), front + Vector3(2.0, 0.0, 0.0))
	var ahead := [front + Vector3(1.0, 0.0, 0.0), front]
	var now := FIRST_TICK + 50.0
	var since := now - CarryOnProps.TRANSFER_TICKS - 1.0
	var left := {"kind": ROLLER, "place": _place(1), "was": _place(0), "changed": since}
	assert_int(PullSide.pick(left, _grid, frame, ahead, WALK_M, 0, now, false, true)).is_equal(0)
	assert_int(int(left.get("pull_side_park", 0))).is_equal(1)
	# Not while its move is under way.
	var moving := {"kind": ROLLER, "place": _place(1), "was": _place(0), "changed": now - 1.0}
	assert_int(PullSide.pick(moving, _grid, frame, ahead, WALK_M, 0, now, false, true)).is_equal(1)


func test_gate_stamped_is_true_only_for_the_stamped_chair_bound_for() -> void:
	assert_bool(_seat.is_empty()).is_false()
	var p := _bound_guest(START + Vector2i(ParkSide.NEAR_CELLS, 0))
	# Too far out for ParkSide to choose: no stamp yet.
	SecurityLooks.hand_of(_world.sim, p, 0)
	assert_bool(PullSide.gate_stamped(_world.sim, p)).is_false()
	p.at = START
	SecurityLooks.hand_of(_world.sim, p, 0)
	assert_bool(PullSide.gate_stamped(_world.sim, p)).is_true()
	# A stamp for another seat is not this chair's.
	var stamps: Dictionary = _world.sim.get_meta(ParkSide.STAMPS)
	stamps[p.id] = ["gate %s" % (_seat["cell"] + Vector2i(1, 0)), 0]
	assert_bool(PullSide.gate_stamped(_world.sim, p)).is_false()
	# Off to board, the guest is no longer bound for the chair.
	SecurityLooks.hand_of(_world.sim, p, 0)
	p.stage = Passenger.Stage.TO_EXIT
	assert_bool(PullSide.gate_stamped(_world.sim, p)).is_false()


## PullSide.resolve() for guest `p` drawn 2 m from FRONT on its walk west,
## having stepped WALK_M, its roller drawn in `drawn`, last changed long ago.
## Returns [the hand resolve() sets, the bag record].
func _resolve(p: Passenger, drawn: int) -> Array:
	var front := _grid.cell_to_world(FRONT)
	var at := front + Vector3(2.0, 0.0, 0.0)
	# Set in this call, with no frame between: the views' own sync cannot move them.
	_views._cur[p.id] = at
	_views._prev[p.id] = at + Vector3(WALK_M, 0.0, 0.0)
	var now := FIRST_TICK + 50.0
	var bag := {"kind": ROLLER, "place": _place(drawn), "was": _place(1 - drawn), "changed": 0.0}
	var hands := [SecurityLooks.hand_of(_world.sim, p, 0)]
	PullSide.resolve(
		[bag], _world.sim, _views, p, [ROLLER], [SecurityLooks.Home.HAND], [false], hands, now
	)
	return [hands[0], bag]


func test_resolve_keeps_a_stamped_guests_roller_in_the_stamped_hand() -> void:
	var p := _bound_guest(Vector2i(16, FRONT.y))
	SecurityLooks.hand_of(_world.sim, p, 0)
	assert_bool(PullSide.gate_stamped(_world.sim, p)).is_true()
	var stamped: int = (_world.sim.get_meta(ParkSide.STAMPS) as Dictionary)[p.id][1]
	assert_int(stamped).is_equal(0)
	var kept := _resolve(p, 0)
	assert_int(int(kept[0])).is_equal(0)
	assert_int(int((kept[1] as Dictionary).get("pull_side_swaps", 0))).is_equal(0)
	var back := _resolve(p, 1)
	assert_int(int(back[0])).is_equal(0)
	assert_int(int((back[1] as Dictionary).get("pull_side_park", 0))).is_equal(1)
	# Control: the same walk not bound for a chair (no stamp) swaps away from
	# the chairs on the right, so it is the stamp that holds the hand.
	p.stage = Passenger.Stage.TO_EXIT
	assert_bool(PullSide.gate_stamped(_world.sim, p)).is_false()
	var free := _resolve(p, 0)
	assert_int(int(free[0])).is_equal(1)
	assert_int(int((free[1] as Dictionary).get("pull_side_swaps", 0))).is_equal(1)


## pick() for a guest walking east along BIN_ROW (the bins on its right) at
## WALK_M, the stamped hand the right, parked, drawn in `drawn`.
func _pick_by_bins(drawn: int) -> Array:
	var at := _bins.cell_to_world(Vector2i(BIN_RUN.x + 2, BIN_ROW))
	var frame := Transform3D(Basis(Vector3.UP, PI / 2.0), at)
	var ahead: Array = []
	for n in range(1, PullSide.AHEAD_CELLS + 1):
		ahead.append(_bins.cell_to_world(Vector2i(BIN_RUN.x + 2 + n, BIN_ROW)))
	var now := FIRST_TICK + 50.0
	var bag := {"kind": ROLLER, "place": _place(drawn), "was": _place(1 - drawn), "changed": 0.0}
	var picked := PullSide.pick(bag, _bins, frame, ahead, WALK_M, 0, now, false, true)
	var poses := PullSide.walk_poses(frame, ahead, WALK_M * PullSide.LOOK_TICKS)
	var settled := PullSide.blocked(_bins, poses, PullSide.footprint(0, false), true)
	return [picked, bag, settled]


func test_furniture_on_the_stamped_side_still_wins() -> void:
	# Control: a bin meets the stamped right's settled footprint here.
	var kept := _pick_by_bins(0)
	assert_bool(bool(kept[2])).is_true()
	# In the stamped right, the bin sends it left as without the stamp.
	assert_int(int(kept[0])).is_equal(1)
	assert_int(int((kept[1] as Dictionary).get("pull_side_swaps", 0))).is_equal(1)
	# In the left, it is not brought across onto the bin.
	var left := _pick_by_bins(1)
	assert_int(int(left[0])).is_equal(1)
	assert_int(int((left[1] as Dictionary).get("pull_side_park", 0))).is_equal(0)


## pick() for a guest facing east at world `at`, its route straight on, the
## stamped hand `first`, drawn in `drawn`; [hand, bag, the walk's poses].
func _pick_east(at: Vector3, first: int, drawn: int, parked: bool) -> Array:
	var frame := Transform3D(Basis(Vector3.UP, PI / 2.0), at)
	var ahead: Array = []
	for n in range(1, PullSide.AHEAD_CELLS + 1):
		ahead.append(at + Vector3(n, 0.0, 0.0))
	var bag := {"kind": ROLLER, "place": _place(drawn), "was": _place(1 - drawn), "changed": 0.0}
	var now := FIRST_TICK + 50.0
	var picked := PullSide.pick(bag, _bins, frame, ahead, WALK_M, first, now, false, parked)
	return [picked, bag, PullSide.walk_poses(frame, ahead, WALK_M * PullSide.LOOK_TICKS)]


func test_a_reach_only_obstacle_off_the_chair_row_still_wins() -> void:
	# A guest walking east this far north of the bins: the right's REACH
	# footprint meets them, its SETTLED one does not.
	var row := _bins.cell_to_world(Vector2i(BIN_RUN.x + 2, BIN_ROW))
	var found := 1.0
	for k in 40:
		var off := -0.02 * k
		var poses: Array = _pick_east(row + Vector3(0.0, 0.0, off), 0, 0, true)[2]
		var settled := PullSide.blocked(_bins, poses, PullSide.footprint(0, false), true)
		var reach := PullSide.blocked(_bins, poses, PullSide.footprint(0, true), true)
		if reach and not settled:
			found = off
			break
	# Control: such a place exists, and the bin is not a gate chair.
	assert_float(found).is_less_equal(0.0)
	var picked := _pick_east(row + Vector3(0.0, 0.0, found), 0, 0, true)
	var poses: Array = picked[2]
	var but := PullSide.GATE_CHAIRS
	assert_bool(PullSide.blocked(_bins, poses, PullSide.footprint(0, true), true, but)).is_true()
	assert_bool(PullSide.stamp_clear(_bins, poses, 0)).is_false()
	assert_int(int(picked[0])).is_equal(1)
	assert_int(int((picked[1] as Dictionary).get("pull_side_swaps", 0))).is_equal(1)


func test_a_stamped_left_onto_furniture_is_not_told_across() -> void:
	var at := _bins.cell_to_world(Vector2i(BIN_RUN.x + 2, LEFT_BIN_ROW))
	# Control: the stamped left's settled footprint meets the bins, and not
	# parked, hand_of()'s left tells the roller across onto them.
	var told := _pick_east(at, 1, 0, false)
	var poses: Array = told[2]
	assert_bool(PullSide.blocked(_bins, poses, PullSide.footprint(1, false), true)).is_true()
	assert_int(int(told[0])).is_equal(1)
	var parked := _pick_east(at, 1, 0, true)
	assert_int(int(parked[0])).is_equal(0)
	assert_int(int((parked[1] as Dictionary).get("pull_side_park", 0))).is_equal(0)
