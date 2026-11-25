class_name AirstairsPose
extends RefCounted
## Pure pose solver and joint applicator for airstairs.glb (decisions 94ae5894,
## 710a78b4). Mirrors tools/blender/airside/build_airside_props.py across port
## (+X) aircraft door sills 0.63 m (04a) to 2.91 m (07a); 03a uses its built-in
## step and never docks airstairs.

const Z_REAR := -1.92
const PIVOT_Y := 0.14
const PIVOT_Z := -1.25
const REST_DEG := 28.0
const REST_RAD := deg_to_rad(REST_DEG)
const REST_SLIDE := 0.59
const L_UP := 2.15
const UPPER_N := 0.175
const PLAT_D := 0.96
const SLIDE_MIN := 0.0
const SLIDE_MAX := 1.75
const HEIGHT_MIN := 0.63
const HEIGHT_MAX := 2.91
const LIMIT_SLACK := 1e-4
const LIFT_A := Vector2(0.16, 0.95)
const LIFT_B_S := 1.20
const LIFT_B_N := -0.06
const STEPS := 7
const SLIDE_KNOTS := [
	Vector2(0.63, 0.00),
	Vector2(1.58, 0.59),
	Vector2(2.39, 1.35),
	Vector2(2.91, 1.75),
]


## Ground height at `stand` (same surface the parked plane rests on).
static func ground_y(stand: Dictionary) -> float:
	return PlaneView.ground_height_at(StandPlacement.stand_point(stand))


## Whether `model` uses airstairs.glb (04a-07a; false for 03a and unknown).
static func docks(model: String) -> bool:
	return JetBridgePose.docks(model)


## Interpolated telescopic upper-stair slide for sill height `height` (m).
static func slide_for_height(height: float) -> float:
	var h := clampf(height, HEIGHT_MIN, HEIGHT_MAX)
	for i in range(1, SLIDE_KNOTS.size()):
		var a: Vector2 = SLIDE_KNOTS[i - 1]
		var b: Vector2 = SLIDE_KNOTS[i]
		if h <= b.x or i == SLIDE_KNOTS.size() - 1:
			var t := clampf((h - a.x) / maxf(b.x - a.x, 1e-6), 0.0, 1.0)
			return clampf(lerpf(a.y, b.y, t), SLIDE_MIN, SLIDE_MAX)
	return REST_SLIDE


## Pure kinematic pose for sill height `height` above ground.
static func solve(height: float) -> Dictionary:
	var ok := height >= HEIGHT_MIN - LIMIT_SLACK and height <= HEIGHT_MAX + LIMIT_SLACK
	var h := clampf(height, HEIGHT_MIN, HEIGHT_MAX)
	var slide := slide_for_height(h)
	var beam_len := slide + L_UP
	var radius := sqrt(beam_len * beam_len + UPPER_N * UPPER_N)
	var phi := atan2(UPPER_N, beam_len)
	var ratio := clampf((h - PIVOT_Y) / maxf(radius, 1e-6), -1.0, 1.0)
	var theta := asin(ratio) - phi
	var hinge_z := PIVOT_Z + beam_len * cos(theta) - UPPER_N * sin(theta)
	var door_z := hinge_z + PLAT_D
	var stair_pitch := -(theta - REST_RAD)
	var counter_pitch := theta - REST_RAD
	var rest_b := Vector2(
		PIVOT_Y + LIFT_B_S * sin(REST_RAD) + LIFT_B_N * cos(REST_RAD),
		PIVOT_Z + LIFT_B_S * cos(REST_RAD) - LIFT_B_N * sin(REST_RAD)
	)
	var now_b := Vector2(
		PIVOT_Y + LIFT_B_S * sin(theta) + LIFT_B_N * cos(theta),
		PIVOT_Z + LIFT_B_S * cos(theta) - LIFT_B_N * sin(theta)
	)
	var ang_rest := atan2((rest_b - LIFT_A).x, (rest_b - LIFT_A).y)
	var ang_now := atan2((now_b - LIFT_A).x, (now_b - LIFT_A).y)
	var lift_base_x := -(ang_now - ang_rest)
	var lift_rod_x := lift_base_x - stair_pitch
	return {
		"ok": ok,
		"height": h,
		"theta": theta,
		"slide": slide,
		"hinge_z": hinge_z,
		"door_z": door_z,
		"stair_pitch": stair_pitch,
		"counter_pitch": counter_pitch,
		"lift_base_x": lift_base_x,
		"lift_rod_x": lift_rod_x,
	}


