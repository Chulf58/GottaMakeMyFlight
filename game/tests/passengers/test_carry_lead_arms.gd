class_name TestCarryLeadArms
extends GdUnitTestSuite
## CarryLeadArms.apply(): each hand takes the plan that weighs most on it, its
## loop grip included, and a hand no plan weighs on reaches for nothing.


func _rig() -> Dictionary:
	var arms: Array = [auto_free(CarryArm.new()), auto_free(CarryArm.new())]
	return {"arms": arms, "stoop": auto_free(CarryStoop.new())}


func _plan(weights: Array, loops: Array, y: float) -> Dictionary:
	return {
		"weights": weights,
		"targets": [Vector3(-0.3, y, 0.2), Vector3(0.3, y, 0.2)],
		"keeps": [0.0, 0.0],
		"drops": [CarryStoop.HIPS_ALL, CarryStoop.HIPS_ALL],
		"loops": loops,
	}


## Two bags' plans: the left hand takes the heavier one's target and loop grip,
## the right the only plan that weighs on it; the stoop gets both hands.
## Control: applied again with no plans, every arm and the stoop let go.
func test_each_hand_takes_the_plan_weighing_most_on_it() -> void:
	var rig := _rig()
	var held := {}
	var light := _plan([0.0, 0.4], [false, false], 0.9)
	var heavy := _plan([0.7, 0.9], [false, true], 1.1)
	CarryLeadArms.apply(held, [light, heavy], rig)
	var left := rig["arms"][1] as CarryArm
	var right := rig["arms"][0] as CarryArm
	var stoop := rig["stoop"] as CarryStoop
	assert_array(held["reach_on"]).is_equal([true, true])
	assert_float(left.reach_weight).is_equal(0.9)
	assert_vector(left.reach_target).is_equal(Vector3(0.3, 1.1, 0.2))
	assert_bool(left.loop_grip).is_true()
	assert_float(right.reach_weight).is_equal(0.7)
	assert_bool(right.loop_grip).is_false()
	assert_array(stoop.sides).is_equal([0, 1])
	CarryLeadArms.apply(held, [], rig)
	assert_array(held["reach_on"]).is_equal([false, false])
	assert_float(left.reach_weight).is_equal(0.0)
	assert_bool(left.loop_grip).is_false()
	assert_array(stoop.targets).is_empty()
	assert_array(stoop.bends).is_empty()
