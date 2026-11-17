class_name TestCarryLoopHook
extends GdUnitTestSuite
## A hand holding a backpack by its grab loop (CarryArm.loop_grip) closes round
## the loop like a grip: it bends its Fingers at the knuckles, its Fingertips
## and its Thumb_Tip by its skeleton's CarryArmPose.LOOP_CURL_DEGREES,
## LOOP_HOOK_DEGREES and LOOP_THUMB_DEGREES, so the tips come back nearer the
## wrist than the knuckles are, on a male and a female body and on both hands,
## with nothing but the body telling the arm which skeleton it is (so a move
## that never runs CarryArmPose.pose_arms() still curls). The grip moves with
## the curled Fingers bone (user-ruled 2026-11-17, "Curl the whole finger",
## board 4e5a26f0), and the reach puts that curled grip on its target, where
## the pack hangs from it. Control: with no curl the same tips point straight
## on past the grip, so the hand was engaged. Bone poses only: a headless baked
## mesh has no skin (anti-pattern a-headless-count-of-body-points-inside-a-
## carried-bag-reads-0), so how the hand looks is left to the windowed probe.

## The bodies (PassengerLooks.SCENES): tcp_male_character_01 and
## tcp_female_character_12.
const BODIES: Array[int] = [0, 17]


## The loop hand of `side` of a new body `body`, reaching for a point beside
## and below its shoulder as a tray-to-back move's side hang does; with
## `tagged` false the node has no "body" meta (not a passenger's).
func _rig(body: int, side: int, tagged := true) -> Dictionary:
	var node := PassengerLooks.SCENES[body].instantiate() as Node3D
	if tagged:
		node.set_meta(&"body", body)
	add_child(node)
	auto_free(node)
	(node.get_node("AnimationPlayer") as AnimationPlayer).play("idle")
	var skeleton := node.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var arm := CarryArm.new()
	arm.side = side
	arm.holds = false
	arm.loop_grip = true
	arm.reach_weight = 1.0
	skeleton.add_child(arm)
	var shoulder := skeleton.get_bone_global_rest(skeleton.find_bone(CarryArm.ARM_BONES[side]))
	var out := signf(shoulder.origin.x)
	arm.reach_target = (
		skeleton.global_transform * (shoulder.origin + Vector3(out * 0.12, -0.32, 0.12))
	)
	return {"node": node, "skeleton": skeleton, "arm": arm, "shoulder": shoulder.origin}


## The hand as drawn (after its modifiers), with the curl, the hook and the
## thumb bend at `degrees` (NAN: the arm's own, from the body): the grip
## (world, as CarryOnProps.grip_of() reads it), the Fingertips bone's axis,
## the tips' end, the wrist and the knuckles, and the Fingers' and the
## Thumb_Tip's bends from rest about their z axis (degrees).
func _pose(rig: Dictionary, degrees: float) -> Dictionary:
	var arm: CarryArm = rig["arm"]
	var skeleton: Skeleton3D = rig["skeleton"]
	arm.loop_curl_degrees = degrees
	arm.loop_hook_degrees = degrees
	arm.loop_thumb_degrees = degrees
	await _drawn(skeleton)
	var suffix: String = [".R", ".L"][arm.side]
	var xf := skeleton.global_transform
	var fingers := xf * skeleton.get_bone_global_pose(skeleton.find_bone("Fingers" + suffix))
	var tips := xf * skeleton.get_bone_global_pose(skeleton.find_bone("Fingertips" + suffix))
	var wrist := xf * skeleton.get_bone_global_pose(skeleton.find_bone("Hand" + suffix))
	var shoulder: Vector3 = xf * (rig["shoulder"] as Vector3)
	var level := arm.reach_target - shoulder
	level.y = 0.0
	return {
		"grip": fingers.origin + fingers.basis.y.normalized() * CarryOnProps.GRIP_ALONG_M,
		"tip": tips.basis.y.normalized(),
		# The tip's end, taken a Fingers bone's length along the Fingertips.
		"end": tips.origin + tips.basis.y.normalized() * tips.origin.distance_to(fingers.origin),
		"wrist": wrist.origin,
		"knuckles": fingers.origin,
		"level": level.normalized(),
		"curl": _bend_of(skeleton, "Fingers" + suffix),
		"thumb": _bend_of(skeleton, "Thumb_Tip" + suffix),
	}


## Bone `name`'s turn from its rest about its own z axis (degrees), as posed.
func _bend_of(skeleton: Skeleton3D, name: String) -> float:
	var bone := skeleton.find_bone(name)
	var rest := skeleton.get_bone_rest(bone).basis.get_rotation_quaternion()
	return rad_to_deg((rest.inverse() * skeleton.get_bone_pose_rotation(bone)).get_euler().z)


