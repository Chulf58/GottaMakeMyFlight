class_name CarryStoop
extends SkeletonModifier3D
## Bends a Toon character down so a hand reaches a bag low down (decision
## carry-on-bags-stay-in-the-hand-during-every-move-no-overhead, user ruling
## "Bend down"): after the animation and before the CarryArms, the back bends
## at the Spine_01 bone toward the targets and the hips go down, the knees
## bending forward and the feet kept where the animation put them (each leg a
## two-bone reach to its foot). How far: the least stoop (needed()) that brings
## each reaching arm's shoulder within REACH_SLACK of its full reach of its
## target, times its weight. CarryOnProps sets the targets each draw; with none
## it does nothing. Ported from the floating-bag WIP (2b44136). The hips also
## go back as they drop (HIP_BACK_M), so the knees come forward less, and a
## target's keep holds the stoop on at any height: a bag lifted off or set on
## the floor is reached ahead, not short of it in front of the thighs (board
## item 5ed915b0).

const LEGS: Array[Array] = [["Quad.R", "Shin.R", "Foot.R"], ["Quad.L", "Shin.L", "Foot.L"]]
## The back's bend at a full stoop, and how far the hips go down and back with
## it.
const STOOP_DEGREES := 80.0
const STOOP_DROP := 0.6
const HIP_BACK_M := 0.2
## A stoop aims the shoulder this much of the arm's full reach from its target.
const REACH_SLACK := 0.96
const STEPS := 24
## Only a target about this low (world metres over the feet) is bent down to,
## fading over LOW_FADE_M either side.
const LOW_M := 0.6
const LOW_FADE_M := 0.15

## The reach targets (world) of the arms that reach, their sides (0 right, 1
## left) and weights (0 to 1).
var targets: Array[Vector3] = []
var sides: Array[int] = []
var weights: Array[float] = []
## How far (0 to 1) each target's stoop is kept on whatever its height (none
## given: 0, the height fade alone).
var keeps: Array[float] = []
## The stoop drawn last (0 to 1), for checks and plates.
var drawn := 0.0


func _process_modification_with_delta(_delta: float) -> void:
	drawn = 0.0
	var skeleton := get_skeleton()
	if skeleton == null or targets.is_empty():
		return
	var hips := skeleton.find_bone("Hips")
	var spine := skeleton.find_bone("Spine_01")
	if hips < 0 or spine < 0:
		return
	var to_skeleton := skeleton.global_transform.affine_inverse()
	var to_world := skeleton.global_transform.basis.get_scale().x
	var pivot := skeleton.get_bone_global_pose(spine).origin
	var aim_at := Vector3.ZERO
	for i in targets.size():
		aim_at += to_skeleton * targets[i] / targets.size()
	var s := 0.0
	for i in targets.size():
		var arm := skeleton.find_bone(CarryArm.ARM_BONES[sides[i]])
		var shoulder := skeleton.get_bone_global_pose(arm).origin
		var reach := CarryArm.reach_of(skeleton, sides[i]) / to_world * REACH_SLACK
		var target := to_skeleton * targets[i]
		# Only for a low target (a bag on the floor), not a tray on a table: the
		# stoop fades out over LOW_FADE_M about LOW_M of height, so a target rising
		# past it (a bag lifted) straightens the back smoothly, never in a frame.
		var height := targets[i].y - skeleton.global_position.y
		var low := 1.0 - smoothstep(LOW_M - LOW_FADE_M, LOW_M + LOW_FADE_M, height)
		if i < keeps.size():
			low = maxf(low, clampf(keeps[i], 0.0, 1.0))
		if low <= 0.0:
			continue
		var need := needed(
			shoulder, pivot, aim_at, target, reach, STOOP_DROP / to_world, HIP_BACK_M / to_world
		)
		s = maxf(s, need * low * clampf(weights[i], 0.0, 1.0))
	if s <= 0.0:
		return
	drawn = s
	var feet: Array[Transform3D] = []
	for leg in LEGS:
		feet.append(skeleton.get_bone_global_pose(skeleton.find_bone(leg[2])))
	var low := skeleton.get_bone_global_pose(hips)
	low.origin.y -= STOOP_DROP / to_world * s
	# Back (the skeleton faces +Z), so the knees come forward less.
	low.origin.z -= HIP_BACK_M / to_world * s
	skeleton.set_bone_global_pose(hips, low)
	var back := skeleton.get_bone_global_pose(spine)
	back.basis = turn(pivot, aim_at, s) * back.basis
	skeleton.set_bone_global_pose(spine, back)
	for i in LEGS.size():
		_plant(skeleton, LEGS[i], feet[i])


