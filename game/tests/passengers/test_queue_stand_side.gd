class_name TestQueueStandSide
extends GdUnitTestSuite
## A roller stood up in a queue beside a wall goes on the walker's open side
## (decision a-roller-stood-in-a-queue-beside-a-wall-goes-on-the-passenge):
## ParkSide.stand_hand() picks the open side's hand, RollerPark.side_first()
## changes hand before the stand and keeps that hand for the still spell, and
## RollerPark.plan() draws the stand there and tips it back into the pull from
## where it stood. The wall is one box as PullSide.walls_near() builds it.

const ROLLER := SecurityLooks.Kind.ROLLER
## A wall box along x at the origin, 0.14 m thick (test_park_walls).
const HALF := Vector3(0.5 + BuildView.WALL_THICKNESS / 2.0, 1.5, BuildView.WALL_THICKNESS / 2.0)
## The walker stands this far from the wall's face: the usual stand (its near
## edge about 0.27 m out) stands in the wall.
const OFF_WALL_M := 0.3
## Nearer still, the usual stand stands wholly past the wall: stander 4 on
## (21, 5) in roller_board_gate_probe stood 0.1 m from the east outer wall.
const NEAR_WALL_M := 0.1
## Lattice points per axis sampled through the roller's box (_points_in()).
const LATTICE := 6
## Plan samples over a move (_frames()).
const SAMPLES := 60
## A male body look (PassengerLooks.BODIES index 0): the widest queue park.
const LOOK := 0


## One wall box at the origin, along x.
func _wall() -> Array:
	return [[Vector3(0.0, HALF.y, 0.0), [Vector3.RIGHT, Vector3.UP, Vector3.BACK], HALF]]


## A walker `off` from the wall's -z face, facing -x along it: its left hand's
## side (+z) is the wall's.
func _beside_wall(off := OFF_WALL_M) -> Transform3D:
	var at := Vector3(0.0, 0.0, -HALF.z - off)
	return Transform3D(Basis(Vector3.UP, -PI / 2.0), at)


## Points of a lattice through the roller's box drawn at `xf` that are inside
## any of `walls` (in each wall's frame, along and across; walls stand taller
## than a roller).
func _points_in(xf: Transform3D, walls: Array) -> int:
	var box := CarryOnProps.bag_box(ROLLER)
	var count := 0
	for a in LATTICE:
		for b in LATTICE:
			for c in LATTICE:
				var local := box.position + box.size * Vector3(a, b, c) / float(LATTICE - 1)
				var at := xf * local
				for wall: Array in walls:
					var d: Vector3 = at - (wall[0] as Vector3)
					var half: Vector3 = wall[2]
					var along := absf(d.dot(wall[1][0]))
					var across := absf(d.dot(wall[1][2]))
					if along < half.x and across < half.z:
						count += 1
	return count


## The hand-side stand (RollerPark.queue_park()) for `frame` and `hand`.
func _stand(frame: Transform3D, hand: int) -> Transform3D:
	return RollerPark.queue_park(frame, hand, 1.0, LOOK)


## The body's left side is the wall's: a roller pulled in the left hand stands
## with the right (stand_hand()), and that stand has no point in the wall.
## Control: the usual (left) stand puts points in the wall.
func test_a_stand_beside_a_wall_goes_on_the_open_side() -> void:
	var frame := _beside_wall()
	var walls := _wall()
	var left_in := _points_in(_stand(frame, 1), walls)
	var right_in := _points_in(_stand(frame, 0), walls)
	print("beside the wall: left stand %d points in the wall, right %d" % [left_in, right_in])
	assert_int(left_in).is_greater(0)
	assert_int(right_in).is_equal(0)
	assert_int(ParkSide.stand_hand(frame, 1, 1.0, LOOK, walls)).is_equal(0)
	# Already on the open side, it stays there.
	assert_int(ParkSide.stand_hand(frame, 0, 1.0, LOOK, walls)).is_equal(0)


## NEAR_WALL_M from the wall the usual (left) stand has no point in the wall
## but stands wholly on its far side, through it: stand_hand() picks the right
## hand too. Control: the left stand's near edge is past the wall's far face.
func test_a_stand_that_would_stand_past_the_wall_goes_on_the_open_side() -> void:
	var frame := _beside_wall(NEAR_WALL_M)
	var walls := _wall()
	var box := CarryOnProps.bag_box(ROLLER)
	var near := INF
	for k in 8:
		near = minf(near, (_stand(frame, 1) * box.get_endpoint(k)).z)
	print("past the wall: left stand from z %.3f, the far face at %.3f" % [near, HALF.z])
	assert_float(near).is_greater(HALF.z)
	assert_int(_points_in(_stand(frame, 1), walls)).is_equal(0)
	assert_int(ParkSide.stand_hand(frame, 1, 1.0, LOOK, walls)).is_equal(0)


