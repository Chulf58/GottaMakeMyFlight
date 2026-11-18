extends GdUnitTestSuite
## Standing at a lane's unpack cell, an arm's kept swing eases to none over
## CarryArmPose.UNPACK_HANG_TICKS, so a bag in the hand hangs at the side: a
## runner's frozen run stride held a lifted roller 0.55 m ahead, into the arch's
## posts (crossing probe --lane --sweep=29, seed 1106001, board c2bb3bc0). The
## share comes from the sim's UNPACK work and the sim time, never from the pose
## drawn. Pure: no scene.


## A passenger at a lane's UNPACK with `left` ticks of work left.
static func _unpacking(left: int) -> Passenger:
	var p := Passenger.new()
	p.carry_on = 1
	p.stage = Passenger.Stage.SECURITY
	p.security_phase = SecurityRuntime.Phase.UNPACK
	p.security_work = left
	return p


## Off UNPACK there is no share (control: a walker in the queue or the arch
## keeps the swing); at UNPACK the work done counts up from 0.
func test_unpack_done_counts_only_at_unpack() -> void:
	var work := SecurityRuntime.work_for(SecurityRuntime.Phase.UNPACK, _unpacking(0))
	assert_int(CarryArmPose.unpack_done(_unpacking(work))).is_equal(0)
	assert_int(CarryArmPose.unpack_done(_unpacking(work - 2))).is_equal(2)
	var walking := _unpacking(work)
	walking.security_phase = SecurityRuntime.Phase.ARCH
	assert_int(CarryArmPose.unpack_done(walking)).is_equal(-1)
	walking.stage = Passenger.Stage.SECURITY_QUEUE
	walking.security_phase = SecurityRuntime.Phase.UNPACK
	assert_int(CarryArmPose.unpack_done(walking)).is_equal(-1)


## The share rises from 0 at UNPACK's first tick to 1 by UNPACK_HANG_TICKS,
## through the tick's drawn fraction, and is 0 off UNPACK.
func test_the_swing_eases_out_over_the_hang_ticks() -> void:
	assert_float(CarryArmPose.unpack_still({"unpack_done": -1}, 500.7)).is_equal(0.0)
	assert_float(CarryArmPose.unpack_still({}, 500.7)).is_equal(0.0)
	assert_float(CarryArmPose.unpack_still({"unpack_done": 0}, 500.0)).is_equal(0.0)
	var part := CarryArmPose.unpack_still({"unpack_done": 0}, 500.5)
	var more := CarryArmPose.unpack_still({"unpack_done": 1}, 500.0)
	assert_float(part).is_greater(0.0)
	assert_float(more).is_greater(part)
	assert_float(more).is_less(1.0)
	var hang := ceili(CarryArmPose.UNPACK_HANG_TICKS)
	assert_float(CarryArmPose.unpack_still({"unpack_done": hang}, 501.0)).is_equal(1.0)


## A lifted roller's put-in record: from the right hand (carried by hand) into
## the tray, its plan holding it in hand 0 with lead weight `weight`.
static func _put_in(weight: float, carry_from := SecurityLooks.Carry.HAND) -> Dictionary:
	return {
		"was": SecurityLooks.Home.HAND * 4,
		"carry_from": carry_from,
		"lead": {"holder": 0, "weights": [weight, 0.0]},
	}