## The turn of the back at stoop `s` (0 to 1), toward `target` from `pivot`
## (the Spine_01 bone), about the level axis across that direction.
static func turn(pivot: Vector3, target: Vector3, s: float) -> Basis:
	var toward := target - pivot
	toward.y = 0.0
	toward = toward.normalized() if toward.length() > 0.001 else Vector3.BACK
	return Basis(Vector3.UP.cross(toward).normalized(), deg_to_rad(STOOP_DEGREES) * s)


## Where `shoulder` is at stoop `s`: the back turned about `pivot` toward
## `aim_at` (turn()) and everything above the hips `drop` * s lower and `back`
## * s further back (-Z, the body facing +Z).
static func stooped(
	shoulder: Vector3,
	pivot: Vector3,
	aim_at: Vector3,
	s: float,
	drop := STOOP_DROP,
	back := HIP_BACK_M
) -> Vector3:
	var turned := pivot + turn(pivot, aim_at, s) * (shoulder - pivot)
	return turned - Vector3.UP * drop * s + Vector3.FORWARD * back * s


## The least stoop (0 to 1), the back bent toward `aim_at`, that brings
## `shoulder` within `reach` of `target` (1 when even the deepest does not).
static func needed(
	shoulder: Vector3,
	pivot: Vector3,
	aim_at: Vector3,
	target: Vector3,
	reach: float,
	drop := STOOP_DROP,
	back := HIP_BACK_M
) -> float:
	var reaches := func(s: float) -> bool:
		return stooped(shoulder, pivot, aim_at, s, drop, back).distance_to(target) <= reach
	if reaches.call(0.0):
		return 0.0
	for step in range(1, STEPS + 1):
		var hi := step / float(STEPS)
		if not reaches.call(hi):
			continue
		# Narrowed between the last step short of it and this one, so the stoop
		# changes smoothly with the target.
		var lo := hi - 1.0 / STEPS
		for i in 8:
			var mid := (lo + hi) * 0.5
			if reaches.call(mid):
				hi = mid
			else:
				lo = mid
		return hi
	return 1.0


## A two-bone reach from `root` (bones `upper` and `lower` long) toward
## `target`, bending toward `pole`: [the middle joint, the end].
static func two_bone(
	root: Vector3, upper: float, lower: float, target: Vector3, pole: Vector3
) -> Array[Vector3]:
	var to := target - root
	var dist := clampf(to.length(), absf(upper - lower) + 0.0001, upper + lower - 0.0001)
	var u := to.normalized() if to.length() > 0.0001 else Vector3.DOWN
	var a := (upper * upper - lower * lower + dist * dist) / (2.0 * dist)
	var h := sqrt(maxf(upper * upper - a * a, 0.0))
	var v := pole - u * pole.dot(u)
	v = v.normalized() if v.length() > 0.0001 else u.cross(Vector3.RIGHT).normalized()
	return [root + u * a + v * h, root + u * dist]


## `basis` turned by the shortest turn that takes direction `now` to `want`.
static func aim(basis: Basis, now: Vector3, want: Vector3) -> Basis:
	var a := now.normalized()
	var b := want.normalized()
	if a.dot(b) > 0.99999 or a.dot(b) < -0.99999:
		return basis
	return Basis(Quaternion(a, b)) * basis


## One leg (`bones`: thigh, shin, foot) reaching the foot pose `foot` from the
## lowered hips, its knee bent forward.
func _plant(skeleton: Skeleton3D, bones: Array, foot: Transform3D) -> void:
	var ids: Array[int] = []
	for bone: String in bones:
		ids.append(skeleton.find_bone(bone))
	if ids.has(-1):
		return
	var thigh := skeleton.get_bone_global_pose(ids[0])
	var shin_local := skeleton.get_bone_pose(ids[1])
	var foot_local := skeleton.get_bone_pose(ids[2])
	var upper := shin_local.origin.length()
	var lower := foot_local.origin.length()
	var outward := signf(thigh.origin.x)
	var pole := Vector3(outward * 0.15, 0.0, 1.0)
	var joints := two_bone(thigh.origin, upper, lower, foot.origin, pole)
	var knee_now := (thigh * shin_local).origin
	thigh.basis = aim(thigh.basis, knee_now - thigh.origin, joints[0] - thigh.origin)
	skeleton.set_bone_global_pose(ids[0], thigh)
	var shin := thigh * shin_local
	var ankle_now := (shin * foot_local).origin
	shin.basis = aim(shin.basis, ankle_now - shin.origin, joints[1] - shin.origin)
	skeleton.set_bone_global_pose(ids[1], shin)
	skeleton.set_bone_global_pose(ids[2], Transform3D(foot.basis, joints[1]))
