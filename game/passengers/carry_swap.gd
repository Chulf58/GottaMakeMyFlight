class_name CarrySwap
extends RefCounted
## A roller going between hanging from the hand by its grip bar and the pull,
## in the same hand (CarryHand.swap_transform, the bag's "swap"): how far
## toward the pull it is, the clock of a swap that turns back, and the holding
## arm's pose on the way (kept out of carry_on_props.gd, at its line cap).
##
## Board 6981b7ac part 3: the arm took the end's pose at once (the grip moved
## 0.35-0.40 m in one frame at the start of each swap), and a swap that turned
## back one still under way started again from its far end (the roller jumped
## 1.07 m from the pull to under the hand).

## The holding arm's pose in the hand carry (CarryArmPose.pose_arms, CarryArmPose.Arm.HAND;
## a roller held by its bar beside the stalls turns out less,
## StallCarry.hand_out_degrees()).
const HAND_OUT_DEGREES := 12.0
const HAND_SWING_KEPT := 0.5


## How far toward the pull a swap is at `k` of its move: 0 hung from the hand
## by the bar, 1 pulled; `to_pull` the way it goes.
static func pull_share(to_pull: bool, k: float) -> float:
	var s := smoothstep(0.0, 1.0, k)
	return s if to_pull else 1.0 - s


## The tick a move of `bag` (CarryOnProps' record, its "swap" and "place" just
## set for the move sync() saw at `now`; `lifted` whether it goes to the hand;
## its body `body`, as drawn) starts its clock from. `now`, except for a swap
## that turns back a swap still under way (the move drawn last is not
## hand-led, so it is a swap: CarryPlace.leads). That one goes back along
## the same path from where the roller was drawn last: its clock is started so
## its share toward the pull then is the old one's (smoothstep(1 - k) is
## 1 - smoothstep(k), with k "placed_k", the share drawn last), and it keeps
## the old swap's trailing end. Turning back to the pull, the follower starts
## at that end ("drawn_axle", RollerPull.drawn) and follows on from
## there; turning back to the hand, the end is kept in the body's frame
## ("swap_trail", hung_trail()). A swap whose follower was started afresh
## jumped the axle by the share times the gap (0.27 m after a corner, Sol
## review of board 6981b7ac).
static func start(bag: Dictionary, lifted: bool, body: Node3D, now: float) -> float:
	var frame := body.global_transform
	var k: float = bag.get("placed_k", 1.0)
	var turning: bool = (
		bag.get("swap", false) and bag.has("since") and not bag.get("led", true) and k < 1.0
	)
	var trail := Vector3.INF
	if turning:
		trail = bag.get("axle_now", Vector3.INF) if lifted else hung_trail(bag, frame)
	bag.erase("swap_trail")
	if not turning or not trail.is_finite():
		return now
	var drawn_at := float(bag["since"]) + k * CarryLead.ticks_of(bag)
	if lifted:
		bag["swap_trail"] = frame.affine_inverse() * trail
	else:
		bag["drawn_axle"] = trail
		bag["drawn_at"] = drawn_at
	return drawn_at - (1.0 - k) * CarryOnProps.TRANSFER_TICKS


## Where the axle of a roller swapping to the hand starts (its trailing end,
## world), its body drawn at `frame`: where it was let go, held in the body's
## frame ("from", CarryPlace._stamp), or the end of the pull swap it turned
## back ("swap_trail", start()).
static func hung_trail(bag: Dictionary, frame: Transform3D) -> Vector3:
	if bag.has("swap_trail"):
		return frame * (bag["swap_trail"] as Vector3)
	return frame * ((bag["from"] as Transform3D) * CarryOnProps.ROLLER_AXLE)


## The share toward the pull (pull_share()) of each hand (right, then left)
## of `held` (CarryOnProps' record of a passenger) holding a swapping roller at
## `now` (sim ticks), or -1 for a hand that is not.
static func arm_shares(held: Dictionary, now: float) -> Array:
	var shares := [-1.0, -1.0]
	var bags: Array = held["bags"]
	for i in bags.size():
		var bag: Dictionary = bags[i]
		var k := CarryPlace.progress_of(bag, now)
		if bag.get("swap", false) and k < 1.0 and held["homes"][i] == SecurityLooks.Home.HAND:
			shares[held["hands"][i]] = pull_share(bag["carry"] == SecurityLooks.Carry.PULL, k)
	return shares


## Poses `arm` (a CarryArm holding a swapping roller, `share` of the way to the
## pull, pull_share(); none when below 0) between the hand carry and the pull:
## its out angle (from `hand_out`, the hand carry's now), kept swing, lean
## back and front weight (`front`, the hand carry's) are blended, so the grip
## goes from the one to the other with the roller's bar in it, instead of
## taking the end's pose at once.
static func pose_arm(
	arm: CarryArm, share: float, front: float, hand_out := HAND_OUT_DEGREES
) -> void:
	if share < 0.0:
		return
	arm.angle_degrees = lerpf(hand_out, CarryArmPose.PULL_OUT_DEGREES, share)
	arm.swing_kept = lerpf(HAND_SWING_KEPT, CarryArmPose.PULL_SWING_KEPT, share)
	arm.lean_back_degrees = lerpf(0.0, CarryArmPose.PULL_LEAN_DEGREES, share)
	arm.front_weight = lerpf(front, 0.0, share)
