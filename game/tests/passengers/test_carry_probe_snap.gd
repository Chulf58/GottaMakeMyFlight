class_name TestCarryProbeSnap
extends GdUnitTestSuite
## The carry probe's roller snap check (game/spike/carry_probe_checks.gd,
## decision carry-on-bag-kinds-as-built item 4): the allowance follows the sim
## time that really passed between two looks, so a broken follower is caught
## when several frames fall inside one tick, and nothing may move when no sim
## time passed.

const CarryChecks := preload("res://spike/carry_probe_checks.gd")


## Allowance: the speed limit over the time that passed plus the slack, and
## nothing but STILL_M at zero (or negative) time.
func test_the_allowance_follows_the_sim_time_that_passed() -> void:
	var limit := CarryOnProps.SWING_JUMP_M
	assert_float(CarryChecks.snap_allowance(1.0)).is_equal_approx(
		limit + CarryChecks.SNAP_SLACK_M, 0.0001
	)
	assert_float(CarryChecks.snap_allowance(0.1)).is_equal_approx(
		limit * 0.1 + CarryChecks.SNAP_SLACK_M, 0.0001
	)
	assert_float(CarryChecks.snap_allowance(0.0)).is_equal(CarryChecks.STILL_M)
	assert_float(CarryChecks.snap_allowance(-0.5)).is_equal(CarryChecks.STILL_M)


## The negative control: followers of known quality over frames inside one
## tick. Control of the control: the old allowance (time floored at a third of
## a tick) lets the creeping follower through, so the case is a real blind spot.
func test_a_broken_follower_inside_one_tick_is_caught() -> void:
	var counts := CarryChecks.snap_control()
	print("snap control, snaps counted: %s" % [counts])
	assert_int(counts["creeping"]).is_equal(CarryChecks.CONTROL_FRAMES)
	assert_int(counts["teleporting"]).is_equal(CarryChecks.CONTROL_FRAMES)
	assert_int(counts["following"]).is_equal(0)
	assert_int(counts["still"]).is_equal(0)
	# Controls: the good follower really moved, the still one did not.
	assert_float(counts["following travelled"]).is_greater(0.05)
	assert_float(counts["still travelled"]).is_equal(0.0)
	assert_int(counts["no time passed"]).is_equal(1)
	assert_bool(CarryChecks.snap_control_ok(counts)).is_true()
	# Control of the control: a check that lets the creeping follower through
	# is not ok.
	var blind := counts.duplicate()
	blind["creeping"] = 0
	assert_bool(CarryChecks.snap_control_ok(blind)).is_false()
	var old_allowance := CarryOnProps.SWING_JUMP_M * maxf(CarryChecks.CONTROL_DT, 0.34)
	assert_float(0.2).is_less(old_allowance)
	assert_float(0.2).is_greater(CarryChecks.snap_allowance(CarryChecks.CONTROL_DT))


## A move that is within the speed limit of the time that passed is not a snap,
## one a little beyond it is, and a sharp turn is counted apart.
func test_judging_one_look_counts_snaps_and_sharp_turns() -> void:
	var dt := 0.5
	var inside := CarryChecks.snap_allowance(dt) - 0.001
	var turns := [0, 0]
	CarryChecks.judge_pulled(
		1, [Vector3.ZERO, 0.0, 4.0], Vector3(inside, 0, 0), 0.0, 4.0 + dt, turns
	)
	assert_array(turns).is_equal([0, 0])
	CarryChecks.judge_pulled(
		1, [Vector3.ZERO, 0.0, 4.0], Vector3(inside + 0.01, 0, 0), PI / 2.0, 4.0 + dt, turns
	)
	assert_array(turns).is_equal([1, 1])
