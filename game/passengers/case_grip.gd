class_name CaseGrip
extends RefCounted
## Where a hand holds a hard case in the side carry, read from the case's body
## mesh (CarryOnProps.grip_anchor(); kept out of carry_on_props.gd, at its line
## cap). The case's handle is in the middle of its handle face, so the corner
## of its bounds (the handle face's height at the top end) is in the air, 4.7 cm
## off the chamfered top edge; the hand holds that edge instead.

## Two vertex coordinates this close are the same.
const SAME_M := 0.001

static var _edge := Vector3.INF


## CarryOnProps.grip_anchor() of a hard case (edge()) or a shoulder bag (its
## bounds' top edge, unchanged).
static func anchor(kind: SecurityLooks.Kind) -> Vector3:
	if kind == SecurityLooks.Kind.CASE:
		return edge()
	var box := CarryOnProps.bag_box(kind)
	return Vector3(0.0, box.end.y, box.end.z)


## The middle of the hard case's top edge on its handle face, in its own frame
## (scale 1): of the body mesh's vertices past the top end's own height (its
## chamfer and its handle face, the top end's face left out), the ones furthest
## up its length, their height their highest, midway across.
static func edge() -> Vector3:
	if not _edge.is_finite():
		var piece := InteriorKit.instantiate(SecurityLooks.KIND_PIECES[SecurityLooks.Kind.CASE])
		var body := piece.find_child("CarryOnBag_Body", true, false) as MeshInstance3D
		var xf := Transform3D.IDENTITY
		var at: Node = body
		while at != null and at != piece:
			xf = (at as Node3D).transform * xf
			at = at.get_parent()
		_edge = edge_of(body.mesh, xf)
		piece.free()
	return _edge


## The middle of a case's top edge on its handle face (edge()) for body mesh
## `mesh` drawn with `xf` in the case's frame.
static func edge_of(mesh: Mesh, xf: Transform3D) -> Vector3:
	var points: Array[Vector3] = []
	for v: Vector3 in mesh.get_faces():
		points.append(xf * v)
	var top := -INF
	for p in points:
		top = maxf(top, p.z)
	var end_high := -INF
	for p in points:
		if p.z > top - SAME_M:
			end_high = maxf(end_high, p.y)
	var past: Array[Vector3] = points.filter(
		func(p: Vector3) -> bool: return p.y > end_high + SAME_M
	)
	var along := -INF
	for p in past:
		along = maxf(along, p.z)
	var high := -INF
	var across := Vector2(INF, -INF)
	for p in past:
		if p.z > along - SAME_M:
			high = maxf(high, p.y)
			across = Vector2(minf(across.x, p.x), maxf(across.y, p.x))
	return Vector3((across.x + across.y) * 0.5, high, along)
