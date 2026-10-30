class_name TestCarryLead
extends GdUnitTestSuite
## Hand-led carry-on moves (CarryLead; decision carry-on-bags-stay-in-the-hand-
## during-every-move-no-overhead): at every progress of a move the bag is
## either at an end where it rests or is worn, or placed from a hand's grip;
## the leading hand reaches a bag before it moves and lets go after it lands;
## a change of hand passes the bag between the hands half way; the stoop bends
## only as far as a low target needs. Pure functions, no scene.

const STEPS := 60
const ENDS := [CarryLead.End.HELD, CarryLead.End.WORN, CarryLead.End.REST]


## Every move between every kind of end, sampled through k: while the bag is
## off its start and short of its end (0 < t < 1) it has a holder, the holder
## is aimed at the carry (weight 1 unless an end is held, where it eases in or
## out of the carry pose), and a holder of -1 only happens at a WORN or REST
## end. Control: the sampled moves do have a carried part.
func test_a_moving_bag_is_always_held_or_at_a_resting_end() -> void:
	var carried := 0
	for from: CarryLead.End in ENDS:
		for to: CarryLead.End in ENDS:
			for step in STEPS + 1:
				var k := step / float(STEPS)
				var ph := CarryLead.phase(k, from, to, 0, 0)
				var t: float = ph["t"]
				if ph["holder"] < 0:
					var at_start := k < CarryLead.span(from, to).x
					var end: CarryLead.End = from if at_start else to
					assert_int(end).is_not_equal(CarryLead.End.HELD)
					continue
				assert_int(ph["holder"]).is_equal(0)
				if t > 0.0 and t < 1.0:
					carried += 1
				if from != CarryLead.End.HELD and to != CarryLead.End.HELD:
					assert_float(ph["weights"][0]).is_equal_approx(1.0, 0.0001)
	assert_int(carried).is_greater(STEPS)


## A bag picked up from the floor waits there while the hand reaches it (the
## hand's weight rises from 0), then rises in the hand; a bag set down is let
## go only once it is down, the hand's weight falling to 0 at the end.
func test_the_hand_reaches_a_resting_bag_first_and_lets_go_last() -> void:
	var up := CarryLead.phase(0.0, CarryLead.End.REST, CarryLead.End.HELD, 1, 1)
	assert_int(up["holder"]).is_equal(-1)
	assert_float(up["weights"][1]).is_equal_approx(0.0, 0.0001)
	var reaching := CarryLead.phase(
		CarryLead.REACH_SHARE * 0.5, CarryLead.End.REST, CarryLead.End.HELD, 1, 1
	)
	assert_int(reaching["holder"]).is_equal(-1)
	assert_float(reaching["weights"][1]).is_between(0.2, 0.8)
	var lifted := CarryLead.phase(
		CarryLead.REACH_SHARE + 0.01, CarryLead.End.REST, CarryLead.End.HELD, 1, 1
	)
	assert_int(lifted["holder"]).is_equal(1)
	var down := CarryLead.phase(1.0, CarryLead.End.HELD, CarryLead.End.REST, 0, 0)
	assert_int(down["holder"]).is_equal(-1)
	assert_float(down["weights"][0]).is_equal_approx(0.0, 0.0001)
	var landing := CarryLead.phase(
		1.0 - CarryLead.REACH_SHARE - 0.01, CarryLead.End.HELD, CarryLead.End.REST, 0, 0
	)
	assert_int(landing["holder"]).is_equal(0)
	assert_float(landing["weights"][0]).is_equal_approx(1.0, 0.0001)


