@tool
extends EditorScenePostImport
## Binds the Toon Series toon materials to every imported surface by glTF material
## name, and makes the characters' looping clips (idle, walk, run, sit_idle and
## the passengers' shower washing clip) loop.
##
## The .glb files come from tools/blender/convert_toon_batch.py, which names every
## material after its pack and atlas. Each .glb.import points its
## import_script/path here. The surfaces get the shared .tres resources as they are;
## nothing is copied from the glTF material, so no PBR scalar or map can leak into
## the toon look. An unmapped name or a missing resource fails the import.

const MATERIALS := {
	"TP_Atlas_1A_D": "res://assets/materials/tp_atlas_toon.tres",
	"TP_Atlas_Simple_1A_D": "res://assets/materials/tp_atlas_simple_toon.tres",
	"TP_Atlas_Lights_1A_D": "res://assets/materials/tp_lights.tres",
	"TP_Glass_1A_D": "res://assets/materials/tp_glass.tres",
	"TCP_Atlas_1A_D": "res://assets/materials/tcp_atlas_toon.tres",
	"TC_Road_1A_D": "res://assets/materials/tc_road_1a_toon.tres",
	"TC_Tree_1A_D": "res://assets/materials/tc_tree_1a_toon.tres",
	"TC_Tree_3A_D": "res://assets/materials/tc_tree_3a_toon.tres",
	"TC_Props_2A_D": "res://assets/materials/tc_props_2a_toon.tres",
	"TC_Building_4A_D": "res://assets/materials/tc_building_4a_toon.tres",
	"TC_Building_17A_D": "res://assets/materials/tc_building_17a_toon.tres",
}
const LOOPING_ANIMATIONS: Array[String] = ["idle", "walk", "run", "sit_idle", "shower"]
const WELD_GRID := 10000.0
const MIN_SUM_RATIO := 0.15
const MIN_MITER_DOT := 0.2


func _post_import(scene: Node) -> Object:
	var bound := 0
	var failed := 0
	for node in scene.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (node as MeshInstance3D).mesh
		if mesh == null:
			continue
		for i in mesh.get_surface_count():
			var source := mesh.surface_get_material(i)
			var key := source.resource_name if source != null else ""
			if not MATERIALS.has(key):
				push_error(
					(
						"toon import: %s: %s surface %d has unmapped material '%s'"
						% [get_source_file(), node.name, i, key]
					)
				)
				failed += 1
				continue
			var toon := load(MATERIALS[key]) as Material
			if toon == null:
				push_error("toon import: cannot load %s" % MATERIALS[key])
				failed += 1
				continue
			mesh.surface_set_material(i, toon)
			bound += 1
	for node in scene.find_children("*", "AnimationPlayer", true, false):
		var player := node as AnimationPlayer
		for anim_name in player.get_animation_list():
			if anim_name in LOOPING_ANIMATIONS:
				player.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
	print("toon import: %s bound=%d unmapped=%d" % [get_source_file(), bound, failed])
	if failed > 0 or bound == 0:
		# Returning null fails the import, so a half-bound asset never ships.
		return null
	var baked := bake_scene_outline_normals(scene)
	print("toon import: %s smooth_surfaces=%d" % [get_source_file(), baked])
	return scene


## Bakes position-welded smooth outline normals and clamped miter scale into
## ARRAY_CUSTOM0 for every static MeshInstance3D surface under `scene`.
## Skinned meshes (skin / skeleton / ARRAY_BONES / ARRAY_WEIGHTS) are skipped so
## animated limbs never extrude along frozen bind-pose normals.
static func bake_scene_outline_normals(scene: Node) -> int:
	var seen := {}
	var baked := 0
	for node in scene.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi.skin != null or not mi.skeleton.is_empty():
			continue
		var mesh := mi.mesh as ArrayMesh
		if mesh == null or seen.has(mesh.get_instance_id()):
			continue
		seen[mesh.get_instance_id()] = true
		baked += bake_array_mesh_outline_normals(mesh)
	return baked


