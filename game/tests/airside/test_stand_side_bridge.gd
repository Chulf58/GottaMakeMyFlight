class_name TestStandSideBridge
extends GdUnitTestSuite
## The jet bridge at a west or east stand (JetBridgePose; design airside-all-
## around-technical-design-one-route-source-per-con, slice S3): its root and
## the plane door's normal turn with the stand, so it stands to its plane as at
## a north stand. The docked pose is the north one's, and every mount is the
## north mount turned about the sill. Stands as in test_stand_side_frame.gd.

const NORTH := {"exit": 2, "x": -22.5, "wall_z": -98.0}
const SILLS := {"W": Vector2(62.0, -150.0), "E": Vector2(-62.0, -150.0)}
const SIDES: Array[String] = ["W", "E"]
const OUT := {"W": Vector3(-1.0, 0.0, 0.0), "E": Vector3(1.0, 0.0, 0.0)}
const DOCKING := "tp_plane_05a"
const ON_FOOT := "tp_plane_03a"
const EPS := 0.0001


static func _turned(side: String, offset: Vector3) -> Vector3:
	if side == "W":
		return Vector3(offset.z, offset.y, -offset.x)
	return Vector3(-offset.z, offset.y, offset.x)


static func _stand(side: String) -> Dictionary:
	return StandPlacement.make(2, SILLS[side].x, SILLS[side].y, side)


static func _point(side: String, north_point: Vector3) -> Vector3:
	var from := Vector3(NORTH["x"], 0.0, NORTH["wall_z"])
	var sill := Vector3(SILLS[side].x, 0.0, SILLS[side].y)
	return sill + _turned(side, north_point - from)


func test_the_root_stands_on_the_sill_facing_out_of_the_wall() -> void:
	var north := JetBridgePose.root_for(NORTH, 0.3)
	assert_vector(north.basis.z).is_equal_approx(Vector3(0.0, 0.0, -1.0), Vector3.ONE * EPS)
	for side in SIDES:
		var root := JetBridgePose.root_for(_stand(side), 0.3)
		print("%s root %s" % [side, root])
		assert_vector(root.origin).is_equal_approx(
			Vector3(SILLS[side].x, 0.3, SILLS[side].y), Vector3.ONE * EPS
		)
		assert_vector(root.basis.z).is_equal_approx(OUT[side], Vector3.ONE * EPS)
		assert_vector(root.basis.x).is_equal_approx(_turned(side, north.basis.x), Vector3.ONE * EPS)
		assert_float(root.basis.determinant()).is_equal_approx(1.0, EPS)


func test_the_docked_bridge_is_the_north_one_turned_about_the_sill() -> void:
	var north := JetBridgePose.pose_for(NORTH, DOCKING, true, 0.3)
	assert_bool(north["docked"]).is_true()
	for side in SIDES:
		var stand := _stand(side)
		assert_bool(JetBridgePose.reaches(stand, DOCKING, 0.3)).is_true()
		var got := JetBridgePose.pose_for(stand, DOCKING, true, 0.3)
		print("%s pose %s door %s normal %s" % [side, got["pose"], got["door"], got["normal"]])
		assert_bool(got["docked"]).is_true()
		for joint in ["slide", "height", "extend", "cab_yaw"]:
			assert_float(got["pose"][joint]).is_equal_approx(north["pose"][joint], EPS)
		assert_vector(got["door"]).is_equal_approx(_point(side, north["door"]), Vector3.ONE * EPS)
		assert_vector(got["normal"]).is_equal_approx(
			_turned(side, north["normal"]), Vector3.ONE * EPS
		)
		for name: StringName in north["mounts"]:
			assert_vector(got["mounts"][name]).is_equal_approx(
				_point(side, north["mounts"][name]), Vector3.ONE * EPS
			)


## The door normal points out of the plane's port side, away from its origin.
func test_the_door_normal_points_out_of_the_port_side() -> void:
	for side in SIDES:
		var stand := _stand(side)
		var at := JetBridgePose.plane_door(stand, ON_FOOT, 0.0)
		var from_plane: Vector3 = at["door"] - StandPlacement.stand_point(stand)
		var normal: Vector3 = at["normal"]
		print("%s door %s normal %s" % [side, at["door"], normal])
		assert_float(normal.dot(Vector3(from_plane.x, 0.0, from_plane.z))).is_greater(0.0)
		assert_float(absf(normal.dot(OUT[side]))).is_equal_approx(0.0, EPS)
		var walk: PackedVector3Array = JetBridgePose.pose_for(stand, ON_FOOT, false)["apron_walk"]
		assert_int(walk.size()).is_equal(5)
