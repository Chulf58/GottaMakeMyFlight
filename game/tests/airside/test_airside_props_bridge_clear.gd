class_name TestAirsidePropsBridgeClear
extends GdUnitTestSuite
## A jet bridge whose gate holds a plane it cannot dock (models 03 and 04)
## swings clear of it (board 82a139d0; ruling plane-04-stops-further-out-with-
## the-passenger-walk-ending-at, part 2): fully retracted, its tunnel along the
## wall line, no mesh edge of the plane or the bridge crossing the other, and
## no plane vertex inside a bridge mesh's bounds (Kit.clearance()), which also
## rules out a part lying wholly inside the other.
## The plane is drawn as PlaneView draws it at the stand and reports through
## PlaneProps.follow(), as in test_airside_props_bridges.gd.
##
## Controls, each a positive count on the same plane and bridge meshes: the
## plain parked pose (which the R11 lane measured cutting plane 03), and the
## swung-clear bridge with the plane moved so its door sill sits on the cab.

const Kit := preload("res://tests/airside/airside_props_kit.gd")
const UNREACHED: Array[String] = ["tp_plane_03a", "tp_plane_04a"]

var _airside: Airside
var _stand := StandPlacement.make(1, 20.0, -230.0)


func before() -> void:
	_airside = Kit.airside_from_main()
	add_child(_airside)
	assert_bool(_airside.set_gate_stands({"A": _stand})).is_true()


func after() -> void:
	_airside.free()


func test_an_undockable_plane_gets_the_bridge_swung_clear_and_uncut() -> void:
	var at := StandPlacement.stand_point(_stand)
	var pose := Transform3D(Basis.IDENTITY, at + Vector3.UP * PlaneView.ground_height_at(at))
	var entry: Dictionary = _airside.props.bridges["A"]
	var bridge: Node3D = entry["node"]
	var cab := bridge.find_child("Cab_Yaw", true, false) as Node3D
	var foot := bridge.find_child("Drive_Foot", true, false) as Node3D
	var wall := float(_stand["wall_z"])
	for model: String in UNREACHED:
		var plane := Kit.posed_model(self, model, pose, at, Vector3.BACK)
		var holder := plane.get_parent() as Node3D
		var props := PlaneProps.new()
		holder.add_child(props)
		props.follow(true, plane, model, FlightSim.State.BOARDING, "A", _airside, 1)
		var clear: Dictionary = entry["pose"]
		var found := Kit.crossings(plane, bridge)
		var reach := _aabb_of(bridge)
		var door: Vector3 = plane.global_transform * PlaneModels.PLANES[model]["doors"][0]
		print(
			(
				(
					"%s: clear %s docked %s, yaw %.1f deg, slide %.2f, pitch %.2f deg: %d crossings"
					+ " (%s); bridge x %.2f..%.2f z %.2f..%.2f (wall %.2f), door %s, foot y %.3f"
				)
				% [
					model,
					entry["clear"],
					entry["docked"],
					rad_to_deg(clear["yaw"]),
					clear["slide"],
					rad_to_deg(clear["pitch"]),
					found["count"],
					found["meshes"],
					reach.position.x,
					reach.end.x,
					reach.position.z,
					reach.end.z,
					wall,
					door,
					foot.global_position.y,
				]
			)
		)
		assert_bool(entry["clear"]).is_true()
		assert_bool(entry["docked"]).is_false()
		assert_float(clear["slide"]).is_equal(0.0)
		assert_float(clear["pitch"]).is_equal(0.0)
		assert_float(absf(clear["yaw"])).is_equal_approx(PI / 2.0, 1e-6)
		assert_int(found["count"]).is_equal(0)
		var gap := Kit.clearance(plane, bridge)
		print(
			(
				"%s: box clearance %.2f m (plane %s to bridge %s)"
				% [model, gap["gap"], gap["a_mesh"], gap["b_mesh"]]
			)
		)
		assert_float(gap["gap"]).is_greater(0.0)
		assert_float(absf(foot.global_position.y - entry["root"].origin.y)).is_less(0.01)
		# Control 1: the plain parked pose on the same meshes.
		JetBridgePose.apply(
			entry["joints"],
			JetBridgePose.parked(entry["root"], JetBridgePose.stand_door(_stand), Vector3.RIGHT)
		)
		var parked := Kit.crossings(plane, bridge)
		var parked_gap := Kit.clearance(plane, bridge)
		var parked_reach := _aabb_of(bridge)
		JetBridgePose.apply(entry["joints"], clear)
		# The swung tunnel comes no nearer the wall than the fixed link stub.
		print("%s: plain parked bridge z ends %.2f" % [model, parked_reach.end.z])
		assert_float(reach.end.z).is_less_equal(parked_reach.end.z + 0.001)
		assert_float(reach.end.z).is_less(wall)
		# Control 2: the swung-clear bridge with the plane's door sill on its cab.
		var shift := cab.global_position - door
		holder.position += shift
		var moved := Kit.crossings(plane, bridge)
		holder.position -= shift
		print(
			(
				(
					"%s controls: plain parked %d crossings (%s), box clearance %.2f m; door on"
					+ " the swung cab %d crossings"
				)
				% [model, parked["count"], parked["meshes"], parked_gap["gap"], moved["count"]]
			)
		)
		assert_int(parked["count"]).is_greater(0)
		assert_float(parked_gap["gap"]).is_equal(0.0)
		assert_int(moved["count"]).is_greater(0)
		props.follow(true, plane, model, FlightSim.State.PUSHBACK, "A", _airside, 1)
		assert_bool(entry["clear"]).is_false()
		assert_float(absf(entry["pose"]["yaw"] - clear["yaw"])).is_greater(0.01)
		holder.free()


## The world bounds of every visible mesh under `node`.
func _aabb_of(node: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for tri: Dictionary in Kit.world_tris(node):
		box = tri["box"] if first else box.merge(tri["box"])
		first = false
	return box