## From the right hand to the left: the right hand holds it to half way, where
## the left hand has come fully to it; the left holds it after.
func test_a_change_of_hand_passes_the_bag_half_way() -> void:
	var lead := CarryLead.lead_hand(CarryLead.End.HELD, CarryLead.End.HELD, 0, 1, 0)
	assert_int(lead).is_equal(1)
	var before := CarryLead.phase(0.45, CarryLead.End.HELD, CarryLead.End.HELD, 0, 1)
	assert_int(before["holder"]).is_equal(0)
	assert_float(before["weights"][0]).is_equal_approx(1.0, 0.0001)
	var at := CarryLead.phase(0.5, CarryLead.End.HELD, CarryLead.End.HELD, 0, 1)
	assert_int(at["holder"]).is_equal(1)
	assert_float(at["weights"][1]).is_equal_approx(1.0, 0.0001)
	var after := CarryLead.phase(1.0, CarryLead.End.HELD, CarryLead.End.HELD, 0, 1)
	assert_float(after["weights"][0]).is_equal_approx(0.0, 0.0001)


## A place's end: in a hand carried by hand or pulled is HELD, on the back or
## the shoulder WORN, on the floor, in a tray or new (-1) REST.
func test_ends_of_places() -> void:
	var hand_r := (SecurityLooks.Home.HAND * 2 + 0) * 2
	var hand_l := (SecurityLooks.Home.HAND * 2 + 1) * 2 + 1
	var tray := (SecurityLooks.Home.TRAY * 2 + 0) * 2
	assert_int(CarryLead.end_of(hand_r, SecurityLooks.Carry.HAND)).is_equal(CarryLead.End.HELD)
	assert_int(CarryLead.end_of(hand_l, SecurityLooks.Carry.PULL)).is_equal(CarryLead.End.HELD)
	assert_int(CarryLead.end_of(hand_r, SecurityLooks.Carry.BACK)).is_equal(CarryLead.End.WORN)
	assert_int(CarryLead.end_of(tray, SecurityLooks.Carry.HAND)).is_equal(CarryLead.End.REST)
	assert_int(CarryLead.end_of(-1, SecurityLooks.Carry.HAND)).is_equal(CarryLead.End.REST)
	assert_int(CarryLead.hand_of(hand_l)).is_equal(1)


## The stoop: none for a target the standing arm reaches; some for a bag on
## the floor ahead, enough that the stooped shoulder is within reach; more for
## a lower target. Skeleton-free (CarryStoop.needed).
func test_the_stoop_bends_only_as_far_as_a_low_target_needs() -> void:
	var shoulder := Vector3(-0.2, 1.35, 0.0)
	var pivot := Vector3(0.0, 1.0, 0.0)
	var reach := 0.6
	var waist := Vector3(-0.25, 0.8, 0.1)
	assert_float(CarryStoop.needed(shoulder, pivot, waist, waist, reach)).is_equal(0.0)
	var floor_bag := Vector3(-0.3, 0.45, 0.3)
	var s := CarryStoop.needed(shoulder, pivot, floor_bag, floor_bag, reach)
	assert_float(s).is_between(0.05, 0.99)
	var bent := CarryStoop.stooped(shoulder, pivot, floor_bag, s)
	assert_float(bent.distance_to(floor_bag)).is_less_equal(reach + 0.001)
	var lower := Vector3(-0.3, 0.3, 0.3)
	assert_float(CarryStoop.needed(shoulder, pivot, lower, lower, reach)).is_greater(s)


## The two-bone reach (CarryStoop.two_bone, used by CarryArm): the end lands on
## a target within reach, and each bone keeps its length.
func test_the_two_bone_reach_lands_on_a_target_in_reach() -> void:
	var root := Vector3(0.0, 1.3, 0.0)
	var target := Vector3(0.3, 0.9, 0.3)
	var joints := CarryStoop.two_bone(root, 0.3, 0.35, target, Vector3(1.0, 0.0, -0.5))
	assert_float(joints[1].distance_to(target)).is_less(0.001)
	assert_float(joints[0].distance_to(root)).is_equal_approx(0.3, 0.001)
	assert_float(joints[0].distance_to(joints[1])).is_equal_approx(0.35, 0.001)


