class_name TestLandsidePavementSeamless
extends GdUnitTestSuite
## Regression tests for seamless landside car pavement: outline-free flat road
## material on carriageway asphalt, markings, and parking aprons; unified y=0.10
## carriageway height; zero x=+-43 Road end-caps; and Road_Ext skirts to -0.12.

const FLAT_ROAD_MAT := "res://assets/landside/materials/tp_atlas_simple_road_toon.tres"
const OUTLINED_SIMPLE_MAT := "res://assets/materials/tp_atlas_simple_toon.tres"
const TOON_SHADER := "res://shaders/toon.gdshader"
const SITE_SCENE := preload("res://assets/buildings/tp_airport_site.glb")
const ROAD_EXT_SCENE := preload("res://assets/landside/landside_road_ext.glb")
const CROSSWALK_SCENE := preload("res://assets/landside/landside_crosswalk.glb")
const BAY_SCENE := preload("res://assets/landside/tp_curb_bay_01a.glb")
const LOT_SCENE := preload("res://assets/landside/tp_parking_01a.glb")
const MULTI_SCENE := preload("res://assets/landside/tc_parking_2a.glb")
const STARTER := preload("res://landside/starter_landside.tres")


func test_flat_road_material_uses_toon_shader_without_outline() -> void:
	var mat := load(FLAT_ROAD_MAT) as ShaderMaterial
	assert_object(mat).is_not_null()
	assert_object(mat.shader).is_not_null()
	assert_str(mat.shader.resource_path).is_equal(TOON_SHADER)
	assert_object(mat.next_pass).is_null()
	var albedo := mat.get_shader_parameter("albedo_texture") as Texture2D
	var ramp := mat.get_shader_parameter("ramp_texture") as Texture2D
	assert_object(albedo).is_not_null()
	assert_object(ramp).is_not_null()
	assert_str(albedo.resource_path).is_equal("res://assets/textures/tp_atlas_1a_d.png")
	assert_str(ramp.resource_path).is_equal("res://assets/textures/tp_toon_ramp_1d_d.png")


func test_site_road_has_no_x43_caps_flat_normals_and_outline_free_asphalt() -> void:
	var site := auto_free(SITE_SCENE.instantiate()) as Node3D
	site.position = Vector3(0.0, 0.0, -80.0)
	var road := site.find_child("Road", true, false) as MeshInstance3D
	assert_object(road).is_not_null()
	var mesh := road.mesh as ArrayMesh
	assert_object(mesh).is_not_null()

	var surf_paths: Array[String] = []
	var flat_surf := -1
	for s in mesh.get_surface_count():
		var mat := mesh.surface_get_material(s)
		assert_object(mat).is_not_null()
		surf_paths.append(mat.resource_path)
		if mat.resource_path == FLAT_ROAD_MAT:
			flat_surf = s
	assert_bool(surf_paths.has(FLAT_ROAD_MAT)).is_true()
	assert_bool(surf_paths.has(OUTLINED_SIMPLE_MAT)).is_true()

	var total_tris := 0
	var x43_caps := 0
	var flat_asphalt_tris := 0
	var flat_sidewalk_tris := 0
	var bad_normals := 0
	var outlined_asphalt_tris := 0
	var outlined_sidewalk_tris := 0
	var to_world := Transform3D(Basis(), Vector3(0.0, 0.0, -80.0)) * road.transform
	var nrm_basis := to_world.basis
	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var idx_var: Variant = arrays[Mesh.ARRAY_INDEX]
		var idx: PackedInt32Array = idx_var if idx_var is PackedInt32Array else PackedInt32Array()
		var tri_count := idx.size() / 3 if not idx.is_empty() else verts.size() / 3
		total_tris += tri_count
		for t in tri_count:
			var i0 := idx[t * 3] if not idx.is_empty() else t * 3
			var i1 := idx[t * 3 + 1] if not idx.is_empty() else t * 3 + 1
			var i2 := idx[t * 3 + 2] if not idx.is_empty() else t * 3 + 2
			var a := to_world * verts[i0]
			var b := to_world * verts[i1]
			var c := to_world * verts[i2]
			if (
				(absf(a.x - 43.0) < 0.002 and absf(b.x - 43.0) < 0.002 and absf(c.x - 43.0) < 0.002)
				or (
					absf(a.x + 43.0) < 0.002
					and absf(b.x + 43.0) < 0.002
					and absf(c.x + 43.0) < 0.002
				)
			):
				x43_caps += 1
			var gn := (c - a).cross(b - a)
			if gn.length() > 1e-6 and gn.normalized().y > 0.99:
				if (
					absf(a.y - 0.10) < 0.001
					and absf(b.y - 0.10) < 0.001
					and absf(c.y - 0.10) < 0.001
				):
					if s == flat_surf:
						flat_asphalt_tris += 1
						for k in [i0, i1, i2]:
							var wn := (nrm_basis * norms[k]).normalized()
							if wn.distance_to(Vector3.UP) > 0.001:
								bad_normals += 1
					else:
						outlined_asphalt_tris += 1
				elif (
					absf(a.y - 0.20) < 0.001
					and absf(b.y - 0.20) < 0.001
					and absf(c.y - 0.20) < 0.001
				):
					if s == flat_surf:
						flat_sidewalk_tris += 1
					else:
						outlined_sidewalk_tris += 1
	assert_int(total_tris).is_greater(0)
	assert_int(x43_caps).is_equal(0)
	assert_int(flat_asphalt_tris).is_greater(0)
	assert_int(outlined_asphalt_tris).is_equal(0)
	assert_int(flat_sidewalk_tris).is_greater(0)
	assert_int(outlined_sidewalk_tris).is_equal(0)
	assert_int(bad_normals).is_equal(0)


