class_name TestPlaneTintedGlass
extends GdUnitTestSuite
## Regression test for ruling c46a5df8: PlaneView overrides TP_Glass_1A_D
## surfaces on plane instances with dark-tinted tp_plane_glass_tinted.tres
## while leaving non-glass surfaces, shared mesh resources, terminal glass walls,
## and shared tp_glass.tres unmodified.

const TINTED_PATH := "res://assets/materials/tp_plane_glass_tinted.tres"
const SHARED_GLASS_PATH := "res://assets/materials/tp_glass.tres"
const ATLAS_PATH := "res://assets/materials/tp_atlas_toon.tres"
const TOON_SHADER_PATH := "res://shaders/toon.gdshader"
const OUTLINE_SHADER_PATH := "res://shaders/toon_outline.gdshader"


func test_tinted_material_is_opaque_dark_toon_and_shared_glass_stays_transparent() -> void:
	var tinted := load(TINTED_PATH) as ShaderMaterial
	assert_object(tinted).is_not_null()
	assert_object(tinted.shader).is_not_null()
	assert_str(tinted.shader.resource_path).is_equal(TOON_SHADER_PATH)
	var outline := tinted.next_pass as ShaderMaterial
	assert_object(outline).is_not_null()
	assert_str(outline.shader.resource_path).is_equal(OUTLINE_SHADER_PATH)
	var tint: Variant = tinted.get_shader_parameter("albedo_tint")
	assert_bool(tint is Color).is_true()
	var c := tint as Color
	assert_float(maxf(c.r, maxf(c.g, c.b))).is_less(0.6)
	assert_float(c.a).is_equal_approx(1.0, 0.001)

	var shared := load(SHARED_GLASS_PATH) as StandardMaterial3D
	assert_object(shared).is_not_null()
	assert_int(shared.transparency).is_equal(BaseMaterial3D.TRANSPARENCY_ALPHA)
	assert_float(shared.albedo_color.a).is_less(0.5)


func test_plane_view_overrides_only_glass_surfaces_across_all_five_planes() -> void:
	var tinted := load(TINTED_PATH) as Material
	var view := PlaneView.new()
	add_child(view)
	view.set_process(false)
	for model: String in PlaneModels.PLANES:
		view.show_model(model)
		var inst := view.get_node("Pivot").get_child(0) as Node3D
		assert_object(inst).is_not_null()
		var glass_hits := 0
		var body_hits := 0
		for child in inst.find_children("*", "MeshInstance3D", true, false):
			var mi := child as MeshInstance3D
			if mi.mesh == null:
				continue
			for s in mi.mesh.get_surface_count():
				var base_mat := mi.mesh.surface_get_material(s)
				var active_mat := mi.get_active_material(s)
				assert_object(base_mat).is_not_null()
				if base_mat.resource_path == SHARED_GLASS_PATH:
					glass_hits += 1
					assert_object(mi.get_surface_override_material(s)).is_same(tinted)
					assert_object(active_mat).is_same(tinted)
				else:
					body_hits += 1
					assert_object(mi.get_surface_override_material(s)).is_null()
					assert_str(active_mat.resource_path).is_equal(ATLAS_PATH)
		assert_int(glass_hits).override_failure_message("%s glass_hits" % model).is_greater(0)
		assert_int(body_hits).override_failure_message("%s body_hits" % model).is_greater(0)
	view.free()


func test_non_plane_glass_assets_keep_transparent_tp_glass() -> void:
	for path: String in [
		"res://assets/interior/wall_glass.glb",
		"res://assets/interior/wall_door.glb",
		"res://assets/airside/props/jet_bridge.glb",
		"res://assets/vehicles/tp_van_01a.glb",
	]:
		var packed := load(path) as PackedScene
		assert_object(packed).is_not_null()
		var inst := packed.instantiate()
		var glass_hits := 0
		for child in inst.find_children("*", "MeshInstance3D", true, false):
			var mi := child as MeshInstance3D
			if mi.mesh == null:
				continue
			for s in mi.mesh.get_surface_count():
				var mat := mi.get_active_material(s)
				if mat != null and mat.resource_path == SHARED_GLASS_PATH:
					glass_hits += 1
		inst.free()
		assert_int(glass_hits).override_failure_message("%s glass" % path).is_greater(0)
