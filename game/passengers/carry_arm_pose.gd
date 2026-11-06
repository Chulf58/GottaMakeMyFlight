class_name CarryArmPose
extends RefCounted
## Poses the CarryArms of a drawn passenger for the bags it holds, and aims the
## hands of the hand-led moves (CarryOnProps.draw() calls lead_arms() and
## pose_arms()). Split out of carry_on_props.gd (board 79212dcd).

enum Arm { FREE, HAND, PULL, STRAP }
## In front, how far from the centre line each hand holds: the hand with one
## bag, each hand with two, and the free hand (measured with the Toon walk and
## run: no body contact, the bags within 0.32 m of the centre line).
const FRONT_ONE_BAG_M := 0.10
const FRONT_TWO_BAGS_M := 0.17
const FRONT_FREE_HAND_M := 0.33
## How much further forward the holding upper arm reaches half way through a
## turn between the side and the front carry (pose_arms).
const TURN_REACH_DEGREES := 45.0
## The strap hand: at the chest just inside the strap (so the forearm stays
## clear of the strap), this far from the centre line, the forearm raised this
## much.
const STRAP_HAND_M := 0.15
const STRAP_HAND_UP_DEGREES := 45.0
## The pulling arm: turned out a little, less swing, leaning back.
const PULL_OUT_DEGREES := 12.0
const PULL_SWING_KEPT := 0.2
const PULL_LEAN_DEGREES := 12.0
## The pulling upper arm's twist (CarryArm.twist_degrees, from its rest, the
## same on both arms, mirrored), per skeleton: the male bodies, then the
## female. Each keeps the right hand's mean grip where the clip's own twist
## put it (within 0.5 cm in height and out from the thigh, walking), and the
## left hand is its mirror (board ed73cfb1, spike/pull_grip_asym_probe.gd).
## Walking only (walk_share()): standing idle the clip's own twist is already
## near a mirror (0.0 and 0.8 cm), and running is left as it was.
const PULL_TWIST_DEGREES: Array[float] = [40.0, 20.0]


## Aims each hand of `body` at its target for the hand-led moves of its bags
## now (CarryLeadArms.apply()).
static func lead_arms(props: CarryOnProps, held: Dictionary, body: Node3D, now: float) -> void:
	var plans := []
	for bag: Dictionary in held["bags"]:
		if CarryPlace.leading(bag, now) and bag.has("lead"):
			plans.append(bag["lead"])
	CarryLeadArms.apply(held, plans, props._rig(body))


