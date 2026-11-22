class_name TestToonOutlinesAndMaterials
extends GdUnitTestSuite
## Regression tests for unified dark ink outline color/width across all 15
## material .tres files, shader compilation/uniform parity, and welded CUSTOM0
## smooth normals on static imports and RoofView (omitted on skinned rigs).

const MATERIALS_DIR := "res://assets/materials"
const OUTER_TOON_MATERIALS := [
	"res://assets/birds/tfp_atlas_toon.tres",
	"res://assets/airside/props/works/ti_road_1a_toon.tres",
	"res://assets/airside/props/works/ti_excavator_1a_toon.tres",
]
const STATIC_GLBS := [
	"res://assets/interior/wall.glb",
	"res://assets/interior/checkin_desk.glb",
	"res://assets/airside/props/works/ti_excavator_1a.glb",
	"res://assets/buildings/tp_airport_shell.glb",
]
const UNIFIED_INK := Color(0.1, 0.1, 0.12, 1.0)
const UNIFIED_PX := 1.5
const TOON_SHADER_PATH := "res://shaders/toon.gdshader"
const OUTLINE_SHADER_PATH := "res://shaders/toon_outline.gdshader"
const OUTLINE_DISSOLVE_PATH := "res://shaders/toon_outline_dissolve.gdshader"
const TOON_IMPORTER := preload("res://assets/toon_post_import.gd")

var _outline_shader: Shader
var _outline_dissolve_shader: Shader
var _materials := {}


func before() -> void:
	_outline_shader = load(OUTLINE_SHADER_PATH) as Shader
	_outline_dissolve_shader = load(OUTLINE_DISSOLVE_PATH) as Shader
	var dir := DirAccess.open(MATERIALS_DIR)
	if dir != null:
		dir.list_dir_begin()
		while true:
			var fname := dir.get_next()
			if fname.is_empty():
				break
			if not dir.current_is_dir() and fname.ends_with(".tres"):
				var path := MATERIALS_DIR.path_join(fname)
				_materials[path] = load(path)
		dir.list_dir_end()
	for path: String in OUTER_TOON_MATERIALS:
		_materials[path] = load(path)


func test_outline_shaders_load_and_preserve_uniform_contract() -> void:
	assert_object(_outline_shader).is_not_null()
	assert_object(_outline_dissolve_shader).is_not_null()

	var base_names: Array[String] = []
	for u in _outline_shader.get_shader_uniform_list():
		base_names.append(u["name"])
	var shared_keys := [
		"outline_color",
		"outline_px",
		"fade_start",
		"fade_end",
		"min_px",
		"depth_bias_m",
	]
	for key: String in shared_keys:
		var msg := "toon_outline missing uniform %s" % key
		assert_bool(base_names.has(key)).override_failure_message(msg).is_true()

	var dissolve_names: Array[String] = []
	for u in _outline_dissolve_shader.get_shader_uniform_list():
		dissolve_names.append(u["name"])
	for key: String in shared_keys + ["dissolve"]:
		var msg := "toon_outline_dissolve missing uniform %s" % key
		assert_bool(dissolve_names.has(key)).override_failure_message(msg).is_true()


func test_outline_shader_default_ink_and_width_match_unified_palette() -> void:
	var inc := load("res://shaders/toon_outline_common.gdshaderinc") as ShaderInclude
	assert_object(inc).is_not_null()
	assert_bool(inc.code.contains("vec4(0.1, 0.1, 0.12, 1.0)")).is_true()
	assert_bool(inc.code.contains("outline_px = 1.5")).is_true()
	assert_bool(inc.code.contains("fade_start = 60.0")).is_true()
	assert_bool(inc.code.contains("fade_end = 240.0")).is_true()
	assert_bool(inc.code.contains("CUSTOM0.a > 0.5")).is_true()
	var rid := _outline_shader.get_rid()
	var def_color: Variant = RenderingServer.shader_get_parameter_default(rid, "outline_color")
	if def_color != null:
		var got_color := (
			def_color as Color
			if def_color is Color
			else Color(def_color.x, def_color.y, def_color.z, def_color.w)
		)
		var msg := "got=%s expected=%s" % [got_color, UNIFIED_INK]
		assert_bool(got_color.is_equal_approx(UNIFIED_INK)).override_failure_message(msg).is_true()
	var def_px: Variant = RenderingServer.shader_get_parameter_default(rid, "outline_px")
	if def_px != null:
		assert_float(float(def_px)).is_equal_approx(UNIFIED_PX, 0.001)


