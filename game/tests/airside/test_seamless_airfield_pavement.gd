class_name TestSeamlessAirfieldPavement
extends GdUnitTestSuite
## Regression tests for seamless runway, taxiway, stand-apron, and operations
## apron surfaces, outline-free flat paving materials, end-only runway markings
## and wear, inset hold bars, and clean junction/pad shoulder line clipping.

var _clock: SimClock
var _airside: Airside
var _flights: FlightSim
var _backdrop: AirfieldBackdrop


func before() -> void:
	_clock = SimClock.new()
	_clock.paused = true
	_airside = TestStandLaneClearance.scene_airside()
	_flights = FlightSim.new()
	_flights.clock = _clock
	_flights.runway.size = Runway.SMALL
	_backdrop = AirfieldBackdrop.new()
	_backdrop.airside = _airside
	_backdrop.flights = _flights
	_backdrop.clock = _clock
	add_child(_clock)
	add_child(_flights)
	add_child(_airside)
	add_child(_backdrop)


func after() -> void:
	_backdrop.free()
	_airside.free()
	_flights.free()
	_clock.free()


func test_taxi_paving_shader_and_material_are_seamless_and_outline_free() -> void:
	var shader := load("res://shaders/taxi_paving_toon.gdshader") as Shader
	assert_object(shader).is_not_null()
	assert_bool(shader.code.contains("bay_id")).is_false()
	assert_bool(shader.code.contains("seam_x")).is_false()
	assert_bool(shader.code.contains("seam_z")).is_false()
	assert_bool(shader.code.contains("world_pos.xz / 8.0")).is_false()
	assert_bool(shader.code.contains("value_noise")).is_true()
	assert_bool(shader.code.contains("is_concrete")).is_true()

	var names: Array[String] = []
	for u in shader.get_shader_uniform_list():
		names.append(u["name"])
	for key: String in ["albedo_texture", "albedo_tint", "ramp_texture", "light_gain"]:
		assert_bool(names.has(key)).is_true()

	var mat := TaxiPaving.MATERIAL as ShaderMaterial
	assert_object(mat).is_not_null()
	assert_object(mat.next_pass).is_null()


func test_runway_is_continuous_mesh_with_end_only_markings_and_wear() -> void:
	for size: String in PlaneClasses.ORDER:
		var built := auto_free(Runway.build(size)) as MeshInstance3D
		assert_object(built).is_not_null()
		var mesh := built.mesh as ArrayMesh
		assert_object(mesh).is_not_null()
		assert_int(mesh.get_surface_count()).is_equal(2)
		assert_object(mesh.surface_get_material(0)).is_same(TaxiPaving.MATERIAL)
		assert_object(mesh.surface_get_material(1)).is_same(TaxiPaving.MATERIAL)
		var top_verts := mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array
		assert_int(top_verts.size()).is_equal(4)
		var half := Runway.length_m(size) * 0.5
		var aabb := mesh.get_aabb()
		assert_float(aabb.position.x).is_equal_approx(-half, 0.01)
		assert_float(aabb.end.x).is_equal_approx(half, 0.01)
		assert_float(aabb.position.z).is_equal_approx(-Runway.WIDTH_M * 0.5, 0.01)
		assert_float(aabb.end.z).is_equal_approx(Runway.WIDTH_M * 0.5, 0.01)
		assert_float(aabb.position.y).is_equal_approx(Runway.SKIRT_Y, 0.001)
		assert_float(aabb.end.y).is_equal_approx(Runway.TOP_Y, 0.001)

		_flights.runway.size = size
		var wear := _backdrop.get_node("RunwayDressing/RunwayWear") as MeshInstance3D
		var wear_verts := wear.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array
		assert_int(wear_verts.size()).is_equal(8)
		for v in wear_verts:
			assert_float(absf(v.x)).is_greater(half - 130.0)
			assert_float(absf(v.x - (-40.0))).is_greater(20.0)

		var markings := _backdrop.get_node("RunwayDressing/RunwayMarkings") as MeshInstance3D
		var mark_verts := (
			markings.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array
		)
		var rz := StandPlacement.RUNWAY_Z
		var saw_mid_dash := false
		for i in range(0, mark_verts.size(), 4):
			var v0 := mark_verts[i]
			var v2 := mark_verts[i + 2]
			var cx := 0.5 * (v0.x + v2.x)
			var qh := absf(v2.z - v0.z)
			if absf(cx) < half - 130.0:
				# Mid-runway only has centerline dashes (1.1 m) and side edge stripes (0.9 m).
				assert_float(qh).is_less(1.5)
				if absf(0.5 * (v0.z + v2.z) - rz) < 0.2:
					saw_mid_dash = true
		assert_bool(saw_mid_dash).is_true()


