class_name TestAirfieldBackdrop
extends GdUnitTestSuite
## Verifies AirfieldBackdrop spatial clearance, runway length adaptation,
## taxi-sign clearance, apron skirt winding, TaxiMarkings junction/side-stand
## geometry, TaxiPavingSite.lift_overlay(), and Toon asset bounds/materials.

const SITE := preload("res://build/terminal_site.tres")
const EDGE_LIGHT_ASSETS := [
	"taxi_edge_light",
	"runway_edge_light_white",
	"runway_edge_light_amber",
	"runway_threshold_light",
	"papi_light_bank",
]
const ALL_PROP_ASSETS := [
	"taxi_edge_light",
	"runway_edge_light_white",
	"runway_edge_light_amber",
	"runway_threshold_light",
	"papi_light_bank",
	"windsock",
]
const ALL_LANDMARK_ASSETS := [
	"tp_control_tower_01a",
	"tp_radar_01a",
	"tp_hangar_01a",
	"tp_hangar_02a",
	"tp_metal_fence_01a",
	"tp_cistern_01a",
	"tp_loading_truck_02a",
	"tp_bus_01a",
	"tp_pick_up_01a",
]

var _airside: Airside
var _flights: FlightSim
var _backdrop: AirfieldBackdrop


func before() -> void:
	_airside = TestStandLaneClearance.scene_airside()
	_flights = FlightSim.new()
	_flights.runway.size = Runway.SMALL
	_backdrop = AirfieldBackdrop.new()
	_backdrop.airside = _airside
	_backdrop.flights = _flights
	add_child(_flights)
	add_child(_airside)
	add_child(_backdrop)


func after() -> void:
	_backdrop.free()
	_airside.free()
	_flights.free()


func test_all_landmarks_stay_strictly_outside_playable_and_runway_bounds() -> void:
	for spec in AirfieldBackdrop.landmark_specs():
		var pos: Vector3 = spec["pos"]
		(
			assert_bool(AirfieldBackdrop.is_outside_playable_bounds(pos))
			. override_failure_message("%s inside playable bounds: %s" % [spec["stem"], pos])
			. is_true()
		)
		(
			assert_bool(AirfieldBackdrop.clears_runway_corridor(pos))
			. override_failure_message("%s inside runway corridor: %s" % [spec["stem"], pos])
			. is_true()
		)
		assert_float(pos.z).is_less_equal(AirfieldBackdrop.NORTH_SAFE_Z_MAX)


func test_all_fences_clear_playable_spurs_and_runway_corridors() -> void:
	var fences := AirfieldBackdrop.fence_specs()
	assert_int(fences.size()).is_greater(50)
	for fspec in fences:
		var pos: Vector3 = fspec["pos"]
		(
			assert_bool(AirfieldBackdrop.is_outside_playable_bounds(pos))
			. override_failure_message("fence inside playable/spur box: %s" % pos)
			. is_true()
		)
		(
			assert_bool(AirfieldBackdrop.clears_runway_corridor(pos))
			. override_failure_message("fence inside runway corridor: %s" % pos)
			. is_true()
		)


func test_runway_edge_lights_adapt_to_runway_length_and_skip_stubs_and_signs() -> void:
	var counts := {}
	var sign_b := Rect2(140.0, -302.36, 6.0, 0.72).grow(0.35)
	var sign_c := Rect2(-108.0, -302.36, 6.0, 0.72).grow(0.35)
	for size: String in [Runway.SMALL, Runway.MEDIUM, Runway.LARGE]:
		var specs := AirfieldBackdrop.runway_edge_light_specs(size)
		counts[size] = specs.size()
		var half := Runway.length_m(size) * 0.5
		for spec in specs:
			var pos: Vector3 = spec["pos"]
			assert_float(absf(pos.x)).is_less_equal(half - 47.0)
			if pos.z > StandPlacement.RUNWAY_Z and spec["stem"] != "runway_threshold_light":
				for sx: float in AirfieldBackdrop.STUB_XS:
					assert_float(absf(pos.x - sx)).is_greater_equal(
						AirfieldBackdrop.STUB_CLEAR_M - 0.01
					)
			var xz := Vector2(pos.x, pos.z)
			(
				assert_bool(sign_b.has_point(xz))
				. override_failure_message("light collides with TaxiSign_B: %s" % pos)
				. is_false()
			)
			(
				assert_bool(sign_c.has_point(xz))
				. override_failure_message("light collides with TaxiSign_C: %s" % pos)
				. is_false()
			)
	assert_int(counts[Runway.MEDIUM]).is_greater(counts[Runway.SMALL])
	assert_int(counts[Runway.LARGE]).is_greater(counts[Runway.MEDIUM])


