class_name TaxiwayWorks
extends RefCounted
## Where the construction works stand (user ruling airside-construction-works-
## are-a-visible-stage-props-mark-th, point 5; board ecd67e67, S8b phase 2).
## Pure: every position is worked out from the geometry it is given, never at
## random, so two layouts from the same geometry are the same. Cosmetic only:
## nothing in the sim reads a layout. TaxiwayWorksView draws them.
##
## The works area is a rect: for a pending side spur the strip it will pave
## (side_layout(): TaxiPaving.WIDTH_M wide about the wanted x, over the z range
## of the side's current spur, spur_span()); for a runway upgrade the two pieces
## the runway grows by at its ends (runway_layout()). The area is cut by every
## live rect (live_rects(): each taxi strip and stand pad drawn now, and the
## runway's asphalt), each grown by CLEAR_M, so the works never touch the
## taxiway in use (pieces()). Each remaining piece at least MIN_PIECE_M across
## shows as unfinished ground, with a row of concrete barriers along each long
## edge at even spacing and a row of cones across each end (edge_props()), all
## inside the piece.
##
## One fenced yard (a loader, a dump trailer and a brick pile, behind hoarding
## on three sides) stands at a fixed spot beside the far end of the works: the
## first of a fixed list of spots (side: outward of the strip, then past its
## end, then inward; runway: north of the east piece, then north of the west
## piece, then south of the east piece) that is clear of every grown live rect.
## Its open side faces the works, with the brick pile just inside it, so the
## 2.45 m hoarding never stands between the works and the 1.5 m pile.
##
## Not guaranteed: the layout knows the taxiway, the pads and the runway, not
## the build. The yard spot outward of a side strip is beyond the outermost
## build by the strip's own clearance, so nothing is built there today, but a
## spot past the strip's end or inward is not checked against built cells.

const DIR := "res://assets/airside/props/works/"
## Prop kind -> [glb stem, footprint size (x, z) at yaw 0, footprint centre
## (x, z) from the node's origin at yaw 0], as the written glbs measure
## (test_taxiway_works_layout.gd checks them against the files).
const KINDS := {
	"cone": ["ti_traffic_cone_1b", Vector2(0.880, 0.880), Vector2(0.0, 0.0)],
	"barrier": ["tc_concrete_barrier_1a", Vector2(1.000, 3.900), Vector2(0.0, 0.0)],
	"fence": ["ti_metal_fence_1a", Vector2(3.932, 0.109), Vector2(0.026, -0.004)],
	"loader": ["ti_excavator_1a", Vector2(3.966, 7.409), Vector2(0.0, 1.149)],
	"bricks": ["ti_brick_pile_1c", Vector2(1.964, 2.038), Vector2(-0.005, 0.008)],
	"trailer": ["tfp_dump_trailer_01a", Vector2(7.551, 2.661), Vector2(3.667, 0.005)],
}
## How far every live rect is grown before the works are cut by it.
const CLEAR_M := 1.5
## A piece narrower than this either way is left out.
const MIN_PIECE_M := 6.0
## The barriers' centre spacing along an edge, at most.
const BARRIER_STEP_M := 8.0
## A barrier's or cone's centre from the piece's edge it stands along.
const EDGE_INSET_M := 0.75
## A barrier row stops this far from each end of its piece, clear of the cones.
const END_GAP_M := 2.5
## The cones' centre spacing across an end, at most.
const CONE_STEP_M := 3.0
## The yard: YARD_OPEN_M along its open side, YARD_DEEP_M back from it, and
## YARD_GAP_M off the works piece it stands beside.
const YARD_OPEN_M := 16.0
const YARD_DEEP_M := 12.0
const YARD_GAP_M := 3.0
## What stands in the yard, in its own frame: u along the open side (0 to
## YARD_OPEN_M), v back from it (0 to YARD_DEEP_M). [kind, Vector2(u, v) of the
## footprint centre, whether the long side runs along u]. Hoarding on the back
## and both ends, the pile 2.5 m inside the open side and 4.4 m off every
## panel, the loader and the trailer at the back.
const YARD_ITEMS := [
	["fence", Vector2(2.0, 11.9), true],
	["fence", Vector2(6.0, 11.9), true],
	["fence", Vector2(10.0, 11.9), true],
	["fence", Vector2(14.0, 11.9), true],
	["fence", Vector2(0.1, 2.0), false],
	["fence", Vector2(0.1, 6.0), false],
	["fence", Vector2(0.1, 10.0), false],
	["fence", Vector2(15.9, 2.0), false],
	["fence", Vector2(15.9, 6.0), false],
	["fence", Vector2(15.9, 10.0), false],
	["loader", Vector2(3.5, 6.5), false],
	["trailer", Vector2(10.5, 9.0), true],
	["bricks", Vector2(10.5, 3.5), false],
]