func test_all_15_materials_share_unified_opaque_ink_and_width() -> void:
	assert_int(_materials.size()).is_equal(15)
	var opaque_toon_count := 0
	for path: String in _materials:
		var mat: Resource = _materials[path]
		assert_object(mat).override_failure_message("%s failed to load" % path).is_not_null()
		if mat is ShaderMaterial:
			var sm := mat as ShaderMaterial
			assert_object(sm.shader).is_not_null()
			assert_str(sm.shader.resource_path).is_equal(TOON_SHADER_PATH)
			var outline := sm.next_pass as ShaderMaterial
			var miss_msg := "%s missing outline next_pass" % path
			assert_object(outline).override_failure_message(miss_msg).is_not_null()
			assert_str(outline.shader.resource_path).is_equal(OUTLINE_SHADER_PATH)
			var col: Variant = outline.get_shader_parameter("outline_color")
			var px: Variant = outline.get_shader_parameter("outline_px")
			var col_type_msg := "%s missing outline_color" % path
			assert_bool(col is Color).override_failure_message(col_type_msg).is_true()
			var col_msg := "%s outline_color=%s expected=%s" % [path, col, UNIFIED_INK]
			var is_ink := (col as Color).is_equal_approx(UNIFIED_INK)
			assert_bool(is_ink).override_failure_message(col_msg).is_true()
			var px_msg := "%s outline_px=%s expected=%.2f" % [path, px, UNIFIED_PX]
			assert_float(float(px)).override_failure_message(px_msg).is_equal_approx(
				UNIFIED_PX, 0.001
			)
			opaque_toon_count += 1
	assert_int(opaque_toon_count).is_equal(13)


func test_glass_and_lights_stay_non_toon_standard_materials() -> void:
	var glass := _materials.get("res://assets/materials/tp_glass.tres") as StandardMaterial3D
	var lights := _materials.get("res://assets/materials/tp_lights.tres") as StandardMaterial3D
	assert_object(glass).is_not_null()
	assert_object(lights).is_not_null()
	assert_int(glass.transparency).is_equal(BaseMaterial3D.TRANSPARENCY_ALPHA)
	assert_int(lights.shading_mode).is_equal(BaseMaterial3D.SHADING_MODE_UNSHADED)


func test_roof_view_dissolve_copy_and_mesh_carry_custom0_normals() -> void:
	var grid := BuildGrid.new(Vector2i(8, 8))
	var edits: Array[BuildEdit] = []
	for y in range(2, 5):
		for x in range(2, 6):
			edits.append(BuildEdit.paint_floor(Vector2i(x, y), BuildGrid.FLOOR_TILE, 1))
	grid.apply_batch(edits)
	EnclosureKit.close_floor(grid)
	var roof: RoofView = auto_free(RoofView.new())
	add_child(roof)
	roof.bind(grid)
	var surf := roof.surface_material()
	assert_object(surf).is_not_null()
	var outline := surf.next_pass as ShaderMaterial
	assert_object(outline).is_not_null()
	assert_str(outline.shader.resource_path).is_equal(OUTLINE_DISSOLVE_PATH)
	var col: Variant = outline.get_shader_parameter("outline_color")
	var px: Variant = outline.get_shader_parameter("outline_px")
	assert_bool((col as Color).is_equal_approx(UNIFIED_INK)).is_true()
	assert_float(float(px)).is_equal_approx(UNIFIED_PX, 0.001)
	var mesh := roof.roof_node().mesh
	assert_object(mesh).is_not_null()
	_assert_surface_has_valid_custom0(mesh, 0, "roof_view")


func test_imported_static_meshes_carry_welded_custom0_smooth_normals() -> void:
	for glb_path: String in STATIC_GLBS:
		var packed := load(glb_path) as PackedScene
		assert_object(packed).override_failure_message("%s failed to load" % glb_path).is_not_null()
		var inst := packed.instantiate()
		var checked := 0
		for mi in inst.find_children("*", "MeshInstance3D", true, false):
			var mesh := (mi as MeshInstance3D).mesh
			if mesh == null:
				continue
			for s in mesh.get_surface_count():
				_assert_surface_has_valid_custom0(mesh, s, "%s:%s" % [glb_path, mi.name])
				checked += 1
		assert_int(checked).is_greater(0)
		if glb_path.ends_with("wall.glb"):
			var wall_nodes := inst.find_children("*", "MeshInstance3D", true, false)
			var wall_mi := wall_nodes[0] as MeshInstance3D
			var arrays := wall_mi.mesh.surface_get_arrays(0)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var custom: PackedByteArray = arrays[Mesh.ARRAY_CUSTOM0]
			var norms_by_pos := {}
			for vi in verts.size():
				var v := verts[vi]
				var key := Vector3i(
					roundi(v.x * 10000.0), roundi(v.y * 10000.0), roundi(v.z * 10000.0)
				)
				var off := vi * 4
				var c := Vector3i(custom[off], custom[off + 1], custom[off + 2])
				if norms_by_pos.has(key):
					assert_vector(Vector3(c)).is_equal(Vector3(norms_by_pos[key] as Vector3i))
				else:
					norms_by_pos[key] = c
		inst.free()