func test_taxiway_edge_lights_clear_strips_pads_runway_and_site() -> void:
	var specs := AirfieldBackdrop.taxi_edge_light_specs(
		_airside.paving.shown, _airside.paving.pads, Runway.SMALL
	)
	assert_int(specs.size()).is_greater(10)
	var site_rect: Rect2 = SITE.grid_rect()
	var rwy_rect := TaxiwayWorks.runway_rect(Runway.SMALL)
	for spec in specs:
		var pos: Vector3 = spec["pos"]
		var pt := Vector2(pos.x, pos.z)
		assert_bool(site_rect.has_point(pt)).is_false()
		assert_bool(rwy_rect.has_point(pt)).is_false()
		for strip in _airside.paving.shown:
			if not strip.has("quad"):
				assert_bool((strip["rect"] as Rect2).has_point(pt)).is_false()
		for pad in _airside.paving.pads:
			assert_bool(pad.has_point(pt)).is_false()


func test_all_15_airfield_assets_and_paving_material_bind_toon_and_ground_cleanly() -> void:
	var entries: Array[Dictionary] = []
	for stem: String in ALL_PROP_ASSETS:
		(
			entries
			. append(
				{
					"stem": stem,
					"path": AirfieldBackdrop.PROPS_DIR + stem + ".glb",
					"edge_light": EDGE_LIGHT_ASSETS.has(stem),
				}
			)
		)
	for stem: String in ALL_LANDMARK_ASSETS:
		(
			entries
			. append(
				{
					"stem": stem,
					"path": AirfieldBackdrop.LANDMARKS_DIR + stem + ".glb",
					"edge_light": false,
				}
			)
		)
	assert_int(entries.size()).is_equal(15)
	for entry in entries:
		var packed := load(entry["path"]) as PackedScene
		assert_object(packed).is_not_null()
		var inst := auto_free(packed.instantiate()) as Node3D
		var aabb := _scene_local_aabb(inst)
		(
			assert_float(absf(aabb.position.y))
			. override_failure_message(
				"%s not grounded min_y=%.3f" % [entry["stem"], aabb.position.y]
			)
			. is_less_equal(0.05)
		)
		if entry["edge_light"]:
			assert_float(aabb.end.y).is_less_equal(AirfieldBackdrop.MAX_EDGE_LIGHT_HEIGHT_M)
		var mats := 0
		for mi in inst.find_children("*", "MeshInstance3D", true, false):
			var mesh := (mi as MeshInstance3D).mesh
			if mesh == null:
				continue
			for i in mesh.get_surface_count():
				var mat := mesh.surface_get_material(i)
				assert_object(mat).is_not_null()
				var path := mat.resource_path
				(
					assert_bool(
						(
							path.begins_with("res://assets/materials/")
							or path.begins_with("res://assets/airside/materials/")
						)
					)
					. is_true()
				)
				if mat is ShaderMaterial:
					var sm := mat as ShaderMaterial
					assert_str(sm.shader.resource_path).is_equal("res://shaders/toon.gdshader")
				mats += 1
		assert_int(mats).is_greater(0)

	var paving_mat := TaxiPaving.MATERIAL as ShaderMaterial
	assert_object(paving_mat).is_not_null()
	var outline := paving_mat.next_pass as ShaderMaterial
	assert_object(outline).is_not_null()
	assert_str(outline.shader.resource_path).is_equal("res://shaders/toon_outline.gdshader")
	var col := outline.get_shader_parameter("outline_color") as Color
	assert_bool(col.is_equal_approx(Color(0.1, 0.1, 0.12, 1.0))).is_true()
	var px := float(outline.get_shader_parameter("outline_px"))
	assert_float(px).is_equal_approx(1.5, 0.001)


func test_operations_apron_skirt_faces_point_outward() -> void:
	var apron := _backdrop.get_node("Landmarks/OperationsApron") as MeshInstance3D
	assert_object(apron).is_not_null()
	var mesh := apron.mesh as ArrayMesh
	assert_int(mesh.get_surface_count()).is_equal(2)
	var arrays := mesh.surface_get_arrays(1)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	assert_int(indices.size()).is_equal(24)
	for t in range(0, indices.size(), 3):
		var v0 := verts[indices[t]]
		var v1 := verts[indices[t + 1]]
		var v2 := verts[indices[t + 2]]
		var geom_out := (v2 - v0).cross(v1 - v0)
		assert_float(geom_out.dot(normals[indices[t]])).is_greater(0.0)


