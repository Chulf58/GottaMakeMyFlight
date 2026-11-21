class_name TestPlane05aTables
extends GdUnitTestSuite
## Regression test for tp_plane_05a.glb cabin tables: verifies TP_Plane_05A_Tables
## was baked to positive unit scale and outward-facing triangle winding.


func test_plane_05a_tables_have_unit_scale_and_outward_winding() -> void:
	var plane: Node3D = (PlaneView.PLANE_SCENES["tp_plane_05a"] as PackedScene).instantiate()
	var tables := plane.find_child("TP_Plane_05A_Tables", true, false) as MeshInstance3D
	assert_object(tables).is_not_null()
	var table_scale := tables.scale
	var table_det := tables.transform.basis.determinant()
	var faces := tables.mesh.get_faces()
	plane.free()
	assert_vector(table_scale).is_equal_approx(Vector3.ONE, Vector3.ONE * 1e-4)
	assert_float(table_det).is_greater(0.0)
	# Group triangles by rounded shared vertices to verify every table island has
	# positive outward volume around its own centroid (matches Blender check).
	var v_tris := {}
	var tri_count := faces.size() / 3
	for t in tri_count:
		for k in 3:
			var p := (faces[t * 3 + k] * 10000.0).round()
			var vk := "%d,%d,%d" % [int(p.x), int(p.y), int(p.z)]
			if not v_tris.has(vk):
				v_tris[vk] = []
			(v_tris[vk] as Array).append(t)
	var visited := PackedByteArray()
	visited.resize(tri_count)
	var island_vols: Array[float] = []
	for start in tri_count:
		if visited[start] == 1:
			continue
		var stack: Array[int] = [start]
		visited[start] = 1
		var island: Array[int] = []
		var center := Vector3.ZERO
		while not stack.is_empty():
			var cur: int = stack.pop_back()
			island.append(cur)
			for k in 3:
				var pt := faces[cur * 3 + k]
				center += pt
				var rp := (pt * 10000.0).round()
				var vk := "%d,%d,%d" % [int(rp.x), int(rp.y), int(rp.z)]
				for nxt: int in v_tris[vk]:
					if visited[nxt] == 0:
						visited[nxt] = 1
						stack.append(nxt)
		center /= float(island.size() * 3)
		var vol := 0.0
		for t in island:
			var a := faces[t * 3] - center
			var b := faces[t * 3 + 1] - center
			var c := faces[t * 3 + 2] - center
			# Godot front faces are clockwise from outside, so inward cross gives negative dot.
			vol -= a.dot((b - a).cross(c - a)) / 6.0
		island_vols.append(vol)
	print(
		(
			"TP_Plane_05A_Tables scale=%s islands=%d min_vol=%.5f"
			% [table_scale, island_vols.size(), island_vols.min()]
		)
	)
	assert_int(island_vols.size()).is_greater(0)
	for v in island_vols:
		assert_float(v).is_greater(0.0)