## A hand-led move from the floor to the hand interrupted while the hand is
## still reaching for the bag (k under REACH_SHARE) has not left its start, so
## the next move (back to the floor) starts there, resting: its hand reaches
## first and nothing holds the bag at its start. Control: stamped from the old
## end as before (the hand, not held any more) the next move would start HELD,
## the bag in the hand at once. A move past its reach, one that started held
## and one not hand-led have all left their start.
func test_a_move_interrupted_in_its_reach_starts_the_next_where_the_bag_is() -> void:
	var floor_at := (SecurityLooks.Home.FLOOR * 2 + 0) * 2
	var hand_at := (SecurityLooks.Home.HAND * 2 + 0) * 2
	var bag := {
		"was": floor_at,
		"carry_from": SecurityLooks.Carry.HAND,
		"home": hand_at,
		"carry": SecurityLooks.Carry.HAND,
		"led": true,
	}
	assert_bool(CarryLead.at_start(bag, 0.1)).is_true()
	assert_bool(CarryLead.at_start(bag, CarryLead.REACH_SHARE + 0.01)).is_false()
	# The stamp keeps "was" and "carry_from" of a move that has not left.
	var next := bag.duplicate()
	next["home"] = floor_at
	var started := CarryLead.start_of(next)
	assert_int(started[0]).is_equal(CarryLead.End.REST)
	var to := CarryLead.end_of(next["home"], next["carry"])
	assert_int(CarryLead.phase(0.05, started[0], to, started[1], 0)["holder"]).is_equal(-1)
	var stale := next.duplicate()
	stale["was"] = hand_at
	assert_int(CarryLead.start_of(stale)[0]).is_equal(CarryLead.End.HELD)
	var from_hand := stale.duplicate()
	from_hand["home"] = floor_at
	assert_bool(CarryLead.at_start(from_hand, 0.1)).is_false()
	var not_led := bag.duplicate()
	not_led["led"] = false
	assert_bool(CarryLead.at_start(not_led, 0.1)).is_false()


## Whether a move is hand-led is decided when it is stamped and kept to its
## end: one stamped outside a toilet stall stays hand-led when its walker steps
## into the stall, and one stamped inside a stall is hand-led too (board item
## c7b0e7be: every move; until then a stall move was not). A swap is never
## hand-led. Control: a finished move leads no more.
func test_a_hand_led_move_keeps_its_mode_across_a_stall_change() -> void:
	var held := {"in_stall": false}
	var bag := {"since": 0.0}
	bag["led"] = CarryOnProps._leads(held, bag)
	held["in_stall"] = true
	assert_bool(CarryOnProps._leading(bag, 1.0)).is_true()
	var in_stall := {"since": 0.0}
	in_stall["led"] = CarryOnProps._leads({"in_stall": true}, in_stall)
	assert_bool(CarryOnProps._leading(in_stall, 1.0)).is_true()
	var swap := {"since": 0.0, "swap": true}
	swap["led"] = CarryOnProps._leads({"in_stall": false}, swap)
	assert_bool(CarryOnProps._leading(swap, 1.0)).is_false()
	assert_bool(CarryOnProps._leading(bag, CarryOnProps.TRANSFER_TICKS)).is_false()


