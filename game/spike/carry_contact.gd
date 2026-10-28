extends RefCounted
## Mesh-level contact checks for carry-on bags (decision carried-bags-stay-
## gripped-in-the-hand-clear-body-contact-by): a point counts as inside a bag
## only when it is inside one of the bag's own meshes (a ray from it crosses
## that mesh an odd number of times), never merely inside its bounding box.
## Body points come from the character's drawn (baked) pose; the vertices
## skinned mostly to a gripping hand (Hand, Fingers, Fingertips, Thumb,
## Thumb_Tip of that side) are left out, because that hand holds the bag.
## Load with preload(); no class_name.

const HAND_CHAIN: Array[String] = ["Hand", "Fingers", "Fingertips", "Thumb", "Thumb_Tip"]
## Skewed so a ray never runs exactly along a box edge or face.
const RAY := Vector3(0.0013, 1.0, 0.0007)
## The spacing of the points that cover a bag's surface.
const SAMPLE_M := 0.04

static var _bag: Array = []


## The carry-on bag's meshes: [transform relative to the piece root, faces
## (PackedVector3Array), AABB], read once from the kit scene.
static func bag_meshes() -> Array:
	if _bag.is_empty():
		var node := InteriorKit.instantiate("carry_on_bag")
		for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
			var xf := Transform3D.IDENTITY
			var at: Node = mi
			while at != null and at != node:
				xf = (at as Node3D).transform * xf
				at = at.get_parent()
			_bag.append([xf, mi.mesh.get_faces(), mi.mesh.get_aabb()])
		node.free()
	return _bag


## World points of a character's drawn body, without the vertices of the
## hands named by `gripping` (".R" and or ".L").
static func body_points(body: Node3D, gripping: Array) -> PackedVector3Array:
	return body_points_owned(body, gripping)[0]


## body_points() and, for each point, the name of its dominant bone.
static func body_points_owned(body: Node3D, gripping: Array) -> Array:
	var out := PackedVector3Array()
	var names := PackedStringArray()
	var skeleton := body.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var skip := {}
	for side in gripping:
		for name in HAND_CHAIN:
			var bone := skeleton.find_bone(name + str(side))
			if bone >= 0:
				skip[bone] = true
	for mi: MeshInstance3D in body.find_children("*", "MeshInstance3D", true, false):
		if not mi.is_visible_in_tree() or mi.mesh == null:
			continue
		var skinned := mi.skin != null
		var mesh: Mesh = mi.bake_mesh_from_current_skeleton_pose() if skinned else mi.mesh
		if mesh == null:
			continue
		for s in mesh.get_surface_count():
			var verts: PackedVector3Array = mesh.surface_get_arrays(s)[Mesh.ARRAY_VERTEX]
			var owners := _dominant_bones(mi, s) if skinned else PackedInt32Array()
			for k in verts.size():
				if not owners.is_empty() and skip.has(owners[k]):
					continue
				out.append(mi.global_transform * verts[k])
				names.append(skeleton.get_bone_name(owners[k]) if not owners.is_empty() else "")
	return [out, names]


## How many of `points` lie inside a bag drawn with world transform `bag_xf`.
static func inside_bag(points: PackedVector3Array, bag_xf: Transform3D) -> int:
	return inside_indices(points, bag_xf).size()


## The indices of `points` inside the bag.
static func inside_indices(points: PackedVector3Array, bag_xf: Transform3D) -> PackedInt32Array:
	var found := PackedInt32Array()
	var meshes := bag_meshes()
	var to_bag := bag_xf.affine_inverse()
	for i in points.size():
		var local := to_bag * points[i]
		for m in meshes:
			var lp: Vector3 = (m[0] as Transform3D).affine_inverse() * local
			if not (m[2] as AABB).grow(0.001).has_point(lp):
				continue
			if _odd(lp, m[1]):
				found.append(i)
				break
	return found


## How many of `points` lie inside a mesh of `node` (each MeshInstance3D's
## mesh tested on its own, so a bag resting on a table top is not inside the
## table the way it is inside the table's bounding box).
static func inside_meshes(points: PackedVector3Array, node: Node3D) -> int:
	var count := 0
	var meshes := []
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		meshes.append(
			[mi.global_transform.affine_inverse(), mi.mesh.get_faces(), mi.mesh.get_aabb()]
		)
	for p in points:
		for m in meshes:
			var lp: Vector3 = (m[0] as Transform3D) * p
			if (m[2] as AABB).grow(0.001).has_point(lp) and _odd(lp, m[1]):
				count += 1
				break
	return count


## World points covering a bag's surface: every triangle of its meshes
## sampled at SAMPLE_M or finer, so a thin wall through the bag meets a point.
static func bag_points(bag_xf: Transform3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	for m in bag_meshes():
		var to_world := bag_xf * (m[0] as Transform3D)
		var faces: PackedVector3Array = m[1]
		for i in range(0, faces.size() - 2, 3):
			var a := to_world * faces[i]
			var ab := to_world * faces[i + 1] - a
			var ac := to_world * faces[i + 2] - a
			var n := maxi(1, ceili(maxf(ab.length(), ac.length()) / SAMPLE_M))
			for u in n + 1:
				for v in n + 1 - u:
					out.append(a + ab * (u / float(n)) + ac * (v / float(n)))
	return out


static func _odd(p: Vector3, faces: PackedVector3Array) -> bool:
	var crossings := 0
	for i in range(0, faces.size() - 2, 3):
		if Geometry3D.ray_intersects_triangle(p, RAY, faces[i], faces[i + 1], faces[i + 2]) != null:
			crossings += 1
	return crossings % 2 == 1


## The skeleton bone with the largest weight on each vertex of surface `s`.
static func _dominant_bones(mi: MeshInstance3D, s: int) -> PackedInt32Array:
	var arrays := mi.mesh.surface_get_arrays(s)
	var bones: PackedInt32Array = (
		arrays[Mesh.ARRAY_BONES] if arrays[Mesh.ARRAY_BONES] else PackedInt32Array()
	)
	var weights: PackedFloat32Array = (
		arrays[Mesh.ARRAY_WEIGHTS] if arrays[Mesh.ARRAY_WEIGHTS] else PackedFloat32Array()
	)
	var count: int = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var out := PackedInt32Array()
	if bones.is_empty() or count == 0:
		return out
	var per := bones.size() / count
	var skeleton := mi.get_node(mi.skeleton) as Skeleton3D
	for k in count:
		var best := 0
		for j in range(1, per):
			if weights[k * per + j] > weights[k * per + best]:
				best = j
		var bind := bones[k * per + best]
		var name := mi.skin.get_bind_name(bind)
		out.append(skeleton.find_bone(name) if name != "" else mi.skin.get_bind_bone(bind))
	return out
