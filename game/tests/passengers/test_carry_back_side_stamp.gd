class_name TestCarryBackSideStamp
extends GdUnitTestSuite
## A backpack's side hang (CarryLead.back_side(), by_side()) takes its height
## from the shoulder height stamped as the move started ("start_shoulder_y",
## CarryLead.stamp_move()), not from the skeleton drawn now (anti-pattern a
## carry move must not take its shape from the hand it is posing; board
## 031cee02): the same stamped move planned with the live shoulders at two
## heights gives the same hand targets and pack placements, on and off the
## back. Controls: the stamp does move the hang, and the hang sits under it.


func _body(shoulder_y: float) -> Dictionary:
	return {
		"hand": 0,
		"grips": [Vector3(-0.1, 1.25, 0.32), Vector3(0.25, 0.8, 0.05)],
		"shoulders_y": [shoulder_y, shoulder_y],
		"bar_z": 0.0,
		"scale": 1.0,
		"strap_top": Vector3.ZERO,
	}


func _flags() -> Dictionary:
	return {
		"in_stall": false,
		"hand_carry": true,
		"from_floor": false,
		"to_floor": false,
		"hand": 0,
		"clear": CarryOnProps.TRANSFER_CLEAR_M,
		"yaw": 0.0,
	}


func _moves(stamp: float) -> Array:
	var kind := SecurityLooks.Kind.BACKPACK
	var front := CarryHand.carried_in_front(Vector3(-0.1, 1.25, 0.32), 0.0, 1.0, kind)
	var back := CarryWorn.worn_back(Transform3D(Basis(), Vector3(0.0, 1.35, -0.05)), 0.0, 1.0)
	var hand_at := (SecurityLooks.Home.HAND * 2 + 0) * 2
	var on_back := {
		"kind": kind,
		"was": hand_at + 1,
		"carry_from": SecurityLooks.Carry.HAND,
		"home": hand_at,
		"carry": SecurityLooks.Carry.BACK,
		"anchor_from": CarryLead.anchor(kind, 0.0),
		"from": front,
		"start_shoulder_y": stamp,
	}
	var off_back := {
		"kind": kind,
		"was": hand_at,
		"carry_from": SecurityLooks.Carry.BACK,
		"home": hand_at + 1,
		"carry": SecurityLooks.Carry.HAND,
		"from": back,
		"start_shoulder_y": stamp,
	}
	return [[on_back, front, back], [off_back, back, front]]


## Samples of one stamped move through k: the hand target and the pack's
## placement, with the live shoulders at `live`.
func _draws(stamp: float, live: float) -> Array:
	var out := []
	for move: Array in _moves(stamp):
		for step in 41:
			var plan := CarryLead.plan(
				move[0], step / 40.0, move[1], move[2], Transform3D(), _flags(), _body(live)
			)
			out.append([plan["targets"][0], plan["xf"]])
	return out


func test_the_same_stamp_gives_the_same_side_hang_whatever_the_live_shoulders() -> void:
	var low := _draws(1.4, 1.42)
	var high := _draws(1.4, 1.62)
	assert_int(low.size()).is_equal(high.size())
	var moved := 0
	for i in low.size():
		assert_vector(low[i][0]).is_equal(high[i][0])
		assert_object(low[i][1]).is_equal(high[i][1])
		if (low[i][0] as Vector3).distance_to(_draws(1.6, 1.42)[i][0]) > 0.001:
			moved += 1
	# Control: a different stamp does move the hand's target on the side hang.
	assert_int(moved).is_greater(5)


func test_the_side_hang_sits_below_the_stamped_shoulder() -> void:
	var stamp := 1.4
	var hung := 0
	for move: Array in _moves(stamp):
		var k := 0.0 if move[0]["carry_from"] == SecurityLooks.Carry.BACK else 1.0
		var plan := CarryLead.plan(
			move[0], k, move[1], move[2], Transform3D(), _flags(), _body(1.62)
		)
		var y: float = (plan["targets"][0] as Vector3).y
		assert_float(y).is_equal_approx(stamp - CarryLead.BACK_HANG_BELOW_M, 0.001)
		hung += 1
	assert_int(hung).is_equal(2)
