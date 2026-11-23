class_name StaffHandProps
extends RefCounted
## Lightweight view-only procedural hand props attached to staff Hand.R / Hand.L
## via BoneAttachment3D without modifying any character .glb skeleton (e7517650).
## Props are visible only in their active matching station pose mode and hidden
## when walking, tucked, idle, pooled, or snapped on load (6d949060).

enum PropKind { NONE, WAND, BOARDING_PASS, CLIPBOARD, COFFEE_CUP }

const TOON_BASE := preload("res://assets/materials/tp_atlas_simple_toon.tres")
const PROP_META := &"staff_hand_props"
const WEIGHT_MIN := 0.3
const OUTLINE_PX := 1.0
const OUTLINE_BIAS_M := 0.002

const COLOR_WAND_GRIP := Color(0.18, 0.21, 0.27)
const COLOR_WAND_HEAD := Color(0.28, 0.38, 0.52)
const COLOR_WAND_LED := Color(0.96, 0.68, 0.22)
const COLOR_PASS_CARD := Color(0.96, 0.94, 0.88)
const COLOR_PASS_STRIPE := Color(0.16, 0.64, 0.78)
const COLOR_CLIPBOARD_BOARD := Color(0.68, 0.48, 0.28)
const COLOR_CLIPBOARD_PAPER := Color(0.95, 0.95, 0.92)
const COLOR_CLIPBOARD_CLIP := Color(0.32, 0.36, 0.42)
const COLOR_CUP_BODY := Color(0.92, 0.88, 0.80)
const COLOR_CUP_SLEEVE := Color(0.60, 0.40, 0.24)
const COLOR_CUP_COFFEE := Color(0.22, 0.13, 0.08)

static var _white_tex: ImageTexture
static var _materials: Dictionary = {}
static var _meshes: Dictionary = {}


## Which prop should be shown right now for the given pose state.
static func desired_prop(
	mode: StaffStationPose.Mode,
	sub_mode: StaffStationPose.SubMode,
	weight: float,
	sim_time: float,
	seed_id: int,
	walking: bool,
	tucked: bool,
) -> PropKind:
	if walking or tucked or weight <= WEIGHT_MIN:
		return PropKind.NONE
	match mode:
		StaffStationPose.Mode.SECURITY_SCAN:
			return PropKind.WAND
		StaffStationPose.Mode.GATE:
			return PropKind.BOARDING_PASS
		StaffStationPose.Mode.CHECKIN:
			if StaffStationPose.checkin_prop_active(sim_time, seed_id):
				return PropKind.BOARDING_PASS
		StaffStationPose.Mode.SHOP:
			if sub_mode == StaffStationPose.SubMode.SHOP_INFO_DESK:
				return PropKind.CLIPBOARD
			if (
				(
					sub_mode == StaffStationPose.SubMode.SHOP_CAFE
					or sub_mode == StaffStationPose.SubMode.SHOP_BAR
				)
				and StaffStationPose.cafe_cup_active(sim_time, seed_id)
			):
				return PropKind.COFFEE_CUP
	return PropKind.NONE


## Updates prop visibility on `node` for the current frame's pose state.
static func update(
	node: Node3D,
	mode: StaffStationPose.Mode,
	sub_mode: StaffStationPose.SubMode,
	weight: float,
	sim_time: float,
	seed_id: int,
	walking: bool,
	tucked: bool,
) -> void:
	var kind := desired_prop(mode, sub_mode, weight, sim_time, seed_id, walking, tucked)
	if kind == PropKind.NONE and not node.has_meta(PROP_META):
		return
	var rec := _ensure(node)
	if rec.is_empty():
		return
	var props: Dictionary = rec["props"]
	for key: int in props:
		var prop_node := props[key] as Node3D
		prop_node.visible = (key == kind)