## Every rect the taxiway in use covers now: each strip of `strip_list` (as
## TaxiPaving.shown holds them; an oriented strip by its bounding rect), each
## pad of `pad_list`, and the asphalt of a `runway_size` runway.
static func live_rects(
	strip_list: Array[Dictionary], pad_list: Array[Rect2], runway_size: String
) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for strip in strip_list:
		out.append(strip["rect"])
	out.append_array(pad_list)
	out.append(runway_rect(runway_size))
	return out


## The asphalt of a `runway_size` runway, centred on x 0 on the runway line.
static func runway_rect(runway_size: String) -> Rect2:
	var piece: AABB = PlaneModels.PIECES[Airside.RUNWAY_PIECE]["aabb"]
	var length := Runway.length_m(runway_size)
	return Rect2(-length / 2.0, StandPlacement.RUNWAY_Z + piece.position.z, length, piece.size.z)


## The z range (north, south) of the spur at `spur_x` in `strip_list`: its
## north-south strip that runs through the lane's square. A side without one
## (no side stand) gets the runway's south edge to the lane's south edge.
static func spur_span(strip_list: Array[Dictionary], spur_x: float) -> Vector2:
	for strip in strip_list:
		var rect: Rect2 = strip["rect"]
		if strip.get("through", false) and absf(rect.get_center().x - spur_x) < TaxiPaving.SAME_M:
			return Vector2(rect.position.y, rect.end.y)
	return Vector2(Airside.runway_south(), StandPlacement.TAXI_LANE_Z + TaxiPaving.WIDTH_M / 2.0)


## The works of `side`'s spur pending to move to `wanted_x`: the strip it will
## pave over `span` (spur_span()), cut by `live` (live_rects()). {"ground":
## Array[Rect2], "props": Array[Dictionary] (prop()), "yard": Rect2, empty
## when no spot is clear}.
static func side_layout(
	side: String, wanted_x: float, span: Vector2, live: Array[Rect2]
) -> Dictionary:
	var half := TaxiPaving.WIDTH_M / 2.0
	var strip := Rect2(wanted_x - half, span.x, TaxiPaving.WIDTH_M, span.y - span.x)
	var ground := pieces(strip, live)
	var out := _with_edges(ground)
	if ground.is_empty():
		return out
	var far := ground[0]
	for piece in ground:
		if piece.end.y > far.end.y:
			far = piece
	var out_x := float(SideSpurs.OUT[side])
	var outer := far.end.x if out_x > 0.0 else far.position.x
	var inner := far.position.x if out_x > 0.0 else far.end.x
	var back := Vector2(out_x, 0.0)
	var north := Vector2(0.0, -1.0)
	var spots: Array[Array] = [
		[Vector2(outer + out_x * YARD_GAP_M, far.end.y), north, back],
		[
			Vector2(far.get_center().x - out_x * YARD_OPEN_M / 2.0, far.end.y + YARD_GAP_M),
			back,
			Vector2(0.0, 1.0),
		],
		[Vector2(inner - out_x * YARD_GAP_M, far.end.y), north, -back],
	]
	_add_yard(out, spots, live)
	return out


## The works of a runway upgrade from `size_now` to `size_next`: the two pieces
## the runway grows by at its ends, cut by `live`, as side_layout() returns.
static func runway_layout(size_now: String, size_next: String, live: Array[Rect2]) -> Dictionary:
	var now := runway_rect(size_now)
	var next := runway_rect(size_next)
	var grow := now.position.x - next.position.x
	var ground: Array[Rect2] = []
	if grow > 0.0:
		var west := Rect2(next.position.x, next.position.y, grow, next.size.y)
		var east := Rect2(now.end.x, next.position.y, grow, next.size.y)
		ground.append_array(pieces(west, live))
		ground.append_array(pieces(east, live))
	var out := _with_edges(ground)
	if ground.is_empty():
		return out
	var west_dir := Vector2(-1.0, 0.0)
	var north_of := next.position.y - YARD_GAP_M
	var spots: Array[Array] = [
		[Vector2(next.end.x, north_of), west_dir, Vector2(0.0, -1.0)],
		[Vector2(next.position.x, north_of), -west_dir, Vector2(0.0, -1.0)],
		[Vector2(next.end.x, next.end.y + YARD_GAP_M), west_dir, Vector2(0.0, 1.0)],
	]
	_add_yard(out, spots, live)
	return out


## `area` less every rect of `blocked` grown by CLEAR_M, as rects at least
## MIN_PIECE_M across. Each cut keeps the full-width parts north and south of
## the cut and the parts west and east of it beside it, in that order.
static func pieces(area: Rect2, blocked: Array[Rect2]) -> Array[Rect2]:
	var out: Array[Rect2] = [area]
	for rect in blocked:
		var cut := rect.grow(CLEAR_M)
		var kept: Array[Rect2] = []
		for piece in out:
			kept.append_array(_minus(piece, cut))
		out = kept
	var big: Array[Rect2] = []
	for piece in out:
		if piece.size.x >= MIN_PIECE_M and piece.size.y >= MIN_PIECE_M:
			big.append(piece)
	return big


