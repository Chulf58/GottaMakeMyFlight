class_name TestPullGripMirror
extends GdUnitTestSuite
## A roller pulled in the left hand is held as high and as far out from the
## left leg as one pulled in the right hand is from the right leg (board
## ed73cfb1). One male and one female body walk, both arms posed as
## CarryArmPose poses a pulling arm (PULL_OUT_DEGREES, PULL_SWING_KEPT,
## PULL_LEAN_DEGREES, the upper arm's twist from its rest, pull_twist_degrees()),
## sampled at SAMPLES points through the walk clip. In the
## body's frame, mirrored so each hand's side is +x, the mean grip height and
## the mean gap from the grip out to its own Quad (thigh) bone agree between
## the hands within TOLERANCE_M. On main c8969cc the male body's left grip was
## 2.9 cm nearer its leg (0.231 vs 0.260 m) and 0.9 cm lower; the walk clip
## twists the left upper arm differently from the right, and the side carry
## kept the clip's twist (spike/pull_grip_asym_probe.gd). The set twist keeps
## the right hand's mean grip within RIGHT_KEPT_M of where the clip's twist
## put it (rest_twist_weight 0, the pose before the fix).

const SAMPLES := 24
const TOLERANCE_M := 0.01
const RIGHT_KEPT_M := 0.005
const MARKS: Array[String] = ["Fingers.R", "Fingers.L", "Quad.R", "Quad.L"]

var _bodies: Array = []


func before() -> void:
	for body in [0, PassengerLooks.PER_VARIANT]:
		var node := PassengerLooks.SCENES[body].instantiate() as Node3D
		add_child(node)
		node.position = Vector3(3.0 * _bodies.size(), 0.0, 0.0)
		node.set_meta(&"body", body)
		var skeleton := node.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		var marks := {}
		for name in MARKS:
			var at := BoneAttachment3D.new()
			at.bone_name = name
			skeleton.add_child(at)
			marks[name] = at
		var arms := []
		for side in 2:
			var arm := CarryArm.new()
			arm.side = side
			arm.holds = true
			arm.angle_degrees = CarryArmPose.PULL_OUT_DEGREES
			arm.swing_kept = CarryArmPose.PULL_SWING_KEPT
			arm.lean_back_degrees = CarryArmPose.PULL_LEAN_DEGREES
			arm.front_weight = 0.0
			arm.active = false
			skeleton.add_child(arm)
			arms.append(arm)
		var player := node.get_node("AnimationPlayer") as AnimationPlayer
		player.play("walk")
		player.pause()
		_bodies.append({"node": node, "marks": marks, "arms": arms, "player": player})


func after() -> void:
	for b: Dictionary in _bodies:
		(b["node"] as Node3D).free()
	_bodies.clear()


## The mean (grip height, grip gap out of its own Quad bone) of each hand of
## each body, mirrored, over the walk clip, with the arms on or off, the
## upper arm's twist `rest_twist` of the way from the clip's to the set one.
func _means(posed: bool, rest_twist := 1.0) -> Array:
	var sums := []
	for b: Dictionary in _bodies:
		for arm: CarryArm in b["arms"]:
			arm.active = posed
			arm.rest_twist_weight = rest_twist
			arm.twist_degrees = CarryArmPose.pull_twist_degrees(b["node"])
		sums.append([Vector2.ZERO, Vector2.ZERO])
	for sample in SAMPLES:
		for b: Dictionary in _bodies:
			var player: AnimationPlayer = b["player"]
			player.seek(player.get_animation("walk").length * sample / SAMPLES, true)
		await get_tree().process_frame
		await get_tree().process_frame
		for i in _bodies.size():
			var b: Dictionary = _bodies[i]
			var to := (b["node"] as Node3D).global_transform.affine_inverse()
			for hand in 2:
				var s := ".R" if hand == 0 else ".L"
				var grip := to * (b["marks"]["Fingers" + s] as Node3D).global_position
				var quad := to * (b["marks"]["Quad" + s] as Node3D).global_position
				var out := (grip.x - quad.x) * (-1.0 if hand == 0 else 1.0)
				sums[i][hand] += Vector2(grip.y, out) / SAMPLES
	return sums


func test_the_left_pulling_grip_mirrors_the_right() -> void:
	var clip: Array = await _means(false)
	var pulled: Array = await _means(true)
	for i in _bodies.size():
		var right: Vector2 = pulled[i][0]
		var left: Vector2 = pulled[i][1]
		print(
			(
				"body %d pulled R (height %.4f, out %.4f) L (%.4f, %.4f); clip R %s L %s"
				% [i, right.x, right.y, left.x, left.y, clip[i][0], clip[i][1]]
			)
		)
		# Control: the pulling arm is posed (the grip moved off the clip's).
		assert_float((right - (clip[i][0] as Vector2)).length()).is_greater(0.02)
		assert_float(right.y).is_greater(0.1)
		assert_float(absf(left.x - right.x)).is_less(TOLERANCE_M)
		assert_float(absf(left.y - right.y)).is_less(TOLERANCE_M)


func test_the_right_pulling_grip_stays_where_the_clip_twist_put_it() -> void:
	var before: Array = await _means(true, 0.0)
	var now: Array = await _means(true)
	for i in _bodies.size():
		var was: Vector2 = before[i][0]
		var right: Vector2 = now[i][0]
		var text := "body %d right grip before (height %.4f, out %.4f) now (%.4f, %.4f)"
		print(text % [i, was.x, was.y, right.x, right.y])
		# Control: the clip's twist leaves the two hands apart, so the set twist
		# changed the pose of at least one of them.
		var left_moved := ((before[i][1] as Vector2) - (now[i][1] as Vector2)).length()
		print("body %d left grip moved %.4f" % [i, left_moved])
		assert_float(absf(right.x - was.x)).is_less(RIGHT_KEPT_M)
		assert_float(absf(right.y - was.y)).is_less(RIGHT_KEPT_M)
	var male_left := ((before[0][1] as Vector2) - (now[0][1] as Vector2)).length()
	assert_float(male_left).is_greater(0.02)
