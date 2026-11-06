extends SceneTree
## Headless measure of the pulling grip on each hand (board ed73cfb1): a male
## and a female passenger body (each gender shares one skeleton), both arms
## posed as CarryArmPose poses a pulling arm, sampled at SAMPLES points through
## each clip a pulling guest plays. Prints, per clip, mode, body and hand, the
## mean grip (Fingers bone) height, its gap out from its own Quad bone and how
## far ahead it is, in the body's frame mirrored so the hand's side is +x.
## Modes: "clip" (no CarryArm), "today" (the pull with the clip's upper-arm
## twist, rest_twist_weight 0), "set" (CarryArmPose.pull_twist_degrees) and a
## sweep of twist_degrees with rest_twist_weight 1.
## Run:
##   timeout 300 Godot_v4.7.2-stable_win64_console.exe --headless --audio-driver Dummy \
##     --path game -s res://spike/pull_grip_asym_probe.gd

const SAMPLES := 24
const CLIPS: Array[String] = ["walk", "run", "idle"]
const SWEEP: Array[float] = [10.0, 15.0, 20.0, 25.0, 30.0, 35.0, 40.0, 45.0, 50.0]
const MARKS: Array[String] = ["Fingers.R", "Fingers.L", "Quad.R", "Quad.L"]

var _bodies: Array = []
var _modes: Array = ["clip", "today", "set"]
var _frame := 0
var _sample := 0
var _mode := 0
var _clip := 0
var _sums := {}


func _initialize() -> void:
	for twist in SWEEP:
		_modes.append("tw%d" % twist)
	for body in [0, PassengerLooks.PER_VARIANT]:
		var node := PassengerLooks.SCENES[body].instantiate() as Node3D
		root.add_child(node)
		node.position = Vector3(_bodies.size() * 3.0, 0.0, 0.0)
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
			skeleton.add_child(arm)
			arms.append(arm)
		var player := node.get_node("AnimationPlayer") as AnimationPlayer
		_bodies.append({"node": node, "marks": marks, "arms": arms, "player": player, "id": body})
	_seek()


func _seek() -> void:
	var mode: String = _modes[_mode]
	for b: Dictionary in _bodies:
		for arm: CarryArm in b["arms"]:
			arm.active = mode != "clip"
			arm.rest_twist_weight = 0.0 if mode == "today" else 1.0
			if mode == "set":
				arm.twist_degrees = CarryArmPose.pull_twist_degrees(b["node"])
			elif mode.begins_with("tw"):
				arm.twist_degrees = float(mode.substr(2))
		var player: AnimationPlayer = b["player"]
		if player.current_animation != CLIPS[_clip]:
			player.play(CLIPS[_clip])
			player.pause()
		var length := player.get_animation(CLIPS[_clip]).length
		player.seek(length * float(_sample) / SAMPLES, true)


func _process(_delta: float) -> bool:
	_frame += 1
	if _frame % 2 == 1:
		return false
	for i in _bodies.size():
		_measure(i)
	_sample += 1
	if _sample >= SAMPLES:
		_sample = 0
		_mode += 1
		if _mode >= _modes.size():
			_mode = 0
			_clip += 1
			if _clip >= CLIPS.size():
				_print()
				return true
	_seek()
	return false


func _measure(i: int) -> void:
	var b: Dictionary = _bodies[i]
	var to := (b["node"] as Node3D).global_transform.affine_inverse()
	for hand in 2:
		var s := ".R" if hand == 0 else ".L"
		var grip := to * (b["marks"]["Fingers" + s] as Node3D).global_position
		var quad := to * (b["marks"]["Quad" + s] as Node3D).global_position
		var out := (grip.x - quad.x) * (-1.0 if hand == 0 else 1.0)
		var key := "%d/%d/%d/%d" % [_clip, _mode, i, hand]
		_sums[key] = (
			(_sums.get(key, Vector3.ZERO) as Vector3) + Vector3(grip.y, out, grip.z) / SAMPLES
		)


func _print() -> void:
	print("PULL_GRIP mean grip (height, out of own Quad, ahead) per hand; d = L - R")
	for clip in CLIPS.size():
		for mode in _modes.size():
			for i in _bodies.size():
				var r: Vector3 = _sums["%d/%d/%d/0" % [clip, mode, i]]
				var l: Vector3 = _sums["%d/%d/%d/1" % [clip, mode, i]]
				var d := l - r
				var text := "%-5s %-6s %-23s R(%.3f %.3f %.3f) L(%.3f %.3f %.3f) d(%+.3f %+.3f %+.3f)"
				var row := [CLIPS[clip], _modes[mode], PassengerLooks.BODIES[_bodies[i]["id"]]]
				print(text % (row + [r.x, r.y, r.z, l.x, l.y, l.z, d.x, d.y, d.z]))