func test_hold_bars_are_inset_clear_of_lane_shoulders_and_junctions_clip_lines() -> void:
	var lane := {"rect": Rect2(-139.0, -299.0, 278.0, 30.0), "across_x": false}
	var spur := {"rect": Rect2(-139.0, -338.0, 30.0, 208.0), "across_x": true, "through": true}
	var near_link := {"rect": Rect2(-120.0, -269.0, 30.0, 120.0), "across_x": true}
	var pad := Rect2(-120.0, -149.0, 30.0, 51.0)
	var strip_list: Array[Dictionary] = [lane, spur, near_link]

	var close_hold := PackedVector3Array([Vector3(-105.0, 0.0, -268.5)])
	var bars := TaxiPaving.hold_bars(close_hold, TaxiPaving.HOLD_BAR_WIDTH_M, -306.0, strip_list)
	assert_int(bars.size()).is_equal(2)
	for bar in bars:
		assert_float(bar.size.x).is_equal_approx(TaxiPaving.HOLD_BAR_WIDTH_M, 0.001)
		assert_float(bar.position.y).is_greater_equal(
			lane["rect"].end.y + TaxiPaving.HOLD_LANE_CLEAR_M - 0.001
		)

	var overlay := TaxiMarkings.mesh_of(
		strip_list, [pad], PackedVector3Array(), PackedVector3Array(), -306.0
	)
	var arrays := overlay.surface_get_arrays(0)
	var verts := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var uvs := arrays[Mesh.ARRAY_TEX_UV] as PackedVector2Array
	for i in range(0, verts.size(), 4):
		if not uvs[i].is_equal_approx(TaxiPaving.MARKING_UV):
			continue
		var v0 := verts[i]
		var v2 := verts[i + 2]
		var qx := 0.5 * (v0.x + v2.x)
		var qz := 0.5 * (v0.z + v2.z)
		var inside_near_pad := pad.grow(-0.2).has_point(Vector2(qx, qz))
		if inside_near_pad and v0.z > pad.position.y + 0.5 and v2.z < pad.end.y - 0.5:
			# Link side shoulder lines must not bleed inside the abutting stand pad mouth.
			(
				assert_bool(
					qx > near_link["rect"].position.x + 0.4 and qx < near_link["rect"].end.x - 0.4
				)
				. is_false()
			)
		if qz > -299.0 and qz < -269.0 and qx > -119.5 and qx < -109.5:
			# Spur east outer shoulder lines must stop cleanly outside the lane/near_link overlap.
			assert_bool(absf(qx - (-110.05)) < 0.2 or absf(qx - (-109.55)) < 0.2).is_false()
	for bar in _airside.paving.bars:
		assert_float(minf(bar.size.x, bar.size.y)).is_equal_approx(TaxiPaving.HOLD_LINE_M, 0.001)
		assert_float(maxf(bar.size.x, bar.size.y)).is_equal_approx(
			TaxiPaving.HOLD_BAR_WIDTH_M, 0.001
		)


func test_operations_apron_is_single_seamless_slab_without_checkerboard() -> void:
	var apron := _backdrop.get_node("Landmarks/OperationsApron") as MeshInstance3D
	assert_object(apron).is_not_null()
	var mesh := apron.mesh as ArrayMesh
	assert_int(mesh.get_surface_count()).is_equal(2)
	var top_verts := mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var top_uvs := mesh.surface_get_arrays(0)[Mesh.ARRAY_TEX_UV] as PackedVector2Array
	assert_int(top_verts.size()).is_equal(4)
	for uv in top_uvs:
		assert_vector(uv).is_equal_approx(AirfieldBackdrop.CONCRETE_UV, Vector2(0.0001, 0.0001))
	assert_object(mesh.surface_get_material(0).next_pass).is_null()
