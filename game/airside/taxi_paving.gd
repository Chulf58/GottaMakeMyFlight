class_name TaxiPaving
extends MeshInstance3D
## The asphalt under every taxi route, so a plane never taxis on grass (user
## ruling pave-the-taxi-lane-and-the-link-from-each-stand-to-it-so-pla). Airside
## gives it the routes its planes follow (taxi in, pushback, taxi out, for the
## one stand or for each gate) after every rebuild, so the paving follows the
## stands as they move and as gates come and go. It is visual only: nothing in
## the sim reads it.
##
## The taxi lane is one strip from the westmost to the eastmost route point on
## it; every other route leg (runway to lane, lane to stand) is a strip of its
## own that stops at the lane's edge, so no two strips overlap and none fights
## another for depth. A leg's runway end lies under the runway, whose asphalt
## is HEIGHT_M above this, and a stand's end under the site's paving.
##
## The look is the runway's: the same toon material and the same atlas column,
## which runs dark at the edges and light down the middle across one 30 m band
## of the runway. The strips are flat and face up, so the toon outline pass
## (cull_front) draws no seam where they meet.
##
## The lane's band runs across z and a link's across x, so a link's light middle
## would butt the lane's dark edge where the two meet (board 1d61370e). The lane
## under each link that meets its edge is mitred instead (junctions()): in each
## half of the lane the band follows the nearest centre line, the lane's or a
## link's on that edge, so a link's band runs on into the lane up to the
## diagonals from its centre. Two links on one edge closer than WIDTH_M (gates
## can stand 19 m apart) share the lane at their midpoint, and their strips are
## drawn only up to it where both run (_drawn_rects()). The band is symmetric about its middle,
## so at every diagonal and midpoint both sides give the same shade.
##
## A thin centre line runs along the lane and each link (user ruling taxiway-
## look-runway-asphalt-with-a-yellow-centreline), in the runway's own line
## marking colour and LINE_LIFT_M above the asphalt, as the runway's markings
## sit over its own. A link's line stops at the lane line's edge and the lane
## line runs half a line width past its end links, so the lines meet in a
## square T or L and never overlap.
##
## A route leg that is neither north-south nor east-west gets an oriented strip
## of its own, WIDTH_M wide with square ends, carrying its centre line in the
## same dict ("quad", "ts" and "line" in strips()). It is not merged with other
## strips and may overlap them; every taxiway on the airside today is axis-
## aligned, so this only keeps a future diagonal leg from being left unpaved.
##
## Each stand gets a pad (stand_pad()), so a parked plane of every class the
## gate takes sits on asphalt from nose to tail and the turn at the end of its
## pushback stays on it: for each class up to the gate's max_class (Airside.
## stand_pads()), the class's swing square (StandEnvelope) merged with each of
## its models' parked footprints (door-aligned, PlaneClasses.stand_offset),
## carried south to the stand's wall line, where the site's paving starts for a
## north-row stand. A pad never paves a larger class's space, where the player
## may still build (decision runway-and-taxi-technical-design-movement-plan-
## analytic-bookings-planned-pauses, point 3).
## Pads lie PAD_DROP_M under the strips in one flat shade, the asphalt band's
## edge, so a strip's band runs over a pad as a lead-in, and two neighbours'
## pads overlap in the same colour without a visible seam.
##
## Each hold line (Airside.hold_points()) gets a yellow hold bar across its
## leg: two HOLD_LINE_M lines HOLD_GAP_M apart, centred on the hold point, in
## the centre line's colour and height. Every hold line sits on a north-south
## leg, so a bar runs east-west across the strip's width. HoldIn and HoldRunway
## lie 2 m inside the runway's 64 m wide asphalt, which would hide a bar there,
## so their bars sit just south of it (hold_bars()).

const WIDTH_M := 30.0
## Height of the paving's top. The runway's asphalt lies at y 0.1 and the
## site's paving at y 0.2, so both cover the strips' ends; the grass is y -0.1.
const HEIGHT_M := 0.0
const MATERIAL := preload("res://assets/materials/tp_atlas_simple_toon.tres")
## The runway's asphalt in the atlas: one column, the v range across one band.
const ASPHALT_U := 0.5047
const ASPHALT_V_FROM := 0.0010
const ASPHALT_V_TO := 0.0614
## The centre line: its width, its height over the asphalt (the runway's own
## markings sit 0.007 m over its asphalt), and the atlas point of the runway's
## line marking colour (the pale yellow of its edge lines and chevrons).
const LINE_WIDTH_M := 0.5
const LINE_LIFT_M := 0.01
const MARKING_UV := Vector2(0.6083, 0.0067)
## How far apart two values may be and still count as the same, in metres.
const SAME_M := 0.01
## How far the stand pads lie under the strips, still over the grass (y -0.1).
const PAD_DROP_M := 0.02
## A hold bar's two lines: each line's depth along the leg and the gap between.
const HOLD_LINE_M := 0.5
const HOLD_GAP_M := 0.5

