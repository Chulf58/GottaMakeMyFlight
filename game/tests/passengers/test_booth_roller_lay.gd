class_name TestBoothRollerLay
extends GdUnitTestSuite
## A booth guest that pulls its roller in the hand on the walled side lays it
## on the open side (BoothRoller.side(), ParkSide): the set-down parks it on
## the pulling hand's side and lays it across in front of the feet. Laid on a
## straight line with CarryLead.keep_out()'s push from the body's centre, the
## push turned from one side to the other as the line passed 0.08 m ahead of
## the centre, and the roller jumped 0.43 m in a third of a tick
## (food_seats_probe booth_alt_13-1, seed 1885947358, k9; board 2eaa9bc4).

## A third of a tick, as the windowed probe steps the clock.
const FRAME_K := 1.0 / (3.0 * RollerPark.TICKS_DOWN)
## The most the roller may move in one frame of the lay: about 0.9 m round the
## front in the lay's 9 frames peaks at 2 / 9 of it, 0.2 m, at an even pull
## (the jump was 0.43 m in the probe, 0.53 m here).
const STEP_MAX_M := 0.25
## The most a frame's move may grow over the frame before (food_seats_probe's
## BAG_KINK_M).
const KINK_M := 0.05
## The least distance of the roller's origin from the body's centre on any
## frame of the lay (it starts and ends 0.32 m out).
const CLEAR_MIN_M := 0.3


## A pull>floor of a roller pulled in the left hand (1) to a floor place of
## the right hand (0), parked in `park_frame` at a booth seat (an empty
## "wall_faces", as BoothRoller.fix_start() keeps one).
func _bag(park_frame: Transform3D) -> Dictionary:
	return {
		"kind": SecurityLooks.Kind.ROLLER,
		"was": SecurityLooks.Home.HAND * 4 + 2,
		"carry_from": SecurityLooks.Carry.PULL,
		"carry": SecurityLooks.Carry.PULL,
		"home": SecurityLooks.Home.FLOOR * 4,
		"from_holder": 1,
		"park": true,
		"ticks": RollerPark.TICKS_DOWN,
		"park_frame": park_frame,
		"faced": true,
		"wall_faces": [],
	}


## The roller's origin drawn by RollerPark.plan() at each frame from the park's
## end to the move's end, the body drawn at `frame`.
func _lay(park_frame: Transform3D, frame: Transform3D, want: Transform3D) -> Array[Vector3]:
	var bag := _bag(park_frame)
	var start := park_frame * Transform3D(Basis.IDENTITY, Vector3(0.3, 0.0, -0.5))
	var looks := {"scale": 1.0, "bar_z": 0.9, "grips": [Vector3.ZERO, Vector3.ZERO]}
	var out: Array[Vector3] = []
	var k := RollerPark.PARK_END - FRAME_K
	while k <= 1.0:
		var plan := RollerPark.plan(bag, k, start, want, frame, {"to_floor": true}, looks)
		out.append((plan["xf"] as Transform3D).origin)
		k += FRAME_K
	return out


## [largest step, largest growth of a step over the one before] of `at`.
func _steps(at: Array[Vector3]) -> Vector2:
	var most := 0.0
	var kink := 0.0
	var last := -1.0
	for i in range(1, at.size()):
		var step := at[i].distance_to(at[i - 1])
		most = maxf(most, step)
		if last >= 0.0:
			kink = maxf(kink, step - last)
		last = step
	return Vector2(most, kink)


