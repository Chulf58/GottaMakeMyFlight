class_name PodRecline
extends SkeletonModifier3D
## Leans a seated Toon character back and lets its head drop to one side, like
## dozing in an airline seat: the nap pod pose (decision
## activity-poses-sit-on-the-lounge-sofa-recline-in-the-nap-pod, user ruling
## "Reclined seat"). After the animation (sit_idle) and before any carry
## modifier, the back turns back about the Spine_01 bone and the head tilts
## at the Head bone, both times `amount`. PassengerViews sets `amount` each
## tick from ActivityPoses.recline(); at 0 it does nothing.

## The back's lean at a full recline, toward the pod's back cushion (itself
## tilted 8 degrees, build_services_kit.py).
const LEAN_DEGREES := 12.0
## The head's drop to the side, and its nod forward, at a full recline.
const HEAD_SIDE_DEGREES := 20.0
const HEAD_NOD_DEGREES := 10.0

## How far (0 to 1) the character is reclined.
var amount := 0.0


func _process_modification_with_delta(_delta: float) -> void:
	if amount <= 0.0:
		return
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	var spine := skeleton.find_bone("Spine_01")
	var head := skeleton.find_bone("Head")
	if spine < 0 or head < 0:
		return
	var a := clampf(amount, 0.0, 1.0)
	# The skeleton faces +Z: a turn about +X by a negative angle takes the top
	# of the back toward -Z, behind the character.
	var back := skeleton.get_bone_global_pose(spine)
	back.basis = Basis(Vector3.RIGHT, -deg_to_rad(LEAN_DEGREES) * a) * back.basis
	skeleton.set_bone_global_pose(spine, back)
	var nod := Basis(Vector3.RIGHT, deg_to_rad(HEAD_NOD_DEGREES) * a)
	var side := Basis(Vector3.BACK, deg_to_rad(HEAD_SIDE_DEGREES) * a)
	var face := skeleton.get_bone_global_pose(head)
	face.basis = side * nod * face.basis
	skeleton.set_bone_global_pose(head, face)
