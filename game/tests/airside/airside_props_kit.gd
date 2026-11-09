extends RefCounted
## Shared set-up for the airside props tests (board 4c08b8e5): the real Airside
## markers and links from main.tscn's saved state, without instancing the
## scene, and a plane model parked or posed as PlaneView draws it.

const MAIN_SCENE := "res://main/main.tscn"
## How far _inside() casts each ray. Geometry3D.segment_intersects_triangle
## drops a hit nearer the start than 1e-5 of the segment, so a 10 km ray
## misses a face 0.1 m away; 100 m covers any plane and misses only 1 mm.
const ENCLOSE_REACH_M := 100.0
## The six ray directions _inside() casts: each axis both ways, skewed.
const ENCLOSE_RAYS: Array[Vector3] = [
	Vector3(1.0, 0.013, 0.021),
	Vector3(-1.0, -0.017, 0.011),
	Vector3(0.019, 1.0, -0.013),
	Vector3(-0.011, -1.0, 0.017),
	Vector3(0.023, -0.009, 1.0),
	Vector3(-0.015, 0.019, -1.0),
]


## A new Airside carrying main.tscn's Marker3D waypoints and links. The caller
## adds it to the tree and frees it.
static func airside_from_main() -> Airside:
	var state: SceneState = (load(MAIN_SCENE) as PackedScene).get_state()
	var airside := Airside.new()
	for i in state.get_node_count():
		var parent := String(state.get_node_path(i, true))
		var props := {}
		for k in state.get_node_property_count(i):
			props[state.get_node_property_name(i, k)] = state.get_node_property_value(i, k)
		if parent == "./Airside" and state.get_node_type(i) == &"Marker3D":
			var marker := Marker3D.new()
			marker.name = state.get_node_name(i)
			marker.transform = props.get(&"transform", Transform3D.IDENTITY)
			airside.add_child(marker)
		elif String(state.get_node_path(i)) == "./Airside":
			airside.links = props[&"links"]
	return airside


## A holder at `pose` with an instance of plane `model` under it, placed as
## PlaneView.model_position_at() places it on the ground for a stand at
## `stand_point` whose parked plane faces `stand_dir`. Returns the model; the
## holder is its parent, added under `parent`.
static func posed_model(
	parent: Node, model: String, pose: Transform3D, stand_point: Vector3, stand_dir: Vector3
) -> Node3D:
	var holder := Node3D.new()
	holder.transform = pose
	parent.add_child(holder)
	var plane: Node3D = (PlaneView.PLANE_SCENES[model] as PackedScene).instantiate()
	plane.position = FlightPose.model_position(model, pose, stand_point, stand_dir)
	holder.add_child(plane)
	return plane


## Edges of `a`'s visible triangles that cross a triangle of `b`'s, and back
## (the R11 clip count): {"count", "meshes": the names of `a`'s meshes
## involved}. Both are read in world space, so both must be in the tree.
static func crossings(a: Node3D, b: Node3D) -> Dictionary:
	var a_tris := world_tris(a)
	var b_tris := world_tris(b)
	var b_box := AABB()
	for i in b_tris.size():
		b_box = b_tris[i]["box"] if i == 0 else b_box.merge(b_tris[i]["box"])
	var count := 0
	var meshes: Array[String] = []
	for ta: Dictionary in a_tris:
		if not (ta["box"] as AABB).intersects(b_box):
			continue
		var hits := 0
		for tb: Dictionary in b_tris:
			if not (ta["box"] as AABB).intersects(tb["box"]):
				continue
			hits += _edges_cross(ta["p"], tb["p"]) + _edges_cross(tb["p"], ta["p"])
		if hits > 0:
			count += hits
			if not meshes.has(ta["mesh"]):
				meshes.append(ta["mesh"])
	return {"count": count, "meshes": meshes}


## The parts (visible meshes) of `a` lying inside a closed mesh of `b`, and of
## `b` inside one of `a`'s: {"count", "parts": "<part> in <mesh>" each}. A
## part with no edge crossing (crossings()) lies wholly inside or wholly
## outside each mesh, so one vertex of it decides (_inside()). With 0
## crossings and 0 nested, the meshes neither meet nor nest.
static func nested(a: Node3D, b: Node3D) -> Dictionary:
	var parts: Array[String] = []
	for pair: Array in [[a, b], [b, a]]:
		for part in _visible_meshes(pair[0]):
			var faces := part.mesh.get_faces()
			if faces.is_empty():
				continue
			var at := part.global_transform * faces[0]
			for mesh in _visible_meshes(pair[1]):
				if _inside(at, mesh):
					parts.append("%s in %s" % [part.name, mesh.name])
	return {"count": parts.size(), "parts": parts}