func test_skinned_characters_and_birds_preserve_color0_and_omit_custom0() -> void:
	for path: String in [
		"res://assets/people/tcp_male_character_01.glb",
		"res://assets/birds/tfp_crow_01.glb",
	]:
		var packed := load(path) as PackedScene
		assert_object(packed).is_not_null()
		var inst := packed.instantiate()
		var meshes := inst.find_children("*", "MeshInstance3D", true, false)
		assert_int(meshes.size()).is_greater(0)
		for node in meshes:
			var mi := node as MeshInstance3D
			if mi.mesh == null:
				continue
			for s in mi.mesh.get_surface_count():
				var fmt: int = mi.mesh.surface_get_format(s)
				var custom_bits := fmt & Mesh.ARRAY_FORMAT_CUSTOM0
				var msg := "%s:%s surface %d must not bake CUSTOM0" % [path, mi.name, s]
				assert_int(custom_bits).override_failure_message(msg).is_equal(0)
				if path.contains("tcp_male_character"):
					assert_int(fmt & Mesh.ARRAY_FORMAT_COLOR).is_not_zero()
		inst.free()


func test_outline_material_binds_cleanly_with_and_without_custom0() -> void:
	var base := _materials.get("res://assets/materials/tp_atlas_toon.tres") as ShaderMaterial
	assert_object(base).is_not_null()
	var box_mi: MeshInstance3D = auto_free(MeshInstance3D.new())
	box_mi.mesh = BoxMesh.new()
	box_mi.set_surface_override_material(0, base)
	add_child(box_mi)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_custom_format(0, SurfaceTool.CUSTOM_RGBA8_UNORM)
	st.set_normal(Vector3.UP)
	st.set_custom(0, Color(0.5, 1.0, 0.5, 0.6))
	st.add_vertex(Vector3(0.0, 0.0, 0.0))
	st.add_vertex(Vector3(1.0, 0.0, 0.0))
	st.add_vertex(Vector3(0.0, 0.0, 1.0))
	var custom_mi: MeshInstance3D = auto_free(MeshInstance3D.new())
	custom_mi.mesh = st.commit()
	custom_mi.set_surface_override_material(0, base)
	add_child(custom_mi)
	assert_int(custom_mi.mesh.surface_get_format(0) & Mesh.ARRAY_FORMAT_CUSTOM0).is_not_zero()


func test_bush_and_static_imports_keep_toon_material_and_shadow_mesh_compress_parity() -> void:
	var bush_packed := load("res://assets/decor/tc_bush_1a.glb") as PackedScene
	assert_object(bush_packed).is_not_null()
	var bush := bush_packed.instantiate()
	var bush_mi := bush.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var bush_mesh := bush_mi.mesh as ArrayMesh
	assert_object(bush_mesh).is_not_null()
	var bush_mat := bush_mesh.surface_get_material(0) as ShaderMaterial
	assert_object(bush_mat).is_not_null()
	assert_str(bush_mat.resource_path).is_equal("res://assets/materials/tc_tree_1a_toon.tres")
	assert_object(bush_mat.next_pass).is_not_null()
	_assert_surface_has_valid_custom0(bush_mesh, 0, "tc_bush_1a")
	_assert_shadow_mesh_compress_parity(bush_mesh, "tc_bush_1a")
	bush.free()

	for glb_path: String in [
		"res://assets/decor/tc_bench_2a_indoor.glb",
		"res://assets/decor/tc_tree_3a_indoor.glb",
		"res://assets/airside/props/works/ti_excavator_1a.glb",
		"res://assets/airside/props/works/ti_traffic_cone_1b.glb",
		"res://assets/buildings/tp_airport_shell.glb",
		"res://assets/vehicles/tp_van_01a.glb",
	]:
		var packed := load(glb_path) as PackedScene
		assert_object(packed).is_not_null()
		var inst := packed.instantiate()
		for node in inst.find_children("*", "MeshInstance3D", true, false):
			var mesh := (node as MeshInstance3D).mesh as ArrayMesh
			if mesh != null:
				_assert_shadow_mesh_compress_parity(mesh, "%s:%s" % [glb_path, node.name])
		inst.free()


