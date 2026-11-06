class_name CaseTurn
extends RefCounted
## How a hard case in the hand turns between the side carry (upright, its
## length down the leg) and the front carry (flat across the body), about the
## grip (CarryHand.case_transform). Pure.
##
## A straight turn between the two swung the case's bottom end in under the
## hand, across the front of the thigh: a walker at full pace put its striding
## thigh into a right-hand case (crossing probe case_turn, 30 points at 2.4 m
## out, board a82c613f). The case instead first tips its bottom end forward,
## out ahead of the legs at about hand height, then turns flat from there, so
## its lower end never hangs in front of the thigh while the hand comes across.
## What it does not guarantee: the hand's own path (CarryArm) is unchanged, so
## a hand still low beside the leg early in the turn is not lifted.

## The share of the turn spent tipping the bottom end forward; the rest turns
## it from there to the front carry.
const TIP_SHARE := 0.5


## The case's rotation at `weight` (0 side, 1 front) of the turn from the side
## carry's basis `side` to the front carry's `ahead`, for a body turned to
## `yaw`. Only a hard case takes the tipped path; any other kind (`hard`
## false) turns straight.
static func turn(side: Basis, ahead: Basis, yaw: float, weight: float, hard := true) -> Quaternion:
	var from := side.get_rotation_quaternion()
	var to := ahead.get_rotation_quaternion()
	if not hard:
		return from.slerp(to, weight)
	var tipped := tip(from, yaw)
	if weight < TIP_SHARE:
		return from.slerp(tipped, weight / TIP_SHARE)
	return tipped.slerp(to, (weight - TIP_SHARE) / (1.0 - TIP_SHARE))


## `from` (an upright case, its bottom end down) tipped about the grip so its
## bottom end points ahead of a body turned to `yaw`.
static func tip(from: Quaternion, yaw: float) -> Quaternion:
	var forward := Basis(Vector3.UP, yaw) * Vector3.BACK
	var bottom := from * Vector3.FORWARD
	return Quaternion(bottom.normalized(), forward) * from