## Whether `point` (world) lies inside the mesh of `mi`: a ray each way
## along every axis (skewed a little, so none grazes an axis-aligned edge)
## meets one of its triangles. Unlike a parity count it does not need the mesh
## closed, unless one of the six rays leaves through an opening. A point it
## wrongly calls inside (in a deep concavity) can only fail a test, never pass
## one.
static func _inside(point: Vector3, mi: MeshInstance3D) -> bool:
	var faces := mi.mesh.get_faces()
	for i in range(0, faces.size(), 3):
		for j in 3:
			faces[i + j] = mi.global_transform * faces[i + j]
	for axis: Vector3 in ENCLOSE_RAYS:
		var far := point + axis * ENCLOSE_REACH_M
		var met := false
		for i in range(0, faces.size(), 3):
			if (
				Geometry3D.segment_intersects_triangle(
					point, far, faces[i], faces[i + 1], faces[i + 2]
				)
				!= null
			):
				met = true
				break
		if not met:
			return false
	return true


## The vertex-to-box gap between `a` and `b`, both ways: {"gap": the smaller
## of "a_to_b" and "b_to_a"}, each {"gap", "from", "into"} from vertex_gap().
## A diagnostic, not a test of contact: a box is looser than its mesh (a
## curved fuselage's box takes in air beside it), so a 0 can be a near miss,
## and the gap is not a bound on the true clearance either, because the
## nearest points can lie mid-face or mid-edge, away from every vertex.
static func clearance(a: Node3D, b: Node3D) -> Dictionary:
	var a_to_b := vertex_gap(a, b)
	var b_to_a := vertex_gap(b, a)
	return {
		"gap": minf(a_to_b["gap"], b_to_a["gap"]),
		"a_to_b": a_to_b,
		"b_to_a": b_to_a,
	}


## The smallest gap from a vertex of `from`'s visible meshes to the bounds of
## one of `into`'s, each box in its own mesh's frame: {"gap" (metres, 0 inside
## a box), "from", "into": the two mesh names}. Each box holds its mesh, so a
## vertex inside a mesh reads 0.
static func vertex_gap(from: Node3D, into: Node3D) -> Dictionary:
	var boxes: Array[Dictionary] = []
	for mi in _visible_meshes(into):
		var inv := mi.global_transform.affine_inverse()
		boxes.append({"inv": inv, "box": mi.get_aabb(), "mesh": String(mi.name)})
	var out := {"gap": INF, "from": "", "into": ""}
	for mi in _visible_meshes(from):
		for v in mi.mesh.get_faces():
			var w := mi.global_transform * v
			for entry: Dictionary in boxes:
				var box: AABB = entry["box"]
				var p: Vector3 = entry["inv"] * w
				var gap := (p.clamp(box.position, box.end) - p).length()
				if gap < out["gap"]:
					out = {"gap": gap, "from": String(mi.name), "into": entry["mesh"]}
	return out


## `node` and the MeshInstance3Ds under it that are on show and have a mesh.
static func _visible_meshes(node: Node3D) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	var found := node.find_children("*", "MeshInstance3D", true, false)
	if node is MeshInstance3D:
		found.append(node)
	for mi: MeshInstance3D in found:
		if mi.is_visible_in_tree() and mi.mesh != null:
			out.append(mi)
	return out


## `node`'s visible triangles in world space: {"p": three points, "box", "mesh"}.
static func world_tris(node: Node3D) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var found := node.find_children("*", "MeshInstance3D", true, false)
	if node is MeshInstance3D:
		found.append(node)
	for mi: MeshInstance3D in found:
		if not mi.is_visible_in_tree() or mi.mesh == null:
			continue
		var faces := mi.mesh.get_faces()
		for i in range(0, faces.size(), 3):
			var p := PackedVector3Array(
				[
					mi.global_transform * faces[i],
					mi.global_transform * faces[i + 1],
					mi.global_transform * faces[i + 2],
				]
			)
			var box := AABB(p[0], Vector3.ZERO).expand(p[1]).expand(p[2]).grow(0.001)
			out.append({"p": p, "box": box, "mesh": String(mi.name)})
	return out


## How many of triangle `edges`' three edges cross triangle `face`.
static func _edges_cross(edges: PackedVector3Array, face: PackedVector3Array) -> int:
	var n := 0
	for i in 3:
		var hit: Variant = Geometry3D.segment_intersects_triangle(
			edges[i], edges[(i + 1) % 3], face[0], face[1], face[2]
		)
		n += 1 if hit != null else 0
	return n