## The strips last built, as returned by strips().
var shown: Array[Dictionary] = []
## The centre lines last built, as returned by centrelines().
var lines: Array[Rect2] = []
## The stand pads last built, one per stand (stand_pad()).
var pads: Array[Rect2] = []
## The hold bar lines last built (hold_bars()).
var bars: Array[Rect2] = []


func _init() -> void:
	name = "TaxiPaving"
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Builds the mesh for `routes` (world points) around the lane at `lane_z`,
## with the stand pads `pad_list` (stand_pad()) and a hold bar at each of
## `holds`, kept clear of the runway asphalt south to `runway_south_z`.
func show_routes(
	routes: Array[PackedVector3Array],
	lane_z: float,
	pad_list: Array[Rect2] = [],
	holds := PackedVector3Array(),
	runway_south_z := -INF
) -> void:
	shown = strips(routes, lane_z)
	lines = centrelines(shown, lane_z)
	pads = pad_list.duplicate()
	bars = hold_bars(holds, WIDTH_M, runway_south_z)
	var marks := lines.duplicate()
	marks.append_array(bars)
	mesh = mesh_of(shown, marks, pads)


## The pad under the stand whose plane point is `stand_point`, as a world xz
## Rect2: for each of `classes`, the class's swing square (StandEnvelope.rects())
## and the parked footprint (PlaneModels bounds) of each of its models, door-
## aligned on the stand and nose to +z, merged and carried south to the wall
## line the stand faces.
static func stand_pad(stand_point: Vector3, classes := PlaneClasses.ORDER) -> Rect2:
	var wall_z := stand_point.z + StandPlacement.NOSE_GAP_M + StandPlacement.NOSE_M
	var stand := StandPlacement.make(0, stand_point.x + StandPlacement.DOOR_SIDE_M, wall_z)
	var pad := Rect2(stand_point.x, wall_z, 0.0, 0.0)
	for plane_class in classes:
		pad = pad.merge(StandEnvelope.rects(stand, plane_class)[0])
		for model: String in PlaneClasses.CLASSES[plane_class]["models"]:
			pad = pad.merge(parked_footprint(stand_point, model))
	return pad


## The ground under `model` parked at the stand point `stand_point`, door-aligned
## (PlaneClasses.stand_offset) and nose to +z, as a world xz Rect2.
static func parked_footprint(stand_point: Vector3, model: String) -> Rect2:
	var shape: Dictionary = PlaneModels.PLANES[model]
	var origin := stand_point + PlaneClasses.stand_offset(model)
	var half: float = shape["half_span"]
	var tail: float = shape["tail"]
	var nose: float = shape["nose"]
	return Rect2(origin.x - half, origin.z - tail, 2.0 * half, tail + nose)


## The two lines of a hold bar across a north-south leg at each of `holds`,
## `width` wide in x, centred on the hold point along the leg. A bar that would
## reach north of `clear_of_z` (the runway asphalt's south edge, which lies over
## the paving and would hide it) is moved south until its north line starts
## HOLD_GAP_M clear of it.
static func hold_bars(
	holds: PackedVector3Array, width := WIDTH_M, clear_of_z := -INF
) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var reach := HOLD_GAP_M / 2.0 + HOLD_LINE_M
	for at in holds:
		var z := maxf(at.z, clear_of_z + HOLD_GAP_M + reach)
		out.append(Rect2(at.x - width / 2.0, z - reach, width, HOLD_LINE_M))
		out.append(Rect2(at.x - width / 2.0, z + HOLD_GAP_M / 2.0, width, HOLD_LINE_M))
	return out


## Whether (x, z) of `point` lies on one of `strip_list`'s strips or one of
## `pad_list`'s pads.
static func paved(strip_list: Array[Dictionary], pad_list: Array[Rect2], point: Vector3) -> bool:
	if covers(strip_list, point):
		return true
	var at := Vector2(point.x, point.z)
	for pad in pad_list:
		if pad.grow(SAME_M).has_point(at):
			return true
	return false