## A pulled roller passed from the right hand to the left (pull.R>pull.L) is
## held by its bar all the way: at every k (0.01 apart) the bag placed from
## the holder's grip, as CarryOnProps places it, has its bar (its rods drawn
## as CarryOnProps blends them, carry_t of the way) within the FLOAT check's
## held bound (5 cm) of that grip. The two pulls have rods 0.4 m apart in
## length. Control: both hands hold it in turn.
func test_a_roller_passed_between_pulling_hands_stays_held_by_its_bar() -> void:
	var grips := [Vector3(-0.25, 0.75, 0.05), Vector3(0.25, 0.75, 0.05)]
	var axles := [Vector3(-0.3, 0.03, -0.6), Vector3(0.3, 0.03, -1.0)]
	var past := 0.2
	var rods := []
	var ends := []
	for hand in 2:
		var xf := CarryOnProps.pulled(grips[hand], axles[hand], 1.0, Vector3.UP)
		ends.append(xf)
		rods.append(grips[hand].distance_to(axles[hand]) + CarryOnProps.ROLLER_AXLE.z - past)
	var bag := {
		"kind": SecurityLooks.Kind.ROLLER,
		"home": 6,
		"carry": SecurityLooks.Carry.PULL,
		"was": 4,
		"carry_from": SecurityLooks.Carry.PULL,
		"from": ends[0],
	}
	var flags := {"in_stall": false, "hand": 0, "yaw": 0.0, "clear": 0.0}
	var holders := {}
	var worst := 0.0
	for step in 101:
		var k := step / 100.0
		var bar_z: float = lerpf(rods[0], rods[1], CarryLead.carry_t(k, bag)) + past
		var body := {
			"hand": 0,
			"grips": grips,
			"shoulders_y": [1.4, 1.4],
			"bar_z": bar_z,
			"scale": 1.0,
			"strap_top": Vector3.ZERO,
		}
		var plan := CarryLead.plan(bag, k, ends[0], ends[1], Transform3D(), flags, body)
		var holder: int = plan["holder"]
		if holder < 0:
			continue
		holders[holder] = true
		var xf: Transform3D = plan["xf"]
		var placed := Transform3D(xf.basis, grips[holder] - xf.basis * (plan["anchor"] as Vector3))
		var bar := placed * Vector3(0.0, CarryOnProps.ROLLER_AXLE.y, bar_z)
		worst = maxf(worst, bar.distance_to(grips[holder]))
		assert_float(bar.distance_to(grips[holder])).is_less_equal(0.05)
	print(
		"pull.R>pull.L: holders %s, the bar at most %.4f m from the grip" % [holders.keys(), worst]
	)
	assert_bool(holders.has(0) and holders.has(1)).is_true()


