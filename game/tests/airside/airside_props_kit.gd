extends RefCounted
## Shared set-up for the airside props tests (board 4c08b8e5): the real Airside
## markers and links from main.tscn's saved state, without instancing the
## scene, and a plane model parked or posed as PlaneView draws it.

const MAIN_SCENE := "res://main/main.tscn"


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


## The smallest gap from a vertex of `a`'s visible meshes to the bounds of one
## of `b`'s, each box in its own mesh's frame: {"gap" (metres, 0 inside a box),
## "a_mesh", "b_mesh"}. The boxes hold their meshes, so the gap never exceeds
## the true clearance, and a part of `a` lying wholly inside `b` (which
## crossings() cannot see) reads 0.
static func clearance(a: Node3D, b: Node3D) -> Dictionary:
	var boxes: Array[Dictionary] = []
	for mi: MeshInstance3D in b.find_children("*", "MeshInstance3D", true, false):
		if mi.is_visible_in_tree() and mi.mesh != null:
			boxes.append({"inv": mi.global_transform.affine_inverse(), "box": mi.get_aabb()})
			boxes[-1]["mesh"] = String(mi.name)
	var out := {"gap": INF, "a_mesh": "", "b_mesh": ""}
	for mi: MeshInstance3D in a.find_children("*", "MeshInstance3D", true, false):
		if not mi.is_visible_in_tree() or mi.mesh == null:
			continue
		for v in mi.mesh.get_faces():
			var w := mi.global_transform * v
			for entry: Dictionary in boxes:
				var box: AABB = entry["box"]
				var p: Vector3 = entry["inv"] * w
				var gap := (p.clamp(box.position, box.end) - p).length()
				if gap < out["gap"]:
					out = {"gap": gap, "a_mesh": String(mi.name), "b_mesh": entry["mesh"]}
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