## The strips covering `routes`: each {"rect": Rect2 of world x and z,
## "across_x": true when the band runs north-south}. Legs on the lane at
## `lane_z` make one lane strip; legs at the same x make one strip.
static func strips(
	routes: Array[PackedVector3Array], lane_z: float, width := WIDTH_M
) -> Array[Dictionary]:
	var half := width / 2.0
	var lane_x := Vector2(INF, -INF)
	# x in SAME_M steps -> {"x": the legs' x, "spans": merged z ranges (from, to)}.
	var columns: Dictionary = {}
	var oriented: Array[Dictionary] = []
	for route in routes:
		for i in range(1, route.size()):
			var a := route[i - 1]
			var b := route[i]
			if absf(a.z - b.z) < SAME_M and absf(a.z - lane_z) < SAME_M:
				lane_x = Vector2(minf(lane_x.x, minf(a.x, b.x)), maxf(lane_x.y, maxf(a.x, b.x)))
			elif absf(a.x - b.x) < SAME_M:
				_add_leg(columns, a.x, a.z, b.z, lane_z, half)
			elif not a.is_equal_approx(b):
				oriented.append(_oriented(Vector2(a.x, a.z), Vector2(b.x, b.z), half))
	var out: Array[Dictionary] = []
	if lane_x.x <= lane_x.y:
		(
			out
			. append(
				{
					"rect":
					Rect2(lane_x.x - half, lane_z - half, lane_x.y - lane_x.x + width, width),
					"across_x": false,
				}
			)
		)
	var xs := columns.keys()
	xs.sort()
	for key: int in xs:
		var x: float = columns[key]["x"]
		for span: Vector2 in columns[key]["spans"]:
			(
				out
				. append(
					{
						"rect": Rect2(x - half, span.x, width, span.y - span.x),
						"across_x": true,
					}
				)
			)
	out.append_array(oriented)
	return out


## The strip of a leg from `a` to `b` (world x and z) that is neither north-south
## nor east-west: {"rect": its bounding Rect2, "across_x": false, "quad": its four
## corners clockwise seen from above, "ts": each corner's position across the
## band (0 to 1), "line": the corners of its centre line}.
static func _oriented(a: Vector2, b: Vector2, half: float) -> Dictionary:
	var dir := (b - a).normalized()
	var side := Vector2(-dir.y, dir.x)
	var quad: Array[Vector2] = [a + side * half, b + side * half, b - side * half, a - side * half]
	var ts: Array[float] = [0.0, 0.0, 1.0, 1.0]
	var half_line := LINE_WIDTH_M / 2.0
	var line: Array[Vector2] = [
		a + side * half_line, b + side * half_line, b - side * half_line, a - side * half_line
	]
	if _signed_area(quad) < 0.0:
		quad.reverse()
		ts.reverse()
		line.reverse()
	var rect := Rect2(quad[0], Vector2.ZERO)
	for corner in quad:
		rect = rect.expand(corner)
	return {"rect": rect, "across_x": false, "quad": quad, "ts": ts, "line": line}


## Twice the area of `corners` seen in the x-z plane, positive when they run in
## the order _corners_of gives a Rect2 (the front face seen from above).
static func _signed_area(corners: Array[Vector2]) -> float:
	var total := 0.0
	for i in corners.size():
		var next := corners[(i + 1) % corners.size()]
		total += corners[i].x * next.y - next.x * corners[i].y
	return total


## Adds the north-south leg at `x` from `z0` to `z1` to `columns`, its end on
## the lane cut back to the lane's edge, merged with the legs it meets.
static func _add_leg(
	columns: Dictionary, x: float, z0: float, z1: float, lane_z: float, half: float
) -> void:
	var lo := minf(z0, z1)
	var hi := maxf(z0, z1)
	if absf(lo - lane_z) < SAME_M:
		lo = lane_z + half
	if absf(hi - lane_z) < SAME_M:
		hi = lane_z - half
	if hi - lo < SAME_M:
		return
	var key := roundi(x / SAME_M)
	var column: Dictionary = columns.get(key, {"x": x, "spans": []})
	var spans: Array = column["spans"]
	var merged := Vector2(lo, hi)
	var kept: Array = []
	for span: Vector2 in spans:
		if span.x <= merged.y + SAME_M and merged.x <= span.y + SAME_M:
			merged = Vector2(minf(span.x, merged.x), maxf(span.y, merged.y))
		else:
			kept.append(span)
	kept.append(merged)
	kept.sort_custom(func(p: Vector2, q: Vector2) -> bool: return p.x < q.x)
	column["spans"] = kept
	columns[key] = column