## Picked up off a stall's floor, a hard case is held by its top while it
## stands (to STALL_TIP_FROM of the carry): FRONT_PALM_M over the middle of its
## top end, inside its face, not at its bounds' top corner, which takes in the
## handle and is past the face. As it tips, the grip goes over its top front
## edge to the point it is carried by, kept at least 2 cm off the case's body,
## and the stoop to it bends the back first (STALL_HIPS). Controls: the bounds'
## corner is past the face, a straight blend between the same two points goes
## into the case, and out of a stall the hips go down with the stoop.
func test_a_stall_case_is_held_by_its_top_and_round_its_edge_as_it_tips() -> void:
	var move := _to_floor(SecurityLooks.Kind.CASE)
	var bag: Dictionary = move[0]
	var body: Dictionary = move[1]
	bag["home"] = (SecurityLooks.Home.HAND * 2 + 0) * 2
	bag["was"] = (SecurityLooks.Home.FLOOR * 2 + 0) * 2
	var box := CarryOnProps.bag_box(SecurityLooks.Kind.CASE)
	var top := CarryLead.stall_top(SecurityLooks.Kind.CASE, Vector3.ZERO)
	var corner := CarryOnProps.grip_anchor(SecurityLooks.Kind.CASE)
	# Standing on its end (its length up), and flat in the hand in front.
	var start := Transform3D(Basis(Vector3.RIGHT, -PI / 2.0), Vector3(0.0, 0.24, 0.5))
	var want := Transform3D(Basis(), Vector3(0.0, 0.9, 0.3))
	var carried := Vector3(0.0, box.end.y + CarryOnProps.FRONT_PALM_M, 0.0)
	body["grips"] = [want * carried, Vector3(0.2, 0.9, 0.3)]
	var stall := {"in_stall": true, "hand_carry": true, "hand": 0, "yaw": 0.0, "clear": 0.3}
	# The case's body, its handle left out.
	var solid := AABB(
		Vector3(box.position.x, 0.0, box.position.z),
		Vector3(box.size.x, CarryLead.STALL_CASE_DEPTH_M, box.size.z)
	)
	print("stall case top %s, bounds corner %s, case body %s" % [top, corner, solid])
	assert_float(top.y).is_between(0.02, CarryLead.STALL_CASE_DEPTH_M - 0.02)
	assert_float(top.z).is_equal_approx(box.end.z + CarryOnProps.FRONT_PALM_M, 0.0001)
	assert_float(corner.y).is_greater(CarryLead.STALL_CASE_DEPTH_M + 0.02)
	var nearest := INF
	for step in 21:
		var t := step / 20.0
		var k := CarryLead.REACH_SHARE + (1.0 - CarryLead.REACH_SHARE) * t
		var held: Vector3 = (
			CarryLead.plan(bag, k, start, want, Transform3D(), stall, body)["anchor"]
		)
		if t <= CarryLead.STALL_TIP_FROM:
			assert_vector(held).is_equal_approx(top, Vector3.ONE * 0.0001)
		var off := held.distance_to(_clamped(held, solid))
		nearest = minf(nearest, off)
		assert_float(off).is_greater_equal(0.02)
	var first := CarryLead.plan(bag, 0.1, start, want, Transform3D(), stall, body)
	assert_vector(first["drops"][0]).is_equal(CarryLead.STALL_HIPS)
	var open := stall.duplicate()
	open["in_stall"] = false
	var outside := CarryLead.plan(bag, 0.1, start, want, Transform3D(), open, body)
	assert_vector(outside["drops"][0]).is_equal(CarryStoop.HIPS_ALL)
	var end: Vector3 = CarryLead.plan(bag, 1.0, start, want, Transform3D(), stall, body)["anchor"]
	assert_vector(end).is_equal_approx(carried, Vector3.ONE * 0.0001)
	var straight := top.lerp(carried, 0.35)
	print(
		"tip: grip at least %.3f m off the case; a straight blend at 0.35: %s" % [nearest, straight]
	)
	assert_float(straight.distance_to(_clamped(straight, solid))).is_equal(0.0)


## Picked up off a stall's floor into the hand, a bag's move is stamped with
## the short reach (STALL_PICK_REACH), so it is already being carried, placed
## from the hand, just past it, and carry_t and at_start read the same reach.
## Controls: the same move out of a stall, or one into a worn carry in a stall,
## keeps REACH_SHARE and is still waiting at its start then.
func test_a_stall_pick_up_into_the_hand_reaches_the_bag_soon() -> void:
	var move := _to_floor(SecurityLooks.Kind.CASE)
	var bag: Dictionary = move[0]
	var body: Dictionary = move[1]
	bag["home"] = (SecurityLooks.Home.HAND * 2 + 0) * 2
	bag["was"] = (SecurityLooks.Home.FLOOR * 2 + 0) * 2
	var open := bag.duplicate()
	var worn := bag.duplicate()
	worn["carry"] = SecurityLooks.Carry.SHOULDER
	CarryLead.stamp_reach(bag, true, SecurityLooks.Home.HAND)
	CarryLead.stamp_reach(open, false, SecurityLooks.Home.HAND)
	CarryLead.stamp_reach(worn, true, SecurityLooks.Home.HAND)
	print(
		(
			"reach: stall %.2f, outside %.2f, worn %.2f"
			% [CarryLead.reach_of(bag), CarryLead.reach_of(open), CarryLead.reach_of(worn)]
		)
	)
	assert_float(CarryLead.reach_of(bag)).is_equal(CarryLead.STALL_PICK_REACH)
	assert_float(CarryLead.reach_of(open)).is_equal(CarryLead.REACH_SHARE)
	assert_float(CarryLead.reach_of(worn)).is_equal(CarryLead.REACH_SHARE)
	var k := CarryLead.STALL_PICK_REACH + 0.01
	var start := Transform3D(Basis(Vector3.RIGHT, -PI / 2.0), Vector3(0.0, 0.24, 0.5))
	var want := Transform3D(Basis(), Vector3(0.0, 0.9, 0.3))
	var flags := {"in_stall": true, "hand_carry": true, "hand": 0, "yaw": 0.0, "clear": 0.3}
	var early := CarryLead.plan(bag, k, start, want, Transform3D(), flags, body)
	var waits := CarryLead.plan(open, k, start, want, Transform3D(), flags, body)
	assert_int(early["holder"]).is_equal(0)
	assert_int(waits["holder"]).is_equal(-1)
	bag["led"] = true
	open["led"] = true
	assert_float(CarryLead.carry_t(k, bag)).is_greater(0.0)
	assert_float(CarryLead.carry_t(k, open)).is_equal(0.0)
	assert_bool(CarryLead.at_start(bag, k)).is_false()
	assert_bool(CarryLead.at_start(open, k)).is_true()


