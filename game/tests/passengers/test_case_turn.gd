class_name TestCaseTurn
extends GdUnitTestSuite
## CaseTurn.turn(): a hard case turning between the side carry and the front
## carry about the grip, built from the real CarryHand.carried() and
## carried_in_front() bases. No game scene.

const _CENTRE := Vector3(0.0, 0.0, 0.0)
const _GRIP_OUT_M := 0.3
const _GRIP_Y := 1.07
const _STEPS := 40
## The bottom end counts as hanging below the hand when it points more than
## 30 degrees below level.
const _HANGING_Y := -0.5


## For each hand, at body yaws 0 and 90 degrees, over the turn to the front
## (weight 0 to 1, 40 steps): while the case's bottom end hangs below the
## hand it never points in toward the body's centre line, where a striding
## thigh is (crossing probe case_turn: a right-hand case's bottom end swung in
## under the hand, 30 thigh points inside the case at 2.4 m out). The
## straight slerp this replaced points it in by 0.71 at weight 0.5 while still
## 45 degrees down. Control: the ends are the side and front carries, and the
## bottom end does come round to point inward by the end for one hand.
func test_a_turning_case_never_hangs_its_bottom_end_in_under_the_hand() -> void:
	var worst := -INF
	var straight_worst := -INF
	var came_in := 0
	for yaw in [0.0, PI / 2.0]:
		var lateral := Basis(Vector3.UP, yaw) * Vector3.RIGHT
		for out: Vector3 in [lateral, -lateral]:
			var grip := _CENTRE + out * _GRIP_OUT_M + Vector3.UP * _GRIP_Y
			var side := CarryHand.carried(grip, _CENTRE, yaw, 1.0).basis
			var ahead := CarryHand.carried_in_front(grip, yaw, 1.0).basis
			var start := CaseTurn.turn(side, ahead, yaw, 0.0)
			var end := CaseTurn.turn(side, ahead, yaw, 1.0)
			assert_bool(Basis(start).is_equal_approx(side.orthonormalized())).is_true()
			assert_bool(Basis(end).is_equal_approx(ahead.orthonormalized())).is_true()
			for step in _STEPS + 1:
				var weight := float(step) / _STEPS
				var bottom := CaseTurn.turn(side, ahead, yaw, weight) * Vector3.FORWARD
				var inward := bottom.dot(-out)
				if bottom.y < _HANGING_Y:
					worst = maxf(worst, inward)
				var flat := CaseTurn.turn(side, ahead, yaw, weight, false) * Vector3.FORWARD
				if flat.y < _HANGING_Y:
					straight_worst = maxf(straight_worst, flat.dot(-out))
			if (end * Vector3.FORWARD).dot(-out) > 0.9:
				came_in += 1
	print(
		(
			"CASE_TURN worst_inward_while_hanging=%.3f straight=%.3f hands_ending_inward=%d"
			% [worst, straight_worst, came_in]
		)
	)
	assert_float(straight_worst).is_greater(0.5)
	assert_float(worst).is_less_equal(0.05)
	assert_int(came_in).is_equal(2)


## A kind that is not a hard case (`hard` false) turns straight, as before.
func test_a_soft_kind_turns_straight() -> void:
	var grip := Vector3(0.3, _GRIP_Y, 0.0)
	var side := CarryHand.carried(grip, _CENTRE, 0.0, 1.0).basis
	var ahead := CarryHand.carried_in_front(grip, 0.0, 1.0).basis
	var straight := side.get_rotation_quaternion().slerp(ahead.get_rotation_quaternion(), 0.4)
	var got := CaseTurn.turn(side, ahead, 0.0, 0.4, false)
	assert_bool(got.is_equal_approx(straight)).is_true()