## The centre line of each strip in `strip_list` (as strips() returns them,
## around the lane at `lane_z`), `line` wide. The lane's line runs from its
## end links' centres plus half a line; a link's end at the lane's edge is
## carried to the lane line's edge, so the two butt without overlapping. An
## oriented strip has its own line and gets none here.
static func centrelines(
	strip_list: Array[Dictionary], lane_z: float, width := WIDTH_M, line := LINE_WIDTH_M
) -> Array[Rect2]:
	var half := width / 2.0
	var half_line := line / 2.0
	var out: Array[Rect2] = []
	for strip in strip_list:
		if strip.has("quad"):
			continue
		var rect: Rect2 = strip["rect"]
		if not strip["across_x"]:
			var from_x := rect.position.x + half - half_line
			var to_x := rect.end.x - half + half_line
			out.append(Rect2(from_x, rect.get_center().y - half_line, to_x - from_x, line))
			continue
		var north := rect.position.y
		var south := rect.end.y
		if absf(south - (lane_z - half)) < SAME_M:
			south = lane_z - half_line
		if absf(north - (lane_z + half)) < SAME_M:
			north = lane_z + half_line
		out.append(Rect2(rect.get_center().x - half_line, north, line, south - north))
	return out


## One flat, upward quad per strip, its atlas band running across the strip,
## and one per centre line in `line_list`, LINE_LIFT_M higher, in the marking
## colour. An oriented strip (strips() gives it "quad") brings its own line.
## Each of `pad_list` is one flat quad PAD_DROP_M lower in the band's edge shade.
static func mesh_of(
	strip_list: Array[Dictionary], line_list: Array[Rect2] = [], pad_list: Array[Rect2] = []
) -> ArrayMesh:
	var out := ArrayMesh.new()
	if strip_list.is_empty() and line_list.is_empty() and pad_list.is_empty():
		return out
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var index := PackedInt32Array()
	for rect in pad_list:
		var pad_base := verts.size()
		for corner in _corners_of(rect):
			verts.append(Vector3(corner.x, HEIGHT_M - PAD_DROP_M, corner.y))
			normals.append(Vector3.UP)
			uvs.append(Vector2(ASPHALT_U, ASPHALT_V_FROM))
		index.append_array(_quad(pad_base))
	for strip in strip_list:
		if strip.has("quad"):
			var quad_base := verts.size()
			var quad: Array[Vector2] = strip["quad"]
			var ts: Array[float] = strip["ts"]
			for i in 4:
				verts.append(Vector3(quad[i].x, HEIGHT_M, quad[i].y))
				normals.append(Vector3.UP)
				uvs.append(Vector2(ASPHALT_U, lerpf(ASPHALT_V_FROM, ASPHALT_V_TO, ts[i])))
			index.append_array(_quad(quad_base))
			var line: Array[Vector2] = strip["line"]
			var line_base := verts.size()
			for corner in line:
				verts.append(Vector3(corner.x, HEIGHT_M + LINE_LIFT_M, corner.y))
				normals.append(Vector3.UP)
				uvs.append(MARKING_UV)
			index.append_array(_quad(line_base))
			continue
		var rect: Rect2 = strip["rect"]
		var across_x: bool = strip["across_x"]
		if not across_x:
			var cuts := junctions(rect, strip_list)
			if not cuts.is_empty():
				_add_mitred_lane(rect, cuts, verts, normals, uvs, index)
				continue
		var parts: Array[Rect2] = [rect]
		if across_x:
			parts = _drawn_rects(strip, strip_list)
		for drawn in parts:
			var base := verts.size()
			for corner in _corners_of(drawn):
				verts.append(Vector3(corner.x, HEIGHT_M, corner.y))
				normals.append(Vector3.UP)
				var t: float = (
					(corner.x - rect.position.x) / rect.size.x
					if across_x
					else (corner.y - rect.position.y) / rect.size.y
				)
				uvs.append(Vector2(ASPHALT_U, lerpf(ASPHALT_V_FROM, ASPHALT_V_TO, t)))
			index.append_array(_quad(base))
	for rect in line_list:
		var base := verts.size()
		for corner in _corners_of(rect):
			verts.append(Vector3(corner.x, HEIGHT_M + LINE_LIFT_M, corner.y))
			normals.append(Vector3.UP)
			uvs.append(MARKING_UV)
		index.append_array(_quad(base))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = index
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	out.surface_set_material(0, MATERIAL)
	return out