## Hides every attached prop on `node` (used on snap/load and pool release).
static func hide_all(node: Node3D) -> void:
	if node == null or not node.has_meta(PROP_META):
		return
	var rec: Dictionary = node.get_meta(PROP_META)
	var props: Dictionary = rec.get("props", {})
	for key: int in props:
		var prop_node := props[key] as Node3D
		if is_instance_valid(prop_node):
			prop_node.visible = false


## Currently visible PropKind on `node`, or PropKind.NONE.
static func active_prop(node: Node3D) -> PropKind:
	if node == null or not node.has_meta(PROP_META):
		return PropKind.NONE
	var rec: Dictionary = node.get_meta(PROP_META)
	var props: Dictionary = rec.get("props", {})
	for key: int in props:
		var prop_node := props[key] as Node3D
		if is_instance_valid(prop_node) and prop_node.visible:
			return key as PropKind
	return PropKind.NONE


## Returns the prop Node3D for `kind` on `node` (lazily attaching if needed).
static func prop_node(node: Node3D, kind: PropKind) -> Node3D:
	if kind == PropKind.NONE or node == null:
		return null
	var rec := _ensure(node)
	if rec.is_empty():
		return null
	return (rec["props"] as Dictionary).get(kind)


static func _ensure(node: Node3D) -> Dictionary:
	if node.has_meta(PROP_META):
		return node.get_meta(PROP_META)
	var skeletons := node.find_children("*", "Skeleton3D", true, false)
	if skeletons.is_empty():
		return {}
	var skeleton := skeletons[0] as Skeleton3D
	var att_r := _attach(skeleton, "Hand.R", "StaffProp_R")
	var att_l := _attach(skeleton, "Hand.L", "StaffProp_L")
	var props := {
		PropKind.WAND: _add_prop(att_r, _build_wand()),
		PropKind.BOARDING_PASS: _add_prop(att_r, _build_boarding_pass()),
		PropKind.COFFEE_CUP: _add_prop(att_r, _build_coffee_cup()),
		PropKind.CLIPBOARD: _add_prop(att_l, _build_clipboard()),
	}
	var rec := {"att_r": att_r, "att_l": att_l, "props": props}
	node.set_meta(PROP_META, rec)
	return rec


static func _attach(skeleton: Skeleton3D, bone: String, node_name: String) -> BoneAttachment3D:
	var att := BoneAttachment3D.new()
	att.name = node_name
	att.bone_name = bone
	skeleton.add_child(att)
	return att


static func _add_prop(parent: BoneAttachment3D, prop: Node3D) -> Node3D:
	prop.visible = false
	parent.add_child(prop)
	return prop


## Hand.R axes: +Y along fingers, +Z thumb side, +X palm normal.
static func _build_wand() -> Node3D:
	var root := Node3D.new()
	root.name = "Wand"
	root.position = Vector3(0.028, 0.085, 0.016)
	root.rotation_degrees = Vector3(-12.0, 0.0, 0.0)
	var grip := _part(
		"Grip",
		_cyl_mesh("wand_grip", 0.015, 0.014, 0.11),
		COLOR_WAND_GRIP,
		Vector3(0.0, -0.01, 0.0),
	)
	var paddle := _part(
		"Paddle",
		_box_mesh("wand_paddle", Vector3(0.018, 0.16, 0.052)),
		COLOR_WAND_HEAD,
		Vector3(0.0, 0.115, 0.0),
	)
	var led := _part(
		"Led",
		_box_mesh("wand_led", Vector3(0.022, 0.022, 0.056)),
		COLOR_WAND_LED,
		Vector3(0.0, 0.05, 0.0),
	)
	root.add_child(grip)
	root.add_child(paddle)
	root.add_child(led)
	return root


