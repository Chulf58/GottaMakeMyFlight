class_name RepackPose
extends SkeletonModifier3D
## Procedural repack posture modifier for passengers in SecurityRuntime.Phase.REPACK
## (ruling staff-station-interaction-poses-and-basic-scanner-scan-repac): replaces
## the plain idle clip with a gentle forward torso lean and alternating hands
## organizing bags at the floor/tray. Eases in after bags finish setting down
## and any pre-repack alarm/liquids reaction finishes, and eases out before
## REPACK ends so CarryStoop/CarryLead pickups are untouched.

const EASE_IN_START := 18.0
const EASE_IN_END := 26.0
const EASE_OUT_START := 14.0
const EASE_OUT_END := 6.0

var amount := 0.0
var sim_time := 0.0
var variant_seed := 0


## Smooth repack weight (0..1) from SecurityRuntime.Phase.REPACK work left,
## easing in after the initial bag set-down and out before pickup begins.
static func weight_for(p: Passenger) -> float:
	if p.stage != Passenger.Stage.SECURITY or p.security_phase != SecurityRuntime.Phase.REPACK:
		return 0.0
	var total := SecurityRuntime.work_for(SecurityRuntime.Phase.REPACK, p)
	var done := float(total - p.security_work)
	var left := float(p.security_work)
	var enter := smoothstep(EASE_IN_START, EASE_IN_END, done)
	var exit := smoothstep(EASE_OUT_END, EASE_OUT_START, left)
	return clampf(minf(enter, exit), 0.0, 1.0)


## Applies or disables the RepackPose modifier on `node`'s Skeleton3D.
static func apply(node: Node3D, new_amount: float, now: float, seed_id: int) -> void:
	var mod: RepackPose = node.get_meta(&"repack_pose") if node.has_meta(&"repack_pose") else null
	var on := new_amount > 0.0
	if on and mod == null:
		var skeletons := node.find_children("*", "Skeleton3D", true, false)
		if skeletons.is_empty():
			return
		var skeleton := skeletons[0] as Skeleton3D
		mod = RepackPose.new()
		mod.name = "RepackPose"
		skeleton.add_child(mod)
		skeleton.move_child(mod, mini(1, skeleton.get_child_count() - 1))
		node.set_meta(&"repack_pose", mod)
	elif not on and mod != null:
		mod.active = false
		mod.amount = 0.0
		return
	if mod != null:
		mod.active = on
		mod.amount = clampf(new_amount, 0.0, 1.0)
		mod.sim_time = now
		mod.variant_seed = seed_id


## Updates `sim_time` on an active RepackPose each frame so motion stays smooth.
static func tick_frame(node: Node3D, now: float) -> void:
	if not node.has_meta(&"repack_pose"):
		return
	var mod: RepackPose = node.get_meta(&"repack_pose")
	if mod.active:
		mod.sim_time = now


func _process_modification_with_delta(_delta: float) -> void:
	if amount <= 0.0:
		return
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	var a := clampf(amount, 0.0, 1.0)
	var t := sim_time / float(SimClock.TICK_RATE) + float(variant_seed % 7) * 0.37
	var osc := sin(t * 5.5)
	var wrist := cos(t * 5.5)
	_rotate_char(skeleton, "Spine_01", Vector3.RIGHT, 10.0 * a)
	_rotate_char(skeleton, "Spine_02", Vector3.RIGHT, 8.0 * a)
	_rotate_char(skeleton, "Neck", Vector3.RIGHT, 6.0 * a)
	_rotate_char(skeleton, "Head", Vector3.RIGHT, 8.0 * a)
	_rotate_char(skeleton, "Arm.L", Vector3.RIGHT, (-34.0 - 7.0 * osc) * a)
	_rotate_char(skeleton, "Arm.L", Vector3.UP, -10.0 * a)
	_rotate_char(skeleton, "Forearm.L", Vector3.RIGHT, (-38.0 + 10.0 * osc) * a)
	_rotate_char(skeleton, "Forearm.L", Vector3.UP, -12.0 * a)
	_rotate_char(skeleton, "Hand.L", Vector3.RIGHT, 8.0 * wrist * a)
	_rotate_char(skeleton, "Arm.R", Vector3.RIGHT, (-34.0 + 7.0 * osc) * a)
	_rotate_char(skeleton, "Arm.R", Vector3.UP, 10.0 * a)
	_rotate_char(skeleton, "Forearm.R", Vector3.RIGHT, (-38.0 - 10.0 * osc) * a)
	_rotate_char(skeleton, "Forearm.R", Vector3.UP, 12.0 * a)
	_rotate_char(skeleton, "Hand.R", Vector3.RIGHT, -8.0 * wrist * a)


func _rotate_char(skeleton: Skeleton3D, bone_name: String, axis_char: Vector3, deg: float) -> void:
	var idx := skeleton.find_bone(bone_name)
	if idx < 0 or absf(deg) < 1e-4:
		return
	var bone_pose := skeleton.get_bone_global_pose(idx)
	bone_pose.basis = Basis(axis_char.normalized(), deg_to_rad(deg)) * bone_pose.basis
	skeleton.set_bone_global_pose(idx, bone_pose)