## A case's stall top lies FRONT_PALM_M (world) over its top end at any scale:
## in its own frame FRONT_PALM_M / scale (a two-bag case is drawn smaller).
## Control: at scale 1 the lift is FRONT_PALM_M itself.
func test_a_stall_case_top_is_front_palm_over_it_at_any_scale() -> void:
	var top := CarryOnProps.bag_box(SecurityLooks.Kind.CASE).end.z
	var big := CarryLead.stall_top(SecurityLooks.Kind.CASE, Vector3.ZERO)
	var small := CarryLead.stall_top(SecurityLooks.Kind.CASE, Vector3.ZERO, 0.55)
	assert_float(big.z - top).is_equal_approx(CarryOnProps.FRONT_PALM_M, 0.0001)
	assert_float((small.z - top) * 0.55).is_equal_approx(CarryOnProps.FRONT_PALM_M, 0.0001)


static func _clamped(at: Vector3, box: AABB) -> Vector3:
	return at.clamp(box.position, box.end)


## A move of a bag of `kind` from the right hand to the floor, as CarryOnProps
## records it, and a body for plan(): [bag, body].
static func _to_floor(kind: SecurityLooks.Kind) -> Array:
	var bag := {
		"kind": kind,
		"home": (SecurityLooks.Home.FLOOR * 2 + 0) * 2 + 1,
		"carry": SecurityLooks.Carry.HAND,
		"was": (SecurityLooks.Home.HAND * 2 + 0) * 2 + 1,
		"carry_from": SecurityLooks.Carry.HAND,
		"anchor_from": Vector3(0.0, 0.2, 0.1),
		"from": Transform3D(),
	}
	var body := {
		"hand": 0,
		"grips": [Vector3(-0.2, 0.9, 0.3), Vector3(0.2, 0.9, 0.3)],
		"shoulders_y": [1.4, 1.4],
		"bar_z": 0.3,
		"scale": 1.0,
		"strap_top": Vector3.ZERO,
	}
	return [bag, body]