static func _build_boarding_pass() -> Node3D:
	var root := Node3D.new()
	root.name = "BoardingPass"
	root.position = Vector3(0.024, 0.135, 0.018)
	root.rotation_degrees = Vector3(0.0, 12.0, -8.0)
	var card := _part(
		"Card",
		_box_mesh("pass_card", Vector3(0.005, 0.13, 0.072)),
		COLOR_PASS_CARD,
		Vector3.ZERO,
	)
	var stripe := _part(
		"Stripe",
		_box_mesh("pass_stripe", Vector3(0.007, 0.028, 0.074)),
		COLOR_PASS_STRIPE,
		Vector3(0.0, 0.036, 0.0),
	)
	root.add_child(card)
	root.add_child(stripe)
	return root


## Hand.L axes: +Y along fingers, +Z thumb (upward when gripping), -X palm normal.
static func _build_clipboard() -> Node3D:
	var root := Node3D.new()
	root.name = "Clipboard"
	root.position = Vector3(-0.028, 0.095, 0.020)
	root.rotation_degrees = Vector3(0.0, -18.0, 14.0)
	var board := _part(
		"Board",
		_box_mesh("clip_board", Vector3(0.012, 0.17, 0.22)),
		COLOR_CLIPBOARD_BOARD,
		Vector3.ZERO,
	)
	var paper := _part(
		"Paper",
		_box_mesh("clip_paper", Vector3(0.005, 0.135, 0.18)),
		COLOR_CLIPBOARD_PAPER,
		Vector3(-0.006, 0.0, -0.006),
	)
	var clip := _part(
		"Clip",
		_box_mesh("clip_metal", Vector3(0.018, 0.056, 0.024)),
		COLOR_CLIPBOARD_CLIP,
		Vector3(-0.003, 0.0, 0.092),
	)
	root.add_child(board)
	root.add_child(paper)
	root.add_child(clip)
	return root


## Hand.R thumb-up grip aligns upright cup cylinder along Hand.R +Z.
static func _build_coffee_cup() -> Node3D:
	var root := Node3D.new()
	root.name = "CoffeeCup"
	root.position = Vector3(0.036, 0.088, 0.018)
	root.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	var body := _part(
		"Body",
		_cyl_mesh("cup_body", 0.036, 0.027, 0.098),
		COLOR_CUP_BODY,
		Vector3.ZERO,
	)
	var sleeve := _part(
		"Sleeve",
		_cyl_mesh("cup_sleeve", 0.035, 0.032, 0.038),
		COLOR_CUP_SLEEVE,
		Vector3(0.0, -0.004, 0.0),
	)
	var coffee := _part(
		"Coffee",
		_cyl_mesh("cup_top", 0.033, 0.033, 0.006),
		COLOR_CUP_COFFEE,
		Vector3(0.0, 0.048, 0.0),
	)
	root.add_child(body)
	root.add_child(sleeve)
	root.add_child(coffee)
	return root


