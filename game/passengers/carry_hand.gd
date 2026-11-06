class_name CarryHand
extends RefCounted
## Where a bag held in a hand is placed: a hard case or lifted roller at the
## side and in front (carried(), carried_in_front()), turned between the two
## (case_transform()), a roller hung from its grip bar (barred()) and one going
## between the hand and the pull (swap_transform()). Split out of
## carry_on_props.gd (board 79212dcd).

## A roller going between the hand and the pull by its bar (swap_transform)
## swings out this far on the hand's side midway, clear of the trailing leg
## (0.15 m put it into a neighbouring stall's partition end from the row); at
## security it goes round the hand's side instead (CarryLead.swap_axle).
const SWAP_OUT_M := 0.08
## A roller held by its bar for a stall has the bar this far from the grip
## point, toward the bag's front (in the palm, a grip offset along the hand's
## axes): hung at the side the bag is that much further from the leg, across
## the front that much lower, under the holding forearm. Pulled, none.
const BAR_PALM_M := 0.06
## How far a roller held by its bar rolls up across the front (barred): 60
## degrees, not lying flat, so its far end stays short of the free forearm.
const FRONT_ROLL := PI / 3.0


## A carried hard case's transform for a grip at `grip` on a body drawn with
## yaw `yaw` at `centre`: upright (its length vertical), its handle face toward
## the body, its top edge at the grip, its body outward from the hand.
static func carried(
	grip: Vector3, centre: Vector3, yaw: float, scale_by: float, kind := SecurityLooks.Kind.CASE
) -> Transform3D:
	var lateral := Basis(Vector3.UP, yaw) * Vector3.RIGHT
	var out := lateral if (grip - centre).dot(lateral) >= 0.0 else -lateral
	var inward := -out
	var hang := Basis(inward.cross(Vector3.UP), inward, Vector3.UP).scaled(Vector3.ONE * scale_by)
	return Transform3D(hang, grip - hang * CarryOnProps.grip_anchor(kind))


## A hard case carried in front of the body (a cell closed on both sides):
## lying flat across the body, its handle on top just under the hand at `grip`
## (FRONT_PALM_M below the knuckles). A backpack hangs from its grab loop at the
## grip, its back panel to the body (CarryWorn.loop_in_front).
static func carried_in_front(
	grip: Vector3, yaw: float, scale_by: float, kind := SecurityLooks.Kind.CASE
) -> Transform3D:
	if kind == SecurityLooks.Kind.BACKPACK:
		return CarryWorn.loop_in_front(grip, yaw, scale_by)
	var size := CarryOnProps.bag_size(kind)
	var flat := _flat(yaw, scale_by)
	return Transform3D(flat, grip - Vector3.UP * (size.y * scale_by + CarryOnProps.FRONT_PALM_M))


## A bag lying flat with its length across a body turned to `yaw`.
static func _flat(yaw: float, scale_by: float) -> Basis:
	var forward := Basis(Vector3.UP, yaw) * Vector3.BACK
	return Basis(forward, Vector3.UP, forward.cross(Vector3.UP)).scaled(Vector3.ONE * scale_by)


## How far passenger `held` has turned to the front carry at sim time `now`,
## 0 (side) to 1 (front), over TRANSFER_TICKS.
static func front_weight(held: Dictionary, now: float) -> float:
	var target := 1.0 if held.get("front", false) else 0.0
	if not held.has("front_since"):
		return target
	var k := clampf((now - held["front_since"]) / CarryOnProps.TRANSFER_TICKS, 0.0, 1.0)
	# Fast at first: a side-carried bag is the widest thing, so it comes in
	# before the passenger reaches the narrow cell.
	return lerpf(held["front_from"], target, 1.0 - (1.0 - k) * (1.0 - k))


## How far a hard case in hand (or a lifted roller) has turned to the front
## carry at sim time `now`, 0 to 1. To the front it eases as the arm does
## (front_weight); back to the side it turns faster, upright ahead of the arm
## (from the front, the arm's weight squared), so its lower end is not swung
## through the thigh as the hand comes out (the arm's own pace measured 5 body
## points inside the case, its square none: windowed bench, 2026-10-29). A
## turn that reverses starts from where the bag is (bag_from).
static func bag_weight(held: Dictionary, now: float) -> float:
	var front: bool = held.get("front", false)
	if not held.has("front_since"):
		return 1.0 if front else 0.0
	var k := clampf((now - held["front_since"]) / CarryOnProps.TRANSFER_TICKS, 0.0, 1.0)
	if front:
		return lerpf(held["bag_from"], 1.0, 1.0 - (1.0 - k) * (1.0 - k))
	return lerpf(held["bag_from"], 0.0, 1.0 - pow(1.0 - k, 4.0))


