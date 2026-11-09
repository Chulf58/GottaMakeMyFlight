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
## (17, 4) to its front (14, 4), the chairs on its right.

const ROLLER := SecurityLooks.Kind.ROLLER
const WALK_M := PassengerSim.WALK_MM / 1000.0
const FIRST_TICK := 100.0
const FRONT := Vector2i(14, 4)
const START := Vector2i(17, 4)

var _grid: BuildGrid


func before() -> void:
	PassengerTestWorld.tracker = self
	_grid = BuildGrid.new()
	assert_bool(ReferenceTerminal.build(_grid)).is_true()


func after() -> void:
	_grid = null
	PassengerTestWorld.tracker = null


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
	var world := PassengerTestWorld.reference_world()
	world.run_to(10)
	var seat: Dictionary = {}
	for s: Dictionary in world.sim.layout.seats:
		if s["front"] == FRONT:
			seat = s
	assert_bool(seat.is_empty()).is_false()
	var p: Passenger = null
	for attempt in 400:
		p = world.passenger(world.sim.spawn_now(PassengerTestWorld.FLIGHT))
		if SecurityLooks.bag_kind(p, 0) == ROLLER:
			break
		p.carry_on = 0
	ToiletTestLayout.calm(p)
	p.carry_on = 1
	p.cleared = true
	p.stage = Passenger.Stage.TO_GATE
	p.seat_object = seat["object_id"]
	p.seat_cell = seat["cell"]
	p.seat_front = seat["front"]
	p.at = START + Vector2i(ParkSide.NEAR_CELLS, 0)
	# Too far out for ParkSide to choose: no stamp yet.
	SecurityLooks.hand_of(world.sim, p, 0)
	assert_bool(PullSide.gate_stamped(world.sim, p)).is_false()
	p.at = START
	SecurityLooks.hand_of(world.sim, p, 0)
	assert_bool(PullSide.gate_stamped(world.sim, p)).is_true()
	# A stamp for another seat is not this chair's.
	var stamps: Dictionary = world.sim.get_meta(ParkSide.STAMPS)
	stamps[p.id] = ["gate %s" % (seat["cell"] + Vector2i(1, 0)), 0]
	assert_bool(PullSide.gate_stamped(world.sim, p)).is_false()
	# Off to board, the guest is no longer bound for the chair.
	SecurityLooks.hand_of(world.sim, p, 0)
	p.stage = Passenger.Stage.TO_EXIT
	assert_bool(PullSide.gate_stamped(world.sim, p)).is_false()
	world.free_all()
