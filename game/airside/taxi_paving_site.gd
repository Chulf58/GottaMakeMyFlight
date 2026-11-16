class_name TaxiPavingSite
extends RefCounted
## Lays TaxiPaving's mesh on the terminal site (decision site-paving-covers-
## only-the-owned-land-plots-and-grows-as-ea). The site's own paving covers
## only the land plots the player owns (OwnedPaving), so on the rest of the
## site a parked or taxiing plane rolls on the taxi paving: on_site() lays it
## SITE_DROP_M under the plane's ground height (PlaneView.ground_height_at(),
## y 0.2 over the whole site grid, ramping to 0 over PAVING_RAMP_M outside
## it), so the site's paving still hides it on owned land and a plane over
## land not yet owned neither floats nor sinks. Where it stands over the
## grass its edges get skirts down into the grass in the band's edge shade.

## How far under the plane's ground height the strips lie on the site: under
## the site's own paving (y 0.2) with their centre lines (LINE_LIFT_M higher).
const SITE_DROP_M := 0.015
## The terminal site whose ground PlaneView.ground_height_at() reads (PlaneView.SITE;
## PlaneView's own constants cannot be read here while it loads this script).
const SITE := preload("res://build/terminal_site.tres")
## The grass's top (main.tscn's Ground); a skirt reaches SKIRT_FOOT_M under it.
const GRASS_Y := -0.1
const SKIRT_FOOT_M := 0.02

## skirt_material(), made once.
static var _skirt_material: Material = null


## How far on_site() lifts the paving at `at` (world): SITE_DROP_M under the
## plane's ground height (PlaneView.ground_height_at()) on the site, going down
## with it along the ramp outside the site, and 0 off the site.
static func lift_at(at: Vector3) -> float:
	var ground := PlaneView.ground_height_at(at)
	if ground <= 0.0:
		return 0.0
	return ground * (1.0 - SITE_DROP_M / SITE.ground_height)


## `flat` (as mesh_of() builds it) laid on the site: each triangle cut along
## the lines where the plane's ground height starts or stops changing
## (_ramp_lines()), every vertex lifted by lift_at(), and a skirt down into the
## grass under every lifted outer edge of the asphalt and pads. So the asphalt
## follows the plane's ground height everywhere but in the 4 m squares off the
## site's corners, where the ramp is round and the cut takes straight values.
## The tops keep their upward normals (the ramp is under 3 degrees). A mesh
## wholly off the site comes back with the same vertices, order and indices.
static func on_site(flat: ArrayMesh) -> ArrayMesh:
	if flat.get_surface_count() == 0:
		return flat
	var arrays := flat.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var lines := _ramp_lines()
	var out_verts := PackedVector3Array()
	for v in verts:
		out_verts.append(v + Vector3.UP * lift_at(v))
	var out_normals := (arrays[Mesh.ARRAY_NORMAL] as PackedVector3Array).duplicate()
	var out_uvs := uvs.duplicate()
	var out_index := PackedInt32Array()
	# Each asphalt edge (flat positions): key -> [uses, a, b, its triangle's third corner].
	var edges := {}
	for t in range(0, index.size(), 3):
		var tri := PackedVector3Array([verts[index[t]], verts[index[t + 1]], verts[index[t + 2]]])
		var tri_uvs := PackedVector2Array([uvs[index[t]], uvs[index[t + 1]], uvs[index[t + 2]]])
		var asphalt := is_equal_approx(tri_uvs[0].x, TaxiPaving.ASPHALT_U)
		if not _crossed(tri, lines):
			out_index.append_array(PackedInt32Array([index[t], index[t + 1], index[t + 2]]))
			if asphalt:
				_note_edges(edges, tri)
			continue
		for piece: Array in _cut(tri, tri_uvs, lines):
			var pts: PackedVector3Array = piece[0]
			var piece_uvs: PackedVector2Array = piece[1]
			for k in range(1, pts.size() - 1):
				var base := out_verts.size()
				for j in [0, k, k + 1]:
					out_verts.append(pts[j] + Vector3.UP * lift_at(pts[j]))
					out_normals.append(Vector3.UP)
					out_uvs.append(piece_uvs[j])
				out_index.append_array(PackedInt32Array([base, base + 1, base + 2]))
				if asphalt:
					_note_edges(edges, PackedVector3Array([pts[0], pts[k], pts[k + 1]]))
	var skirt_verts := PackedVector3Array()
	var skirt_normals := PackedVector3Array()
	var skirt_uvs := PackedVector2Array()
	var skirt_index := PackedInt32Array()
	for key: String in edges:
		var edge: Array = edges[key]
		var a: Vector3 = edge[1]
		var b: Vector3 = edge[2]
		if edge[0] != 1 or maxf(lift_at(a), lift_at(b)) < TaxiPaving.SAME_M / 10.0:
			continue
		var top_a := a + Vector3.UP * lift_at(a)
		var top_b := b + Vector3.UP * lift_at(b)
		_add_skirt(top_a, top_b, edge[3], skirt_verts, skirt_normals, skirt_uvs, skirt_index)
	var out := ArrayMesh.new()
	_add_surface(out, out_verts, out_normals, out_uvs, out_index, TaxiPaving.MATERIAL)
	if not skirt_index.is_empty():
		_add_surface(out, skirt_verts, skirt_normals, skirt_uvs, skirt_index, skirt_material())
	return out