## Laid across from the pulling hand's side to the open side, the roller moves
## no more than STEP_MAX_M a frame, its step grows by no more than KINK_M, and
## it stays CLEAR_MIN_M from the body's centre while it crosses. Control: it
## started on the left, ended on the right, and moved.
func test_a_booth_roller_laid_across_moves_smoothly_round_the_front() -> void:
	var park_frame := Transform3D(Basis.IDENTITY, Vector3(-15.5, 0.22, -95.5))
	var want := park_frame * Transform3D(Basis.IDENTITY, Vector3(-RollerPark.PARK_SIDE_M, 0, 0))
	var at := _lay(park_frame, park_frame, want)
	var steps := _steps(at)
	var nearest := INF
	for point in at:
		var local := park_frame.affine_inverse() * point
		nearest = minf(nearest, Vector2(local.x, local.z).length())
	var first := park_frame.affine_inverse() * at[0]
	var last := park_frame.affine_inverse() * at[at.size() - 1]
	print(
		(
			(
				"booth lay across: frames %d, largest step %.3f m, growth %.3f m,"
				+ " nearest %.3f m, from x %.3f to %.3f"
			)
			% [at.size(), steps.x, steps.y, nearest, first.x, last.x]
		)
	)
	assert_float(first.x).is_greater(0.2)
	assert_float(last.x).is_less(-0.2)
	assert_float(steps.x).is_greater(0.01)
	assert_float(steps.x).is_less_equal(STEP_MAX_M)
	assert_float(steps.y).is_less_equal(KINK_M)
	assert_float(nearest).is_greater_equal(CLEAR_MIN_M)


## The crossing lay takes its way from the park's frame, not from the body as
## drawn: a body drawn turned and stepped 0.2 m lays the roller on the same
## points. Control: the two bodies differ.
func test_a_booth_roller_lay_does_not_follow_the_drawn_body() -> void:
	var park_frame := Transform3D(Basis.IDENTITY, Vector3(2.0, 0.0, 3.0))
	var want := park_frame * Transform3D(Basis.IDENTITY, Vector3(-RollerPark.PARK_SIDE_M, 0, 0))
	var moved := Transform3D(Basis(Vector3.UP, 0.4), park_frame.origin + Vector3(0.2, 0.0, 0.1))
	var still := _lay(park_frame, park_frame, want)
	var turned := _lay(park_frame, moved, want)
	var most := 0.0
	for i in still.size():
		most = maxf(most, still[i].distance_to(turned[i]))
	print("booth lay, body moved 0.22 m and turned: largest difference %.4f m" % most)
	assert_float(moved.origin.distance_to(park_frame.origin)).is_greater(0.2)
	assert_float(most).is_less(0.001)


## A guest that walked in pulling on its left and turned round to face out of
## the booth has its roller on its right of that facing: the set-down is led by
## the floor place's hand (the right, RollerPark.set_down_hand()) and parks the
## roller on that side, so it is not laid across. Control: the same move with
## the roller left on the pulling hand's side is led by that hand, parked on
## its side and laid across.
func test_a_turned_booth_guest_sets_down_from_the_roller_side_hand() -> void:
	var park_frame := Transform3D(Basis.IDENTITY, Vector3(1.0, 0.0, 2.0))
	var want := park_frame * Transform3D(Basis.IDENTITY, Vector3(-RollerPark.PARK_SIDE_M, 0, 0))
	var looks := {"scale": 1.0, "bar_z": 0.9, "grips": [Vector3.ZERO, Vector3.ZERO]}
	var leads: Array[int] = []
	var crossed: Array[bool] = []
	var parked_x: Array[float] = []
	for side in [-1.0, 1.0]:
		var bag := _bag(park_frame)
		var start := park_frame * Transform3D(Basis.IDENTITY, Vector3(0.3 * side, 0.0, 0.5))
		bag["from_world"] = start
		leads.append(RollerPark.set_down_hand(bag))
		var plan := RollerPark.plan(bag, 0.5, start, want, park_frame, {"to_floor": true}, looks)
		var xf: Transform3D = plan["xf"]
		parked_x.append((park_frame.affine_inverse() * xf.origin).x)
		crossed.append(RollerPark.across(park_frame, xf, want))
	print("turned booth guest: leads %s, parked x %s, crosses %s" % [leads, parked_x, crossed])
	assert_array(leads).is_equal([0, 1])
	assert_float(parked_x[0]).is_less(-0.2)
	assert_bool(crossed[0]).is_false()
	assert_float(parked_x[1]).is_greater(0.2)
	assert_bool(crossed[1]).is_true()