## Poses each arm of `body` for the bags it holds now (CarryArm): a hand with
## a hard case, a hand pulling a roller, a hand on a shoulder strap (as the bag
## comes onto the shoulder), or free; a free hand and a hard case's hand follow
## the front-carry turn while a hard case is carried.
static func pose_arms(props: CarryOnProps, held: Dictionary, body: Node3D, now: float) -> void:
	var modes := [Arm.FREE, Arm.FREE]
	var strap := [0.0, 0.0]
	var cases := 0
	# Hard cases the free hand comes to the front beside (a roller held by its
	# bar lies across the front to the free side, so that hand stays down).
	var beside := 0
	var homes: Array = held["homes"]
	for i in homes.size():
		var bag: Dictionary = held["bags"][i]
		var k := CarryPlace.progress_of(bag, now)
		var hand: int = held["hands"][i]
		match bag["carry"]:
			SecurityLooks.Carry.HAND:
				if homes[i] == SecurityLooks.Home.HAND:
					modes[hand] = Arm.HAND
					cases += 1
					beside += 0 if bag.get("by_bar", false) else 1
			SecurityLooks.Carry.PULL:
				if homes[i] == SecurityLooks.Home.HAND:
					modes[hand] = Arm.PULL
			SecurityLooks.Carry.SHOULDER:
				var side := SecurityLooks.worn_side(i)
				var was_hand: bool = int(bag.get("was", -1)) / 4 == SecurityLooks.Home.HAND
				# The hand is on the strap before it stretches (CarryPlace.reach_blend) and
				# lets go after it is slack.
				var on := 0.0
				if homes[i] == SecurityLooks.Home.HAND:
					on = clampf(k / 0.6, 0.0, 1.0)
				elif was_hand:
					on = 1.0 - clampf((k - 0.4) / 0.6, 0.0, 1.0)
				if on > 0.0:
					modes[side] = Arm.STRAP
					strap[side] = on
	# The arms keep what was set until it changes (most frames nothing does).
	var tuck: float = held.get("tuck_weight", 0.0)
	var reach_on: Array = held.get("reach_on", [false, false])
	var swaps := CarrySwap.arm_shares(held, now)
	var outs := StallCarry.hand_out_degrees(held, now)
	var walk := walk_share(held, body)
	var key := [modes, strap, cases, beside, held["weight"], tuck, reach_on, swaps, outs, walk]
	if held.get("arm_key", []) == key and held.get("arm_body") == body:
		return
	held["arm_key"] = key
	held["arm_body"] = body
	var arms: Array = props._rig(body)["arms"]
	for side in arms.size():
		var arm := arms[side] as CarryArm
		arm.holds = modes[side] == Arm.HAND or modes[side] == Arm.PULL
		arm.active = modes[side] != Arm.FREE or cases > 0 or tuck > 0.0 or reach_on[side]
		var pulling: bool = modes[side] == Arm.PULL
		arm.angle_degrees = PULL_OUT_DEGREES if pulling else outs[side]
		arm.swing_kept = PULL_SWING_KEPT if pulling else 0.5
		arm.lean_back_degrees = PULL_LEAN_DEGREES if pulling else 0.0
		arm.front_upper_degrees = 0.0 if modes[side] == Arm.STRAP else 20.0
		arm.front_up_degrees = STRAP_HAND_UP_DEGREES if modes[side] == Arm.STRAP else -10.0
		match modes[side]:
			Arm.STRAP:
				arm.front_half_width = STRAP_HAND_M
				arm.front_weight = strap[side]
			Arm.PULL:
				arm.front_weight = 0.0
			Arm.HAND:
				arm.front_half_width = FRONT_ONE_BAG_M if cases < 2 else FRONT_TWO_BAGS_M
				arm.front_weight = held["weight"]
				# Turning between the side and the front, the upper arm reaches
				# further forward (most at half way, none at either end), so the
				# turning bag passes ahead of the thighs.
				var w: float = held["weight"]
				arm.front_upper_degrees = 20.0 + TURN_REACH_DEGREES * 4.0 * w * (1.0 - w)
			_:
				# Beside a front-carried case, or tucked in through a booth.
				arm.front_half_width = BoothCarry.free_hand_width(beside > 0, tuck)
				arm.front_weight = maxf(held["weight"] if beside > 0 else 0.0, tuck)
		CarrySwap.pose_arm(arm, swaps[side], held["weight"], outs[side])
		# The set twist with the pull while walking, eased in and out with a
		# swap's share and with the walk clip's crossfade.
		var share: float = swaps[side]
		arm.rest_twist_weight = walk * (share if share >= 0.0 else (1.0 if pulling else 0.0))
		arm.twist_degrees = pull_twist_degrees(body)


## How much of `body`'s drawn pose is the walk clip, 0 to 1: 1 walking, 0 in
## any other clip, and in between through a crossfade (ClipCrossfade) to or
## from the walk, as its weight eases (the clip blended from is kept in
## `held`, "walk_from", while no crossfade runs).
static func walk_share(held: Dictionary, body: Node3D) -> float:
	var walking := 1.0 if body.get_meta(&"clip", "") == "walk" else 0.0
	var fade := body.get_meta(&"crossfade", null) as ClipCrossfade
	if fade == null or not fade.blending():
		held["walk_from"] = walking
		return walking
	var was: float = held.get("walk_from", walking)
	return lerpf(was, walking, smoothstep(0.0, 1.0, fade.weight))


## The pulling upper arm's twist for passenger body `body` (PULL_TWIST_DEGREES
## by the skeleton its body uses, PassengerLooks.PER_VARIANT; a node with no
## body takes the male's).
static func pull_twist_degrees(body: Node3D) -> float:
	var female := int(body.get_meta(&"body", 0)) >= PassengerLooks.PER_VARIANT
	return PULL_TWIST_DEGREES[1 if female else 0]


## Turns off both CarryArms of a character with no bags (or released), with
## no reach, and its CarryStoop with no target.
static func arms_off(props: CarryOnProps, body: Node3D) -> void:
	if not body.has_meta(&"carry_rig"):
		return
	var rig := props._rig(body)
	for arm: CarryArm in rig["arms"]:
		arm.active = false
		arm.front_weight = 0.0
		arm.rest_twist_weight = 0.0
		arm.reach_weight = 0.0
	var stoop: CarryStoop = rig["stoop"]
	for list: Array in [stoop.targets, stoop.sides, stoop.weights, stoop.keeps, stoop.drops]:
		list.clear()
