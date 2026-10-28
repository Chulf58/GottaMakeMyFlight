class_name InteriorKit
extends RefCounted
## The interior kit pieces (game/assets/interior/) the build view draws, and
## which piece and local transform each wall kind and object uses. A piece is
## named by its .glb basename; pieces load once and are cached.
##
## Every piece's pivot is at height 0 on its footprint centre (walls on the
## cell edge, posts on the vertex), front +Z at facing 0, so a piece goes in at
## the grid transform with no offset.

enum WallKind { PLAIN, GLASS, DOOR }

const PIECE_PATH := "res://assets/interior/%s.glb"
## Height of a cut-away wall or post.
const STUB_HEIGHT := 0.3
const WALL_HEIGHT := 2.5
const POST_HEIGHT := 2.54
## Top of the glass wall's trim kerb: a cut glass wall keeps only the kerb.
const GLASS_KERB_TOP := 0.22
## Piece made at run time from wall_glass: its kerb only.
const GLASS_KERB := "wall_glass_kerb"
## A cut door keeps two short jambs, each a plain wall stub this wide, centred
## this far either side of the door axis (the 0.8 m opening stays clear).
const JAMB_WIDTH := 0.1
const JAMB_OFFSET := 0.45
const OBJECT_PIECES := {
	&"checkin_desk": "checkin_desk",
	&"security_scanner": "security_scanner",
	&"seat_row": "seat_row",
	&"entrance_door": "wall_door",
	&"exit_door": "wall_door",
	&"cafe_counter": "cafe_counter",
	&"cafe_table": "cafe_table",
	&"baggage_belt": "baggage_belt",
	&"baggage_belt_corner": "baggage_belt_corner",
	&"baggage_belt_feed": "baggage_belt_feed",
	&"baggage_belt_end": "baggage_belt_end",
	&"baggage_cart": "baggage_cart",
	&"security_arch": "security_arch",
	&"tray_table": "tray_table",
	&"xray_belt": "xray_belt",
	&"pickup_table": "pickup_table",
}
## Where a piece sits in its object's frame (footprint centre, facing 0), for
## objects whose piece is not centred on the footprint. The entrance and exit
## draw a door on their back edge, the way out.
const OBJECT_OFFSETS := {
	&"entrance_door": Vector3(0.0, 0.0, -0.5),
	&"exit_door": Vector3(0.0, 0.0, -0.5),
}
const WALL_PIECES := {
	WallKind.PLAIN: "wall",
	WallKind.GLASS: "wall_glass",
	WallKind.DOOR: "wall_door",
}

## piece name -> Array of [Mesh, Transform3D relative to the piece root].
static var _meshes: Dictionary = {}


## The piece an object type is drawn with, or "" when the kit has none.
static func object_piece(def_id: StringName) -> String:
	return OBJECT_PIECES.get(def_id, "")


## The offset of an object's piece in the object's frame (zero for most).
static func object_offset(def_id: StringName) -> Vector3:
	return OBJECT_OFFSETS.get(def_id, Vector3.ZERO)


## The parts a wall edge draws, as [piece, local transform] pairs in the
## edge's own frame (wall_transform). A cut plain wall is the wall scaled to
## STUB_HEIGHT; a cut glass wall is its kerb; a cut door is two jamb stubs.
static func wall_parts(kind: WallKind, cut: bool) -> Array:
	if not cut:
		return [[WALL_PIECES[kind], Transform3D.IDENTITY]]
	var stub := Basis.from_scale(Vector3(1.0, STUB_HEIGHT / WALL_HEIGHT, 1.0))
	match kind:
		WallKind.GLASS:
			return [[GLASS_KERB, Transform3D.IDENTITY]]
		WallKind.DOOR:
			var jamb := Basis.from_scale(Vector3(JAMB_WIDTH, STUB_HEIGHT / WALL_HEIGHT, 1.0))
			return [
				["wall", Transform3D(jamb, Vector3(-JAMB_OFFSET, 0.0, 0.0))],
				["wall", Transform3D(jamb, Vector3(JAMB_OFFSET, 0.0, 0.0))],
			]
	return [["wall", Transform3D(stub, Vector3.ZERO)]]


## The post at a wall vertex: full height, or scaled to STUB_HEIGHT.
static func post_parts(cut: bool) -> Array:
	if not cut:
		return [["wall_post", Transform3D.IDENTITY]]
	var stub := Basis.from_scale(Vector3(1.0, STUB_HEIGHT / POST_HEIGHT, 1.0))
	return [["wall_post", Transform3D(stub, Vector3.ZERO)]]


## A fresh node tree of a piece, with its own toon materials.
static func instantiate(piece: String) -> Node3D:
	return (load(PIECE_PATH % piece) as PackedScene).instantiate()


## The meshes of a piece with each one's transform relative to the piece root
## (the door leaves sit on offset nodes), for multimesh drawing.
static func meshes(piece: String) -> Array:
	if _meshes.has(piece):
		return _meshes[piece]
	var parts: Array = []
	if piece == GLASS_KERB:
		for part in meshes(WALL_PIECES[WallKind.GLASS]):
			parts.append([kerb_mesh(part[0], GLASS_KERB_TOP), part[1]])
	else:
		var root := instantiate(piece)
		for mi in root.find_children("*", "MeshInstance3D", true, false):
			var local: Transform3D = (mi as MeshInstance3D).transform
			var parent := mi.get_parent()
			while parent != root:
				local = (parent as Node3D).transform * local
				parent = parent.get_parent()
			parts.append([(mi as MeshInstance3D).mesh, local])
		root.free()
	_meshes[piece] = parts
	return parts


## Surface arrays holding only the vertices `index` uses, renumbered, so the
## mesh bounds cover just the kept triangles.
static func _compact(arrays: Array, index: PackedInt32Array) -> Array:
	var remap := {}
	var order: Array[int] = []
	var new_index := PackedInt32Array()
	for i in index:
		if not remap.has(i):
			remap[i] = order.size()
			order.append(i)
		new_index.append(remap[i])
	var count: int = (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
	var out := []
	out.resize(Mesh.ARRAY_MAX)
	for k in Mesh.ARRAY_MAX:
		if k == Mesh.ARRAY_INDEX or arrays[k] == null:
			continue
		var source: Variant = arrays[k]
		var stride: int = source.size() / count
		var picked: Variant = source.slice(0, 0)
		for i in order:
			picked.append_array(source.slice(i * stride, i * stride + stride))
		out[k] = picked
	out[Mesh.ARRAY_INDEX] = new_index
	return out


## A copy of `mesh` holding only the triangles at or below `top`, less any
## downward face lying flat on `top` (the bottoms of the parts above it).
## Vertex data and surface materials are kept as they are.
static func kerb_mesh(mesh: Mesh, top: float) -> ArrayMesh:
	const EPS := 0.002
	var out := ArrayMesh.new()
	for i in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(i)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var kept := PackedInt32Array()
		for t in range(0, index.size(), 3):
			var ys := [verts[index[t]].y, verts[index[t + 1]].y, verts[index[t + 2]].y]
			if ys.max() > top + EPS:
				continue
			var down := normals[index[t]].y + normals[index[t + 1]].y + normals[index[t + 2]].y
			if ys.min() >= top - EPS and down < 0.0:
				continue
			kept.append_array([index[t], index[t + 1], index[t + 2]])
		if kept.is_empty():
			continue
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _compact(arrays, kept))
		out.surface_set_material(out.get_surface_count() - 1, mesh.surface_get_material(i))
	return out
