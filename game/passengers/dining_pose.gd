class_name DiningPose
extends SkeletonModifier3D
## Seated posture modifier for cafe, restaurant and bar guests (board VF6):
## replaces the stiff thighs-locked sit_idle pose with a natural forward torso
## lean, reaching forearms/hands just above tabletops or bar counters, lower-back
## support against restaurant_booth cushions, and bar-stool foot tuck onto the
## stool footrest. Zero changes to character .glb skeletons (ruling e7517650).
## Placed after AnimationPlayer and ClipCrossfade on Skeleton3D; at NONE or
## amount 0 it does nothing.

enum Kind { NONE, TABLE, BOOTH, BAR }

const EASE_TICKS := 8

var kind: Kind = Kind.NONE
var amount := 0.0
var variant_seed := 0


## Creates, updates or removes the DiningPose modifier on `node`'s Skeleton3D.
static func apply(node: Node3D, new_kind: Kind, new_amount: float, seed_id: int) -> void:
	var pose: DiningPose = node.get_meta(&"dining_pose") if node.has_meta(&"dining_pose") else null
	var active := new_kind != Kind.NONE and new_amount > 0.0
	if active and pose == null:
		var skeletons := node.find_children("*", "Skeleton3D", true, false)
		if skeletons.is_empty():
			return
		var skeleton := skeletons[0] as Skeleton3D
		pose = DiningPose.new()
		pose.name = "DiningPose"
		skeleton.add_child(pose)
		# Run right after ClipCrossfade (index 0) and before carry modifiers.
		skeleton.move_child(pose, mini(1, skeleton.get_child_count() - 1))
		node.set_meta(&"dining_pose", pose)
	elif not active and pose != null:
		var parent := pose.get_parent()
		if parent != null:
			parent.remove_child(pose)
		pose.queue_free()
		node.remove_meta(&"dining_pose")
		return
	if pose != null:
		pose.kind = new_kind
		pose.amount = clampf(new_amount, 0.0, 1.0)
		pose.variant_seed = seed_id


## Smoothly ramps DiningPose on during CAFE_SEATED and eases out before stand-up.
static func seated_weight(sim: PassengerSim, p: Passenger, visit: CafeVisit) -> float:
	if visit == null:
		return 0.0
	var spent := sim.tick - p.stage_tick
	var left := maxi(visit.dwell_end - sim.tick, 0)
	var edge := mini(spent, left)
	return smoothstep(0.0, 1.0, clampf(edge / float(EASE_TICKS), 0.0, 1.0))


## Maps a cafe piece definition id to its DiningPose.Kind.
static func kind_for(def_id: StringName) -> Kind:
	match def_id:
		&"cafe_table", &"restaurant_table":
			return Kind.TABLE
		&"restaurant_booth":
			return Kind.BOOTH
		&"bar_counter":
			return Kind.BAR
	return Kind.NONE


func _process_modification_with_delta(_delta: float) -> void:
	if kind == Kind.NONE or amount <= 0.0:
		return
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	var a := clampf(amount, 0.0, 1.0)
	var handed := 1.0 if (variant_seed % 2) == 0 else -1.0
	match kind:
		Kind.TABLE:
			_rotate_char(skeleton, "Spine_01", Vector3.RIGHT, 5.0 * a)
			_rotate_char(skeleton, "Spine_02", Vector3.RIGHT, 4.0 * a)
			_rotate_char(skeleton, "Head", Vector3.RIGHT, -4.0 * a)
			_rotate_char(skeleton, "Head", Vector3.UP, 3.0 * handed * a)
			_reach_arms(skeleton, a, handed, -22.0, -24.0, -18.0)
		Kind.BOOTH:
			# Gentle forward torso lean toward booth table while keeping lower back clear of cushion.
			_rotate_char(skeleton, "Spine_01", Vector3.RIGHT, 3.0 * a)
			_rotate_char(skeleton, "Spine_02", Vector3.RIGHT, 4.0 * a)
			_rotate_char(skeleton, "Spine_03", Vector3.RIGHT, 2.0 * a)
			_rotate_char(skeleton, "Head", Vector3.RIGHT, -4.0 * a)
			_rotate_char(skeleton, "Head", Vector3.UP, 2.5 * handed * a)
			_reach_arms(skeleton, a, handed, -22.0, -24.0, -18.0)
		Kind.BAR:
			_rotate_char(skeleton, "Spine_01", Vector3.RIGHT, 5.0 * a)
			_rotate_char(skeleton, "Spine_02", Vector3.RIGHT, 5.0 * a)
			_rotate_char(skeleton, "Head", Vector3.RIGHT, -5.0 * a)
			_rotate_char(skeleton, "Head", Vector3.UP, 3.0 * handed * a)
			_reach_arms(skeleton, a, handed, -26.0, -28.0, -22.0)
			# Tuck shins gently back so lifted feet clear the stool pan and rest near the footrest.
			_rotate_char(skeleton, "Shin.L", Vector3.RIGHT, 10.0 * a)
			_rotate_char(skeleton, "Shin.R", Vector3.RIGHT, 10.0 * a)
			_rotate_char(skeleton, "Foot.L", Vector3.RIGHT, -8.0 * a)
			_rotate_char(skeleton, "Foot.R", Vector3.RIGHT, -8.0 * a)


func _reach_arms(
	skeleton: Skeleton3D,
	a: float,
	handed: float,
	arm_pitch: float,
	dom_forearm: float,
	off_forearm: float
) -> void:
	for side_info: Array in [[".L", -1.0, handed > 0.0], [".R", 1.0, handed < 0.0]]:
		var suffix: String = side_info[0]
		var inward: float = side_info[1]
		var is_dom: bool = side_info[2]
		_rotate_char(skeleton, "Arm" + suffix, Vector3.RIGHT, arm_pitch * a)
		_rotate_char(skeleton, "Arm" + suffix, Vector3.UP, -1.5 * inward * a)
		var f_pitch := dom_forearm if is_dom else off_forearm
		_rotate_char(skeleton, "Forearm" + suffix, Vector3.RIGHT, f_pitch * a)
		_rotate_char(skeleton, "Forearm" + suffix, Vector3.UP, 2.0 * inward * a)


## Rotates `bone_name` about `axis_char` (given in skeleton/character space,
## +X left, +Y up, +Z forward) by `deg` degrees while preserving child kinematics.
func _rotate_char(skeleton: Skeleton3D, bone_name: String, axis_char: Vector3, deg: float) -> void:
	var idx := skeleton.find_bone(bone_name)
	if idx < 0 or absf(deg) < 1e-4:
		return
	var pose := skeleton.get_bone_global_pose(idx)
	pose.basis = Basis(axis_char.normalized(), deg_to_rad(deg)) * pose.basis
	skeleton.set_bone_global_pose(idx, pose)