## Full world docking pose and 3D walk waypoints for `model` parked at `stand`.
## Waypoints: [bottom_entry, stair_foot, stair_top, top_door].
static func pose_for(stand: Dictionary, model: String, on_ground_y := 0.0) -> Dictionary:
	if not docks(model) or stand.is_empty():
		return {
			"docks": false,
			"theta": REST_RAD,
			"slide": REST_SLIDE,
			"root": Transform3D.IDENTITY,
			"waypoints": PackedVector3Array(),
			"bottom_entry": Vector3.ZERO,
			"top_door": Vector3.ZERO,
		}
	var at := JetBridgePose.plane_door(stand, model, on_ground_y)
	var door: Vector3 = at["door"]
	var normal: Vector3 = at["normal"]
	var s := solve(door.y - on_ground_y)
	var yaw := atan2(-normal.x, -normal.z)
	var origin := Vector3(door.x, on_ground_y, door.z) + normal * float(s["door_z"])
	var root := Transform3D(Basis(Vector3.UP, yaw), origin)
	var bottom_entry := root * Vector3(0.0, 0.0, Z_REAR)
	var stair_foot := root * Vector3(0.0, PIVOT_Y, PIVOT_Z)
	var stair_top := root * Vector3(0.0, float(s["height"]), float(s["hinge_z"]))
	var top_door := root * Vector3(0.0, float(s["height"]), float(s["door_z"]))
	return {
		"docks": true,
		"ok": s["ok"],
		"theta": s["theta"],
		"slide": s["slide"],
		"pose": s,
		"root": root,
		"door": door,
		"normal": normal,
		"bottom_entry": bottom_entry,
		"top_door": top_door,
		"waypoints": PackedVector3Array([bottom_entry, stair_foot, stair_top, top_door]),
	}


## Collects the articulated joints of an instanced airstairs.glb.
static func joints_of(stairs: Node) -> Dictionary:
	if stairs == null:
		return {}
	var out := {}
	for name in ["Stair_Pivot", "Upper_Stairs", "Top_Platform", "Lift_Base", "Lift_Rod"]:
		var node := stairs.find_child(name, true, false) as Node3D
		if node == null:
			push_error("AirstairsPose: airstairs.glb missing '%s'" % name)
			return {}
		out[StringName(name)] = node
	var steps: Array[Node3D] = []
	for prefix in ["Step_L_", "Step_U_"]:
		for i in range(1, STEPS + 1):
			var step_name := "%s%02d" % [prefix, i]
			var step := stairs.find_child(step_name, true, false) as Node3D
			if step == null:
				push_error("AirstairsPose: airstairs.glb missing '%s'" % step_name)
				return {}
			steps.append(step)
	out[&"steps"] = steps
	return out


## Applies `solved` (from solve() or pose_for()["pose"]) to `joints` (from joints_of()).
static func apply(joints: Dictionary, solved: Dictionary) -> void:
	if joints.is_empty():
		return
	var p: Dictionary = solved.get("pose", solved)
	(joints[&"Stair_Pivot"] as Node3D).rotation.x = float(p["stair_pitch"])
	(joints[&"Upper_Stairs"] as Node3D).position = (
		Vector3(0.0, sin(REST_RAD), cos(REST_RAD)) * float(p["slide"])
	)
	var counter := float(p["counter_pitch"])
	(joints[&"Top_Platform"] as Node3D).rotation.x = counter
	for step: Node3D in joints[&"steps"]:
		step.rotation.x = counter
	(joints[&"Lift_Base"] as Node3D).rotation.x = float(p["lift_base_x"])
	(joints[&"Lift_Rod"] as Node3D).rotation.x = float(p["lift_rod_x"])
