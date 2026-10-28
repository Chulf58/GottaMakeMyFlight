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

## Which arm: 0 the right, 1 the left (the order of CarryOnProps' hands).
@export var side := 0
## Side carry: how far the upper arm turns out from where the animation put it.
@export var angle_degrees := 12.0
## Side carry: how much of the animation's arm swing is kept (1 all, 0 none).
@export var swing_kept := 0.5
## Side carry: how far back from hanging straight down the kept-still part of
## the arm points (a hand pulling a roller trails a little behind the hip).
@export var lean_back_degrees := 0.0
## Whether this hand holds a bag (the side carry); a free hand keeps the
## animation's pose and only comes forward with front_weight.
@export var holds := true
## How far the arm has turned from its side pose (0) to the front carry (1).
@export var front_weight := 0.0
## Front carry: the upper arm's angle forward from hanging straight down.
@export var front_upper_degrees := 20.0
## Front carry: how far from the centre line the hand ends, and the forearm's
## angle up from level toward the hand (below level: higher at the elbow, clear
## of the bag lying under the hand).
@export var front_half_width := 0.1
@export var front_up_degrees := -10.0


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
	var outward := signf(pose.origin.x)
	var weight := clampf(front_weight, 0.0, 1.0)
	var low := _side(skeleton, bones, pose, outward) if holds else _animated(skeleton, bones)
	var high := _front(skeleton, bones, pose, outward) if weight > 0.0 else low
	# The arm turns between the two poses with the bag's move (front_weight),
	# each bone placed on its blended parent.
	var parent := Transform3D()
	for i in bones.size():
		var basis := _blend(low[i].basis, high[i].basis, weight)
		var origin: Vector3 = (
			low[i].origin if i == 0 else (parent * skeleton.get_bone_rest(bones[i])).origin
		)
		parent = Transform3D(basis, origin)
		skeleton.set_bone_global_pose(bones[i], parent)


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
	# A point below the shoulder moves toward +X for a positive turn about +Z,
	# so the sign follows the shoulder's side.
	pose.basis = Basis(Vector3.BACK, deg_to_rad(angle_degrees) * outward) * pose.basis
	# The elbow and wrist straight, as in the rest pose: a bent running arm
	# would put the forearm through the bag hanging from its hand.
	var out: Array[Transform3D] = [pose]
	for i in [1, 2]:
		out.append(out[i - 1] * skeleton.get_bone_rest(bones[i]))
	return out


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