## Rebuilds static surfaces of `mesh` with welded smooth normals in CUSTOM0
## (RGBA8_UNORM: xyz = n * 0.5 + 0.5, a = 0.6..1.0 encoding miter 1.0..1.5).
static func bake_array_mesh_outline_normals(mesh: ArrayMesh) -> int:
	var count := mesh.get_surface_count()
	if count == 0:
		return 0
	var had_shadow := mesh.shadow_mesh != null
	var specs: Array[Dictionary] = []
	var changed := 0
	for i in count:
		var fmt := mesh.surface_get_format(i)
		var arrays := mesh.surface_get_arrays(i)
		var prim := mesh.surface_get_primitive_type(i)
		var mat := mesh.surface_get_material(i)
		var sname := mesh.surface_get_name(i)
		var blends := mesh.surface_get_blend_shape_arrays(i)
		var verts_any: Variant = arrays[Mesh.ARRAY_VERTEX]
		var vert_count := 0
		if verts_any is PackedVector3Array:
			vert_count = (verts_any as PackedVector3Array).size()
		var lods := _extract_surface_lods(mesh, i, vert_count)
		var preserve_flags := (
			fmt
			& (
				Mesh.ARRAY_FLAG_COMPRESS_ATTRIBUTES
				| Mesh.ARRAY_FLAG_USE_2D_VERTICES
				| Mesh.ARRAY_FLAG_USE_DYNAMIC_UPDATE
			)
		)
		var has_skin := (
			(fmt & (Mesh.ARRAY_FORMAT_BONES | Mesh.ARRAY_FORMAT_WEIGHTS)) != 0
			or arrays[Mesh.ARRAY_BONES] != null
			or arrays[Mesh.ARRAY_WEIGHTS] != null
		)
		if not has_skin and prim == Mesh.PRIMITIVE_TRIANGLES and arrays[Mesh.ARRAY_NORMAL] != null:
			var custom := _compute_custom0_normals(arrays)
			if not custom.is_empty():
				arrays[Mesh.ARRAY_CUSTOM0] = custom
				changed += 1
		var spec := {
			"prim": prim,
			"arrays": arrays,
			"blends": blends,
			"lods": lods,
			"preserve_flags": preserve_flags,
			"has_skin": has_skin,
			"has_custom0": arrays[Mesh.ARRAY_CUSTOM0] != null,
			"mat": mat,
			"name": sname,
		}
		specs.append(spec)
	if changed == 0:
		return 0
	mesh.clear_surfaces()
	for spec in specs:
		var flags := int(spec["preserve_flags"])
		if spec["has_custom0"]:
			flags |= Mesh.ARRAY_CUSTOM_RGBA8_UNORM << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
		var spec_lods: Dictionary = spec["lods"]
		mesh.add_surface_from_arrays(spec["prim"], spec["arrays"], spec["blends"], spec_lods, flags)
		var idx := mesh.get_surface_count() - 1
		if spec["mat"] != null:
			mesh.surface_set_material(idx, spec["mat"])
		if not String(spec["name"]).is_empty():
			mesh.surface_set_name(idx, spec["name"])
	if had_shadow:
		mesh.shadow_mesh = _build_shadow_mesh(specs)
	return changed


static func _build_shadow_mesh(specs: Array[Dictionary]) -> ArrayMesh:
	var sm := ArrayMesh.new()
	for spec in specs:
		if spec["has_skin"]:
			return null
		var src_arrays: Array = spec["arrays"]
		if src_arrays[Mesh.ARRAY_VERTEX] == null:
			return null
		var sm_arrays: Array = []
		sm_arrays.resize(Mesh.ARRAY_MAX)
		sm_arrays[Mesh.ARRAY_VERTEX] = src_arrays[Mesh.ARRAY_VERTEX]
		if src_arrays[Mesh.ARRAY_INDEX] != null:
			sm_arrays[Mesh.ARRAY_INDEX] = src_arrays[Mesh.ARRAY_INDEX]
		var sm_lods: Dictionary = spec["lods"]
		var sm_flags := int(spec["preserve_flags"])
		sm.add_surface_from_arrays(spec["prim"], sm_arrays, [], sm_lods, sm_flags)
	return sm


static func _extract_surface_lods(mesh: ArrayMesh, surface: int, vert_count: int) -> Dictionary:
	var out := {}
	var surfaces_prop: Variant = mesh.get("_surfaces")
	if surfaces_prop is Array and surface < (surfaces_prop as Array).size():
		var surf_entry: Variant = (surfaces_prop as Array)[surface]
		if surf_entry is Dictionary:
			var raw_lods: Variant = (surf_entry as Dictionary).get("lods", [])
			if raw_lods is Array:
				var lod_arr := raw_lods as Array
				var k := 0
				while k + 1 < lod_arr.size():
					var dist := float(lod_arr[k])
					var bytes_any: Variant = lod_arr[k + 1]
					if bytes_any is PackedByteArray:
						var decoded := _decode_lod_indices(bytes_any as PackedByteArray, vert_count)
						if not decoded.is_empty():
							out[dist] = decoded
					k += 2
	if not out.is_empty():
		return out
	var rid := mesh.get_rid()
	if not rid.is_valid():
		return out
	var rs_surf: Dictionary = RenderingServer.mesh_get_surface(rid, surface)
	var rs_lods: Variant = rs_surf.get("lods", [])
	if rs_lods is Array:
		for entry: Variant in rs_lods as Array:
			if not (entry is Dictionary):
				continue
			var ld := entry as Dictionary
			var bytes_any: Variant = ld.get("index_data", PackedByteArray())
			if bytes_any is PackedByteArray:
				var decoded := _decode_lod_indices(bytes_any as PackedByteArray, vert_count)
				if not decoded.is_empty():
					out[float(ld.get("edge_length", 0.0))] = decoded
	return out