## The links in `strip_list` that meet the edges of the lane strip `lane` (a
## north-south strip as wide as the lane, inside its x range, with an end on
## its north or south edge), west to east: each {"x": the link's centre x,
## "north": a link meets the north edge there, "south": one meets the south
## edge}. A link at the same x on both edges makes one entry. Links closer
## than the lane is wide are all kept; _add_mitred_lane() splits the lane
## between them.
static func junctions(lane: Rect2, strip_list: Array[Dictionary]) -> Array[Dictionary]:
	var width := lane.size.y
	var by_x: Dictionary = {}
	for strip in strip_list:
		if not strip["across_x"] or strip.has("quad"):
			continue
		var rect: Rect2 = strip["rect"]
		if absf(rect.size.x - width) > SAME_M:
			continue
		if rect.position.x < lane.position.x - SAME_M or rect.end.x > lane.end.x + SAME_M:
			continue
		var north := absf(rect.end.y - lane.position.y) < SAME_M
		var south := absf(rect.position.y - lane.end.y) < SAME_M
		if not north and not south:
			continue
		var key := roundi(rect.get_center().x / SAME_M)
		var entry: Dictionary = by_x.get(
			key, {"x": rect.get_center().x, "north": false, "south": false}
		)
		entry["north"] = entry["north"] or north
		entry["south"] = entry["south"] or south
		by_x[key] = entry
	var keys := by_x.keys()
	keys.sort()
	var out: Array[Dictionary] = []
	for key: int in keys:
		out.append(by_x[key])
	return out


## Adds the lane strip `lane` to the arrays, mitred under the links at `cuts`
## (junctions()). In each half of the lane the band follows the nearest centre
## line: the lane's, or that of a link meeting that half's edge. So a link's
## band reaches into the lane as far as the diagonals from its centre, and two
## links on one edge share the lane at their midpoint. The half is cut into x
## slabs at every link's centre, edges and midpoints, where each part is linear.
static func _add_mitred_lane(
	lane: Rect2,
	cuts: Array[Dictionary],
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	index: PackedInt32Array
) -> void:
	var half := lane.size.y / 2.0
	var mid_z := lane.get_center().y
	for side: String in ["north", "south"]:
		# Toward the half's outer edge: -z for the north half, +z for the south.
		var out_dir := -1.0 if side == "north" else 1.0
		var outer := mid_z + out_dir * half
		var xs: Array[float] = []
		for cut in cuts:
			if cut[side]:
				xs.append(cut["x"])
		var breaks: Array[float] = [lane.position.x, lane.end.x]
		for i in xs.size():
			breaks.append_array([xs[i], xs[i] - half, xs[i] + half])
			if i > 0:
				breaks.append((xs[i - 1] + xs[i]) / 2.0)
		breaks.sort()
		for i in range(1, breaks.size()):
			var a := maxf(breaks[i - 1], lane.position.x)
			var b := minf(breaks[i], lane.end.x)
			if b - a < SAME_M:
				continue
			var link_x := INF
			for x in xs:
				if absf((a + b) / 2.0 - x) < absf((a + b) / 2.0 - link_x):
					link_x = x
			var ga := minf(absf(a - link_x), half)
			var gb := minf(absf(b - link_x), half)
			# The lane's part, from the centre line out to the diagonal.
			var lane_t := func(p: Vector2) -> float: return (p.y - lane.position.y) / lane.size.y
			_add_part(
				[
					Vector2(a, mid_z),
					Vector2(b, mid_z),
					Vector2(b, mid_z + out_dir * gb),
					Vector2(a, mid_z + out_dir * ga)
				],
				lane_t,
				verts,
				normals,
				uvs,
				index
			)
			# The link's part, from the diagonal out to the lane's edge.
			var link_t := func(p: Vector2) -> float: return (p.x - link_x + half) / (2.0 * half)
			_add_part(
				[
					Vector2(a, mid_z + out_dir * ga),
					Vector2(b, mid_z + out_dir * gb),
					Vector2(b, outer),
					Vector2(a, outer)
				],
				link_t,
				verts,
				normals,
				uvs,
				index
			)


