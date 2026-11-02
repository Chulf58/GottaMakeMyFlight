class_name CarrySwap
extends RefCounted
## A roller going between hanging from the hand by its grip bar and the pull,
## in the same hand (CarryOnProps._swap_transform, the bag's "swap"): how far
## toward the pull it is, the clock of a swap that turns back, and the holding
## arm's pose on the way (kept out of carry_on_props.gd, at its line cap).
##
## Board 6981b7ac part 3: the arm took the end's pose at once (the grip moved
## 0.35-0.40 m in one frame at the start of each swap), and a swap that turned
## back one still under way started again from its far end (the roller jumped
## 1.07 m from the pull to under the hand).

## The holding arm's pose in the hand carry (CarryOnProps._pose_arms, Arm.HAND).
const HAND_OUT_DEGREES := 12.0
const HAND_SWING_KEPT := 0.5


## How far toward the pull a swap is at `k` of its move: 0 hung from the hand
## by the bar, 1 pulled; `to_pull` the way it goes.
static func pull_share(to_pull: bool, k: float) -> float:
	var s := smoothstep(0.0, 1.0, k)
	return s if to_pull else 1.0 - s


## The tick a move of `bag` (CarryOnProps' record, its "swap" just set for the
## move sync() saw at `now`) starts its clock from: `now`, except for a swap to
## the pull (`lifted` false) that turns back a swap still under way (the move
## being drawn is not hand-led, so it is a swap: CarryOnProps._leads): that one
## is started as far before `now` as the swap under way had gone, so the
## roller goes back from where it is drawn (their pull_share() agree, and
## smoothstep(1 - k) is 1 - smoothstep(k)). A swap back to the hand needs no
## such start: it begins at the roller as drawn ("from", CarryOnProps._stamp).
static func changed_at(bag: Dictionary, lifted: bool, now: float) -> float:
	if lifted or not bag.get("swap", false) or not bag.has("since") or bag.get("led", true):
		return now
	var k := clampf((now - float(bag["since"])) / CarryLead.ticks_of(bag), 0.0, 1.0)
	if k >= 1.0:
		return now
	return now - (1.0 - k) * CarryOnProps.TRANSFER_TICKS


## The share toward the pull (pull_share()) of each hand (right, then left)
## of `held` (CarryOnProps' record of a passenger) holding a swapping roller at
## `now` (sim ticks), or -1 for a hand that is not.
static func arm_shares(held: Dictionary, now: float) -> Array:
	var shares := [-1.0, -1.0]
	var bags: Array = held["bags"]
	for i in bags.size():
		var bag: Dictionary = bags[i]
		var k := CarryOnProps._progress_of(bag, now)
		if bag.get("swap", false) and k < 1.0 and held["homes"][i] == SecurityLooks.Home.HAND:
			shares[held["hands"][i]] = pull_share(bag["carry"] == SecurityLooks.Carry.PULL, k)
	return shares


## Poses `arm` (a CarryArm holding a swapping roller, `share` of the way to the
## pull, pull_share(); none when below 0) between the hand carry and the pull:
## its out angle, kept swing, lean back and front weight (`front`, the hand
## carry's) are blended, so the grip goes from the one to the other with the
## roller's bar in it, instead of taking the end's pose at once.
static func pose_arm(arm: CarryArm, share: float, front: float) -> void:
	if share < 0.0:
		return
	arm.angle_degrees = lerpf(HAND_OUT_DEGREES, CarryOnProps.PULL_OUT_DEGREES, share)
	arm.swing_kept = lerpf(HAND_SWING_KEPT, CarryOnProps.PULL_SWING_KEPT, share)
	arm.lean_back_degrees = lerpf(0.0, CarryOnProps.PULL_LEAN_DEGREES, share)
	arm.front_weight = lerpf(front, 0.0, share)
