class_name TestSecurityOverhaulAssets
extends GdUnitTestSuite
## Regression tests for Security Overhaul S1 Blender assets:
## secondary bag-search table, clear-sided glass confiscation bin,
## 8 contraband gag props, confiscation_glass.tres isolation, and
## 12-slot staggered interior bin containment with exact mount positions/yaws.

const TABLE_GLB := "res://assets/interior/security_search_table.glb"
const BIN_GLB := "res://assets/interior/security_confiscation_bin.glb"
const CONTRABAND_DIR := "res://assets/interior/contraband"
const GAG_PROPS: Array[String] = [
	"gag_snow_globe",
	"gag_syrup_jug",
	"gag_garden_gnome",
	"gag_bowling_ball",
	"gag_flamingo",
	"gag_rubber_duck",
	"gag_giant_wrench",
	"gag_mystery_thermos",
]
const TOON_ATLAS := "res://assets/materials/tp_atlas_toon.tres"
const GLASS_MAT := "res://assets/interior/security_materials/confiscation_glass.tres"
const EXPECTED_INSPECT_POS := Vector3(0.0, 0.830, 0.0)
const EXPECTED_BIN_SLOTS: Array[Dictionary] = [
	{"pos": Vector3(-0.140, 0.110, -0.140), "yaw_deg": 18.0},
	{"pos": Vector3(0.140, 0.110, -0.140), "yaw_deg": -32.0},
	{"pos": Vector3(-0.140, 0.110, 0.140), "yaw_deg": 145.0},
	{"pos": Vector3(0.140, 0.110, 0.140), "yaw_deg": -115.0},
	{"pos": Vector3(-0.115, 0.345, -0.145), "yaw_deg": 65.0},
	{"pos": Vector3(0.145, 0.345, -0.115), "yaw_deg": -78.0},
	{"pos": Vector3(-0.145, 0.345, 0.115), "yaw_deg": -15.0},
	{"pos": Vector3(0.115, 0.345, 0.145), "yaw_deg": 122.0},
	{"pos": Vector3(-0.145, 0.580, -0.115), "yaw_deg": -45.0},
	{"pos": Vector3(0.115, 0.580, -0.145), "yaw_deg": 28.0},
	{"pos": Vector3(-0.115, 0.580, 0.145), "yaw_deg": 165.0},
	{"pos": Vector3(0.145, 0.580, 0.115), "yaw_deg": -150.0},
]
const BIN_INTERIOR_HALF := 0.298
const BIN_CLEARANCE_MARGIN := 0.020
const BIN_FLOOR_Y := 0.110
const BIN_COLLAR_BOTTOM_Y := 0.830
const EPS := 0.006

var _scenes: Dictionary = {}


func before() -> void:
	_scenes["table"] = load(TABLE_GLB)
	_scenes["bin"] = load(BIN_GLB)
	for prop_name: String in GAG_PROPS:
		_scenes[prop_name] = load("%s/%s.glb" % [CONTRABAND_DIR, prop_name])


func after() -> void:
	_scenes.clear()


func test_all_10_glbs_load_grounded_with_valid_materials_and_zero_seams() -> void:
	for key: String in _scenes:
		var packed := _scenes[key] as PackedScene
		assert_object(packed).override_failure_message("%s failed load" % key).is_not_null()
		var inst := packed.instantiate() as Node3D
		var box := _local_aabb(inst)
		assert_float(box.position.y).override_failure_message("%s min_y" % key).is_equal_approx(
			0.0, EPS
		)
		var mats := _surface_material_paths(inst)
		var atlas_msg := "%s missing toon atlas" % key
		assert_bool(mats.has(TOON_ATLAS)).override_failure_message(atlas_msg).is_true()
		if key == "bin":
			assert_bool(mats.has(GLASS_MAT)).override_failure_message("bin missing glass").is_true()
			assert_int(mats.size()).is_equal(2)
		else:
			assert_int(mats.size()).is_equal(1)
		_assert_custom0_on_atlas_surfaces(inst, key)
		var seams := _seam_counts(inst)
		assert_int(seams[0]).override_failure_message("%s zero_area" % key).is_equal(0)
		assert_int(seams[1]).override_failure_message("%s dup_coplanar" % key).is_equal(0)
		inst.free()


func test_search_table_fits_1x1_cell_and_exposes_exact_surface_mount() -> void:
	var inst := (_scenes["table"] as PackedScene).instantiate() as Node3D
	var box := _local_aabb(inst)
	assert_float(absf(box.position.x)).is_less_equal(0.48)
	assert_float(absf(box.end.x)).is_less_equal(0.48)
	assert_float(absf(box.position.z)).is_less_equal(0.48)
	assert_float(absf(box.end.z)).is_less_equal(0.48)
	assert_float(box.end.y).is_between(0.82, 0.87)
	var mount := inst.find_child("Mount_Inspect", true, false) as Node3D
	assert_object(mount).is_not_null()
	assert_vector(mount.position).is_equal_approx(EXPECTED_INSPECT_POS, Vector3.ONE * 0.002)
	var forward := (mount.basis * Vector3.BACK).normalized()
	assert_vector(forward).is_equal_approx(Vector3.BACK, Vector3.ONE * 0.01)
	inst.free()


