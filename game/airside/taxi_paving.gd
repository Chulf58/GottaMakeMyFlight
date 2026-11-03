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

## The strips last built, as returned by strips().
var shown: Array[Dictionary] = []
## The centre lines last built, as returned by centrelines().
var lines: Array[Rect2] = []


func _init() -> void:
	name = "TaxiPaving"
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Builds the mesh for `routes` (world points) around the lane at `lane_z`.
func show_routes(routes: Array[PackedVector3Array], lane_z: float) -> void:
	shown = strips(routes, lane_z)
	lines = centrelines(shown, lane_z)
	mesh = mesh_of(shown, lines)


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
static func mesh_of(strip_list: Array[Dictionary], line_list: Array[Rect2] = []) -> ArrayMesh:
	var out := ArrayMesh.new()
	if strip_list.is_empty() and line_list.is_empty():
		return out
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var index := PackedInt32Array()
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
		var base := verts.size()
		for corner in _corners_of(rect):
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
