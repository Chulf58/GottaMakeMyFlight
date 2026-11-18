extends GdUnitTestSuite
## A backpack held by its grab loop on or off the back is turned about the grip
## so the loop lies across the holding hand (CarryLead.loop_yaw(), board
## bcad1dd0): out of a lane tray the hand lay along the loop and its fingertips
## went into the pack past the loop's ends. Pure: no scene. The clip itself is
## checked only by the windowed crossing probe (anti-pattern 6d691dee).


## A pack standing upright (its z axis up, as worn or hung) turned `yaw`
## about world up, tipped `tilt` about its own x, its origin at `at`.
static func _pack(yaw: float, at: Vector3, tilt := 0.0) -> Transform3D:
	var upright := Basis(Vector3.RIGHT, -PI / 2.0)
	return Transform3D(Basis(Vector3.UP, yaw) * upright * Basis(Vector3.RIGHT, tilt), at)


## Fully turned, the pack hangs plumb (its z axis up) with its loop (its x)
## square to the hand's level way, for hands pointing every way round and
## packs tipped either way, and the grip stays where it was; the turn about up
## is never more than a quarter turn. Control: the tipped packs did start off
## plumb.
func test_the_pack_hangs_plumb_with_the_loop_across_the_hand() -> void:
	var grip := Vector3(0.3, 1.0, 0.4)
	var checked := 0
	var tipped := 0
	for i in 12:
		for j in 8:
			var tilt: float = [0.0, 0.4, -0.3][j % 3]
			var start := _pack(TAU * j / 8.0 + 0.1, grip + Vector3(-0.05, -0.2, 0.08), tilt)
			tipped += int(start.basis.z.normalized().dot(Vector3.UP) < 0.99)
			var level := Vector3(cos(TAU * i / 12.0), -0.3, sin(TAU * i / 12.0))
			var got := CarryLead.loop_yaw(start, grip, level, 1.0)
			var flat := Vector3(level.x, 0.0, level.z).normalized()
			assert_float(absf(got.basis.x.normalized().dot(flat))).is_less(0.001)
			assert_vector(got.basis.z.normalized()).is_equal_approx(
				Vector3.UP, Vector3.ONE * 0.0001
			)
			# The grip, in the pack's frame, is the same point.
			var held := start.affine_inverse() * grip
			assert_vector(got * held).is_equal_approx(grip, Vector3.ONE * 0.0001)
			var plumb := Basis(Quaternion(start.basis.z.normalized(), Vector3.UP)) * start.basis
			var turned := plumb.x.angle_to(got.basis.x)
			assert_float(turned).is_less_equal(PI / 2.0 + 0.0001)
			checked += 1
	assert_int(checked).is_equal(96)
	assert_int(tipped).is_greater(40)


## A loop already across the hand is not turned; weight 0 leaves the pack as
## placed; half weight turns half the angle (the control: the full turn there
## is not zero).
func test_weight_and_a_loop_already_across() -> void:
	var grip := Vector3(0.0, 1.0, 0.0)
	var across := _pack(0.0, Vector3(0.1, 0.8, 0.0))
	var got := CarryLead.loop_yaw(across, grip, Vector3(0.0, 0.0, 1.0), 1.0)
	assert_vector(got.basis.x).is_equal_approx(across.basis.x, Vector3.ONE * 0.0001)
	var along := _pack(PI / 3.0, Vector3(0.1, 0.8, 0.0))
	var level := Vector3(1.0, 0.0, 0.0)
	var none := CarryLead.loop_yaw(along, grip, level, 0.0)
	assert_vector(none.basis.x).is_equal_approx(along.basis.x, Vector3.ONE * 0.0001)
	var full := along.basis.x.angle_to(CarryLead.loop_yaw(along, grip, level, 1.0).basis.x)
	var half := along.basis.x.angle_to(CarryLead.loop_yaw(along, grip, level, 0.5).basis.x)
	assert_float(full).is_greater(0.1)
	assert_float(half).is_equal_approx(full * 0.5, 0.0001)


## The plan turns the pack only while the hand holds it on a move on or off the
## back, eased in from 0 at the carry's start and out to 0 at its end.
func test_plan_eases_the_turn_over_a_back_move() -> void:
	var got := []
	for n in 21:
		got.append(_plan_yaw(n / 20.0))
	print("loop_yaw over k: ", got)
	assert_float(got[0]).is_equal(0.0)
	assert_float(got[20]).is_equal(0.0)
	assert_float(got.max()).is_equal_approx(1.0, 0.0001)
	var ramp := CarryLead.span(CarryLead.End.REST, CarryLead.End.WORN)
	assert_float(_plan_yaw(ramp.x + 0.001)).is_less(0.01)
	assert_float(_plan_yaw(ramp.y - 0.001)).is_less(0.01)


## loop_yaw of a backpack's move out of a tray onto the back at `k`.
static func _plan_yaw(k: float) -> float:
	var frame := Transform3D(Basis(), Vector3.ZERO)
	var bag := {
		"kind": SecurityLooks.Kind.BACKPACK,
		"home": SecurityLooks.Home.HAND * 4 + 2,
		"carry": SecurityLooks.Carry.BACK,
		"carry_from": SecurityLooks.Carry.BACK,
		"was": SecurityLooks.Home.TRAY * 4,
		"from": Transform3D(Basis(), Vector3(0.4, 0.9, 0.5)),
		"start_body": frame,
		"start_shoulder_y": 1.4,
	}
	var body := {
		"hand": 0,
		"grips": [Vector3(-0.3, 0.9, 0.0), Vector3(0.3, 0.9, 0.0)],
		"shoulders_y": [1.4, 1.4],
		"bar_z": 0.0,
		"scale": 1.0,
		"look": -1,
		"strap_top": Vector3.ZERO,
	}
	var flags := {"in_stall": false, "yaw": 0.0, "clear": 0.25, "hand": 0}
	var plan := CarryLead.plan(
		bag,
		k,
		Transform3D(Basis(), Vector3(0.4, 0.9, 0.5)),
		Transform3D(Basis(), Vector3(0.0, 1.1, -0.2)),
		frame,
		flags,
		body
	)
	return plan["loop_yaw"]