## Set down from a hand carry, the hand keeps its HAND carry pose (so its target
## at the move's start is the carry pose's grip, not the clip's hand) until the
## plan weighs it fully on its target; then the plan's target alone. Controls:
## none once the bag is home in the tray, none from a pull or a worn carry, none
## for the other hand, none before any plan.
func test_a_hand_set_down_keeps_the_carry_pose_until_the_lead_takes_over() -> void:
	var tray := SecurityLooks.Home.TRAY
	assert_bool(CarryArmPose.leaving_hand(_put_in(0.0), tray, 0, 0.01)).is_true()
	assert_bool(CarryArmPose.leaving_hand(_put_in(0.6), tray, 0, 0.2)).is_true()
	assert_bool(CarryArmPose.leaving_hand(_put_in(1.0), tray, 0, 0.3)).is_false()
	assert_bool(CarryArmPose.leaving_hand(_put_in(0.0), tray, 0, 1.0)).is_false()
	assert_bool(CarryArmPose.leaving_hand(_put_in(0.0), tray, 1, 0.01)).is_false()
	var pulled := _put_in(0.0, SecurityLooks.Carry.PULL)
	assert_bool(CarryArmPose.leaving_hand(pulled, tray, 0, 0.01)).is_false()
	var no_plan := _put_in(0.0)
	no_plan.erase("lead")
	assert_bool(CarryArmPose.leaving_hand(no_plan, tray, 0, 0.01)).is_false()
	var from_tray := _put_in(0.0)
	from_tray["was"] = tray * 4
	assert_bool(CarryArmPose.leaving_hand(from_tray, SecurityLooks.Home.HAND, 0, 0.01)).is_false()


## The carry pose's hand at the start is where the plan aims it: a lifted
## roller's put-in plan at k just above 0 aims the hand at the handle where the
## bag hung (plan data), weight still under 1, so the carry pose holds it.
func test_the_put_in_plan_starts_at_the_hung_handle_with_the_carry_pose_on() -> void:
	var start := Transform3D(Basis(Vector3.RIGHT, -PI / 2.0), Vector3(-0.3, 0.65, 0.1))
	var bag := {
		"kind": SecurityLooks.Kind.ROLLER,
		"home": SecurityLooks.Home.TRAY * 4,
		"carry": SecurityLooks.Carry.PULL,
		"carry_from": SecurityLooks.Carry.HAND,
		"was": SecurityLooks.Home.HAND * 4,
		"from": start,
		"anchor_from": CarryOnProps.ROLLER_HANDLE,
		"hung_at": CarryOnProps.ROLLER_HANDLE,
		"start_body": Transform3D(),
	}
	var body := {
		"hand": 0,
		"grips": [Vector3(-0.25, 1.2, 0.3), Vector3(0.25, 1.2, 0.3)],
		"shoulders_y": [1.4, 1.4],
		"bar_z": 0.32,
		"scale": 1.0,
		"strap_top": Vector3.ZERO,
	}
	var flags := {"hand": 0, "clear": CarryOnProps.TRANSFER_CLEAR_M, "yaw": 0.0}
	var want := Transform3D(Basis(), Vector3(-0.9, 0.75, 0.4))
	var plan := CarryLead.plan(bag, 0.01, start, want, Transform3D(), flags, body)
	bag["lead"] = plan
	print(
		(
			"k 0.01 holder %d weights %s target %s"
			% [plan["holder"], plan["weights"], plan["targets"][0]]
		)
	)
	assert_int(plan["holder"]).is_equal(0)
	var handle := start * CarryOnProps.ROLLER_HANDLE
	# Within the 3 cm the path has moved by k 0.01; the bar is 25 cm off.
	var bar := start * Vector3(0.0, CarryOnProps.ROLLER_AXLE.y, 0.32)
	assert_float((plan["targets"][0] as Vector3).distance_to(handle)).is_less(0.05)
	assert_float((plan["targets"][0] as Vector3).distance_to(bar)).is_greater(0.15)
	assert_vector(plan["anchor"]).is_equal_approx(CarryOnProps.ROLLER_HANDLE, Vector3.ONE * 1e-4)
	assert_float(plan["weights"][0]).is_less(1.0)
	assert_bool(CarryArmPose.leaving_hand(bag, SecurityLooks.Home.TRAY, 0, 0.01)).is_true()


