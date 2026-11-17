class_name TestCarryLoopHook
extends GdUnitTestSuite
## A hand holding a backpack by its grab loop (CarryArm.loop_grip) hooks its
## Fingertips down and back toward the palm by its skeleton's
## CarryArmPose.LOOP_HOOK_DEGREES, on a male and a female body and on both
## hands, and the grip does not move (the Fingers bone stays at its rest;
## board 4e5a26f0). Control: with no hook the same tips point straight on
## past the grip, so the hand was engaged. Bone poses only: a headless baked
## mesh has no skin (anti-pattern a-headless-count-of-body-points-inside-a-
## carried-bag-reads-0), so how the hand looks is left to the windowed probe.

## The bodies (PassengerLooks.SCENES): tcp_male_character_01 and
## tcp_female_character_12.
const BODIES: Array[int] = [0, 17]


## The loop hand of `side` of a new body `body`, reaching for a point beside
## and below its shoulder as a tray-to-back move's side hang does.
func _rig(body: int, side: int) -> Dictionary:
	var node := PassengerLooks.SCENES[body].instantiate() as Node3D
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


## The grip (world) and the Fingertips bone's axis, with the hook at
## `degrees`, read as the skeleton is drawn (after its modifiers).
func _pose(rig: Dictionary, degrees: float) -> Dictionary:
	var arm: CarryArm = rig["arm"]
	var skeleton: Skeleton3D = rig["skeleton"]
	arm.loop_hook_degrees = degrees
	await get_tree().process_frame
	await get_tree().process_frame
	await skeleton.skeleton_updated
	var suffix: String = [".R", ".L"][arm.side]
	var xf := skeleton.global_transform
	var fingers := xf * skeleton.get_bone_global_pose(skeleton.find_bone("Fingers" + suffix))
	var tips := xf * skeleton.get_bone_global_pose(skeleton.find_bone("Fingertips" + suffix))
	var shoulder: Vector3 = xf * (rig["shoulder"] as Vector3)
	var level := arm.reach_target - shoulder
	level.y = 0.0
	return {
		"grip": fingers.origin + fingers.basis.y.normalized() * CarryOnProps.GRIP_ALONG_M,
		"tip": tips.basis.y.normalized(),
		"level": level.normalized(),
	}


func test_the_loop_hand_hooks_its_fingertips_and_keeps_its_grip() -> void:
	for body in BODIES:
		for side in [0, 1]:
			var rig := _rig(body, side)
			var hook := CarryArmPose.loop_hook_degrees(rig["node"])
			var straight: Dictionary = await _pose(rig, 0.0)
			var hooked: Dictionary = await _pose(rig, hook)
			var tag := "body %d side %d hook %.0f" % [body, side, hook]
			var level: Vector3 = hooked["level"]
			print(
				(
					"LOOP_HOOK %s straight up=%.2f on=%.2f hooked up=%.2f on=%.2f grip_moved=%.4f"
					% [
						tag,
						straight["tip"].y,
						straight["tip"].dot(level),
						hooked["tip"].y,
						hooked["tip"].dot(level),
						(hooked["grip"] as Vector3).distance_to(straight["grip"]),
					]
				)
			)
			# Control: unhooked, the tips point on past the grip.
			assert_float(straight["tip"].dot(level)).override_failure_message(tag).is_greater(0.5)
			# Hooked: back toward the palm under the hand, not down into the pack
			# (the hand's roll, and so the tips' height, follows the clip's).
			assert_float(hooked["tip"].dot(level)).override_failure_message(tag).is_less(-0.5)
			assert_float(hooked["tip"].y).override_failure_message(tag).is_greater(-0.5)
			var moved := (hooked["grip"] as Vector3).distance_to(straight["grip"])
			assert_float(moved).override_failure_message(tag).is_less(0.001)


## Each skeleton takes its own value: the male bodies the first, the female
## the second.
func test_each_skeleton_takes_its_own_hook() -> void:
	var male := auto_free(Node3D.new()) as Node3D
	male.set_meta(&"body", 0)
	var female := auto_free(Node3D.new()) as Node3D
	female.set_meta(&"body", PassengerLooks.PER_VARIANT)
	assert_float(CarryArmPose.loop_hook_degrees(male)).is_equal(CarryArmPose.LOOP_HOOK_DEGREES[0])
	assert_float(CarryArmPose.loop_hook_degrees(female)).is_equal(CarryArmPose.LOOP_HOOK_DEGREES[1])
	assert_float(CarryArmPose.LOOP_HOOK_DEGREES[0]).is_greater(0.0)
	assert_float(CarryArmPose.LOOP_HOOK_DEGREES[1]).is_greater(0.0)