func test_taxi_markings_clear_junction_mouths_and_mark_side_stand_open_edges() -> void:
	var lane := {"rect": Rect2(-100.0, -299.0, 200.0, 30.0), "across_x": false}
	var link := {"rect": Rect2(-15.0, -269.0, 30.0, 59.0), "across_x": true}
	var stub := {"rect": Rect2(-85.0, -370.0, 30.0, 71.0), "across_x": true}
	var parallel := {"rect": Rect2(-100.0, -267.0, 200.0, 30.0), "across_x": false}
	var strips: Array[Dictionary] = [lane, link, stub, parallel]
	var overlay := TaxiMarkings.mesh_of(
		strips, [], PackedVector3Array(), PackedVector3Array(), -306.0
	)
	var verts: PackedVector3Array = overlay.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for v in verts:
		# Neither link south mouth nor stub north mouth should have lane edge lines across them.
		if v.x > -14.0 and v.x < 14.0:
			(
				assert_bool(v.z > -270.3 and v.z < -268.8)
				. override_failure_message("lane edge line crossed link mouth at %s" % v)
				. is_false()
			)
		if v.x > -84.0 and v.x < -56.0:
			(
				assert_bool(v.z > -299.2 and v.z < -297.7)
				. override_failure_message("lane edge line crossed stub mouth at %s" % v)
				. is_false()
			)
	# Non-abutting parallel strip 2.0 m south must not strip outer lane lines at x = 60.0.
	var saw_far_south_line := false
	for i in range(0, verts.size(), 4):
		var v0 := verts[i]
		var v1 := verts[i + 1]
		var min_x := minf(v0.x, v1.x)
		var max_x := maxf(v0.x, v1.x)
		if min_x <= 60.0 and max_x >= 60.0 and absf(v0.z - (-269.55)) < 0.25:
			saw_far_south_line = true
			break
	assert_bool(saw_far_south_line).is_true()

	# West & East stands must omit their wall edge and keep open apron edges marked.
	var west_stand := StandPlacement.make(1, -46.0, -140.0, StandPlacement.WEST)
	var east_stand := StandPlacement.make(2, 46.0, -140.0, StandPlacement.EAST)
	var w_pad := TaxiPaving.pad_for(west_stand, PlaneClasses.ORDER)
	var e_pad := TaxiPaving.pad_for(east_stand, PlaneClasses.ORDER)
	var w_pt := StandPlacement.stand_point(west_stand)
	var e_pt := StandPlacement.stand_point(east_stand)
	var w_row := {
		"rect": Rect2(-124.0, w_pt.z - 15.0, w_pad.end.x + 124.0, 30.0),
		"across_x": false,
		"row": true
	}
	var e_row := {
		"rect": Rect2(e_pad.position.x, e_pt.z - 15.0, 124.0 - e_pad.position.x, 30.0),
		"across_x": false,
		"row": true
	}
	var side_mesh := TaxiMarkings.mesh_of(
		[w_row, e_row],
		[w_pad, e_pad],
		PackedVector3Array(),
		PackedVector3Array([w_pt, e_pt]),
		-306.0
	)
	var s_verts: PackedVector3Array = side_mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var w_wall_x := w_pad.end.x - TaxiMarkings.PAD_BORDER_INSET_M
	var e_wall_x := e_pad.position.x + TaxiMarkings.PAD_BORDER_INSET_M
	var w_south_z := w_pad.end.y - TaxiMarkings.PAD_BORDER_INSET_M
	var e_south_z := e_pad.end.y - TaxiMarkings.PAD_BORDER_INSET_M
	var w_open_x := w_pad.position.x + TaxiMarkings.PAD_BORDER_INSET_M
	var e_open_x := e_pad.end.x - TaxiMarkings.PAD_BORDER_INSET_M
	var saw_w_south := false
	var saw_w_open := false
	var saw_e_south := false
	var saw_e_open := false
	for i in range(0, s_verts.size(), 4):
		var v0 := s_verts[i]
		var v2 := s_verts[i + 2]
		var qx := 0.5 * (v0.x + v2.x)
		var qz := 0.5 * (v0.z + v2.z)
		var qw := absf(v2.x - v0.x)
		var qh := absf(v2.z - v0.z)
		if w_pad.has_point(Vector2(qx, qz)):
			if qw < 0.5 and qh > 0.5:
				assert_float(absf(qx - w_wall_x)).is_greater(0.25)
			if absf(qz - w_south_z) < 0.20:
				saw_w_south = true
			if qw < 0.5 and absf(qx - w_open_x) < 0.20:
				saw_w_open = true
		if e_pad.has_point(Vector2(qx, qz)):
			if qw < 0.5 and qh > 0.5:
				assert_float(absf(qx - e_wall_x)).is_greater(0.25)
			if absf(qz - e_south_z) < 0.20:
				saw_e_south = true
			if qw < 0.5 and absf(qx - e_open_x) < 0.20:
				saw_e_open = true
	assert_bool(saw_w_south and saw_w_open).is_true()
	assert_bool(saw_e_south and saw_e_open).is_true()