static func _part(part_name: String, mesh: Mesh, color: Color, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = part_name
	mi.mesh = mesh
	mi.material_override = _material(color)
	mi.position = pos
	return mi


static func _material(color: Color) -> ShaderMaterial:
	var key := color.to_rgba32()
	if _materials.has(key):
		return _materials[key]
	if _white_tex == null:
		var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		img.set_pixel(0, 0, Color.WHITE)
		_white_tex = ImageTexture.create_from_image(img)
	var mat := TOON_BASE.duplicate() as ShaderMaterial
	mat.set_shader_parameter("albedo_texture", _white_tex)
	mat.set_shader_parameter("albedo_tint", color)
	if mat.next_pass is ShaderMaterial:
		var outline := (mat.next_pass as ShaderMaterial).duplicate() as ShaderMaterial
		outline.set_shader_parameter("outline_px", OUTLINE_PX)
		outline.set_shader_parameter("depth_bias_m", OUTLINE_BIAS_M)
		mat.next_pass = outline
	_materials[key] = mat
	return mat


static func _box_mesh(key: String, size: Vector3) -> ArrayMesh:
	if _meshes.has(key):
		return _meshes[key]
	var box := BoxMesh.new()
	box.size = size
	var mesh := _to_welded_mesh(box)
	_meshes[key] = mesh
	return mesh


static func _cyl_mesh(key: String, top_r: float, bottom_r: float, height: float) -> ArrayMesh:
	if _meshes.has(key):
		return _meshes[key]
	var cyl := CylinderMesh.new()
	cyl.top_radius = top_r
	cyl.bottom_radius = bottom_r
	cyl.height = height
	cyl.radial_segments = 10
	cyl.rings = 1
	var mesh := _to_welded_mesh(cyl)
	_meshes[key] = mesh
	return mesh


static func _to_welded_mesh(prim: PrimitiveMesh) -> ArrayMesh:
	var arrays := prim.get_mesh_arrays()
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var custom := PackedByteArray()
	if not verts.is_empty() and normals.size() == verts.size():
		custom = _welded_custom0(verts, normals, indices)
	arrays[Mesh.ARRAY_CUSTOM0] = custom
	var mesh := ArrayMesh.new()
	var flags := 0
	if not custom.is_empty():
		flags = Mesh.ARRAY_CUSTOM_RGBA8_UNORM << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
	return mesh


static func _welded_custom0(
	verts: PackedVector3Array, normals: PackedVector3Array, indices: PackedInt32Array
) -> PackedByteArray:
	var pos_keys: Array[Vector3i] = []
	pos_keys.resize(verts.size())
	var sum_by_pos := {}
	var weight_by_pos := {}
	for vi in verts.size():
		var v := verts[vi]
		pos_keys[vi] = Vector3i(roundi(v.x * 10000.0), roundi(v.y * 10000.0), roundi(v.z * 10000.0))
	var tri_count := indices.size() if not indices.is_empty() else verts.size()
	for base in range(0, tri_count, 3):
		var idx0 := indices[base] if not indices.is_empty() else base
		var idx1 := indices[base + 1] if not indices.is_empty() else base + 1
		var idx2 := indices[base + 2] if not indices.is_empty() else base + 2
		var p := [verts[idx0], verts[idx1], verts[idx2]]
		var idxs := [idx0, idx1, idx2]
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
			var ci: int = idxs[k]
			var key := pos_keys[ci]
			sum_by_pos[key] = sum_by_pos.get(key, Vector3.ZERO) + normals[ci].normalized() * angle
			weight_by_pos[key] = float(weight_by_pos.get(key, 0.0)) + angle
	var smooth_by_pos := {}
	for key: Vector3i in sum_by_pos:
		var total_w := float(weight_by_pos[key])
		var sum_n: Vector3 = sum_by_pos[key]
		if total_w > 0.0 and sum_n.length() > 0.15 * total_w:
			smooth_by_pos[key] = sum_n.normalized()
	var min_dot_by_pos := {}
	for vi in verts.size():
		var key := pos_keys[vi]
		if smooth_by_pos.has(key):
			var d: float = (smooth_by_pos[key] as Vector3).dot(normals[vi].normalized())
			min_dot_by_pos[key] = minf(float(min_dot_by_pos.get(key, 1.0)), d)
	var custom := PackedByteArray()
	custom.resize(verts.size() * 4)
	for vi in verts.size():
		var key := pos_keys[vi]
		var n := normals[vi].normalized()
		var miter := 1.0
		if smooth_by_pos.has(key):
			n = smooth_by_pos[key]
			var min_d := float(min_dot_by_pos[key])
			if min_d > 0.2:
				miter = clampf(1.0 / min_d, 1.0, 1.5)
		var off := vi * 4
		custom[off] = clampi(roundi((n.x * 0.5 + 0.5) * 255.0), 0, 255)
		custom[off + 1] = clampi(roundi((n.y * 0.5 + 0.5) * 255.0), 0, 255)
		custom[off + 2] = clampi(roundi((n.z * 0.5 + 0.5) * 255.0), 0, 255)
		var a_f := 0.6 + 0.4 * clampf((miter - 1.0) / 0.5, 0.0, 1.0)
		custom[off + 3] = clampi(roundi(a_f * 255.0), 0, 255)
	return custom
