class_name TestAirsidePropsBridges
extends GdUnitTestSuite
## The jet bridges (board 4c08b8e5, Runway R11): one per gate stand, backed
## onto the terminal wall, docked with its Mount_Door on the drawn plane's front
## port door for every model the rig reaches, and parked otherwise. The parked
## plane is drawn as PlaneView draws it (FlightPose.model_position() on the
## stand point) and reports through PlaneProps.follow(), the code PlaneView
## calls each frame.

const Kit := preload("res://tests/airside/airside_props_kit.gd")
const BRIDGE_SCENE := preload("res://assets/airside/props/jet_bridge.glb")
## How far Mount_Door may sit from the door it docks at, in metres.
const DOCK_TOLERANCE_M := 0.01
## The models the rig reaches (door sills 1.58-2.91 m) and the ones it cannot
## (0.79 m and 0.63 m, below its 9 degree pitch limit).
const REACHED: Array[String] = ["tp_plane_05a", "tp_plane_06a", "tp_plane_07a"]
const UNREACHED: Array[String] = ["tp_plane_03a", "tp_plane_04a"]

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
		"Tunnel_Yaw": Vector3(0.0, JetBridgePose.ROT_FLOOR, 0.0),
		"Tunnel_Pitch": Vector3(0.0, 0.0, JetBridgePose.HINGE_Z),
		"Cab_Level": Vector3(0.0, 0.0, JetBridgePose.CAB_Z),
		"Drive_Level": Vector3(0.0, -JetBridgePose.TUN_B_SINK, JetBridgePose.DRIVE_Z),
		"Drive_Foot": Vector3(0.0, -(JetBridgePose.ROT_FLOOR - JetBridgePose.TUN_B_SINK), 0.0),
		"Mount_Door": Vector3(0.0, 0.0, JetBridgePose.MOUNT_DOOR_Z),
		"Mount_Link": Vector3(0.0, JetBridgePose.ROT_FLOOR, -JetBridgePose.LINK_Z),
	}
	for joint: String in rest:
		var node := bridge.find_child(joint, true, false) as Node3D
		assert_object(node).is_not_null()
		print("%s rest %s, want %s" % [joint, node.position, rest[joint]])
		assert_vector(node.position).is_equal_approx(rest[joint], Vector3.ONE * 0.005)
	assert_int(JetBridgePose.joints_of(bridge).size()).is_equal(JetBridgePose.JOINTS.size())
	bridge.free()


func test_each_gate_gets_one_bridge_backed_onto_its_wall_east_of_the_door() -> void:
	var props := _airside.props
	assert_array(props.bridges.keys()).contains_exactly_in_any_order(["A", "B"])
	for gate: String in ["A", "B"]:
		var stand: Dictionary = _stand if gate == "A" else _east
		var bridge: Node3D = props.bridges[gate]["node"]
		var link := (bridge.find_child("Mount_Link", true, false) as Node3D).global_position
		var door := JetBridgePose.stand_door(stand)
		print(
			(
				"gate %s: root %s, link back z %.2f (wall %.2f), door %s"
				% [gate, bridge.global_position, link.z, stand["wall_z"], door]
			)
		)
		assert_float(link.z).is_between(stand["wall_z"] - 0.31, stand["wall_z"] - 0.29)
		assert_float(bridge.global_position.x - door.x).is_greater(JetBridgePose.MOUNT_DOOR_Z)


func test_bridge_docks_on_the_front_port_door_of_every_model_it_reaches() -> void:
	var at := StandPlacement.stand_point(_stand)
	# On the ground under the stand, as PlaneView.pose_at() lifts a ground pose.
	var pose := Transform3D(Basis.IDENTITY, at + Vector3.UP * PlaneView.ground_height_at(at))
	var entry: Dictionary = _airside.props.bridges["A"]
	var mount := entry["node"].find_child("Mount_Door", true, false) as Node3D
	var foot := entry["node"].find_child("Drive_Foot", true, false) as Node3D
	for model: String in REACHED + UNREACHED:
		var plane := Kit.posed_model(self, model, pose, at, Vector3.BACK)
		var props := _props_under(plane.get_parent())
		props.follow(true, plane, model, FlightSim.State.BOARDING, "A", _airside, 1)
		var door: Vector3 = plane.global_transform * PlaneModels.PLANES[model]["doors"][0]
		var pose_now: Dictionary = entry["pose"]
		var off := mount.global_position.distance_to(door)
		print(
			(
				(
					"%s: docked %s, Mount_Door %.4f m off the door %s, slide %.2f, pitch %.2f deg,"
					+ " drive foot y %.3f (root y %.3f)"
				)
				% [
					model,
					entry["docked"],
					off,
					door,
					pose_now["slide"],
					rad_to_deg(pose_now["pitch"]),
					foot.global_position.y,
					entry["root"].origin.y,
				]
			)
		)
		if REACHED.has(model):
			assert_bool(entry["docked"]).is_true()
			assert_bool(entry["clear"]).is_false()
			assert_float(off).is_less(DOCK_TOLERANCE_M)
		else:
			assert_bool(entry["docked"]).is_false()
			# Swung clear of the plane (test_airside_props_bridge_clear.gd).
			assert_bool(entry["clear"]).is_true()
			assert_float(pose_now["slide"]).is_equal(0.0)
		assert_float(absf(foot.global_position.y - entry["root"].origin.y)).is_less(0.01)
		props.follow(true, plane, model, FlightSim.State.PUSHBACK, "A", _airside, 1)
		assert_bool(entry["docked"]).is_false()
		assert_bool(entry["clear"]).is_false()
		plane.get_parent().free()


func test_a_bridge_parks_only_when_no_plane_reports_its_gate() -> void:
	var props := _airside.props
	var door := JetBridgePose.stand_door(_stand) + Vector3(0.0, 2.39, 0.0)
	props.dock_plane(7, "A", door, Vector3.RIGHT)
	props.dock_plane(8, "A", door, Vector3.RIGHT)
	assert_bool(props.bridges["A"]["docked"]).is_true()
	assert_bool(props.bridges["B"]["docked"]).is_false()
	props.release_plane(7)
	assert_bool(props.bridges["A"]["docked"]).is_true()
	props.dock_plane(
		8, "B", JetBridgePose.stand_door(_east) + Vector3(0.0, 2.39, 0.0), Vector3.RIGHT
	)
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


func _props_under(holder: Node) -> PlaneProps:
	var props := PlaneProps.new()
	holder.add_child(props)
	return props