## In open floor, and walled on both sides, each hand keeps its usual side.
## Control: the two-wall case does put both stands in a wall.
func test_open_floor_and_both_sides_walled_keep_the_usual_side() -> void:
	var frame := _beside_wall()
	for hand in 2:
		assert_int(ParkSide.stand_hand(frame, hand, 1.0, LOOK, [])).is_equal(hand)
	var both := _wall()
	var other: Array = _wall()[0].duplicate(true)
	other[0] = Vector3(0.0, HALF.y, -2.0 * HALF.z - 2.0 * OFF_WALL_M)
	both.append(other)
	var ins := [_points_in(_stand(frame, 0), both), _points_in(_stand(frame, 1), both)]
	print("walled on both sides: stand points in a wall %s" % [ins])
	assert_int(ins[0]).is_greater(0)
	assert_int(ins[1]).is_greater(0)
	for hand in 2:
		assert_int(ParkSide.stand_hand(frame, hand, 1.0, LOOK, both)).is_equal(hand)


## A roller in the left hand's pull: side_first() puts the stand off, the ask
## is not made again while the roller is still in the left hand, hold_park()
## moves it to the right hand, and once it is settled there the stand is asked
## for again and stamped as a stand in the right hand. The side is chosen once
## a still spell: asked again with the other hand, it does not change. Walking
## on keeps the hand only while PullSide keeps a stood roller (stood()).
func test_the_change_of_hand_comes_before_the_stand_and_is_kept() -> void:
	var bag := _pulled(1)
	var now := 100.0
	for t in RollerPark.STILL_TICKS + 1:
		RollerPark.queue_stand(bag, ROLLER, true, now)
		now += 1.0
	now -= 1.0
	assert_bool(RollerPark.restamps(bag)).is_true()
	assert_bool(RollerPark.side_first(bag, 0)).is_true()
	assert_bool(RollerPark.restamps(bag)).is_false()
	# Still in the left hand: no new ask, and hold_park() turns it to the right.
	now += 1.0
	RollerPark.queue_stand(bag, ROLLER, true, now)
	assert_bool(RollerPark.restamps(bag)).is_false()
	var homes := [SecurityLooks.Home.HAND]
	var hands := [1]
	RollerPark.hold_park(bag, ROLLER, homes, hands, 0, now)
	assert_int(hands[0]).is_equal(0)
	# The change of hand made and settled (as CarryOnProps and CarryPlace do).
	var place := (SecurityLooks.Home.HAND * 2 + 0) * 2
	bag["place"] = place
	bag["home"] = place
	bag["changed"] = now
	bag["since"] = now
	now += CarryOnProps.TRANSFER_TICKS + 1.0
	RollerPark.queue_stand(bag, ROLLER, true, now)
	assert_bool(RollerPark.restamps(bag)).is_true()
	# Decided for the spell: the right hand stands, whatever is asked now.
	assert_bool(RollerPark.side_first(bag, 1)).is_false()
	assert_int(int(bag["queue_hand"][1])).is_equal(0)
	_stamped(bag, now)
	assert_bool(RollerPark.queued(bag)).is_true()
	assert_int(CarryLead.start_of(bag)[1]).is_equal(0)
	# Walking on: the tip, then held in the right hand for PullSide's stood().
	now += 10.0
	RollerPark.queue_stand(bag, ROLLER, false, now)
	assert_bool(bag.has("still_from")).is_false()
	hands = [1]
	RollerPark.hold_park(bag, ROLLER, homes, hands, 0, now)
	assert_int(hands[0]).is_equal(0)
	var over := float(bag["since"]) + CarryLead.ticks_of(bag) + PullSide.LOOK_TICKS + 1.0
	hands = [1]
	RollerPark.hold_park(bag, ROLLER, homes, hands, 0, over)
	assert_int(hands[0]).is_equal(1)


## The roller already in the open side's hand (or in open floor): side_first()
## stamps the side and lets the stand go ahead at once, and hold_park() leaves
## the hand to PullSide as before. Control: a changed side is held
## (test_the_change_of_hand_comes_before_the_stand_and_is_kept).
func test_a_roller_on_the_open_side_stands_at_once() -> void:
	var bag := _pulled(0)
	var now := 100.0
	for t in RollerPark.STILL_TICKS + 1:
		RollerPark.queue_stand(bag, ROLLER, true, now)
		now += 1.0
	assert_bool(RollerPark.side_first(bag, 0)).is_false()
	assert_bool(RollerPark.restamps(bag)).is_true()
	var hands := [1]
	RollerPark.hold_park(bag, ROLLER, [SecurityLooks.Home.HAND], hands, 0, now)
	assert_int(hands[0]).is_equal(1)


