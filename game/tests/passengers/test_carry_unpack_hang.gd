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
