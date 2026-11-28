class_name CarryArm
extends SkeletonModifier3D
## Poses a Toon character's arm while that hand carries a carry-on bag
## (decisions carried-bags-stay-gripped-in-the-hand-clear-body-contact-by and
## in-a-cell-closed-on-both-sides-a-passenger-carries-their-bag), after the
## animation has posed it. Turned off (active = false) when the hand is empty.
## The Toon skeletons face +Z with +Y up in skeleton space.
##
## Side carry (front_weight 0): the upper arm keeps half of its swing, turns
## out from the side and the elbow and wrist are straight, so the bag hanging
## from the hand clears the hip and thigh through the walk and run.
## Front carry (front_weight 1): the upper arm hangs a little forward and the
## forearm and hand point forward, aimed so the hand ends front_half_width
## from the centre line. CarryOnProps sets it on the holding hand (the bag in
## front of the body, inside its width, for a cell closed on both sides) and
## on the free hand, which comes forward beside the bag instead of swinging
## across it. The same front pose, with the forearm raised, is the hand
## holding a shoulder bag's strap at the chest (decision carry-on-bag-kinds-
## backpack-shoulder-or-tote-bag-small-rolle); a hand pulling a roller is a side
## carry that leans back (lean_back_degrees) with less swing.

const ARM_BONES: Array[String] = ["Arm.R", "Arm.L"]
const FOREARMS: Array[String] = ["Forearm.R", "Forearm.L"]
const HANDS: Array[String] = ["Hand.R", "Hand.L"]
## About the Toon forearm's length, to aim it.
const FOREARM_M := 0.3
## The way the elbow bends (skeleton space, x outward) on a reach with
## loop_grip: down and a little out, not out and back.
const LOOP_POLE := Vector3(0.3, -1.0, 0.0)
## The finger bones (".R" or ".L" added) a loop_grip hand turns to their rest,
## and the ones of them it then bends on: the Fingers by loop_curl_degrees, the
## Fingertips by loop_hook_degrees, the Thumb by loop_fold_degrees and the
## Thumb_Tip by loop_thumb_degrees.
const LOOP_FINGERS: Array[String] = ["Fingers", "Fingertips", "Thumb", "Thumb_Tip"]
const LOOP_CURL_BONE := "Fingers"
const LOOP_HOOK_BONE := "Fingertips"
const LOOP_FOLD_BONE := "Thumb"
const LOOP_THUMB_BONE := "Thumb_Tip"

