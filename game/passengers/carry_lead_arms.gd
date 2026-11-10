class_name CarryLeadArms
extends RefCounted
## Each hand's part in the hand-led moves of one drawn passenger's bags
## (CarryLead.plan(), CarryOnProps' "lead"): the move whose plan weighs most on
## a hand aims it, and the rig's arms (CarryArm) and stoop (CarryStoop) are set
## from those plans. Taken out of CarryOnProps, which draws the moves.


## Aims each hand of a rig (CarryOnProps._rig(): "arms", "stoop") at its target
## in `plans` (the "lead" plans of the bags in a hand-led move now) by the
## plan's weight (CarryArm.reach_weight) and bends it down as far as a low one
## needs (CarryStoop), with a backpack held by its loop as the plan says
## (CarryArm.loop_grip, the palm on the pack's top: loop_up). A hand in no
## move reaches for nothing. Writes which hands reach to `held` ("reach_on").
static func apply(held: Dictionary, plans: Array, rig: Dictionary) -> void:
	var weights := [0.0, 0.0]
	var targets := [Vector3.ZERO, Vector3.ZERO]
	var keeps := [0.0, 0.0]
	var drops := [CarryStoop.HIPS_ALL, CarryStoop.HIPS_ALL]
	var bends := [1.0, 1.0]
	var loops := [false, false]
	var ups := [Vector3.UP, Vector3.UP]
	for plan: Dictionary in plans:
		for hand in 2:
			if plan["weights"][hand] > weights[hand]:
				weights[hand] = plan["weights"][hand]
				targets[hand] = plan["targets"][hand]
				keeps[hand] = plan["keeps"][hand]
				drops[hand] = plan["drops"][hand]
				bends[hand] = plan.get("bends", bends)[hand]
				loops[hand] = plan.get("loops", loops)[hand]
				ups[hand] = plan.get("loop_up", Vector3.UP)
	held["reach_on"] = [weights[0] > 0.0, weights[1] > 0.0]
	var stoop: CarryStoop = rig["stoop"]
	for list: Array in [stoop.targets, stoop.sides, stoop.weights, stoop.keeps, stoop.drops]:
		list.clear()
	stoop.bends.clear()
	for hand in 2:
		var arm := rig["arms"][hand] as CarryArm
		arm.reach_weight = weights[hand]
		arm.reach_target = targets[hand]
		arm.loop_grip = loops[hand]
		arm.loop_up = ups[hand]
		if weights[hand] > 0.0:
			stoop.targets.append(targets[hand])
			stoop.sides.append(hand)
			stoop.weights.append(weights[hand])
			stoop.keeps.append(keeps[hand])
			stoop.drops.append(drops[hand])
			stoop.bends.append(bends[hand])
