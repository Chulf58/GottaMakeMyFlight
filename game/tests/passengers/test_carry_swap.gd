extends GdUnitTestSuite
## CarrySwap: a roller going between hanging from the hand by its bar and the
## pull, in the same hand (board 6981b7ac part 3). A swap that turns back one
## under way goes back from where the roller is drawn, and the holding arm
## goes between the two poses with it.


## A swap to the pull that turns back a swap to the hand under way at k (old)
## is started so that its share toward the pull at the turn equals the old
## one's (the roller is drawn where it was): at every k 0.05 apart. Control:
## started at `now` instead, as before the fix, the shares differ by up to the
## whole way (the 1.07 m jump).
func test_a_turned_back_swap_goes_on_from_where_the_roller_is() -> void:
	var worst := 0.0
	var worst_unfixed := 0.0
	for step in range(1, 20):
		var k_old := step * 0.05
		var since := 100.0
		var now := since + k_old * CarryOnProps.TRANSFER_TICKS
		var bag := {"swap": true, "led": false, "since": since}
		var old_share := CarrySwap.pull_share(false, k_old)
		var changed := CarrySwap.changed_at(bag, false, now)
		var k_new := (now - changed) / CarryOnProps.TRANSFER_TICKS
		worst = maxf(worst, absf(CarrySwap.pull_share(true, k_new) - old_share))
		worst_unfixed = maxf(worst_unfixed, absf(CarrySwap.pull_share(true, 0.0) - old_share))
	print("turned back: share gap %.6f, from the far end %.3f" % [worst, worst_unfixed])
	assert_float(worst).is_less(0.0001)
	assert_float(worst_unfixed).is_greater(0.9)


## changed_at() starts every other move at `now`: a swap back to the hand (it
## begins at the roller as drawn), a swap after a hand-led move (not a swap
## under way), after a swap that has ended, and a bag with no move yet.
## Control: the turned-back swap is started before `now`.
func test_only_a_swap_to_the_pull_turning_one_back_starts_early() -> void:
	var now := 103.0
	var under_way := {"swap": true, "led": false, "since": 100.0}
	assert_float(CarrySwap.changed_at(under_way, false, now)).is_less(now)
	assert_float(CarrySwap.changed_at(under_way, true, now)).is_equal(now)
	var led := {"swap": true, "led": true, "since": 100.0}
	assert_float(CarrySwap.changed_at(led, false, now)).is_equal(now)
	var ended := {"swap": true, "led": false, "since": now - CarryOnProps.TRANSFER_TICKS}
	assert_float(CarrySwap.changed_at(ended, false, now)).is_equal(now)
	var not_swap := {"swap": false, "led": false, "since": 100.0}
	assert_float(CarrySwap.changed_at(not_swap, false, now)).is_equal(now)
	assert_float(CarrySwap.changed_at({"swap": true, "led": false}, false, now)).is_equal(now)


## The holding arm is posed between the hand carry (share 0) and the pull
## (share 1): each value is the hand's at 0, the pull's at 1 and midway at
## 0.5. Control: a hand not swapping (share -1) is left as it was.
func test_the_holding_arm_goes_between_the_two_poses() -> void:
	var arm: CarryArm = auto_free(CarryArm.new())
	var front := 0.4
	CarrySwap.pose_arm(arm, 0.0, front)
	assert_float(arm.swing_kept).is_equal(CarrySwap.HAND_SWING_KEPT)
	assert_float(arm.lean_back_degrees).is_equal(0.0)
	assert_float(arm.front_weight).is_equal(front)
	CarrySwap.pose_arm(arm, 1.0, front)
	assert_float(arm.swing_kept).is_equal(CarryOnProps.PULL_SWING_KEPT)
	assert_float(arm.lean_back_degrees).is_equal(CarryOnProps.PULL_LEAN_DEGREES)
	assert_float(arm.angle_degrees).is_equal(CarryOnProps.PULL_OUT_DEGREES)
	assert_float(arm.front_weight).is_equal(0.0)
	CarrySwap.pose_arm(arm, 0.5, front)
	var mid_swing := (CarrySwap.HAND_SWING_KEPT + CarryOnProps.PULL_SWING_KEPT) / 2.0
	assert_float(arm.swing_kept).is_equal_approx(mid_swing, 0.0001)
	assert_float(arm.lean_back_degrees).is_equal_approx(
		CarryOnProps.PULL_LEAN_DEGREES / 2.0, 0.0001
	)
	assert_float(arm.front_weight).is_equal_approx(front / 2.0, 0.0001)
	var swing := arm.swing_kept
	CarrySwap.pose_arm(arm, -1.0, front)
	assert_float(arm.swing_kept).is_equal(swing)


## arm_shares() gives the share of the hand holding a roller that is swapping
## to the pull (here the left), and -1 for the other hand, for a swap that
## has ended and for a hand-led move. Control: the share is the one
## pull_share() gives at the bag's k.
func test_arm_shares_name_the_swapping_hand() -> void:
	var now := 103.0
	var swapping := {"swap": true, "since": 100.0, "carry": SecurityLooks.Carry.PULL}
	var held := {
		"bags": [swapping],
		"homes": [SecurityLooks.Home.HAND],
		"hands": [1],
	}
	var shares := CarrySwap.arm_shares(held, now)
	var k := 3.0 / CarryOnProps.TRANSFER_TICKS
	assert_float(shares[0]).is_equal(-1.0)
	assert_float(shares[1]).is_equal_approx(CarrySwap.pull_share(true, k), 0.0001)
	assert_float(shares[1]).is_greater(0.0)
	swapping["since"] = now - CarryOnProps.TRANSFER_TICKS
	assert_float(CarrySwap.arm_shares(held, now)[1]).is_equal(-1.0)
	swapping["since"] = 100.0
	swapping["swap"] = false
	assert_float(CarrySwap.arm_shares(held, now)[1]).is_equal(-1.0)