## Which arm: 0 the right, 1 the left (the order of CarryOnProps' hands).
@export var side := 0
## Side carry: how far the upper arm turns out from where the animation put it.
@export var angle_degrees := 12.0
## Side carry: how much of the animation's arm swing is kept (1 all, 0 none).
@export var swing_kept := 0.5
## Side carry: how far back from hanging straight down the kept-still part of
## the arm points (a hand pulling a roller trails a little behind the hip).
@export var lean_back_degrees := 0.0
## Side carry: how far (0 to 1) the upper arm's twist about its own axis is
## taken from its rest, turned twist_degrees out, instead of from the clip.
## The walk clip twists the left upper arm differently from the right, and the
## forearm and hand are not in line with the upper arm, so a kept clip twist
## put the left hand of a pulled roller 2.9 cm nearer its leg than the right
## (board ed73cfb1, spike/pull_grip_asym_probe.gd). Set for the pull
## (CarryArmPose).
@export var rest_twist_weight := 0.0
@export var twist_degrees := 0.0
## Whether this hand holds a bag (the side carry); a free hand keeps the
## animation's pose and only comes forward with front_weight.
@export var holds := true
## How far the arm has turned from its side pose (0) to the front carry (1).
@export var front_weight := 0.0
## Front carry: the upper arm's angle forward from hanging straight down.
@export var front_upper_degrees := 12.0
## Front carry: how far from the centre line the hand ends, and the forearm's
## angle up from level toward the hand (below level: higher at the elbow, clear
## of the bag lying under the hand).
@export var front_half_width := 0.1
@export var front_up_degrees := -20.0
## How much (0 to 1) a hand holding a case or pulling a roller bar curls its
## fingers around the grip instead of hanging straight open.
@export var grip_curl := 0.0
## A hand-led bag move (CarryLead): how far (0 to 1) the arm turns from the
## pose above to reach reach_target (world) with its grip (CarryOnProps.
## grip_of: GRIP_ALONG_M past the Fingers bone), wrist straight, elbow out.
@export var reach_weight := 0.0
var reach_target := Vector3.ZERO
## The reach holds a backpack by its grab loop (CarryLead plan "loops",
## _reach_loop()): the hand level and the elbow down (LOOP_POLE), so the fingers
## stay over the loop, out of the pack. Set by CarryOnProps with the reach.
var loop_grip := false
## How far a loop_grip hand is rolled from the roll its forearm gives it to
## palm down (_palm_down()), 0 to 1: CarryLead's plan "loop_yaw", the share of
## the way the pack has turned to hang plumb under the hand. Palm down over a
## pack still lying as it left its tray, the curled fingers went into the
## pack's top beside the loop (crossing probe --lane, seed 1106001, passenger
## 2 tray>back at k 0.28, 76 points). Set by CarryLeadArms with loop_grip.
var loop_roll := 1.0
## How far a loop_grip hand bends its Fingers, its Fingertips and its
## Thumb_Tip on from their rest, toward the palm, so the whole finger closes
## round the loop like a grip instead of lying open over it (board 4e5a26f0).
## NAN (unset) takes the skeleton's own values from the body this arm poses
## (CarryArmPose.loop_curl_degrees(), loop_hook_degrees(),
## loop_thumb_degrees()), so every move that holds a pack by its loop bends
## them, whichever code posed the arm. With no body above the skeleton they
## are not guessed (_loop_degrees()).
var loop_curl_degrees := NAN
var loop_hook_degrees := NAN
var loop_thumb_degrees := NAN
## The same for the whole Thumb, folded in across the palm under the curled
## fingers (CarryArmPose.loop_fold_degrees()).
var loop_fold_degrees := NAN
## Whether this arm has already warned that it found no body.
var _no_body_warned := false


