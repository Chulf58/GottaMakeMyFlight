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
## Not guaranteed: a route leg that is neither north-south nor east-west gets
## no strip (an error says so); every taxiway on the airside is one or the other.

const WIDTH_M := 30.0
## Height of the paving's top. The runway's asphalt lies at y 0.1 and the
## site's paving at y 0.2, so both cover the strips' ends; the grass is y -0.1.
const HEIGHT_M := 0.0
const MATERIAL := preload("res://assets/materials/tp_atlas_simple_toon.tres")
## The runway's asphalt in the atlas: one column, the v range across one band.
const ASPHALT_U := 0.5047
const ASPHALT_V_FROM := 0.0010
const ASPHALT_V_TO := 0.0614
## How far apart two values may be and still count as the same, in metres.
const SAME_M := 0.01

## The strips last built, as returned by strips().
var shown: Array[Dictionary] = []


func _init() -> void:
	name = "TaxiPaving"
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Builds the mesh for `routes` (world points) around the lane at `lane_z`.
func show_routes(routes: Array[PackedVector3Array], lane_z: float) -> void:
	shown = strips(routes, lane_z)
	mesh = mesh_of(shown)


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
	for route in routes:
		for i in range(1, route.size()):
			var a := route[i - 1]
			var b := route[i]
			if absf(a.z - b.z) < SAME_M and absf(a.z - lane_z) < SAME_M:
				lane_x = Vector2(minf(lane_x.x, minf(a.x, b.x)), maxf(lane_x.y, maxf(a.x, b.x)))
			elif absf(a.x - b.x) < SAME_M:
				_add_leg(columns, a.x, a.z, b.z, lane_z, half)
			elif not a.is_equal_approx(b):
				push_error("TaxiPaving: leg %s to %s is not north-south or east-west" % [a, b])
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
	return out


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


## One flat, upward quad per strip, its atlas band running across the strip.
static func mesh_of(strip_list: Array[Dictionary]) -> ArrayMesh:
	var out := ArrayMesh.new()
	if strip_list.is_empty():
		return out
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var index := PackedInt32Array()
	for strip in strip_list:
		var rect: Rect2 = strip["rect"]
		var across_x: bool = strip["across_x"]
		var base := verts.size()
		for corner: Vector2 in [
			rect.position,
			Vector2(rect.end.x, rect.position.y),
			rect.end,
			Vector2(rect.position.x, rect.end.y),
		]:
			verts.append(Vector3(corner.x, HEIGHT_M, corner.y))
			normals.append(Vector3.UP)
			var t: float = (
				(corner.x - rect.position.x) / rect.size.x
				if across_x
				else (corner.y - rect.position.y) / rect.size.y
			)
			uvs.append(Vector2(ASPHALT_U, lerpf(ASPHALT_V_FROM, ASPHALT_V_TO, t)))
		# Clockwise seen from above, Godot's front face.
		index.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = index
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	out.surface_set_material(0, MATERIAL)
	return out


## Whether the point (x, z) of `point` lies on one of `strip_list`'s strips.
static func covers(strip_list: Array[Dictionary], point: Vector3) -> bool:
	for strip in strip_list:
		var rect: Rect2 = strip["rect"]
		var at := Vector2(point.x, point.z)
		if (
			at.x >= rect.position.x - SAME_M
			and at.x <= rect.end.x + SAME_M
			and at.y >= rect.position.y - SAME_M
			and at.y <= rect.end.y + SAME_M
		):
			return true
	return false
