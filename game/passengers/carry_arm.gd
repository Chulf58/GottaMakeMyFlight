class_name CarryArm
extends SkeletonModifier3D
## Holds a Toon character's arm a little out from its side while that hand
## carries a carry-on bag (decision carried-bags-stay-gripped-in-the-hand-
## clear-body-contact-by), so the bag hanging from the hand clears the hip and
## thigh through the walk and run swing. It turns the upper arm (Arm.R or
## Arm.L) outward about the character's forward axis after the animation has
## posed it; the swing itself is kept. Turned off (active = false) when the
## hand is empty. The Toon skeletons face +Z with +Y up in skeleton space.

const ARM_BONES: Array[String] = ["Arm.R", "Arm.L"]
const FOREARMS: Array[String] = ["Forearm.R", "Forearm.L"]
const HANDS: Array[String] = ["Hand.R", "Hand.L"]

## Which arm: 0 the right, 1 the left (the order of CarryOnProps' hands).
@export var side := 0
## How far the upper arm turns out from where the animation put it.
@export var angle_degrees := 12.0
## How much of the animation's arm swing is kept (1 all, 0 hanging still).
@export var swing_kept := 0.5


func _process_modification_with_delta(_delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	var arm := skeleton.find_bone(ARM_BONES[side])
	if arm < 0:
		return
	var pose := skeleton.get_bone_global_pose(arm)
	# Keep only part of the swing: a bag swung back would meet the leg that
	# kicks back in a run.
	var along := pose.basis.y.normalized()
	if along.dot(Vector3.DOWN) > -0.999:
		var to_down := Quaternion(along, Vector3.DOWN)
		pose.basis = Basis(Quaternion.IDENTITY.slerp(to_down, 1.0 - swing_kept)) * pose.basis
	# A point below the shoulder moves toward +X for a positive turn about +Z,
	# so the sign follows the shoulder's side.
	var turn := deg_to_rad(angle_degrees) * signf(pose.origin.x)
	pose.basis = Basis(Vector3.BACK, turn) * pose.basis
	skeleton.set_bone_global_pose(arm, pose)
	# The elbow and wrist straight, as in the rest pose: a bent running arm
	# would put the forearm through the bag hanging from its hand.
	var parent := pose
	for name in [FOREARMS[side], HANDS[side]]:
		var bone := skeleton.find_bone(name)
		if bone < 0:
			return
		parent = parent * skeleton.get_bone_rest(bone)
		skeleton.set_bone_global_pose(bone, parent)
