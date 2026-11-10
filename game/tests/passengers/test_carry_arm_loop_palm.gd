class_name TestCarryArmLoopPalm
extends GdUnitTestSuite
## A hand holding a backpack by its grab loop (CarryArm.loop_grip) lies flat
## on the pack's top (board bcad1dd0 item 2): with the arm posed over the walk
## clip and the pack upright or tilted (CarryArm.loop_up), no finger or thumb
## bone line of the holding hand comes nearer the pack's top, along the pack's
## up, than half a finger's thickness (the top is CarryLead.BACK_LOOP_UP under
## the grip: the grip is held that far over the loop, whose top is the
## pack's). On main 5baa5e0 the hand kept the clip's roll and stood on its
## edge, thumb up, and the fingers kept their rest curl: out of a lane tray
## the fingertips were up to 8.3 cm and the thumb's tip 10.6 cm under the
## grip, inside the pack's top (crossing probe seed 1106001 --lane, 38
## frames). One male and one female body, the left hand reaching to the side
## hang (CarryLead.BACK_SIDE_M out, BACK_HANG_BELOW_M under the shoulder).
##
## Bone lines, not vertices: headless, bake_mesh_from_current_skeleton_pose()
## gives no mesh, so CarryContact.body_points_owned() reads no body points.

const SAMPLES := 6
## The holding hand's finger and thumb bones (".L" added), each with the bone
## its far end is measured to (its child; the last bones run on as far as the
## one before them) and whether its joint is measured too: the thumb's root
## is in the heel of the hand, back by the wrist, not over the loop.
const PARTS := [
	["Fingers", "Fingertips", true],
	["Fingertips", "", true],
	["Thumb", "Thumb_Tip", false],
	["Thumb_Tip", "", true],
]
## A finger's or thumb's half thickness round its bone line.
const HALF_THICK_M := 0.01
## The pack's up: upright, and tilted as it is part way out of a tray.
const UPS := [Vector3.UP, Vector3(0.0, 0.87, 0.5)]

var _bodies: Array = []


func before() -> void:
	for body in [0, PassengerLooks.PER_VARIANT]:
		var node := PassengerLooks.SCENES[body].instantiate() as Node3D
		add_child(node)
		node.position = Vector3(3.0 * _bodies.size(), 0.0, 0.0)
		var skeleton := node.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		var names := ["Arm.L"]
		for part: Array in PARTS:
			names.append(part[0] + ".L")
		var marks := {}
		for name: String in names:
			var at := BoneAttachment3D.new()
			at.bone_name = name
			skeleton.add_child(at)
			marks[name] = at
		var arm := CarryArm.new()
		arm.side = 1
		arm.holds = true
		arm.loop_grip = true
		arm.reach_weight = 1.0
		skeleton.add_child(arm)
		var player := node.get_node("AnimationPlayer") as AnimationPlayer
		player.play("walk")
		player.pause()
		_bodies.append({"node": node, "marks": marks, "arm": arm, "player": player})


func after() -> void:
	for b: Dictionary in _bodies:
		(b["node"] as Node3D).free()
	_bodies.clear()


## Over the walk clip with the pack's up `up`: per body {"low" (the lowest
## point of a finger or thumb bone line (PARTS), under the grip
## along `up`, metres, negative under it), "part" (its bone), "points" (bone
## points measured), "miss" (the furthest the grip came from its target)}.
func _lowest(up: Vector3) -> Array:
	var out := []
	for b: Dictionary in _bodies:
		out.append({"low": INF, "part": "", "points": 0, "miss": 0.0})
	for sample in SAMPLES:
		for b: Dictionary in _bodies:
			var player: AnimationPlayer = b["player"]
			player.seek(player.get_animation("walk").length * sample / SAMPLES, true)
			var node := b["node"] as Node3D
			var shoulder := (b["marks"]["Arm.L"] as Node3D).global_position
			var arm := b["arm"] as CarryArm
			# The body faces +Z, its left is +X.
			arm.reach_target = Vector3(
				node.global_position.x + CarryLead.BACK_SIDE_M,
				shoulder.y - CarryLead.BACK_HANG_BELOW_M,
				node.global_position.z
			)
			arm.loop_up = up.normalized()
		await get_tree().process_frame
		await get_tree().process_frame
		for i in _bodies.size():
			var b: Dictionary = _bodies[i]
			var fingers := b["marks"]["Fingers.L"] as Node3D
			var grip := (
				fingers.global_position
				+ fingers.global_basis.y.normalized() * CarryOnProps.GRIP_ALONG_M
			)
			var seen: Dictionary = out[i]
			var target := (b["arm"] as CarryArm).reach_target
			seen["miss"] = maxf(seen["miss"], grip.distance_to(target))
			var length := 0.0
			for part: Array in PARTS:
				var bone := b["marks"][part[0] + ".L"] as Node3D
				if part[1] != "":
					var child := b["marks"][part[1] + ".L"] as Node3D
					length = bone.global_position.distance_to(child.global_position)
				var tip := bone.global_position + bone.global_basis.y.normalized() * length
				var points := [bone.global_position, tip] if part[2] else [tip]
				for at: Vector3 in points:
					seen["points"] += 1
					var under := (at - grip).dot(up.normalized())
					if under < seen["low"]:
						seen["low"] = under
						seen["part"] = part[0]
	return out


func test_a_loop_grip_hand_lies_flat_on_the_pack_top() -> void:
	var limit := -CarryLead.BACK_LOOP_UP.z + HALF_THICK_M
	for up: Vector3 in UPS:
		var seen: Array = await _lowest(up)
		for i in seen.size():
			var s: Dictionary = seen[i]
			print(
				(
					(
						"body %d up %s: lowest finger or thumb bone point %.3f m under the grip"
						+ " (%s), %d points, grip off its target at most %.3f m"
					)
					% [i, up, s["low"], s["part"], s["points"], s["miss"]]
				)
			)
			# Controls: the hand's bones were measured and it reached its target
			# (the bag is placed from the grip, so a miss would hide nothing here).
			assert_int(s["points"]).is_greater(0)
			assert_float(s["miss"]).is_less(0.05)
			assert_float(s["low"]).is_greater_equal(limit)