func _process_modification_with_delta(_delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	var bones: Array[int] = [
		skeleton.find_bone(ARM_BONES[side]),
		skeleton.find_bone(FOREARMS[side]),
		skeleton.find_bone(HANDS[side]),
	]
	if bones.has(-1):
		return
	var pose := skeleton.get_bone_global_pose(bones[0])
	var outward := -1.0 if side == 0 else 1.0
	var weight := clampf(front_weight, 0.0, 1.0)
	var low := _side(skeleton, bones, pose, outward) if holds else _animated(skeleton, bones)
	var high := _front(skeleton, bones, pose, outward) if weight > 0.0 else low
	# The arm turns between the two poses with the bag's move (front_weight),
	# each bone placed on its blended parent.
	var chain: Array[Transform3D] = []
	var parent := Transform3D()
	for i in bones.size():
		var basis := _blend(low[i].basis, high[i].basis, weight)
		var origin: Vector3 = (
			low[i].origin if i == 0 else (parent * skeleton.get_bone_rest(bones[i])).origin
		)
		parent = Transform3D(basis, origin)
		chain.append(parent)
	var reach := clampf(reach_weight, 0.0, 1.0)
	if reach > 0.0:
		var reached := _reach(skeleton, chain, outward)
		for i in chain.size():
			var basis := _blend(chain[i].basis, reached[i].basis, reach)
			var origin: Vector3 = (
				chain[i].origin
				if i == 0
				else (chain[i - 1] * skeleton.get_bone_rest(bones[i])).origin
			)
			chain[i] = Transform3D(basis, origin)
	for i in bones.size():
		skeleton.set_bone_global_pose(bones[i], chain[i])
	if loop_grip and reach > 0.0:
		_loop_fingers(skeleton, reach)
	elif grip_curl > 0.0 and holds:
		_grip_fingers(skeleton, grip_curl, reach)


## A hand over a backpack's grab loop (loop_grip): its fingers and thumb turned
## `weight` of the way from the clip's curl to their rest bent on by
## _loop_degrees() (about the bone's own z axis, mirrored on the left hand,
## the way the walk and idle clips curl the fingers): the Fingers and their
## Fingertips closed toward the palm, the thumb's tip tucked. Curled as the
## clips hold them, the fingers went up to 6 cm under the grip, into the loop
## and the pack's top below it (backpack_pickup_probe, board 41c159bc); with
## only the Fingertips bent the hand still read as flat and open (board
## 4e5a26f0). The grip moves with the Fingers bone (CarryOnProps.grip_of()), so
## the reach aims the curled grip (_grip()) and the pack hangs from it.
## A skeleton with no body above it and no values set has no known curl: its
## fingers stay as the clip has them.
func _loop_fingers(skeleton: Skeleton3D, weight: float) -> void:
	var suffix: String = [".R", ".L"][side]
	var bends := _loop_degrees(skeleton)
	if bends.is_empty():
		return
	for name in LOOP_FINGERS:
		var bone := skeleton.find_bone(name + suffix)
		if bone < 0:
			continue
		var rest := skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()
		if bends.has(name):
			rest = rest * _bend(bends[name])
		var now := skeleton.get_bone_pose_rotation(bone)
		skeleton.set_bone_pose_rotation(bone, now.slerp(rest, weight))


## Closes Fingers/Thumb smoothly around a carried handle or pull bar when `holds`.
## Child digits (Fingertips, Thumb) close even during IK reach without shifting grip_of().
func _grip_fingers(skeleton: Skeleton3D, weight: float, reach := 0.0) -> void:
	if weight <= 0.0:
		return
	var suffix: String = [".R", ".L"][side]
	var bends := {
		LOOP_CURL_BONE: 65.0,
		LOOP_HOOK_BONE: 75.0,
		LOOP_FOLD_BONE: -45.0,
		LOOP_THUMB_BONE: -60.0,
	}
	for name in LOOP_FINGERS:
		var w := weight * (1.0 - reach) if name == LOOP_CURL_BONE else weight
		if w <= 0.0:
			continue
		var bone := skeleton.find_bone(name + suffix)
		if bone < 0:
			continue
		var rest := skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()
		if bends.has(name):
			rest = rest * _bend(bends[name])
		var now := skeleton.get_bone_pose_rotation(bone)
		skeleton.set_bone_pose_rotation(bone, now.slerp(rest, w))


## The loop hand's bends from rest (degrees) by bone name: LOOP_CURL_BONE,
## LOOP_HOOK_BONE, LOOP_FOLD_BONE and LOOP_THUMB_BONE, each this arm's own
## value or, unset, its body's skeleton's (CarryArmPose). Empty, and a warning once per arm,
## when one is unset and there is no passenger body above the skeleton.
func _loop_degrees(skeleton: Skeleton3D) -> Dictionary:
	var curl := loop_curl_degrees
	var hook := loop_hook_degrees
	var thumb := loop_thumb_degrees
	var fold := loop_fold_degrees
	if is_nan(curl) or is_nan(hook) or is_nan(thumb) or is_nan(fold):
		var body := _body_of(skeleton)
		if body == null:
			if not _no_body_warned:
				_no_body_warned = true
				var why := 'no passenger body ("body" meta) above the skeleton'
				push_warning("CarryArm %s: %s, so the loop hand is not curled" % [get_path(), why])
			return {}
		if is_nan(curl):
			curl = CarryArmPose.loop_curl_degrees(body)
		if is_nan(hook):
			hook = CarryArmPose.loop_hook_degrees(body)
		if is_nan(thumb):
			thumb = CarryArmPose.loop_thumb_degrees(body)
		if is_nan(fold):
			fold = CarryArmPose.loop_fold_degrees(body)
	return {
		LOOP_CURL_BONE: curl, LOOP_HOOK_BONE: hook, LOOP_FOLD_BONE: fold, LOOP_THUMB_BONE: thumb
	}


## A finger bend of `degrees` toward the palm about the bone's z axis, mirrored
## on the left hand.
func _bend(degrees: float) -> Quaternion:
	return Quaternion(Vector3.BACK, deg_to_rad(degrees) * (1.0 if side == 0 else -1.0))


## The passenger body node `skeleton` belongs to (the nearest node above it
## with a "body" meta, PassengerViews), or null when there is none.
static func _body_of(skeleton: Skeleton3D) -> Node3D:
	var at: Node = skeleton
	while at != null:
		if at.has_meta(&"body") and at is Node3D:
			return at
		at = at.get_parent()
	return null


## The arm `chain` (arm, forearm, hand; skeleton space) turned so the grip
## reaches reach_target: a two-bone reach (CarryStoop.two_bone) from the
## shoulder, the elbow bent out and back, the wrist kept as it is (with
## loop_grip, _reach_loop()).
func _reach(skeleton: Skeleton3D, chain: Array[Transform3D], outward: float) -> Array[Transform3D]:
	if loop_grip:
		return _reach_loop(skeleton, chain, outward)
	var target := skeleton.global_transform.affine_inverse() * reach_target
	var shoulder := chain[0].origin
	var elbow := chain[1].origin
	var grip := _grip(skeleton, chain[2])
	var upper_len := elbow.distance_to(shoulder)
	var fore_len := grip.distance_to(elbow)
	var pole := Vector3(outward, 0.0 if target.z < shoulder.z else -0.30, -0.5)
	if (
		target.distance_to(shoulder) < absf(upper_len - fore_len) + 0.08
		and target.y >= shoulder.y - 0.04
	):
		var wrist_len := chain[2].origin.distance_to(elbow)
		var hand_len := grip.distance_to(chain[2].origin)
		var away := Vector3(outward * 0.05, 0.64, 0.77).normalized()
		var wrist_goal := target + away * hand_len
		var near_pole := Vector3(-outward * 0.28, -0.15, 0.95)
		var joints := CarryStoop.two_bone(shoulder, upper_len, wrist_len, wrist_goal, near_pole)
		var arm := chain[0]
		var fore_in_arm := arm.affine_inverse() * chain[1]
		var hand_in_fore := chain[1].affine_inverse() * chain[2]
		arm.basis = CarryStoop.aim(arm.basis, elbow - shoulder, joints[0] - shoulder)
		var fore := arm * fore_in_arm
		var wrist_now := (fore * hand_in_fore).origin
		fore.basis = CarryStoop.aim(fore.basis, wrist_now - fore.origin, joints[1] - fore.origin)
		var hand := fore * hand_in_fore
		var hand_grip := _grip(skeleton, hand)
		hand.basis = CarryStoop.aim(hand.basis, hand_grip - hand.origin, target - hand.origin)
		return [arm, fore, hand]
	var joints := CarryStoop.two_bone(shoulder, upper_len, fore_len, target, pole)
	var arm := chain[0]
	var fore_in_arm := arm.affine_inverse() * chain[1]
	var hand_in_fore := chain[1].affine_inverse() * chain[2]
	arm.basis = CarryStoop.aim(arm.basis, elbow - shoulder, joints[0] - shoulder)
	var fore := arm * fore_in_arm
	var grip_now := _grip(skeleton, fore * hand_in_fore)
	fore.basis = CarryStoop.aim(fore.basis, grip_now - fore.origin, joints[1] - fore.origin)
	return [arm, fore, fore * hand_in_fore]


## _reach() for a hand holding a backpack by its grab loop: the hand level
## (its axis along the way from the shoulder to the target, seen from above),
## so the fingers lie over the loop, not down into the pack below it, and the
## elbow down (LOOP_POLE), not out and back. The wrist is put where the level
## hand's grip lands on the target. Posed as _reach() poses any other hand, the
## hand pointed down at the loop and the fingers were up to 6 cm under it
## inside the pack (backpack_pickup_probe, seed 2811556352, board 41c159bc).
func _reach_loop(
	skeleton: Skeleton3D, chain: Array[Transform3D], outward: float
) -> Array[Transform3D]:
	var target := skeleton.global_transform.affine_inverse() * reach_target
	var shoulder := chain[0].origin
	var level := Vector3(target.x - shoulder.x, 0.0, target.z - shoulder.z)
	level = level.normalized() if level.length() > 0.001 else Vector3(outward, 0.0, 0.0)
	# The curled grip lies under and behind the knuckles, off the hand's axis:
	# the wrist goes where the level hand's own grip lands on the target,
	# measured on the hand as the clip turns it, then again as the reach turned
	# it.
	var hand := Transform3D(_palm_down(skeleton, chain[2].basis, level), chain[2].origin)
	var reached := chain
	for i in 3:
		var wrist_to_grip := _grip(skeleton, hand) - hand.origin
		reached = _reach_wrist(skeleton, chain, target - wrist_to_grip, outward, level)
		hand = reached[2]
	return reached


## The arm `chain` turned so its wrist reaches `wrist` (skeleton space), the
## elbow down (LOOP_POLE) and the hand pointed along `level`, palm down
## (_palm_down(), _reach_loop()).
func _reach_wrist(
	skeleton: Skeleton3D, chain: Array[Transform3D], wrist: Vector3, outward: float, level: Vector3
) -> Array[Transform3D]:
	var shoulder := chain[0].origin
	var elbow := chain[1].origin
	var skel_scale := skeleton.global_transform.basis.get_scale().x
	# Keep loop-reaching wrist outside the shoulder line and clear of Spine_03 so
	# putting a pack on the back never twists the upper arm behind the torso.
	var min_side := absf(shoulder.x) + 0.01 / skel_scale
	var min_z := shoulder.z - 0.05 / skel_scale
	var clamped := wrist
	if clamped.z < shoulder.z + 0.02 / skel_scale:
		if clamped.x * outward < min_side:
			clamped.x = outward * min_side
		if clamped.z < min_z:
			clamped.z = min_z
	var pole := LOOP_POLE * Vector3(outward, 1.0, 1.0)
	var joints := CarryStoop.two_bone(
		shoulder, elbow.distance_to(shoulder), chain[2].origin.distance_to(elbow), clamped, pole
	)
	var arm := chain[0]
	var fore_in_arm := arm.affine_inverse() * chain[1]
	var hand_in_fore := chain[1].affine_inverse() * chain[2]
	arm.basis = CarryStoop.aim(arm.basis, elbow - shoulder, joints[0] - shoulder)
	var fore := arm * fore_in_arm
	var wrist_now := (fore * hand_in_fore).origin
	fore.basis = CarryStoop.aim(fore.basis, wrist_now - fore.origin, joints[1] - fore.origin)
	var hand := fore * hand_in_fore
	return [arm, fore, Transform3D(_palm_down(skeleton, hand.basis, level), hand.origin)]


## The hand bone's `basis` (skeleton space) pointed along `level` and rolled
## about it loop_roll of the way so its curled Fingers (_loop_degrees()) bend
## straight down, round the loop under the palm. Left with the roll the forearm gave it, the curl
## went partly sideways and differed by hand: the fingers' lowest point was
## 1.5 to 6.3 cm under the grip (tools/blender/out/loop_hand spike, board 4e5a26f0),
## so no one hang height put every fist on the loop.
func _palm_down(skeleton: Skeleton3D, basis: Basis, level: Vector3) -> Basis:
	var pointed := _pointed(basis, level, 1.0)
	var fingers := skeleton.find_bone(CarryOnProps.GRIP_BONES[side])
	var curl: float = _loop_degrees(skeleton).get(LOOP_CURL_BONE, 0.0)
	var bent := pointed * skeleton.get_bone_rest(fingers).basis * Basis(_bend(curl))
	var axis := pointed.y.normalized()
	var out := bent.y - axis * bent.y.dot(axis)
	if out.length() < 0.001:
		return pointed
	return Basis(axis, out.signed_angle_to(Vector3.DOWN, axis) * loop_roll) * pointed


## Where the grip is (skeleton space) for the hand bone at `hand`: the Fingers
## bone as at rest on it (with loop_grip, curled as _loop_fingers() curls it),
## GRIP_ALONG_M along its own axis, as CarryOnProps.grip_of() reads it drawn.
func _grip(skeleton: Skeleton3D, hand: Transform3D) -> Vector3:
	var fingers := skeleton.find_bone(CarryOnProps.GRIP_BONES[side])
	var at := hand * skeleton.get_bone_rest(fingers)
	if loop_grip:
		var curl: float = _loop_degrees(skeleton).get(LOOP_CURL_BONE, 0.0)
		at.basis = at.basis * Basis(_bend(curl))
	var along := CarryOnProps.GRIP_ALONG_M / skeleton.global_transform.basis.get_scale().x
	return at.origin + at.basis.y.normalized() * along


## How far (world metres) the grip of arm `side` of `skeleton` reaches from
## its shoulder joint, at rest with the elbow and wrist straight.
static func reach_of(skeleton: Skeleton3D, side: int) -> float:
	var ids: Array[int] = []
	for bone: String in [FOREARMS[side], HANDS[side], CarryOnProps.GRIP_BONES[side]]:
		ids.append(skeleton.find_bone(bone))
	if ids.has(-1):
		return 0.6
	var scale_by := skeleton.global_transform.basis.get_scale().x
	var upper := skeleton.get_bone_rest(ids[0]).origin.length()
	var lower := skeleton.get_bone_rest(ids[1]).origin.length()
	var hand := skeleton.get_bone_rest(ids[2]).origin.length()
	return (upper + lower + hand) * scale_by + CarryOnProps.GRIP_ALONG_M


## A bone's rotation `weight` of the way from `low` to `high` (as rotations,
## keeping `low`'s scale), exactly `low` at 0 and `high` at 1.
static func _blend(low: Basis, high: Basis, weight: float) -> Basis:
	if weight <= 0.0:
		return low
	if weight >= 1.0:
		return high
	var turn := low.get_rotation_quaternion().slerp(high.get_rotation_quaternion(), weight)
	return Basis(turn) * Basis.from_scale(low.get_scale())


## The arm, forearm and hand as the animation posed them (a free hand).
func _animated(skeleton: Skeleton3D, bones: Array[int]) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for bone in bones:
		out.append(skeleton.get_bone_global_pose(bone))
	return out


## The side carry: half the swing, turned out, elbow and wrist straight.
func _side(
	skeleton: Skeleton3D, bones: Array[int], pose: Transform3D, outward: float
) -> Array[Transform3D]:
	# Keep only part of the swing: a bag swung back would meet the leg that
	# kicks back in a run.
	var lean := deg_to_rad(lean_back_degrees)
	pose.basis = _pointed(pose.basis, Vector3(0.0, -cos(lean), -sin(lean)), 1.0 - swing_kept)
	if rest_twist_weight > 0.0:
		var twisted := _rest_twisted(skeleton, bones[0], pose.basis, outward)
		pose.basis = _blend(pose.basis, twisted, rest_twist_weight)
	# A point below the shoulder moves toward +X for a positive turn about +Z,
	# so the sign follows the shoulder's side.
	pose.basis = Basis(Vector3.BACK, deg_to_rad(angle_degrees) * outward) * pose.basis
	# The elbow and wrist straight, as in the rest pose: a bent running arm
	# would put the forearm through the bag hanging from its hand.
	var out: Array[Transform3D] = [pose]
	for i in [1, 2]:
		out.append(out[i - 1] * skeleton.get_bone_rest(bones[i]))
	return out


## The upper arm's rest (skeleton space) turned by the shortest turn onto the
## axis of `basis`, then twisted twist_degrees about that axis, out on the
## arm's side: the same twist on both arms, mirrored, whatever the clip's.
func _rest_twisted(skeleton: Skeleton3D, bone: int, basis: Basis, outward: float) -> Basis:
	var along := basis.y.normalized()
	var rest := _pointed(skeleton.get_bone_global_rest(bone).basis, along, 1.0)
	var spin := Basis(along, deg_to_rad(twist_degrees) * outward)
	return (spin * rest).orthonormalized() * Basis.from_scale(basis.get_scale())


## The front carry: upper arm a little forward, forearm and hand aimed so
## the hand ends front_half_width from the centre line.
func _front(
	skeleton: Skeleton3D, bones: Array[int], pose: Transform3D, outward: float
) -> Array[Transform3D]:
	var upper := deg_to_rad(front_upper_degrees)
	pose.basis = _pointed(pose.basis, Vector3(0.0, -cos(upper), sin(upper)), 1.0)
	var lift := deg_to_rad(front_up_degrees)
	var elbow := (pose * skeleton.get_bone_rest(bones[1])).origin
	var ahead := Vector3(
		outward * front_half_width - elbow.x, FOREARM_M * sin(lift), FOREARM_M * cos(lift)
	)
	ahead = ahead.normalized()
	var out: Array[Transform3D] = [pose]
	for i in [1, 2]:
		var next := out[i - 1] * skeleton.get_bone_rest(bones[i])
		next.basis = _pointed(next.basis, ahead, 1.0)
		out.append(next)
	return out


## `basis` turned by `weight` of the shortest turn that points its bone axis
## (+Y) along `along`.
static func _pointed(basis: Basis, along: Vector3, weight: float) -> Basis:
	var bone := basis.y.normalized()
	var to := along.normalized()
	if bone.dot(to) < -0.999:
		return basis
	return Basis(Quaternion.IDENTITY.slerp(Quaternion(bone, to), weight)) * basis