func test_taxi_paving_site_lift_overlay_tracks_terrain_ramp() -> void:
	var flat := ArrayMesh.new()
	var y := TaxiPaving.HEIGHT_M + TaxiPaving.LINE_LIFT_M
	var verts := PackedVector3Array(
		[
			Vector3(0.0, y, -200.0),
			Vector3(150.0, y, -200.0),
			Vector3(150.0, y, -160.0),
			Vector3(0.0, y, -160.0),
		]
	)
	var normals := PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP])
	var uvs := PackedVector2Array([Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN])
	var idx := PackedInt32Array([0, 1, 2, 0, 2, 3])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	flat.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var lifted := TaxiPavingSite.lift_overlay(flat)
	var out_verts: PackedVector3Array = lifted.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var max_lifted_y := -INF
	var min_lifted_y := INF
	for v in out_verts:
		max_lifted_y = maxf(max_lifted_y, v.y)
		min_lifted_y = minf(min_lifted_y, v.y)
	assert_float(max_lifted_y).is_greater(y + 0.10)
	assert_float(min_lifted_y).is_equal_approx(y, 0.01)


func test_backdrop_rebuild_stability_and_exit_tree_resets_ground_shader() -> void:
	var rwy_count_small := _backdrop._runway_root.get_child_count()
	var taxi_count_0 := _backdrop._taxi_lights_root.get_child_count()
	_flights.runway.size = Runway.LARGE
	assert_str(_backdrop._last_runway_size).is_equal(Runway.LARGE)
	var half_large := float(
		AirfieldBackdrop.GROUND_MATERIAL.get_shader_parameter("runway_half_length")
	)
	assert_float(half_large).is_equal_approx(Runway.length_m(Runway.LARGE) * 0.5, 0.1)
	_flights.runway.size = Runway.SMALL
	assert_int(_backdrop._runway_root.get_child_count()).is_equal(rwy_count_small)
	_backdrop.refresh_taxi_lights()
	assert_int(_backdrop._taxi_lights_root.get_child_count()).is_equal(taxi_count_0)

	var tmp := AirfieldBackdrop.new()
	var tmp_flights := FlightSim.new()
	tmp_flights.runway.size = Runway.LARGE
	tmp.flights = tmp_flights
	add_child(tmp_flights)
	add_child(tmp)
	(
		assert_float(
			float(AirfieldBackdrop.GROUND_MATERIAL.get_shader_parameter("runway_half_length"))
		)
		. is_equal_approx(Runway.length_m(Runway.LARGE) * 0.5, 0.1)
	)
	remove_child(tmp)
	tmp.free()
	tmp_flights.free()
	(
		assert_float(
			float(AirfieldBackdrop.GROUND_MATERIAL.get_shader_parameter("runway_half_length"))
		)
		. is_equal_approx(Runway.length_m(Runway.SMALL) * 0.5, 0.1)
	)


static func _scene_local_aabb(root_node: Node3D) -> AABB:
	var out := AABB()
	var has := false
	var stack: Array = [[root_node, Transform3D.IDENTITY]]
	while not stack.is_empty():
		var item: Array = stack.pop_back()
		var node: Node = item[0]
		var xf: Transform3D = item[1]
		if node is MeshInstance3D:
			var mi := node as MeshInstance3D
			if mi.mesh != null:
				var transformed := xf * mi.mesh.get_aabb()
				if not has:
					out = transformed
					has = true
				else:
					out = out.merge(transformed)
		for child in node.get_children():
			var cxf := xf * (child as Node3D).transform if child is Node3D else xf
			stack.append([child, cxf])
	return out
