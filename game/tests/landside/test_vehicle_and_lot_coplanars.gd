class_name TestVehicleAndLotCoplanars
extends GdUnitTestSuite
## Regression test verifying tp_loading_truck_01a.glb and tp_parking_01a.glb
## contain zero duplicate coplanar triangles.

const TRUCK_SCENE := preload("res://assets/vehicles/tp_loading_truck_01a.glb")
const LOT_SCENE := preload("res://assets/landside/tp_parking_01a.glb")


func test_loading_truck_and_parking_lot_have_zero_duplicate_coplanar_triangles() -> void:
	for scene: PackedScene in [TRUCK_SCENE, LOT_SCENE]:
		var root_node: Node3D = scene.instantiate()
		var dups := 0
		for mi: MeshInstance3D in root_node.find_children("*", "MeshInstance3D", true, false):
			var faces := mi.mesh.get_faces()
			var seen := {}
			for i in range(0, faces.size(), 3):
				var pts: Array[String] = []
				for k in 3:
					var v := (faces[i + k] * 10000.0).round()
					pts.append("%d,%d,%d" % [int(v.x), int(v.y), int(v.z)])
				pts.sort()
				var key := "|".join(pts)
				if seen.has(key):
					dups += 1
				else:
					seen[key] = true
		root_node.free()
		assert_int(dups).is_equal(0)