## Adds the flat quad `corners` (world x and z, in order around it) as two
## triangles, each turned to face up and left out when it has no area, with
## each corner's band position given by `t_of`.
static func _add_part(
	corners: Array[Vector2],
	t_of: Callable,
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	index: PackedInt32Array
) -> void:
	for tri: Array[Vector2] in [
		[corners[0], corners[1], corners[2]] as Array[Vector2],
		[corners[0], corners[2], corners[3]] as Array[Vector2]
	]:
		var area := _signed_area(tri)
		if absf(area) < SAME_M * SAME_M:
			continue
		if area < 0.0:
			tri.reverse()
		var base := verts.size()
		for p in tri:
			_add_asphalt(p, t_of.call(p), verts, normals, uvs)
		index.append_array(PackedInt32Array([base, base + 1, base + 2]))


## The parts of the north-south strip `strip` that are drawn, north to south.
## Where another north-south strip in `strip_list` overlaps it (two links closer
## than the strips are wide), the strip is cut at their midpoint over the z
## span they share, so the two never draw the same ground; outside that span it
## is drawn at full width, so a longer link stays whole past a shorter one's
## end. Its band still runs across the whole strip, so both give the same shade
## at the cut.
static func _drawn_rects(strip: Dictionary, strip_list: Array[Dictionary]) -> Array[Rect2]:
	var rect: Rect2 = strip["rect"]
	var x := rect.get_center().x
	var neighbours: Array[Rect2] = []
	var cuts: Array[float] = [rect.position.y, rect.end.y]
	for other in strip_list:
		if other == strip or not other["across_x"] or other.has("quad"):
			continue
		var them: Rect2 = other["rect"]
		if absf(them.get_center().x - x) < SAME_M or not rect.grow(-SAME_M).intersects(them):
			continue
		neighbours.append(them)
		for z in [them.position.y, them.end.y]:
			if z > rect.position.y and z < rect.end.y:
				cuts.append(z)
	cuts.sort()
	var out: Array[Rect2] = []
	for i in range(1, cuts.size()):
		var top := cuts[i - 1]
		var bottom := cuts[i]
		if bottom - top < SAME_M:
			continue
		var lo := rect.position.x
		var hi := rect.end.x
		for them in neighbours:
			if them.position.y >= bottom - SAME_M or them.end.y <= top + SAME_M:
				continue
			var other_x := them.get_center().x
			if other_x < x:
				lo = maxf(lo, (x + other_x) / 2.0)
			else:
				hi = minf(hi, (x + other_x) / 2.0)
		out.append(Rect2(lo, top, hi - lo, bottom - top))
	return out


## One upward asphalt vertex at `at` (world x and z), `t` across the band.
static func _add_asphalt(
	at: Vector2,
	t: float,
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array
) -> void:
	verts.append(Vector3(at.x, HEIGHT_M, at.y))
	normals.append(Vector3.UP)
	uvs.append(Vector2(ASPHALT_U, lerpf(ASPHALT_V_FROM, ASPHALT_V_TO, t)))


static func _corners_of(rect: Rect2) -> Array[Vector2]:
	return [
		rect.position,
		Vector2(rect.end.x, rect.position.y),
		rect.end,
		Vector2(rect.position.x, rect.end.y)
	]


## The two triangles of the quad whose corners start at `base`, clockwise seen
## from above (Godot's front face).
static func _quad(base: int) -> PackedInt32Array:
	return PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3])


## Whether the point (x, z) of `point` lies on one of `strip_list`'s strips.
static func covers(strip_list: Array[Dictionary], point: Vector3) -> bool:
	for strip in strip_list:
		var rect: Rect2 = strip["rect"]
		var at := Vector2(point.x, point.z)
		if strip.has("quad"):
			if _in_quad(strip["quad"], at):
				return true
			continue
		if (
			at.x >= rect.position.x - SAME_M
			and at.x <= rect.end.x + SAME_M
			and at.y >= rect.position.y - SAME_M
			and at.y <= rect.end.y + SAME_M
		):
			return true
	return false


## Whether `at` lies on the quad `quad`, a SAME_M tolerance inside every edge.
static func _in_quad(quad: Array[Vector2], at: Vector2) -> bool:
	for i in 4:
		var edge := quad[(i + 1) % 4] - quad[i]
		# Clockwise corners seen from above: the strip lies on the side where this is >= 0.
		if edge.cross(at - quad[i]) / edge.length() < -SAME_M:
			return false
	return true