func test_confiscation_bin_dims_glass_material_and_12_slot_containment() -> void:
	var glass := load(GLASS_MAT) as StandardMaterial3D
	assert_object(glass).is_not_null()
	assert_bool(GLASS_MAT.begins_with("res://assets/materials/")).is_false()
	assert_int(glass.transparency).is_equal(BaseMaterial3D.TRANSPARENCY_ALPHA)
	assert_float(glass.albedo_color.a).is_equal_approx(0.12, 0.01)

	var bin := (_scenes["bin"] as PackedScene).instantiate() as Node3D
	var box := _local_aabb(bin)
	assert_float(box.size.x).is_equal_approx(0.66, 0.02)
	assert_float(box.size.z).is_equal_approx(0.66, 0.02)
	assert_float(box.size.y).is_equal_approx(0.92, 0.02)

	var slots: Array[Transform3D] = []
	for i in EXPECTED_BIN_SLOTS.size():
		var slot_name := "Mount_Prop_%02d" % i
		var node := bin.find_child(slot_name, true, false) as Node3D
		assert_object(node).override_failure_message(slot_name).is_not_null()
		var spec: Dictionary = EXPECTED_BIN_SLOTS[i]
		var want_pos: Vector3 = spec["pos"]
		var want_yaw := deg_to_rad(float(spec["yaw_deg"]))
		assert_vector(node.position).override_failure_message(slot_name).is_equal_approx(
			want_pos, Vector3.ONE * 0.002
		)
		var want_fwd := Vector3(sin(want_yaw), 0.0, cos(want_yaw))
		var got_fwd := (node.basis * Vector3.BACK).normalized()
		assert_vector(got_fwd).override_failure_message("%s yaw" % slot_name).is_equal_approx(
			want_fwd, Vector3.ONE * 0.01
		)
		slots.append(node.transform)

	var max_abs_xz := BIN_INTERIOR_HALF - BIN_CLEARANCE_MARGIN
	for prop_name: String in GAG_PROPS:
		var prop := (_scenes[prop_name] as PackedScene).instantiate() as Node3D
		var p_box := _local_aabb(prop)
		var max_dim := maxf(p_box.size.x, maxf(p_box.size.y, p_box.size.z))
		assert_float(max_dim).override_failure_message(prop_name).is_between(0.20, 0.26)
		var verts := _all_vertices_local(prop)
		assert_int(verts.size()).is_greater(0)
		for s_idx in slots.size():
			var xf := slots[s_idx]
			for v: Vector3 in verts:
				var w := xf * v
				var tag := "%s@slot%02d" % [prop_name, s_idx]
				assert_float(absf(w.x)).override_failure_message("%s x" % tag).is_less_equal(
					max_abs_xz
				)
				assert_float(absf(w.z)).override_failure_message("%s z" % tag).is_less_equal(
					max_abs_xz
				)
				assert_float(w.y).override_failure_message("%s y_lo" % tag).is_greater_equal(
					BIN_FLOOR_Y - 0.001
				)
				assert_float(w.y).override_failure_message("%s y_hi" % tag).is_less(
					BIN_COLLAR_BOTTOM_Y
				)
		prop.free()
	bin.free()


func _local_aabb(root: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		var xf := _frame_in(m, root)
		var b := xf * m.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box


func _all_vertices_local(root: Node3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var xf := _frame_in(m, root)
		for s in m.mesh.get_surface_count():
			var arrays := m.mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for v in verts:
				out.append(xf * v)
	return out


func _frame_in(node: Node3D, root: Node3D) -> Transform3D:
	var xf := node.transform
	var p := node.get_parent()
	while p != null and p != root:
		xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf


func _surface_material_paths(root: Node3D) -> Dictionary:
	var paths := {}
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).mesh
		if m == null:
			continue
		for s in m.get_surface_count():
			var mat := m.surface_get_material(s)
			if mat != null:
				paths[mat.resource_path] = true
	return paths


func _assert_custom0_on_atlas_surfaces(root: Node3D, tag: String) -> void:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m: Mesh = (mi as MeshInstance3D).mesh
		if m == null:
			continue
		for s in m.get_surface_count():
			var mat := m.surface_get_material(s)
			if mat != null and mat.resource_path == TOON_ATLAS:
				var fmt: int = m.surface_get_format(s)
				(
					assert_int(fmt & Mesh.ARRAY_FORMAT_CUSTOM0)
					. override_failure_message("%s surf %d CUSTOM0" % [tag, s])
					. is_not_zero()
				)


func _seam_counts(root: Node3D) -> Array[int]:
	var zero_area := 0
	var tris := []
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var xf := _frame_in(m, root)
		var faces := m.mesh.get_faces()
		for i in range(0, faces.size(), 3):
			var a := xf * faces[i]
			var b := xf * faces[i + 1]
			var c := xf * faces[i + 2]
			var cross := (b - a).cross(c - a)
			var area := cross.length() * 0.5
			if area < 1e-8:
				zero_area += 1
				continue
			tris.append([(a + b + c) / 3.0, cross.normalized(), area])
	var buckets := {}
	for t: Array in tris:
		var k := Vector3i(((t[0] as Vector3) * 200.0).round())
		if not buckets.has(k):
			buckets[k] = []
		(buckets[k] as Array).append(t)
	var dup := 0
	for t: Array in tris:
		var centre: Vector3 = t[0]
		var n: Vector3 = t[1]
		var area: float = t[2]
		var base := Vector3i((centre * 200.0).round())
		var found := 0
		for dx in [-1, 0, 1]:
			for dy in [-1, 0, 1]:
				for dz in [-1, 0, 1]:
					for other: Array in buckets.get(base + Vector3i(dx, dy, dz), []):
						if (
							centre.distance_to(other[0]) < 1e-3
							and absf(n.dot(other[1])) > 0.999
							and absf(area - float(other[2])) < 1e-4
						):
							found += 1
		if found > 1:
			dup += 1
	return [zero_area, dup / 2]
