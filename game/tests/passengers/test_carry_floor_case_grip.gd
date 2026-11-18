class_name TestCarryFloorCaseGrip
extends GdUnitTestSuite
## A hard case lifted off the floor into the hand is held with the palm
## CarryLead.FLOOR_PALM_M over its top, and stays within that of its grip (the
## handle face from its top edge to the top of its handle, read from the body
## mesh by FloatCheck.case_grip_gap(), as the probes' GRIP_ON reads it) on every
## step of the carry, whichever carry it ends in. Board item G (a365cb0b): at a
## lane's repack berth the case ends in the front carry, held FRONT_PALM_M over
## its handle, and that offset was added on top of the floor palm, so the grip
## went 0.071 to 0.086 m off (limit 0.07; crossing probe --lane, seed 1106001,
## passengers 5 and 6). The gap does not depend on where the hand is drawn: the
## case is placed with the plan's anchor at the grip (CarryPlace).
## Controls: reaching for it the grip is a full FLOOR_PALM_M over its edge, and
## the carry ends on the end's own held point.

const FloatCheck := preload("res://spike/carry_float_check.gd")
const FLOOR_AT := (SecurityLooks.Home.FLOOR * 2 + 0) * 2
const HAND_AT := (SecurityLooks.Home.HAND * 2 + 0) * 2
const GRIP := Vector3(-0.3, 0.8, 0.05)
const STEPS := 60

var _case: Node3D


func before_test() -> void:
	_case = InteriorKit.instantiate(SecurityLooks.KIND_PIECES[SecurityLooks.Kind.CASE]) as Node3D
	add_child(_case)


func after_test() -> void:
	_case.free()
	_case = null


## The ends a floor pick-up can go to at `scale_by`: the side carry and the
## front carry, both held at GRIP.
func _ends(scale_by: float) -> Dictionary:
	return {
		"side": CarryHand.carried(GRIP, Vector3.ZERO, 0.0, scale_by),
		"front": CarryHand.carried_in_front(GRIP, 0.0, scale_by),
	}


## The largest GRIP_ON gap over the carry of a floor pick-up ending at `want`,
## the case at `scale_by`: [largest gap, at k, steps held].
func _worst(want: Transform3D, scale_by: float) -> Array:
	var lying := Transform3D(
		Basis(Vector3.UP, PI / 2.0).scaled(Vector3.ONE * scale_by), Vector3(0.0, 0.0, 0.56)
	)
	var flags := {"from_floor": true, "yaw": 0.0, "hand": 0}
	var body := _body(scale_by)
	var worst := [-1.0, -1.0, 0]
	for step in STEPS + 1:
		var k := float(step) / STEPS
		var plan := CarryLead.plan(_bag(lying), k, lying, want, Transform3D(), flags, body)
		if int(plan["holder"]) < 0:
			continue
		var xf: Transform3D = plan["xf"]
		_case.global_transform = xf
		var gap := FloatCheck.case_grip_gap(_case, xf * (plan["anchor"] as Vector3))
		worst[2] += 1
		if gap > worst[0]:
			worst[0] = gap
			worst[1] = k
	return worst


## On every held step of the carry, into the side or the front carry, at either
## bag scale, the grip is no further off the handle face than FLOOR_PALM_M.
func test_off_the_floor_the_grip_stays_within_the_palm_of_the_handle_face() -> void:
	for scale_by: float in [0.9, 1.0, 1.1]:
		var ends := _ends(scale_by)
		for end: String in ends:
			var worst := _worst(ends[end], scale_by)
			print("floor pick-up into %s carry at %.1f: %s" % [end, scale_by, worst])
			assert_int(worst[2]).is_greater(STEPS / 2)
			assert_float(worst[0]).is_less_equal(CarryLead.FLOOR_PALM_M + 0.001)


## Controls: reaching for the case the grip is FLOOR_PALM_M over its edge (the
## check is engaged), and at the end of the carry the plan holds it by the end
## carry's own held point (the front carry's is over the handle, not the edge).
func test_the_palm_is_over_the_edge_at_the_reach_and_on_the_end_point_at_the_end() -> void:
	var lying := Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(0.0, 0.0, 0.56))
	var flags := {"from_floor": true, "yaw": 0.0, "hand": 0}
	var s := CarryLead.span(CarryLead.End.REST, CarryLead.End.HELD)
	var edge := CarryOnProps.grip_anchor(SecurityLooks.Kind.CASE)
	for end: String in ["side", "front"]:
		var want: Transform3D = _ends(1.0)[end]
		var reach := CarryLead.plan(
			_bag(lying), s.x * 0.5, lying, want, Transform3D(), flags, _body(1.0)
		)
		var over: Vector3 = reach["targets"][0] - lying * edge
		assert_vector(over).is_equal_approx(
			Vector3(0.0, CarryLead.FLOOR_PALM_M, 0.0), Vector3.ONE * 0.0001
		)
		var done := CarryLead.plan(
			_bag(lying), 0.999, lying, want, Transform3D(), flags, _body(1.0)
		)
		var held_end := want.affine_inverse() * GRIP
		print("%s carry end anchor %s, the end's held point %s" % [end, done["anchor"], held_end])
		assert_vector(done["anchor"] as Vector3).is_equal_approx(held_end, Vector3.ONE * 0.002)
	# The front carry's held point is not the edge (so the front case tests a
	# different end).
	var front_held: Vector3 = _ends(1.0)["front"].affine_inverse() * GRIP
	assert_float(front_held.distance_to(edge)).is_greater(0.1)


func _bag(lying: Transform3D) -> Dictionary:
	return {
		"was": FLOOR_AT,
		"carry_from": SecurityLooks.Carry.HAND,
		"home": HAND_AT,
		"carry": SecurityLooks.Carry.HAND,
		"kind": SecurityLooks.Kind.CASE,
		"led": true,
		"from": lying,
	}


func _body(scale_by: float) -> Dictionary:
	return {
		"hand": 0,
		"grips": [GRIP, Vector3(0.3, 0.8, 0.05)],
		"shoulders_y": [1.35, 1.35],
		"bar_z": 0.0,
		"scale": scale_by,
		"strap_top": Vector3.ZERO,
	}
