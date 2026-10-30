class_name TestCarrySelfclip
extends GdUnitTestSuite
## The carry self-clip fixes after the floating-bag fix (board item 5ed915b0):
## the stoop is kept on through a floor pickup and a set-down, the hips go
## back as they drop, a bag lifted off the floor turns to hang sooner than one
## lifted off a tray, a bag set down on the floor goes out ahead before it goes
## down, and a hand reaching for or letting go of a pack on the back comes and
## goes by the side. Pure functions, no scene but the kit's bag bounds.

const FLOOR_AT := (SecurityLooks.Home.FLOOR * 2 + 0) * 2
const TRAY_AT := (SecurityLooks.Home.TRAY * 2 + 0) * 2
const HAND_AT := (SecurityLooks.Home.HAND * 2 + 0) * 2


## Lifting a bag off the floor the stoop is kept on through the reach and the
## first part of the carry, then let go; setting one down it comes on for the
## last part and the let-go. Off a tray, or between two hands, it never is.
func test_the_stoop_is_kept_through_a_floor_pickup_and_a_set_down() -> void:
	var rest := CarryLead.End.REST
	var held := CarryLead.End.HELD
	var s := CarryLead.span(rest, held)
	var at_t := func(t: float) -> float: return s.x + t * (s.y - s.x)
	assert_float(CarryLead.floor_keep(0.1, rest, held, true, false)).is_equal(1.0)
	assert_float(CarryLead.floor_keep(at_t.call(0.2), rest, held, true, false)).is_equal(1.0)
	var mid := CarryLead.floor_keep(at_t.call(0.47), rest, held, true, false)
	assert_float(mid).is_between(0.05, 0.95)
	assert_float(CarryLead.floor_keep(at_t.call(0.7), rest, held, true, false)).is_equal(0.0)
	# Off a tray (not the floor): the height fade alone.
	assert_float(CarryLead.floor_keep(0.1, rest, held, false, false)).is_equal(0.0)
	var down := CarryLead.span(held, rest)
	var down_t := func(t: float) -> float: return down.x + t * (down.y - down.x)
	assert_float(CarryLead.floor_keep(down_t.call(0.2), held, rest, false, true)).is_equal(0.0)
	assert_float(CarryLead.floor_keep(down_t.call(0.8), held, rest, false, true)).is_equal(1.0)
	assert_float(CarryLead.floor_keep(0.95, held, rest, false, true)).is_equal(1.0)
	assert_float(CarryLead.floor_keep(0.5, held, held, true, true)).is_equal(0.0)


## The hips going back as they drop take the stooped shoulder back by `back`
## at a full stoop, so a bag on the floor ahead needs a deeper stoop than with
## the hips straight down (and still less than a full one).
func test_hips_back_take_the_shoulder_back() -> void:
	var shoulder := Vector3(-0.2, 1.35, 0.0)
	var pivot := Vector3(0.0, 1.0, 0.0)
	var floor_bag := Vector3(-0.3, 0.3, 0.45)
	var straight := CarryStoop.stooped(shoulder, pivot, floor_bag, 1.0, 0.6, 0.0)
	var hinged := CarryStoop.stooped(shoulder, pivot, floor_bag, 1.0, 0.6, 0.2)
	assert_float(straight.z - hinged.z).is_equal_approx(0.2, 0.0001)
	var without := CarryStoop.needed(shoulder, pivot, floor_bag, floor_bag, 0.6, 0.6, 0.0)
	var with_back := CarryStoop.needed(shoulder, pivot, floor_bag, floor_bag, 0.6, 0.6, 0.2)
	assert_float(without).is_between(0.05, 0.99)
	assert_float(with_back).is_greater(without)
	assert_float(with_back).is_less(1.0)


## A hard case lifted off the floor has turned further toward hanging from the
## hand than one lifted off a tray at the same point of the carry (lying flat
## it met the thighs); both are placed from the hand.
func test_off_the_floor_a_case_turns_to_hang_sooner() -> void:
	var lying := Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(0.0, 0.0, 0.56))
	var hanging := CarryOnProps.carried(Vector3(-0.3, 0.8, 0.05), Vector3.ZERO, 0.0, 1.0)
	var k := CarryLead.REACH_SHARE + (1.0 - CarryLead.REACH_SHARE) * 0.15
	var turned := []
	for from_at: int in [FLOOR_AT, TRAY_AT]:
		var bag := _bag(from_at, lying)
		var flags := {"from_floor": from_at == FLOOR_AT, "yaw": 0.0, "hand": 0}
		var plan := CarryLead.plan(bag, k, lying, hanging, Transform3D(), flags, _body())
		assert_int(plan["holder"]).is_equal(0)
		var q: Quaternion = (plan["xf"] as Transform3D).basis.get_rotation_quaternion()
		turned.append(q.angle_to(hanging.basis.get_rotation_quaternion()))
	# Control: the tray's turn has started but is not done.
	assert_float(turned[1]).is_greater(0.05)
	assert_float(turned[0]).is_less(turned[1])