## An ordinary roller lifted from the pull into the hand at UNPACK, its set-down
## into the tray stamped before that six-tick swap ends (Sol review of
## b30e1fcc): the set-down is held by the point stamped from the bag's geometry
## ("hung_at"), not the hand drawn last ("anchor_from"), so a view drawn on every
## tick (the swap last drawn three ticks in) and one drawn late (last drawn on
## the swap's first tick) stamp different held points, and the set-down plans
## the same targets, place and anchor at every k. Control: the two stamped held
## points are more than 1 cm apart (the swap's own plan, at those ticks).
func test_a_set_down_cutting_a_pull_to_hand_swap_plans_the_same_whenever_drawn() -> void:
	var frame := Transform3D(Basis(Vector3.UP, 0.4), Vector3(2.0, 0.0, -1.0))
	var body := {
		"hand": 0,
		"grips": [frame * Vector3(-0.25, 0.8, 0.1), frame * Vector3(0.25, 0.8, 0.1)],
		"shoulders_y": [1.4, 1.4],
		"bar_z": 0.6,
		"scale": 1.0,
		"strap_top": Vector3.ZERO,
	}
	var flags := {"in_stall": false, "hand": 0, "yaw": 0.4, "clear": 0.0}
	var pulled := (
		frame * RollerPull.pulled(Vector3(-0.25, 0.8, 0.1), Vector3(-0.3, 0.03, -0.6), 1.0)
	)
	var lifted := frame * Transform3D(Basis(), Vector3(-0.25, 0.35, 0.1))
	var swap := {
		"kind": SecurityLooks.Kind.ROLLER,
		"home": SecurityLooks.Home.HAND * 4,
		"carry": SecurityLooks.Carry.HAND,
		"was": SecurityLooks.Home.HAND * 4,
		"carry_from": SecurityLooks.Carry.PULL,
		"from": frame.affine_inverse() * pulled,
		"anchor_from": CarryOnProps.ROLLER_HANDLE,
		"start_shoulder_y": 1.4,
	}
	var drawn := []
	for ticks: float in [3.0, 1.0]:
		var k := ticks / CarryOnProps.TRANSFER_TICKS
		drawn.append(CarryLead.plan(swap, k, pulled, lifted, frame, flags, body)["anchor"])
	var tray := frame * Transform3D(Basis(Vector3.RIGHT, -PI / 2.0), Vector3(-0.8, 0.75, 0.4))
	# Stamped from the bag's geometry (CarryPlace.hung_grip()), the same for both.
	var hung := Vector3(0.0, CarryOnProps.ROLLER_AXLE.y - CarryHand.BAR_PALM_M, 0.6)
	var seen := []
	for held: Vector3 in drawn:
		var down := {
			"kind": SecurityLooks.Kind.ROLLER,
			"home": SecurityLooks.Home.TRAY * 4,
			"carry": SecurityLooks.Carry.PULL,
			"was": SecurityLooks.Home.HAND * 4,
			"carry_from": SecurityLooks.Carry.HAND,
			"anchor_from": held,
			"hung_at": hung,
			"from": frame.affine_inverse() * lifted,
			"start_shoulder_y": 1.4,
		}
		var plans := []
		for step in 21:
			plans.append(CarryLead.plan(down, step / 20.0, lifted, tray, frame, flags, body))
		seen.append(plans)
	var apart := 0.0
	for step in 21:
		var every: Dictionary = seen[0][step]
		var late: Dictionary = seen[1][step]
		for hand in 2:
			var at: Vector3 = every["targets"][hand]
			apart = maxf(apart, at.distance_to(late["targets"][hand]))
		apart = maxf(apart, (every["anchor"] as Vector3).distance_to(late["anchor"]))
		apart = maxf(apart, every["xf"].origin.distance_to(late["xf"].origin))
	print(
		(
			"held drawn every tick %s, drawn late %s; set-down plans apart by %.5f m"
			% [drawn[0], drawn[1], apart]
		)
	)
	assert_float((drawn[0] as Vector3).distance_to(drawn[1])).is_greater(0.01)
	assert_float(apart).is_less(0.0001)