## The stand drawn by RollerPark.plan() in the open side's hand (right) has no
## point in the wall standing, nor on any frame of its tip back into the pull,
## which starts from where it stood. Control: the same move in the left hand,
## without the walls kept, stands in the wall; with them (the ParkWalls
## backstop, for a stand walled on both sides or a two-bag guest's) it is moved
## out, and its tip starts from where it was moved to, not from the unmoved
## stand: its first tip step is small, and far shorter than the way from the
## unmoved stand to that first tip frame.
func test_the_open_side_stand_and_its_tip_stay_out_of_the_wall() -> void:
	var frame := _beside_wall()
	var walls := _wall()
	var right := _frames(0, frame, walls)
	var left := _frames(1, frame, walls, false)
	var kept := _frames(1, frame, walls)
	print(
		(
			(
				"plan in the wall: right stand %d tip %d (first tip step %.4f m); left stand %d, "
				+ "left with the backstop %d"
			)
			% [right["stand"], right["tip"], right["tip_step"], left["stand"], kept["stand"]]
		)
	)
	assert_int(left["stand"]).is_greater(0)
	assert_int(kept["stand"]).is_equal(0)
	assert_int(right["stand"]).is_equal(0)
	assert_int(right["tip"]).is_equal(0)
	assert_float(right["tip_step"]).is_less(0.05)
	assert_int(right["stood_frames"]).is_greater(0)
	assert_int(right["tip_frames"]).is_greater(0)
	# The moved stand tips from where it stood (kept), not from the unmoved stand.
	var moved: float = kept["stood_at"].distance_to(left["stood_at"])
	var from_unmoved: float = kept["first_tip"].distance_to(left["stood_at"])
	print(
		(
			"backstop: moved %.4f m, first tip step %.4f m, from the unmoved stand %.4f m"
			% [moved, kept["tip_step"], from_unmoved]
		)
	)
	assert_int(kept["stood_frames"]).is_greater(0)
	assert_int(kept["tip_frames"]).is_greater(0)
	assert_float(moved).is_greater(0.05)
	assert_float(kept["tip_step"]).is_less(0.05)
	assert_float(from_unmoved).is_greater(kept["tip_step"] + 0.05)


## A roller's record settled in hand `hand`'s pull since tick 0.
static func _pulled(hand: int) -> Dictionary:
	var place := (SecurityLooks.Home.HAND * 2 + hand) * 2
	return {
		"kind": ROLLER,
		"place": place,
		"home": place,
		"carry": SecurityLooks.Carry.PULL,
		"settled": true,
		"since": 0.0,
		"changed": 0.0,
	}


## `bag` stamped as CarryOnProps stamps the move it asked for at `now`.
func _stamped(bag: Dictionary, now: float) -> void:
	bag["led"] = true
	bag["was"] = bag["home"]
	bag["carry_from"] = SecurityLooks.Carry.PULL
	bag["since"] = bag["changed"]
	CarryLead.stamp_move(bag, false, SecurityLooks.Home.HAND, Transform3D.IDENTITY)
	assert_float(float(bag["since"])).is_equal(now)


## A queue stand in hand `hand` for a body standing at `frame`, planned
## (RollerPark.plan()) over its stand, a hold and its tip, with `walls` kept as
## CarryPlace keeps them for the ParkWalls backstop when `backstop`: points in
## the wall standing and tipping, frame counts, the last stood and first tip
## frames' origins and the step between them.
func _frames(hand: int, frame: Transform3D, walls: Array, backstop := true) -> Dictionary:
	var bag := _pulled(hand)
	var now := 100.0
	for t in RollerPark.STILL_TICKS + 1:
		RollerPark.queue_stand(bag, ROLLER, true, now)
		now += 1.0
	now -= 1.0
	_stamped(bag, now)
	if backstop:
		bag["queue_walls"] = walls
	# Stood 10 ticks, then the walker walks on.
	var stood_until := now + 10.0
	while now < stood_until:
		now += 1.0
		RollerPark.queue_stand(bag, ROLLER, true, now)
	RollerPark.queue_stand(bag, ROLLER, false, now + 1.0)
	var ticks := CarryLead.ticks_of(bag)
	var tip: float = bag["queue_tip"]
	# The pull behind the body on the hand's side, as the move starts and ends.
	var pull := RollerPark.park(frame, hand, 1.0, -0.9, 0.2)
	var body := {"scale": 1.0, "look": LOOK, "bar_z": CarryOnProps.REACH_BUILT_M}
	var flags := {"hand": hand}
	var seen := {
		"stand": 0,
		"tip": 0,
		"stood_frames": 0,
		"tip_frames": 0,
		"tip_step": 0.0,
		"stood_at": Vector3.ZERO,
		"first_tip": Vector3.ZERO,
	}
	var last := Transform3D()
	for n in SAMPLES + 1:
		var k := float(n) / SAMPLES
		var at := k * ticks
		var xf: Transform3D = RollerPark.plan(bag, k, pull, pull, frame, flags, body)["xf"]
		if at >= RollerPark.QUEUE_STAND_TICKS and at < tip:
			seen["stand"] += _points_in(xf, walls)
			seen["stood_frames"] += 1
			last = xf
		elif at >= tip:
			if seen["tip_frames"] == 0:
				seen["tip_step"] = xf.origin.distance_to(last.origin)
				seen["stood_at"] = last.origin
				seen["first_tip"] = xf.origin
			seen["tip"] += _points_in(xf, walls)
			seen["tip_frames"] += 1
	return seen