## `piece` less `cut`: up to four rects (north, south, west, east).
static func _minus(piece: Rect2, cut: Rect2) -> Array[Rect2]:
	if not piece.intersects(cut):
		return [piece]
	var inside := piece.intersection(cut)
	var parts: Array[Rect2] = [
		Rect2(
			piece.position.x, piece.position.y, piece.size.x, inside.position.y - piece.position.y
		),
		Rect2(piece.position.x, inside.end.y, piece.size.x, piece.end.y - inside.end.y),
		Rect2(
			piece.position.x, inside.position.y, inside.position.x - piece.position.x, inside.size.y
		),
		Rect2(inside.end.x, inside.position.y, piece.end.x - inside.end.x, inside.size.y),
	]
	var out: Array[Rect2] = []
	for part in parts:
		if part.size.x > 0.0 and part.size.y > 0.0:
			out.append(part)
	return out


## The barriers along both long edges of `piece` at even spacing, at most
## BARRIER_STEP_M apart and END_GAP_M off each end, and the cones across both
## ends at most CONE_STEP_M apart.
static func edge_props(piece: Rect2) -> Array[Dictionary]:
	var along_x := piece.size.x > piece.size.y
	var axis := 0 if along_x else 1
	var cross := 1 - axis
	var lo := piece.position
	var hi := piece.end
	var out: Array[Dictionary] = []
	var length: float = KINDS["barrier"][1].y
	for edge: float in [lo[cross] + EDGE_INSET_M, hi[cross] - EDGE_INSET_M]:
		var from := lo[axis] + END_GAP_M + length / 2.0
		var to := hi[axis] - END_GAP_M - length / 2.0
		for at in _even(from, to, BARRIER_STEP_M):
			out.append(prop("barrier", _point(axis, at, edge), along_x))
	for end: float in [lo[axis] + EDGE_INSET_M, hi[axis] - EDGE_INSET_M]:
		var from := lo[cross] + EDGE_INSET_M
		var to := hi[cross] - EDGE_INSET_M
		for at in _even(from, to, CONE_STEP_M):
			out.append(prop("cone", _point(cross, at, end), false))
	return out


## Points from `from` to `to`, both included, evenly spaced at most `step`
## apart; the one point when they are equal, none when `to` is before `from`.
static func _even(from: float, to: float, step: float) -> Array[float]:
	var out: Array[float] = []
	if to < from:
		return out
	var count := ceili((to - from) / step) + 1
	if count < 2:
		out.append((from + to) / 2.0)
		return out
	for i in count:
		out.append(lerpf(from, to, float(i) / float(count - 1)))
	return out


## The world point (x, z) with `at` on `axis` (0 x, 1 z) and `other` on the other.
static func _point(axis: int, at: float, other: float) -> Vector2:
	return Vector2(at, other) if axis == 0 else Vector2(other, at)


## A prop of `kind` whose footprint is centred on `centre` (world x, z) with its
## long side along x when `along_x`: {"kind", "centre", "yaw": 0 or PI/2,
## "rect": its footprint, "origin": Vector2 where its node's origin goes}.
static func prop(kind: String, centre: Vector2, along_x: bool) -> Dictionary:
	var size: Vector2 = KINDS[kind][1]
	var offset: Vector2 = KINDS[kind][2]
	var native_x := size.x > size.y
	var yaw := 0.0
	if native_x != along_x and not is_equal_approx(size.x, size.y):
		yaw = PI / 2.0
		size = Vector2(size.y, size.x)
		# A quarter turn about +y takes a local (x, z) to (z, -x).
		offset = Vector2(offset.y, -offset.x)
	return {
		"kind": kind,
		"centre": centre,
		"yaw": yaw,
		"rect": Rect2(centre - size / 2.0, size),
		"origin": centre - offset,
	}


## `ground` with the edge_props() of each piece: a layout with no yard yet.
static func _with_edges(ground: Array[Rect2]) -> Dictionary:
	var props: Array[Dictionary] = []
	for piece in ground:
		props.append_array(edge_props(piece))
	return {"ground": ground, "props": props, "yard": Rect2()}


## Adds the yard at the first of `spots` clear of every rect of `live` grown by
## CLEAR_M to `layout`. A spot is [the corner where the open side starts, the
## unit direction along the open side (u), the unit direction back from it (v)].
static func _add_yard(layout: Dictionary, spots: Array[Array], live: Array[Rect2]) -> void:
	for spot in spots:
		var corner: Vector2 = spot[0]
		var u: Vector2 = spot[1]
		var v: Vector2 = spot[2]
		var far := corner + u * YARD_OPEN_M + v * YARD_DEEP_M
		var rect := Rect2(corner, Vector2.ZERO).expand(far)
		var clear := true
		for rect_live in live:
			if rect.intersects(rect_live.grow(CLEAR_M)):
				clear = false
				break
		if not clear:
			continue
		layout["yard"] = rect
		for item: Array in YARD_ITEMS:
			var at: Vector2 = item[1]
			var long: Vector2 = u if item[2] else v
			var centre := corner + u * at.x + v * at.y
			layout["props"].append(prop(item[0], centre, absf(long.x) > 0.5))
		return