## Set down in a toilet stall, a bag from the hand is placed from the hand at
## every k up to its let-go, which starts early (STALL_LET_GO: the body shuffles
## back to the seat), with the hand aimed at the bag's path at full weight from
## k 0 (the body turns round to sit in one frame) and its stoop kept on, back
## first (STALL_HIPS). A roller set down there is left by its grip bar, on top
## as it stands, not by its carry handle. Controls: out of a stall the hand
## eases in from weight 0, is still holding the bag past the stall's let-go,
## its stoop takes the hips at once, and a roller is left by its carry handle.
func test_a_stall_set_down_is_held_from_its_start_and_a_roller_left_by_its_bar() -> void:
	var start := Transform3D(Basis(), Vector3(0.0, 0.6, 0.4))
	var want := Transform3D(Basis(), Vector3(0.0, 0.0, 0.4))
	var stall := {"in_stall": true, "hand_carry": true, "hand": 0, "yaw": 0.0, "clear": 0.3}
	var open := stall.duplicate()
	open["in_stall"] = false
	var case_move := _to_floor(SecurityLooks.Kind.CASE)
	var down := 1.0 - CarryLead.STALL_LET_GO
	var frame := Transform3D()
	for step in 11:
		var k := down * step / 10.0 * 0.999
		var plan := CarryLead.plan(case_move[0], k, start, want, frame, stall, case_move[1])
		assert_int(plan["holder"]).is_equal(0)
		assert_float(plan["weights"][0]).is_equal_approx(1.0, 0.0001)
		assert_float(plan["keeps"][0]).is_equal_approx(1.0, 0.0001)
		assert_vector(plan["drops"][0]).is_equal(CarryLead.STALL_HIPS)
	var late := down + 0.01
	(
		assert_int(
			CarryLead.plan(case_move[0], late, start, want, frame, stall, case_move[1])["holder"]
		)
		. is_equal(-1)
	)
	var outside := CarryLead.plan(case_move[0], 0.0, start, want, frame, open, case_move[1])
	assert_int(outside["holder"]).is_equal(0)
	assert_float(outside["weights"][0]).is_equal_approx(0.0, 0.0001)
	assert_vector(outside["drops"][0]).is_equal(CarryStoop.HIPS_ALL)
	(
		assert_int(
			CarryLead.plan(case_move[0], late, start, want, frame, open, case_move[1])["holder"]
		)
		. is_equal(0)
	)
	var roller := _to_floor(SecurityLooks.Kind.ROLLER)
	var bar := CarryLead.anchor(SecurityLooks.Kind.ROLLER, 0.3)
	var left := CarryLead.plan(roller[0], 1.0, start, want, frame, stall, roller[1])
	var left_open := CarryLead.plan(roller[0], 1.0, start, want, frame, open, roller[1])
	print(
		(
			"roller let go at %s in a stall (bar %s), at %s outside (handle %s)"
			% [left["targets"][0], want * bar, left_open["targets"][0], CarryOnProps.ROLLER_HANDLE]
		)
	)
	assert_vector(left["targets"][0]).is_equal_approx(want * bar, Vector3.ONE * 0.0001)
	assert_vector(left_open["targets"][0]).is_equal_approx(
		want * CarryOnProps.ROLLER_HANDLE, Vector3.ONE * 0.0001
	)


## Picked up off a stall's floor while the stooping hand is still low, a case's
## path rises toward the carry (the hand no lower than STALL_CARRY_GRIP_M over
## the feet), not toward where the low hand puts its carry end, which led the
## hand down with it. Control: out of a stall the same move follows the low end.
func test_a_stall_pick_up_rises_to_the_carry_not_to_the_low_hand() -> void:
	var move := _to_floor(SecurityLooks.Kind.CASE)
	var bag: Dictionary = move[0]
	var body: Dictionary = move[1]
	bag["home"] = (SecurityLooks.Home.HAND * 2 + 0) * 2
	bag["was"] = (SecurityLooks.Home.FLOOR * 2 + 0) * 2
	# The hand stooped low: its grip, and the carry end placed from it, low.
	body["grips"] = [Vector3(0.0, 0.3, 0.4), Vector3(0.2, 0.3, 0.3)]
	var start := Transform3D(Basis(), Vector3(0.0, 0.0, 0.5))
	var want := Transform3D(Basis(), Vector3(0.0, 0.2, 0.4))
	var stall := {"in_stall": true, "hand_carry": true, "hand": 0, "yaw": 0.0, "clear": 0.3}
	var open := stall.duplicate()
	open["in_stall"] = false
	var k := 0.9
	var up: Vector3 = CarryLead.plan(bag, k, start, want, Transform3D(), stall, body)["targets"][0]
	var low: Vector3 = CarryLead.plan(bag, k, start, want, Transform3D(), open, body)["targets"][0]
	print("stall pick-up target at k %.2f: %s; outside: %s" % [k, up, low])
	assert_float(up.y).is_greater(CarryLead.STALL_CARRY_GRIP_M * 0.9)
	assert_float(low.y).is_less(0.5)