## Reaching for a pack on the back the hand starts at the side hang and ends at
## the loop; letting go of one it starts at the loop and ends at the side. In
## the carry the target is left as it is.
func test_a_hand_comes_and_goes_by_the_side_for_a_pack_on_the_back() -> void:
	var worn := CarryLead.End.WORN
	var rest := CarryLead.End.REST
	var body := _body()
	var loop := Vector3(0.0, 1.5, -0.25)
	var side := Vector3(-CarryLead.BACK_SIDE_M, body["shoulders_y"][0] - 0.1, 0.0)
	var s := CarryLead.span(worn, rest)
	var start := CarryLead.by_side(loop, 0.0, worn, rest, Transform3D(), 0.0, 0, body)
	assert_float(start.distance_to(side)).is_less(0.0001)
	var reached := CarryLead.by_side(loop, s.x - 0.001, worn, rest, Transform3D(), 0.0, 0, body)
	assert_float(reached.distance_to(loop)).is_less(0.01)
	var s_on := CarryLead.span(rest, worn)
	var gone := CarryLead.by_side(loop, 1.0, rest, worn, Transform3D(), 0.0, 0, body)
	assert_float(gone.distance_to(side)).is_less(0.0001)
	var letting := CarryLead.by_side(loop, s_on.y + 0.001, rest, worn, Transform3D(), 0.0, 0, body)
	assert_float(letting.distance_to(loop)).is_less(0.01)
	var carried := CarryLead.by_side(loop, 0.5, rest, worn, Transform3D(), 0.0, 0, body)
	assert_vector(carried).is_equal(loop)


## A bag set down on the floor ahead goes out ahead first and down late, lifted
## only CarryLead.SET_DOWN_LIFT_M: half way it is further ahead than the same
## move onto a tray's spot (a straight blend with the full lift) and lower than
## it, above the straight blend without a lift (down late), and at no point
## more than SET_DOWN_LIFT_M above where it started; both end at the spot.
## Changed for board item 5ed915b0: this test first pinned the set-down higher
## than the fully lifted blend half way, and that lift put the case top against
## the face of a passenger stooping to set it down (crossing probe SELF_HEAD
## gap 0.005 m at k 0.5); then it pinned no lift at all, which left the hand low
## beside the case's top corner, palm out, not on it (plate review).
func test_a_bag_set_down_on_the_floor_goes_out_ahead_first() -> void:
	var start := Transform3D(Basis(), Vector3(-0.3, 0.3, 0.05))
	var want := Transform3D(Basis(), Vector3(0.0, 0.0, 0.56))
	var flags := {"hand": 0, "yaw": 0.0, "clear": 0.0}
	var to_floor := flags.duplicate()
	to_floor["to_floor"] = true
	var plain := CarryLead.path(start, want, 0.5, Transform3D(), start, flags)
	var ahead := CarryLead.path(start, want, 0.5, Transform3D(), start, to_floor)
	assert_float(ahead.origin.z - plain.origin.z).is_greater(0.1)
	assert_float(plain.origin.y - ahead.origin.y).is_greater(0.05)
	var straight := lerpf(start.origin.y, want.origin.y, 0.5)
	assert_float(ahead.origin.y - straight).is_greater(0.05)
	for n in 21:
		var at := CarryLead.path(start, want, n / 20.0, Transform3D(), start, to_floor)
		assert_float(at.origin.y).is_less_equal(start.origin.y + CarryLead.SET_DOWN_LIFT_M)
	var landed := CarryLead.path(start, want, 1.0, Transform3D(), start, to_floor)
	assert_float(landed.origin.distance_to(want.origin)).is_less(0.0001)


## A roller swapping between the right hand and the pull at security from an
## axle that trailed behind the left leg: its axle starts and ends where it
## should and midway is round the right side, SWING_RADIUS_M or more from the
## body's centre, not behind the shins. Control: the straight blend midway is
## behind the body, within 0.1 m of its centre line.
func test_a_security_swap_goes_round_the_hand_side() -> void:
	var frame := Transform3D(Basis(Vector3.UP, 0.4), Vector3(2.0, 0.0, 1.0))
	var hung := frame * Vector3(-0.3, 0.35, 0.02)
	var trailing := frame * Vector3(0.15, 0.03, -0.95)
	var clear := CarryOnProps.SWING_RADIUS_M
	var at_start := CarryLead.swap_axle(frame, hung, trailing, 0.0, 0, clear)
	var at_end := CarryLead.swap_axle(frame, hung, trailing, 1.0, 0, clear)
	assert_float(at_start.distance_to(hung)).is_less(0.0001)
	assert_float(at_end.distance_to(trailing)).is_less(0.0001)
	var mid := frame.affine_inverse() * CarryLead.swap_axle(frame, hung, trailing, 0.5, 0, clear)
	assert_float(Vector2(mid.x, mid.z).length()).is_greater_equal(clear - 0.0001)
	assert_float(mid.x).is_less(-0.2)
	var straight := frame.affine_inverse() * hung.lerp(trailing, 0.5)
	assert_float(Vector2(straight.x, straight.z).length()).is_less(0.6)
	assert_float(absf(straight.x)).is_less(0.1)


func _bag(from_at: int, lying: Transform3D) -> Dictionary:
	return {
		"was": from_at,
		"carry_from": SecurityLooks.Carry.HAND,
		"home": HAND_AT,
		"carry": SecurityLooks.Carry.HAND,
		"kind": SecurityLooks.Kind.CASE,
		"led": true,
		"from": lying,
	}


func _body() -> Dictionary:
	return {
		"hand": 0,
		"grips": [Vector3(-0.3, 0.8, 0.05), Vector3(0.3, 0.8, 0.05)],
		"shoulders_y": [1.35, 1.35],
		"bar_z": 0.0,
		"scale": 1.0,
		"strap_top": Vector3.ZERO,
	}