func _assert_shadow_mesh_compress_parity(mesh: ArrayMesh, tag: String) -> void:
	var sm := mesh.shadow_mesh
	if sm == null:
		return
	assert_int(sm.get_surface_count()).is_equal(mesh.get_surface_count())
	for s in mesh.get_surface_count():
		var m_comp := mesh.surface_get_format(s) & Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES
		var s_comp := sm.surface_get_format(s) & Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES
		var msg := "%s[%d] shadow_mesh COMPRESS flag mismatch (%d vs %d)" % [tag, s, m_comp, s_comp]
		assert_int(m_comp).override_failure_message(msg).is_equal(s_comp)


func test_static_imports_and_baker_preserve_generated_lods() -> void:
	for glb_path: String in STATIC_GLBS + ["res://assets/decor/tc_tree_3a_indoor.glb"]:
		var packed := load(glb_path) as PackedScene
		assert_object(packed).is_not_null()
		var inst := packed.instantiate()
		var total_lods := 0
		for node in inst.find_children("*", "MeshInstance3D", true, false):
			var mesh := (node as MeshInstance3D).mesh as ArrayMesh
			if mesh == null:
				continue
			for s in mesh.get_surface_count():
				var rs_surf: Dictionary = RenderingServer.mesh_get_surface(mesh.get_rid(), s)
				var lods: Array = rs_surf.get("lods", [])
				total_lods += lods.size()
		var msg := "%s lost all generated LODs after CUSTOM0 bake" % glb_path
		assert_int(total_lods).override_failure_message(msg).is_greater(0)
		inst.free()

	var verts := PackedVector3Array(
		[
			Vector3(0.0, 0.0, 0.0),
			Vector3(1.0, 0.0, 0.0),
			Vector3(0.0, 1.0, 0.0),
			Vector3(1.0, 1.0, 0.0),
		]
	)
	var norms := PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK, Vector3.BACK])
	var idx := PackedInt32Array([0, 1, 2, 1, 3, 2])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_INDEX] = idx
	var synth := ArrayMesh.new()
	var comp_flag := Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES
	synth.add_surface_from_arrays(
		Mesh.PRIMITIVE_TRIANGLES, arrays, [], {0.5: PackedInt32Array([0, 1, 2])}, comp_flag
	)
	var synth_sm := ArrayMesh.new()
	var sm_arrays: Array = []
	sm_arrays.resize(Mesh.ARRAY_MAX)
	sm_arrays[Mesh.ARRAY_VERTEX] = verts
	sm_arrays[Mesh.ARRAY_INDEX] = idx
	synth_sm.add_surface_from_arrays(
		Mesh.PRIMITIVE_TRIANGLES, sm_arrays, [], {0.5: PackedInt32Array([0, 1, 2])}, comp_flag
	)
	synth.shadow_mesh = synth_sm
	var baked: int = TOON_IMPORTER.bake_array_mesh_outline_normals(synth)
	assert_int(baked).is_equal(1)
	_assert_surface_has_valid_custom0(synth, 0, "synthetic_lod")
	_assert_shadow_mesh_compress_parity(synth, "synthetic_lod")
	var rs_after: Dictionary = RenderingServer.mesh_get_surface(synth.get_rid(), 0)
	var lods_after: Array = rs_after.get("lods", [])
	assert_int(lods_after.size()).is_equal(1)
	assert_object(synth.shadow_mesh).is_not_null()
	assert_int(synth.shadow_mesh.get_instance_id()).is_not_equal(synth_sm.get_instance_id())


func _assert_surface_has_valid_custom0(mesh: Mesh, surface: int, tag: String) -> void:
	var fmt: int = mesh.surface_get_format(surface)
	var fmt_msg := "%s surface %d missing ARRAY_FORMAT_CUSTOM0" % [tag, surface]
	assert_int(fmt & Mesh.ARRAY_FORMAT_CUSTOM0).override_failure_message(fmt_msg).is_not_zero()
	var arrays := mesh.surface_get_arrays(surface)
	var custom: PackedByteArray = arrays[Mesh.ARRAY_CUSTOM0]
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	assert_int(custom.size()).is_equal(verts.size() * 4)
	for vi in verts.size():
		var off := vi * 4
		var a := float(custom[off + 3]) / 255.0
		var a_msg := "%s v%d sentinel %.3f <= 0.5" % [tag, vi, a]
		assert_float(a).override_failure_message(a_msg).is_greater(0.5)
		var nx := (float(custom[off]) / 255.0) * 2.0 - 1.0
		var ny := (float(custom[off + 1]) / 255.0) * 2.0 - 1.0
		var nz := (float(custom[off + 2]) / 255.0) * 2.0 - 1.0
		var len_sq := nx * nx + ny * ny + nz * nz
		assert_float(len_sq).is_between(0.75, 1.25)
