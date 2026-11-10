class_name TestAirsidePropsBridges
extends GdUnitTestSuite
## The nose-loader jet bridges (board 0adca5c6; rulings jet-bridges-are-nose-
## loader-pedestal-bridges-an-enclosed-wal, nose-loader-bridge-design-stair-
## landing-and-cab-share-one-fl, plane-03-boards-on-foot-from-the-apron-plane-
## 04-docks-the-no): one per gate stand, rooted exactly on the gate's exit door
## sill; docked with Mount_Door on the drawn plane's front port door for models
## 04 to 07, parked for 03 and when no plane reports; and the pure
## JetBridgePose.pose_for() names the same pose and mounts the drawn bridge
## shows. The parked plane is drawn as PlaneView draws it (FlightPose.
## model_position() on the stand point) and reports through PlaneProps.follow().

const Kit := preload("res://tests/airside/airside_props_kit.gd")
const BRIDGE_SCENE := preload("res://assets/airside/props/jet_bridge.glb")
## How far Mount_Door may sit from the door it docks at, and how far a drawn
## mount may sit from pose_for()'s, in metres.
const DOCK_TOLERANCE_M := 0.01
const MOUNT_TOLERANCE_M := 0.001
const DOCKING: Array[String] = ["tp_plane_04a", "tp_plane_05a", "tp_plane_06a", "tp_plane_07a"]
const ON_FOOT: Array[String] = ["tp_plane_03a"]

var _airside: Airside
var _stand := StandPlacement.make(1, 20.0, -230.0)
var _east := StandPlacement.make(2, 60.0, -230.0)


func before() -> void:
	_airside = Kit.airside_from_main()
	add_child(_airside)
	assert_bool(_airside.set_gate_stands({"A": _stand, "B": _east})).is_true()


func after() -> void:
	_airside.free()


func test_rig_constants_match_the_written_glb() -> void:
	var bridge: Node3D = BRIDGE_SCENE.instantiate()
	var rest := {
		"Mount_ExitSill": Vector3.ZERO,
		"Mount_ApronDoor": Vector3(JetBridgePose.VEST_HALF, 0.0, JetBridgePose.APRON_Z),
		"Mount_StairFoot": Vector3(0.0, 0.0, JetBridgePose.STAIR_Z0 - JetBridgePose.STEP_OFF),
		"Mount_StairTop": Vector3(0.0, 0.0, JetBridgePose.STAIR_Z1 + JetBridgePose.STEP_OFF),
		"Cab_Yaw": Vector3(0.0, 0.0, JetBridgePose.CAB_Z),
		"Mount_Door": Vector3(0.0, 0.0, JetBridgePose.MOUNT_DOOR_Z),
		"Curtain_Low": Vector3(0.0, 0.0, JetBridgePose.LANDING_END - JetBridgePose.CURTAIN_T),
		"Curtain_High":
		Vector3(
			0.0,
			JetBridgePose.CAB_IN + JetBridgePose.CURTAIN_GAP,
			JetBridgePose.LANDING_END - JetBridgePose.CURTAIN_T
		),
	}
	for joint: String in rest:
		var node := bridge.find_child(joint, true, false) as Node3D
		assert_object(node).is_not_null()
		print("%s rest %s, want %s" % [joint, node.position, rest[joint]])
		assert_vector(node.position).is_equal_approx(rest[joint], Vector3.ONE * 0.001)
	assert_int(JetBridgePose.joints_of(bridge).size()).is_equal(JetBridgePose.JOINTS.size())
	bridge.free()


## The root is the exit door's sill on the wall line, exactly, turned so +z
## points out from the wall.
func test_each_gate_gets_one_bridge_rooted_on_its_exit_door() -> void:
	var props := _airside.props
	assert_array(props.bridges.keys()).contains_exactly_in_any_order(["A", "B"])
	for gate: String in ["A", "B"]:
		var stand: Dictionary = _stand if gate == "A" else _east
		var bridge: Node3D = props.bridges[gate]["node"]
		var sill := (bridge.find_child("Mount_ExitSill", true, false) as Node3D).global_position
		var out := bridge.global_basis.z
		print("gate %s: root %s, sill %s, +z %s" % [gate, bridge.global_position, sill, out])
		assert_float(sill.x).is_equal_approx(float(stand["x"]), 0.0001)
		assert_float(sill.z).is_equal_approx(float(stand["wall_z"]), 0.0001)
		assert_vector(out).is_equal_approx(Vector3.FORWARD, Vector3.ONE * 0.0001)