func test_the_loop_hand_closes_round_the_loop_and_its_grip_reaches_the_target() -> void:
	for body in BODIES:
		for side in [0, 1]:
			var rig := _rig(body, side)
			var curl := CarryArmPose.loop_curl_degrees(rig["node"])
			var mirror := 1.0 if side == 0 else -1.0
			var straight: Dictionary = await _pose(rig, 0.0)
			var closed: Dictionary = await _pose(rig, NAN)
			var tag := "body %d side %d curl %.0f" % [body, side, curl]
			var wrist: Vector3 = closed["wrist"]
			var tip_back := (closed["end"] as Vector3).distance_to(wrist)
			var knuckle_back := (closed["knuckles"] as Vector3).distance_to(wrist)
			var drop: float = (closed["grip"] as Vector3).y - (closed["end"] as Vector3).y
			var miss := (closed["grip"] as Vector3).distance_to(
				(rig["arm"] as CarryArm).reach_target
			)
			print(
				(
					"LOOP_HOOK %s straight on=%.2f closed curl=%.1f tip_to_wrist=%.3f"
					+ (
						" knuckle_to_wrist=%.3f drop=%.3f miss=%.4f"
						% [
							tag,
							straight["tip"].dot(straight["level"]),
							closed["curl"] * mirror,
							tip_back,
							knuckle_back,
							drop,
							miss,
						]
					)
				)
			)
			# Control: uncurled, the tips point on past the grip.
			var on: float = straight["tip"].dot(straight["level"])
			assert_float(on).override_failure_message(tag).is_greater(0.5)
			# Closed: the Fingers bent at the knuckles by the skeleton's curl
			# (mirrored on the left hand), and the tips' ends back nearer the
			# wrist than the knuckles are, a fist round the loop. With only the
			# Fingertips bent (main before this change) the Fingers stayed at
			# rest and the tips ended 11 to 12 cm from the wrist, past the
			# knuckles.
			assert_float(closed["curl"] * mirror).override_failure_message(tag).is_greater(60.0)
			assert_float(tip_back).override_failure_message(tag).is_less(knuckle_back - 0.015)
			# The curled tips stay above the floor of the region the clip check
			# leaves to the holding hand (carry_probe_checks LOOP_BOX z 0.205),
			# 5.8 cm under a grip held CarryLead.BACK_LOOP_UP over the loop top.
			assert_float(drop).override_failure_message(tag).is_less(0.058)
			# The reach aims the curled grip, the point the pack hangs from.
			assert_float(miss).override_failure_message(tag).is_less(0.01)
			# The thumb bend is the skeleton's, mirrored on the left hand.
			var thumb := CarryArmPose.loop_thumb_degrees(rig["node"]) * mirror
			assert_float(closed["thumb"]).override_failure_message(tag).is_equal_approx(thumb, 1.0)


## Each skeleton takes its own values: the male bodies the first, the female
## the second.
func test_each_skeleton_takes_its_own_hook() -> void:
	var male := auto_free(Node3D.new()) as Node3D
	male.set_meta(&"body", 0)
	var female := auto_free(Node3D.new()) as Node3D
	female.set_meta(&"body", PassengerLooks.PER_VARIANT)
	assert_float(CarryArmPose.loop_curl_degrees(male)).is_equal(CarryArmPose.LOOP_CURL_DEGREES[0])
	assert_float(CarryArmPose.loop_curl_degrees(female)).is_equal(CarryArmPose.LOOP_CURL_DEGREES[1])
	assert_float(CarryArmPose.loop_hook_degrees(male)).is_equal(CarryArmPose.LOOP_HOOK_DEGREES[0])
	assert_float(CarryArmPose.loop_hook_degrees(female)).is_equal(CarryArmPose.LOOP_HOOK_DEGREES[1])
	for degrees in CarryArmPose.LOOP_CURL_DEGREES + CarryArmPose.LOOP_HOOK_DEGREES:
		assert_float(degrees).is_greater(0.0)
	assert_float(CarryArmPose.loop_thumb_degrees(male)).is_equal(CarryArmPose.LOOP_THUMB_DEGREES[0])
	assert_float(CarryArmPose.loop_thumb_degrees(female)).is_equal(
		CarryArmPose.LOOP_THUMB_DEGREES[1]
	)


## A skeleton with no passenger body above it gets no curl, no hook and no
## thumb bend unless they are set: its loop hand's Fingers, Fingertips and
## Thumb_Tip stay as the clip has them (it warns once), never a guessed
## skeleton's values. Control: with all three set on the same arm, the loop
## hand is bent (the path ran).
func test_a_skeleton_with_no_body_is_not_hooked() -> void:
	var rig := _rig(0, 0, false)
	var arm: CarryArm = rig["arm"]
	var skeleton: Skeleton3D = rig["skeleton"]
	var bones: Array[int] = []
	for name in ["Fingers.R", "Fingertips.R", "Thumb_Tip.R"]:
		bones.append(skeleton.find_bone(name))
	arm.loop_grip = false
	await _drawn(skeleton)
	var clip: Array[Quaternion] = []
	for bone in bones:
		clip.append(skeleton.get_bone_pose_rotation(bone))
	arm.loop_grip = true
	await _drawn(skeleton)
	var off: Array[float] = []
	for i in bones.size():
		off.append(rad_to_deg(clip[i].angle_to(skeleton.get_bone_pose_rotation(bones[i]))))
	arm.loop_curl_degrees = 80.0
	arm.loop_hook_degrees = 90.0
	arm.loop_thumb_degrees = -90.0
	await _drawn(skeleton)
	var set_off := rad_to_deg(clip[1].angle_to(skeleton.get_bone_pose_rotation(bones[1])))
	var curl_off := rad_to_deg(clip[0].angle_to(skeleton.get_bone_pose_rotation(bones[0])))
	print(
		(
			"LOOP_HOOK no body fingers_off=%.2f tips_off=%.2f thumb_off=%.2f set_off=%.1f curl_off=%.1f"
			% [off[0], off[1], off[2], set_off, curl_off]
		)
	)
	for o in off:
		assert_float(o).is_less(0.5)
	assert_float(set_off).is_greater(45.0)
	assert_float(curl_off).is_greater(45.0)


## Waits until `skeleton` has been drawn again after its modifiers.
func _drawn(skeleton: Skeleton3D) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await skeleton.skeleton_updated