## The skirts' material: the paving's toon material without its outline pass.
## A skirt's outline is drawn at the skirt's depth, 1.5 to 3.5 cm under the
## site's own paving, but pushed a pixel or so up the screen, where the paving
## lies farther away, so it showed through owned paving as a dotted dark line
## (user ruling touching-owned-land-plots-pave-as-one-seamless-surface-no-lin).
static func skirt_material() -> Material:
	if _skirt_material == null:
		_skirt_material = TaxiPaving.MATERIAL.duplicate() as Material
		_skirt_material.next_pass = null
	return _skirt_material


static func _add_surface(
	mesh: ArrayMesh,
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	index: PackedInt32Array,
	material: Material
) -> void:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = index
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(mesh.get_surface_count() - 1, material)


## The x lines, then the z lines, where the plane's ground height starts or
## stops changing: the edges of the site grid (SiteDefinition.grid_rect(), the
## area PlaneView.ground_height_at() paves) and PAVING_RAMP_M outside them.
static func _ramp_lines() -> Array[Array]:
	var site: Rect2 = SITE.grid_rect()
	var low := site.position
	var high := site.end
	var ramp := PlaneView.paving_ramp_m()
	return [
		[low.x - ramp, low.x, high.x, high.x + ramp],
		[low.y - ramp, low.y, high.y, high.y + ramp],
	]


## Whether one of `lines` (_ramp_lines()) runs through the inside of `tri`
## where it reaches the site or its ramp; off them the lines change nothing.
static func _crossed(tri: PackedVector3Array, lines: Array[Array]) -> bool:
	var los: Array[float] = []
	var his: Array[float] = []
	for axis in 2:
		los.append(INF)
		his.append(-INF)
		for p in tri:
			los[axis] = minf(los[axis], _along(p, axis))
			his[axis] = maxf(his[axis], _along(p, axis))
		if his[axis] <= lines[axis][0] or los[axis] >= lines[axis][3]:
			return false
	for axis in 2:
		for at: float in lines[axis]:
			if (
				at > los[axis] + TaxiPaving.SAME_M / 20.0
				and at < his[axis] - TaxiPaving.SAME_M / 20.0
			):
				return true
	return false


## `tri` with its `tri_uvs` cut along every one of `lines`, as [points, uvs]
## convex pieces in the triangle's own winding.
static func _cut(
	tri: PackedVector3Array, tri_uvs: PackedVector2Array, lines: Array[Array]
) -> Array:
	var pieces: Array = [[tri, tri_uvs]]
	for axis in 2:
		for at: float in lines[axis]:
			var next: Array = []
			for piece: Array in pieces:
				next.append_array(_split(piece[0], piece[1], axis, at))
			pieces = next
	return pieces