## A backpack going between the front carry (a stall's approach, StallCarry)
## and the back, both ways, outside a stall (board item stall-bags-probe-fails-
## on-main-at-backpack-out-1-quad-r-vert): on the path legs to and from the
## side hang (path(), where the push out is at full weight, its arc past 0.5)
## the bag's middle, not only its origin (a corner of its back panel), is kept
## TRANSFER_CLEAR_M from the body's centre line, so its body does not swing
## into the walker's belly and hips as it turns (windowed stall_bags_probe,
## seeds 3894526912 and 2386967894: the middle 0.31 m out, belly vertices
## inside it). Control: each leg was sampled at full push.
func test_a_backpack_between_the_front_and_the_back_keeps_its_middle_clear() -> void:
	var kind := SecurityLooks.Kind.BACKPACK
	var middle := CarryOnProps.bag_box(kind).get_center()
	var front := CarryOnProps.carried_in_front(Vector3(-0.1, 1.25, 0.32), 0.0, 1.0, kind)
	var back := CarryOnProps.worn_back(Transform3D(Basis(), Vector3(0.0, 1.35, -0.05)), 0.0, 1.0)
	var hand_at := (SecurityLooks.Home.HAND * 2 + 0) * 2
	var body := {
		"hand": 0,
		"grips": [Vector3(-0.1, 1.25, 0.32), Vector3(0.25, 0.8, 0.05)],
		"shoulders_y": [1.42, 1.42],
		"bar_z": 0.0,
		"scale": 1.0,
		"strap_top": Vector3.ZERO,
	}
	var flags := {
		"in_stall": false,
		"hand_carry": true,
		"from_floor": false,
		"to_floor": false,
		"hand": 0,
		"clear": CarryOnProps.TRANSFER_CLEAR_M,
		"yaw": 0.0,
	}
	var on_back := {
		"kind": kind,
		"was": hand_at + 1,
		"carry_from": SecurityLooks.Carry.HAND,
		"home": hand_at,
		"carry": SecurityLooks.Carry.BACK,
		"anchor_from": CarryLead.anchor(kind, 0.0),
		"from": front,
	}
	var off_back := {
		"kind": kind,
		"was": hand_at,
		"carry_from": SecurityLooks.Carry.BACK,
		"home": hand_at + 1,
		"carry": SecurityLooks.Carry.HAND,
		"from": back,
	}
	for move: Array in [[on_back, front, back], [off_back, back, front]]:
		var bag: Dictionary = move[0]
		var started := CarryLead.start_of(bag)
		var to := CarryLead.end_of(bag["home"], bag["carry"])
		var s := CarryLead.span(started[0], to)
		var nearest := INF
		var sampled := 0
		for step in 201:
			var k := step / 200.0
			var t := (k - s.x) / (s.y - s.x)
			# The path leg (path()) of the move: before the side hang going on, after it
			# coming off; u how far along it.
			var u := t / (1.0 - CarryLead.BACK_SHARE)
			if bag == off_back:
				u = (t - CarryLead.BACK_SHARE) / (1.0 - CarryLead.BACK_SHARE)
			if u < 0.15 or u > 0.85:
				continue
			var plan := CarryLead.plan(bag, k, move[1], move[2], Transform3D(), flags, body)
			var at: Vector3 = (plan["xf"] as Transform3D) * middle
			nearest = minf(nearest, Vector2(at.x, at.z).length())
			sampled += 1
		print(
			(
				"%s: middle at least %.3f m out over %d samples"
				% ["hand>back" if bag == on_back else "back>hand", nearest, sampled]
			)
		)
		assert_int(sampled).is_greater(20)
		assert_float(nearest).is_greater_equal(CarryOnProps.TRANSFER_CLEAR_M - 0.001)
