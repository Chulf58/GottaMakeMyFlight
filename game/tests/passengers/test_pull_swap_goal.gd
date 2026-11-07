class_name TestPullSwapGoal
extends GdUnitTestSuite
## A pulled roller passed between the pulling hands (CarryLead.pull_swap_goal,
## CarryLead.pull_swap_start; decision left-hand-roller-grip-as-built): the
## goal is the start's grip bar mirrored across the body with the axle where a
## straight pull trails it on the other side, whatever the receiving hand's own
## grip does before PULL_SWAP_END, and however wide the start was swung; the
## start turns round a turning walker no faster than RollerPull.SWING_TURN.
## Pure functions, no scene. The swung start is the cafe guest of
## test_roller_hand_change_reach on b91040f: stamped in a turn, its origin
## 0.484 m out on the right (0.302 m on a straight walk).

const SCALE := 1.0
## The roller's grip bar in its own frame (CarryLead.anchor(), rods half out).
const BAR := Vector3(0.0, 0.03, 0.75)
const EPS := 0.0005


## A right-hand pull with its axle at (`x`, -`z`) in the body's frame (body
## facing +Z, its right -X), bar at hand height ahead of the axle.
static func _pull(x: float, z: float) -> Transform3D:
	var axle := Vector3(x, CarryOnProps.ROLLER_AXLE.y * SCALE, -z)
	var grip := Vector3(-0.29, 0.94, 0.14)
	return RollerPull.pulled(grip, axle, SCALE)


static func _axle_x(goal: Transform3D, frame: Transform3D) -> float:
	return (frame.affine_inverse() * (goal * CarryOnProps.ROLLER_AXLE)).x


## Two different receiving-hand grips (the hand this move poses, drawn high or
## low on the first frame) give the same goal up to PULL_SWAP_END.x
## (anti-pattern a-carry-move-must-not-take-its-shape-from-the-hand-it-is-pos);
## at t 1 the goal is each want. Control: the two wants differ.
func test_the_goal_does_not_follow_the_receiving_hand() -> void:
	var frame := Transform3D(Basis(Vector3.UP, 0.7), Vector3(3.0, 0.0, -2.0))
	var from := _pull(-0.30, 1.0)
	var low := frame * RollerPull.pulled(Vector3(0.3, 0.8, 0.0), Vector3(0.3, 0.03, -1.0), SCALE)
	var high := frame * RollerPull.pulled(Vector3(0.1, 1.3, 0.3), Vector3(0.3, 0.03, -1.0), SCALE)
	var gap := low.origin.distance_to(high.origin) + (low.basis.z - high.basis.z).length()
	print("wants differ by %.3f" % gap)
	assert_float(gap).is_greater(0.1)
	for t: float in [0.0, 0.3, 0.6, CarryLead.PULL_SWAP_END.x]:
		var a := CarryLead.pull_swap_goal(from, low, frame, t, BAR)
		var b := CarryLead.pull_swap_goal(from, high, frame, t, BAR)
		assert_vector(a.origin).is_equal_approx(b.origin, Vector3.ONE * EPS)
		assert_vector(a.basis.z).is_equal_approx(b.basis.z, Vector3.ONE * EPS)
	var end := CarryLead.pull_swap_goal(from, high, frame, 1.0, BAR)
	assert_vector(end.origin).is_equal_approx(high.origin, Vector3.ONE * EPS)


## A start stamped swung wide in a turn (axle 0.48 m out) and one on a straight
## pull (0.30 m out) give a goal with its axle TRAIL_SIDE_M out on the other
## side and the grip bar mirrored: the mirrored start put the wide one's axle
## 0.48 m out, past where the receiving hand pulls it. Control: the two starts'
## axles are 0.18 m apart.
func test_a_wide_start_heads_for_the_straight_pull_on_the_other_side() -> void:
	var frame := Transform3D(Basis(Vector3.UP, -1.2), Vector3(-14.0, 0.0, -24.5))
	var want := frame * _pull(0.30, 1.0)
	for x: float in [-0.30, -0.48]:
		var from := _pull(x, 0.95)
		var goal := CarryLead.pull_swap_goal(from, want, frame, 0.5, BAR)
		var local := frame.affine_inverse() * goal
		# Its rods run from the axle toward the start's bar mirrored (the rods'
		# length is drawn as it is, not set here).
		var mirrored := from * BAR
		mirrored.x = -mirrored.x
		var toward := (mirrored - local * CarryOnProps.ROLLER_AXLE).normalized()
		print("start axle x %.3f: goal axle x %.3f, rods %s" % [x, _axle_x(goal, frame), toward])
		assert_float(_axle_x(goal, frame)).is_equal_approx(RollerPull.TRAIL_SIDE_M, EPS)
		assert_vector(local.basis.z.normalized()).is_equal_approx(toward, Vector3.ONE * EPS)
	var wide := absf((_pull(-0.48, 0.95) * CarryOnProps.ROLLER_AXLE).x)
	var straight := absf((_pull(-0.30, 0.95) * CarryOnProps.ROLLER_AXLE).x)
	assert_float(wide - straight).is_greater(0.15)


## The start of a change of hand turns round a walker turning faster than
## SWING_TURN by SWING_TURN a tick, and with one turning slower all the way;
## on the move's first frame it is where it was stamped. Control: the fast
## walker turned more than SWING_TURN.
func test_the_start_turns_no_faster_than_the_trailing_roller_swings() -> void:
	var began := Transform3D(Basis(Vector3.UP, 2.0), Vector3(1.0, 0.0, 1.0))
	var from := _pull(-0.48, 0.95)
	for rate: float in [deg_to_rad(22.0), deg_to_rad(10.0)]:
		var bag := {"start_body": began, "from": from}
		var at := CarryLead.pull_swap_start(bag, began, 100.0)
		assert_vector(at.origin).is_equal_approx((began * from).origin, Vector3.ONE * EPS)
		var yaw := 2.0
		var frame := began
		for i in 3:
			yaw -= rate / 3.0
			frame = Transform3D(Basis(Vector3.UP, yaw), began.origin + Vector3(0.0, 0.0, 0.03 * i))
			at = CarryLead.pull_swap_start(bag, frame, 100.0 + (i + 1) / 3.0)
		var turned := angle_difference(2.0, float(bag["swap_yaw"]))
		var expected := -minf(rate, RollerPull.SWING_TURN)
		print("body turned %.3f rad, start %.3f rad" % [-rate, turned])
		assert_float(turned).is_equal_approx(expected, 0.0001)
		var held := Transform3D(Basis(Vector3.UP, 2.0 + turned), frame.origin) * from
		assert_vector(at.origin).is_equal_approx(held.origin, Vector3.ONE * EPS)
	assert_float(deg_to_rad(22.0)).is_greater(RollerPull.SWING_TURN)