## A hard case in the hand: between side and front carry it stays in the
## hand, turning as the arm turns (bag_weight).
static func case_transform(
	props: CarryOnProps, held: Dictionary, body: Node3D, i: int
) -> Transform3D:
	var scale_by: float = held["scale"]
	var grip := props.grip_of(body, held["hands"][i])
	var kind: SecurityLooks.Kind = held["bags"][i]["kind"]
	var side_xf := carried(grip, body.global_position, body.rotation.y, scale_by, kind)
	var weight: float = held.get("bag_weight", 0.0)
	if held["bags"][i].get("by_bar", false):
		return barred(props, held, body, i, grip, weight)
	if weight <= 0.0:
		return side_xf
	var ahead := carried_in_front(grip, body.rotation.y, scale_by, kind)
	if weight >= 1.0:
		return ahead
	# Turned about the grip: the bag's point held in the hand moves across its
	# surface from the side carry's to the front carry's, and stays at the hand.
	var held_side := side_xf.affine_inverse() * grip
	var held_ahead := ahead.affine_inverse() * grip
	var turn := side_xf.basis.get_rotation_quaternion().slerp(
		ahead.basis.get_rotation_quaternion(), weight
	)
	var basis := Basis(turn).scaled(Vector3.ONE * scale_by)
	return Transform3D(basis, grip - basis * held_side.lerp(held_ahead, weight))


## A roller going between hanging from the hand by its grip bar (rods in,
## case_transform) and the pull, at `k` of the move, held by the bar
## throughout: its axle goes between under the hand and the pull's (the
## follower's, as stepped this draw; lifted, where it was let go, held in the
## body's frame), swung out SWAP_OUT_M midway (at security round the hand's
## side), the rods running out or in to keep the bar in the hand. Returns
## [transform, rod length].
static func swap_transform(
	props: CarryOnProps, held: Dictionary, body: Node3D, i: int, k: float
) -> Array:
	var bag: Dictionary = held["bags"][i]
	var scale_by: float = held["scale"]
	var hand: int = held["hands"][i]
	var grip := props.grip_of(body, hand)
	var outward := _outward(body, hand)
	var to_pull: bool = bag["carry"] == SecurityLooks.Carry.PULL
	var trailing: Vector3
	if to_pull:
		trailing = bag.get("axle_now", Vector3.INF)
		if not trailing.is_finite():
			trailing = RollerPull.drawn(props, bag, body, scale_by, hand)
	else:
		trailing = CarrySwap.hung_trail(bag, body.global_transform)
	var t := CarrySwap.pull_share(to_pull, k)
	var hung := hung_axle(props, bag, grip, scale_by)
	var axle := hung.lerp(trailing, t) + outward * SWAP_OUT_M * 4.0 * t * (1.0 - t)
	# At security (no stall partition near) round the hand's side, clear of the
	# legs (CarryLead.swap_axle); the bar stays in the hand.
	if held.get("security", false):
		var frame := Transform3D(Basis(Vector3.UP, body.rotation.y), body.global_position)
		axle = CarryLead.swap_axle(frame, hung, trailing, t, hand, RollerPull.SWING_RADIUS_M)
	var ref := outward.lerp(Vector3.UP, t).normalized()
	var rods := props._reach_base(props._part(bag["node"], "Pull_Reach"))
	var xf := RollerPull.pulled(grip, axle, scale_by, ref).translated(
		outward * BAR_PALM_M * (1.0 - t)
	)
	return [xf, RollerPull.pull_length(grip, axle, scale_by, rods.z)]


## A roller taken in hand for a stall, held by its grip bar with its rods in,
## turned `weight` of the way to the front carry: at the side it hangs straight
## down from the bar, its back panel (rods) to the leg and its front out to
## the hand's side; turning to the front it rolls about the body's forward
## axis, its far end coming up across the body, FRONT_ROLL of the way (two
## bags: 45 degrees, so it stays clear of the other bag), its front face down.
## The bar stays in the hand throughout; the roll carries the bag's end through
## the space in front of the hips, away from the arm above the hand.
static func barred(
	props: CarryOnProps, held: Dictionary, body: Node3D, i: int, grip: Vector3, weight: float
) -> Transform3D:
	var bag: Dictionary = held["bags"][i]
	var scale_by: float = held["scale"]
	var outward := _outward(body, held["hands"][i])
	var roll := weight * (FRONT_ROLL if (held["bags"] as Array).size() < 2 else PI / 4.0)
	var length := (
		(bar_z(props, bag["node"], CarryOnProps.REACH_BUILT_M) - CarryOnProps.ROLLER_AXLE.z)
		* scale_by
	)
	var axle := grip - (Vector3.UP * cos(roll) + outward * sin(roll)) * length
	var ref := outward * cos(roll) + Vector3.DOWN * sin(roll)
	return RollerPull.pulled(grip, axle, scale_by, ref).translated(ref * BAR_PALM_M)


## Where the axle of a roller hung from the hand by its grip bar at `grip`,
## rods in, is: straight under the bar.
static func hung_axle(
	props: CarryOnProps, bag: Dictionary, grip: Vector3, scale_by: float
) -> Vector3:
	return (
		grip
		- (
			Vector3.UP
			* (bar_z(props, bag["node"], CarryOnProps.REACH_BUILT_M) - CarryOnProps.ROLLER_AXLE.z)
			* scale_by
		)
	)


## The grip bar's middle along a roller's length (its own z, scale 1) with
## rods `length` out (RollerPull.pull_length() the other way round).
static func bar_z(props: CarryOnProps, node: Node3D, length: float) -> float:
	return (
		length
		+ props._reach_base(props._part(node, "Pull_Reach")).z
		+ CarryOnProps.ROLLER_GRIP_PAST_TOP_M
	)


## Out to the side of hand `hand` (0 right, 1 left) of `body`, level.
static func _outward(body: Node3D, hand: int) -> Vector3:
	return Basis(Vector3.UP, body.rotation.y) * (Vector3.LEFT if hand == 0 else Vector3.RIGHT)
