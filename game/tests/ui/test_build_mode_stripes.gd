class_name TestBuildModeStripes
extends GdUnitTestSuite
## Regression tests for build_mode_stripes.gdshader loading, uniform contract,
## and analytic fwidth/smoothstep anti-aliasing setup.

const SHADER_PATH := "res://ui/build_mode_stripes.gdshader"

var _shader: Shader


func before() -> void:
	_shader = load(SHADER_PATH) as Shader


func test_stripes_shader_loads_with_expected_uniforms() -> void:
	assert_object(_shader).is_not_null()
	var names: Array[String] = []
	for u in _shader.get_shader_uniform_list():
		names.append(u["name"])
	for key: String in ["period", "origin", "yellow", "dark", "band_size"]:
		var msg := "build_mode_stripes missing uniform %s" % key
		assert_bool(names.has(key)).override_failure_message(msg).is_true()


func test_stripes_shader_uses_analytic_anti_aliasing_and_preserves_modulate() -> void:
	var code := _shader.get_code()
	assert_bool(code.contains("smoothstep")).is_true()
	assert_bool(code.contains("dFdx") and code.contains("dFdy")).is_true()
	assert_bool(code.contains("COLOR *=")).is_true()


func test_build_mode_frame_bands_remain_disjoint_at_all_four_corners() -> void:
	var port: SubViewport = auto_free(SubViewport.new())
	port.size = Vector2i(1280, 720)
	add_child(port)
	var frame := BuildModeFrame.new()
	port.add_child(frame)
	frame.set_building(true)
	var rects: Array[Rect2] = []
	for i in 4:
		var band := frame.band(i)
		rects.append(Rect2(band.position, band.size))
		var mat := band.material as ShaderMaterial
		assert_object(mat).is_not_null()
		assert_str(mat.shader.resource_path).is_equal(SHADER_PATH)
	for i in 4:
		for j in range(i + 1, 4):
			var msg := "band %d %s overlaps band %d %s" % [i, rects[i], j, rects[j]]
			assert_bool(rects[i].intersects(rects[j])).override_failure_message(msg).is_false()


func test_build_mode_frame_four_corner_seams_match_stripe_phase_exactly() -> void:
	var port: SubViewport = auto_free(SubViewport.new())
	port.size = Vector2i(1280, 720)
	add_child(port)
	var frame := BuildModeFrame.new()
	port.add_child(frame)
	frame.set_building(true)
	var w := 1280.0
	var h := 720.0
	var t := BuildModeFrame.THICKNESS
	var mats: Array[ShaderMaterial] = []
	for i in 4:
		mats.append(frame.band(i).material as ShaderMaterial)
	# Each corner seam shares two endpoints (outer edge & inner miter point)
	# between a horizontal band (0=Top, 1=Bottom) and vertical band (2=Left, 3=Right).
	var corner_seams := [
		[0, Vector2(0.0, 1.0), 2, Vector2(0.0, 0.0), Vector2(0.0, t)],
		[0, Vector2(t / w, 1.0), 2, Vector2(1.0, 0.0), Vector2(t, t)],
		[0, Vector2((w - t) / w, 1.0), 3, Vector2(0.0, 0.0), Vector2(w - t, t)],
		[0, Vector2(1.0, 1.0), 3, Vector2(1.0, 0.0), Vector2(w, t)],
		[1, Vector2(0.0, 0.0), 2, Vector2(0.0, 1.0), Vector2(0.0, h - t)],
		[1, Vector2(t / w, 0.0), 2, Vector2(1.0, 1.0), Vector2(t, h - t)],
		[1, Vector2((w - t) / w, 0.0), 3, Vector2(0.0, 1.0), Vector2(w - t, h - t)],
		[1, Vector2(1.0, 0.0), 3, Vector2(1.0, 1.0), Vector2(w, h - t)],
	]
	for seam: Array in corner_seams:
		var h_idx: int = seam[0]
		var h_uv: Vector2 = seam[1]
		var v_idx: int = seam[2]
		var v_uv: Vector2 = seam[3]
		var expected: Vector2 = seam[4]
		var h_at := _band_at(mats[h_idx], h_uv)
		var v_at := _band_at(mats[v_idx], v_uv)
		assert_vector(h_at).is_equal_approx(expected, Vector2(1e-4, 1e-4))
		assert_vector(v_at).is_equal_approx(expected, Vector2(1e-4, 1e-4))
		var h_phase := (h_at.x + h_at.y) / float(mats[h_idx].get_shader_parameter("period"))
		var v_phase := (v_at.x + v_at.y) / float(mats[v_idx].get_shader_parameter("period"))
		assert_float(h_phase).is_equal_approx(v_phase, 1e-5)


func _band_at(mat: ShaderMaterial, uv: Vector2) -> Vector2:
	var origin: Vector2 = mat.get_shader_parameter("origin")
	var band_size: Vector2 = mat.get_shader_parameter("band_size")
	return origin + uv * band_size