func test_the_bridge_docks_every_docking_model_and_parks_for_03() -> void:
	var entry: Dictionary = _airside.props.bridges["A"]
	var mount := entry["node"].find_child("Mount_Door", true, false) as Node3D
	for model: String in DOCKING + ON_FOOT:
		var plane := _park(model)
		var door: Vector3 = plane.global_transform * PlaneModels.PLANES[model]["doors"][0]
		var pose: Dictionary = entry["pose"]
		var off := mount.global_position.distance_to(door)
		print(
			(
				(
					"%s: model %s docked %s, Mount_Door %.4f m off the door %s; slide %.3f height %.3f"
					+ " yaw %.1f extend %.3f"
				)
				% [
					model,
					entry["model"],
					entry["docked"],
					off,
					door,
					pose["slide"],
					pose["height"],
					rad_to_deg(pose["cab_yaw"]),
					pose["extend"]
				]
			)
		)
		assert_str(entry["model"]).is_equal(model)
		if DOCKING.has(model):
			assert_bool(entry["docked"]).is_true()
			assert_float(off).is_less(DOCK_TOLERANCE_M)
			assert_float(pose["height"]).is_equal_approx(
				PlaneModels.PLANES[model]["doors"][0].y, 0.001
			)
		else:
			assert_bool(entry["docked"]).is_false()
			assert_dict(pose).is_equal(JetBridgePose.parked())
		var props := plane.get_parent().get_child(1) as PlaneProps
		props.follow(true, plane, model, FlightSim.State.PUSHBACK, "A", _airside, 1)
		assert_bool(entry["docked"]).is_false()
		assert_dict(entry["pose"]).is_equal(JetBridgePose.parked())
		plane.get_parent().free()


## pose_for() is the bridge the game draws: the same pose, every mount on its
## glb node, and the plane door where the drawn plane has it.
func test_pose_for_names_the_drawn_pose_and_mounts() -> void:
	var entry: Dictionary = _airside.props.bridges["A"]
	var bridge: Node3D = entry["node"]
	var ground := float(entry["root"].origin.y)
	for model: String in DOCKING + ON_FOOT + [""]:
		var plane: Node3D = null if model == "" else _park(model)
		var want := JetBridgePose.pose_for(_stand, model, model != "", ground)
		var worst := 0.0
		for name: StringName in want["mounts"]:
			var node := bridge.find_child(String(name), true, false) as Node3D
			worst = maxf(worst, node.global_position.distance_to(want["mounts"][name]))
		var door_off := 0.0
		if plane != null:
			var drawn: Vector3 = plane.global_transform * PlaneModels.PLANES[model]["doors"][0]
			door_off = drawn.distance_to(want["door"])
		print(
			(
				(
					"%s: pose_for docks %s docked %s; worst mount %.5f m off its node, door %.5f m"
					+ " off the drawn door; walk %d points, apron walk %d points"
				)
				% [
					model if model != "" else "none",
					want["docks"],
					want["docked"],
					worst,
					door_off,
					want["walk"].size(),
					want["apron_walk"].size()
				]
			)
		)
		assert_float(worst).is_less(MOUNT_TOLERANCE_M)
		assert_float(door_off).is_less(MOUNT_TOLERANCE_M)
		assert_dict(want["pose"]).is_equal(entry["pose"])
		assert_bool(want["docked"]).is_equal(entry["docked"])
		assert_int(want["walk"].size()).is_equal(5 if DOCKING.has(model) else 0)
		assert_int(want["apron_walk"].size()).is_equal(3 if ON_FOOT.has(model) else 0)
		if plane != null:
			plane.get_parent().free()


func test_a_bridge_parks_only_when_no_plane_reports_its_gate() -> void:
	var props := _airside.props
	props.dock_plane(7, "A", "tp_plane_06a")
	props.dock_plane(8, "A", "tp_plane_06a")
	assert_bool(props.bridges["A"]["docked"]).is_true()
	assert_bool(props.bridges["B"]["docked"]).is_false()
	props.release_plane(7)
	assert_bool(props.bridges["A"]["docked"]).is_true()
	props.dock_plane(8, "B", "tp_plane_06a")
	assert_bool(props.bridges["A"]["docked"]).is_false()
	assert_bool(props.bridges["B"]["docked"]).is_true()
	props.release_plane(8)
	assert_bool(props.bridges["B"]["docked"]).is_false()


func test_a_gate_that_loses_its_stand_loses_its_bridge() -> void:
	var airside := Kit.airside_from_main()
	add_child(airside)
	assert_bool(airside.set_gate_stands({"A": _stand, "B": _east})).is_true()
	assert_int(airside.props.bridges.size()).is_equal(2)
	assert_bool(airside.set_gate_stands({"B": _east})).is_true()
	assert_array(airside.props.bridges.keys()).contains_exactly(["B"])
	airside.free()


## Plane `model` parked at the stand, reporting to gate A as in BOARDING; its
## PlaneProps is the holder's second child.
func _park(model: String) -> Node3D:
	var at := StandPlacement.stand_point(_stand)
	var pose := Transform3D(Basis.IDENTITY, at + Vector3.UP * PlaneView.ground_height_at(at))
	var plane := Kit.posed_model(self, model, pose, at, Vector3.BACK)
	var props := PlaneProps.new()
	plane.get_parent().add_child(props)
	props.follow(true, plane, model, FlightSim.State.BOARDING, "A", _airside, 1)
	return plane