func test_road_ext_markings_and_aprons_use_outline_free_material_and_ground_skirts() -> void:
	var road_ext := auto_free(ROAD_EXT_SCENE.instantiate()) as Node3D
	var ext_mesh := (road_ext.find_child("Road_Ext", true, false) as MeshInstance3D).mesh
	var ext_paths := _surface_paths(ext_mesh)
	assert_bool(ext_paths.has(FLAT_ROAD_MAT)).is_true()
	assert_bool(ext_paths.has(OUTLINED_SIMPLE_MAT)).is_true()
	var ext_aabb := (road_ext.find_child("Road_Ext", true, false) as MeshInstance3D).get_aabb()
	assert_float(ext_aabb.position.y).is_equal_approx(-0.12, 0.001)
	assert_float(ext_aabb.end.y).is_equal_approx(0.20, 0.001)

	var dashes_mesh := (road_ext.find_child("Road_Ext_Dashes", true, false) as MeshInstance3D).mesh
	assert_array(_surface_paths(dashes_mesh)).is_equal([FLAT_ROAD_MAT])

	var xwalk := auto_free(CROSSWALK_SCENE.instantiate()) as Node3D
	var xwalk_mi := xwalk.find_child("Crosswalk_Stripes", true, false) as MeshInstance3D
	assert_array(_surface_paths(xwalk_mi.mesh)).is_equal([FLAT_ROAD_MAT])
	assert_float(xwalk_mi.get_aabb().position.y).is_equal_approx(0.012, 0.001)

	var bay := auto_free(BAY_SCENE.instantiate()) as Node3D
	var bay_mi := bay.find_child("TP_Curb_Bay_01A", true, false) as MeshInstance3D
	assert_array(_surface_paths(bay_mi.mesh)).is_equal([FLAT_ROAD_MAT])
	assert_float(bay_mi.get_aabb().position.y).is_equal_approx(0.012, 0.001)

	var lot := auto_free(LOT_SCENE.instantiate()) as Node3D
	var lot_apron := lot.find_child("TP_Parking_01A_Apron", true, false) as MeshInstance3D
	assert_array(_surface_paths(lot_apron.mesh)).is_equal([FLAT_ROAD_MAT])
	var lot_apron_aabb := lot_apron.transform * lot_apron.get_aabb()
	assert_float(lot_apron_aabb.position.y).is_equal_approx(-0.10, 0.001)
	assert_float(lot_apron_aabb.end.y).is_equal_approx(0.10, 0.001)

	var multi := auto_free(MULTI_SCENE.instantiate()) as Node3D
	var multi_apron := multi.find_child("Parking_2A_Apron", true, false) as MeshInstance3D
	assert_array(_surface_paths(multi_apron.mesh)).is_equal([FLAT_ROAD_MAT])
	var multi_aabb := multi_apron.transform * multi_apron.get_aabb()
	assert_float(multi_aabb.position.y).is_equal_approx(-0.10, 0.001)


func test_landside_places_and_dressing_unify_road_y_at_point_one() -> void:
	assert_float(LandsideStreetDressing.ROAD_Y).is_equal_approx(0.10, 0.0001)
	var sim := auto_free(LandsideSim.new()) as LandsideSim
	sim.use_definition(STARTER)
	sim.wallet = Wallet.new()
	var places := auto_free(LandsidePlaces.new()) as LandsidePlaces
	assert_float(places.road_top).is_equal_approx(0.10, 0.0001)
	places.landside = sim
	add_child(places)
	places.refresh()
	assert_float(places.starter_bay(0).position.y).is_equal_approx(0.10, 0.0001)


func _surface_paths(mesh: Mesh) -> Array[String]:
	var out: Array[String] = []
	for s in mesh.get_surface_count():
		out.append(mesh.surface_get_material(s).resource_path)
	return out