## The convex polygon `pts` (with `pts_uvs`) cut along the line where its
## coordinate `axis` (0 x, 1 z) is `at`: one piece when the line misses its
## inside, else the piece on each side, each in the polygon's own winding.
static func _split(
	pts: PackedVector3Array, pts_uvs: PackedVector2Array, axis: int, at: float
) -> Array:
	var near := TaxiPaving.SAME_M / 20.0
	var below := false
	var above := false
	for p in pts:
		below = below or _along(p, axis) < at - near
		above = above or _along(p, axis) > at + near
	if not (below and above):
		return [[pts, pts_uvs]]
	var low_pts := PackedVector3Array()
	var low_uvs := PackedVector2Array()
	var high_pts := PackedVector3Array()
	var high_uvs := PackedVector2Array()
	for i in pts.size():
		var j := (i + 1) % pts.size()
		var here := _along(pts[i], axis) - at
		var there := _along(pts[j], axis) - at
		if here <= near:
			low_pts.append(pts[i])
			low_uvs.append(pts_uvs[i])
		if here >= -near:
			high_pts.append(pts[i])
			high_uvs.append(pts_uvs[i])
		if (here < -near and there > near) or (here > near and there < -near):
			var t := here / (here - there)
			var cut := pts[i].lerp(pts[j], t)
			if axis == 0:
				cut.x = at
			else:
				cut.z = at
			var cut_uv := pts_uvs[i].lerp(pts_uvs[j], t)
			low_pts.append(cut)
			low_uvs.append(cut_uv)
			high_pts.append(cut)
			high_uvs.append(cut_uv)
	var out: Array = []
	if low_pts.size() >= 3:
		out.append([low_pts, low_uvs])
	if high_pts.size() >= 3:
		out.append([high_pts, high_uvs])
	return out


## The coordinate `axis` (0 x, 1 z) of `p`.
static func _along(p: Vector3, axis: int) -> float:
	return p.x if axis == 0 else p.z


## Counts each edge of `tri` in `edges` (on_site()), keyed by its two ends to
## the millimetre, so an edge two triangles share counts twice.
static func _note_edges(edges: Dictionary, tri: PackedVector3Array) -> void:
	for i in 3:
		var a := tri[i]
		var b := tri[(i + 1) % 3]
		var key_a := str(Vector3i((a * 1000.0).round()))
		var key_b := str(Vector3i((b * 1000.0).round()))
		var key := key_a + "|" + key_b if key_a < key_b else key_b + "|" + key_a
		if edges.has(key):
			edges[key][0] += 1
		else:
			edges[key] = [1, a, b, tri[(i + 2) % 3]]


## Adds the skirt under the lifted edge `top_a` to `top_b`, from it down to
## SKIRT_FOOT_M under the grass, facing away from `inside` (a point of the
## asphalt it edges), in the band's edge shade.
static func _add_skirt(
	top_a: Vector3,
	top_b: Vector3,
	inside: Vector3,
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	index: PackedInt32Array
) -> void:
	var out := Vector3(top_b.z - top_a.z, 0.0, top_a.x - top_b.x).normalized()
	var middle := (top_a + top_b) / 2.0
	if out.dot(Vector3(inside.x - middle.x, 0.0, inside.z - middle.z)) > 0.0:
		out = -out
	var foot := GRASS_Y - SKIRT_FOOT_M
	var quad: Array[Vector3] = [
		top_a, top_b, Vector3(top_b.x, foot, top_b.z), Vector3(top_a.x, foot, top_a.z)
	]
	if (quad[2] - quad[0]).cross(quad[1] - quad[0]).dot(out) < 0.0:
		quad.reverse()
	var base := verts.size()
	for p in quad:
		verts.append(p)
		normals.append(out)
		uvs.append(Vector2(TaxiPaving.ASPHALT_U, TaxiPaving.ASPHALT_V_FROM))
	index.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