static func _decode_lod_indices(bytes: PackedByteArray, vert_count: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	if bytes.is_empty():
		return out
	if vert_count <= 65536:
		var count := bytes.size() / 2
		out.resize(count)
		for i in count:
			out[i] = bytes.decode_u16(i * 2)
	else:
		var count := bytes.size() / 4
		out.resize(count)
		for i in count:
			out[i] = bytes.decode_u32(i * 4)
	return out


static func _compute_custom0_normals(arrays: Array) -> PackedByteArray:
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	if verts.is_empty() or normals.size() != verts.size():
		return PackedByteArray()
	var indices: PackedInt32Array = (
		arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
	)
	var tri_count := indices.size() / 3 if not indices.is_empty() else verts.size() / 3
	if tri_count == 0:
		return PackedByteArray()

	var pos_keys: Array[Vector3i] = []
	pos_keys.resize(verts.size())
	var sum_by_pos := {}
	var weight_by_pos := {}
	for vi in verts.size():
		var v := verts[vi]
		pos_keys[vi] = Vector3i(
			roundi(v.x * WELD_GRID), roundi(v.y * WELD_GRID), roundi(v.z * WELD_GRID)
		)

	for t in tri_count:
		var base := t * 3
		var i0 := indices[base] if not indices.is_empty() else base
		var i1 := indices[base + 1] if not indices.is_empty() else base + 1
		var i2 := indices[base + 2] if not indices.is_empty() else base + 2
		var p := [verts[i0], verts[i1], verts[i2]]
		var corner_idx := [i0, i1, i2]
		for k in 3:
			var ea: Vector3 = p[(k + 1) % 3] - p[k]
			var eb: Vector3 = p[(k + 2) % 3] - p[k]
			var la := ea.length()
			var lb := eb.length()
			if la < 1e-6 or lb < 1e-6:
				continue
			var angle := acos(clampf(ea.dot(eb) / (la * lb), -1.0, 1.0))
			if angle <= 1e-6:
				continue
			var ci: int = corner_idx[k]
			var key := pos_keys[ci]
			var n := normals[ci].normalized()
			sum_by_pos[key] = sum_by_pos.get(key, Vector3.ZERO) + n * angle
			weight_by_pos[key] = float(weight_by_pos.get(key, 0.0)) + angle

	var smooth_by_pos := {}
	for key: Vector3i in sum_by_pos:
		var total_w := float(weight_by_pos[key])
		var sum_n: Vector3 = sum_by_pos[key]
		if total_w > 0.0 and sum_n.length() > MIN_SUM_RATIO * total_w:
			smooth_by_pos[key] = sum_n.normalized()

	var min_dot_by_pos := {}
	for vi in verts.size():
		var key := pos_keys[vi]
		if not smooth_by_pos.has(key):
			continue
		var sn: Vector3 = smooth_by_pos[key]
		var d := sn.dot(normals[vi].normalized())
		min_dot_by_pos[key] = minf(float(min_dot_by_pos.get(key, 1.0)), d)

	var out := PackedByteArray()
	out.resize(verts.size() * 4)
	for vi in verts.size():
		var key := pos_keys[vi]
		var n := normals[vi].normalized()
		var miter := 1.0
		if smooth_by_pos.has(key):
			n = smooth_by_pos[key]
			var min_d := float(min_dot_by_pos[key])
			if min_d > MIN_MITER_DOT:
				miter = clampf(1.0 / min_d, 1.0, 1.5)
		var off := vi * 4
		out[off] = clampi(roundi((n.x * 0.5 + 0.5) * 255.0), 0, 255)
		out[off + 1] = clampi(roundi((n.y * 0.5 + 0.5) * 255.0), 0, 255)
		out[off + 2] = clampi(roundi((n.z * 0.5 + 0.5) * 255.0), 0, 255)
		var a_f := 0.6 + 0.4 * clampf((miter - 1.0) / 0.5, 0.0, 1.0)
		out[off + 3] = clampi(roundi(a_f * 255.0), 0, 255)
	return out
