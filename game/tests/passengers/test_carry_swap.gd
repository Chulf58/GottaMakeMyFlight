extends GdUnitTestSuite
## CarrySwap: a roller going between hanging from the hand by its bar and the
## pull, in the same hand (board 6981b7ac part 3). A swap that turns back one
## under way goes back from where the roller is drawn, and the holding arm
## goes between the two poses with it.


## The clock of a swap that turns back one under way, drawn last at k (old,
## "placed_k"), in either direction: its share toward the pull at that draw
## is the old one's, at every k 0.05 apart. This pins the clock only; the
## roller's place at the turn is tested through the real views in
## test_carry_swap_reversal.gd. Control: started at the draw instead, the
## shares differ by up to the whole way (the 1.07 m jump).
func test_a_turned_back_swap_keeps_its_share_toward_the_pull() -> void:
	var worst := 0.0
	var worst_unfixed := 0.0
	for lifted in [false, true]:
		for step in range(1, 20):
			var k_old := step * 0.05
			var since := 100.0
			var drawn := since + k_old * CarryOnProps.TRANSFER_TICKS
			var bag := {
				"swap": true,
				"led": false,
				"since": since,
				"placed_k": k_old,
				"from": Transform3D.IDENTITY,
				"axle_now": Vector3(0.3, 0.03, -1.0),
			}
			var old_share := CarrySwap.pull_share(lifted, k_old)
			var changed := CarrySwap.start(bag, lifted, _body(Transform3D.IDENTITY), drawn + 0.2)
			var k_new := (drawn - changed) / CarryOnProps.TRANSFER_TICKS
			worst = maxf(worst, absf(CarrySwap.pull_share(not lifted, k_new) - old_share))
			var unfixed := absf(CarrySwap.pull_share(not lifted, 0.0) - old_share)
			worst_unfixed = maxf(worst_unfixed, unfixed)
	print("turned back: share gap %.6f, from the far end %.3f" % [worst, worst_unfixed])
	assert_float(worst).is_less(0.0001)
	assert_float(worst_unfixed).is_greater(0.9)


## start() keeps the old swap's trailing end: turning back to the pull it
## seeds the follower there (at the old draw's time), turning back to the hand
## it keeps the follower's last axle in the body's frame. Every other move
## starts at `now` with no kept end: after a hand-led move, a swap that has
## ended, a move that is not a swap, a bag with no move yet. Control: the
## turned-back swaps start before `now`.
func test_a_turned_back_swap_keeps_its_trailing_end() -> void:
	var now := 103.0
	var frame := Transform3D(Basis(Vector3.UP, 0.5), Vector3(2.0, 0.0, 1.0))
	var from := Transform3D(Basis.IDENTITY, Vector3(-0.6, 0.0, -0.95))
	var to_pull := {"swap": true, "led": false, "since": 100.0, "placed_k": 0.4, "from": from}
	assert_float(CarrySwap.start(to_pull, false, _body(frame), now)).is_less(now)
	var trail: Vector3 = frame * (from * CarryOnProps.ROLLER_AXLE)
	assert_vector(to_pull["drawn_axle"]).is_equal_approx(trail, Vector3.ONE * 0.0001)
	assert_float(to_pull["drawn_at"]).is_equal_approx(
		100.0 + 0.4 * CarryOnProps.TRANSFER_TICKS, 0.0001
	)
	var axle := Vector3(1.4, 0.03, 0.2)
	var to_hand := {"swap": true, "led": false, "since": 100.0, "placed_k": 0.4, "axle_now": axle}
	assert_float(CarrySwap.start(to_hand, true, _body(frame), now)).is_less(now)
	assert_vector(CarrySwap.hung_trail(to_hand, frame)).is_equal_approx(axle, Vector3.ONE * 0.0001)
	for bag: Dictionary in [
		{"swap": true, "led": true, "since": 100.0, "placed_k": 0.4, "from": from},
		{"swap": true, "led": false, "since": 100.0, "placed_k": 1.0, "from": from},
		{"swap": false, "led": false, "since": 100.0, "placed_k": 0.4, "from": from},
		{"swap": true, "led": false, "placed_k": 0.4, "from": from, "swap_trail": Vector3.ONE},
	]:
		assert_float(CarrySwap.start(bag, false, _body(frame), now)).is_equal(now)
		assert_bool(bag.has("drawn_axle") or bag.has("swap_trail")).is_false()


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
	assert_float(arm.swing_kept).is_equal(CarryArmPose.PULL_SWING_KEPT)
	assert_float(arm.lean_back_degrees).is_equal(CarryArmPose.PULL_LEAN_DEGREES)
	assert_float(arm.angle_degrees).is_equal(CarryArmPose.PULL_OUT_DEGREES)
	assert_float(arm.front_weight).is_equal(0.0)
	CarrySwap.pose_arm(arm, 0.5, front)
	var mid_swing := (CarrySwap.HAND_SWING_KEPT + CarryArmPose.PULL_SWING_KEPT) / 2.0
	assert_float(arm.swing_kept).is_equal_approx(mid_swing, 0.0001)
	assert_float(arm.lean_back_degrees).is_equal_approx(
		CarryArmPose.PULL_LEAN_DEGREES / 2.0, 0.0001
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


## A body node drawn at `frame`, freed after the test.
func _body(frame: Transform3D) -> Node3D:
	var body: Node3D = auto_free(Node3D.new())
	add_child(body)
	body.global_transform = frame
	return body
