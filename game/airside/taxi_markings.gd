class_name TaxiMarkings
extends RefCounted
## Builds the upgraded painted markings overlay for TaxiPaving: double-yellow
## taxiway shoulder/edge lines along uncovered strip boundaries, enhanced dashed
## hold-short companion bars, and apron stand nose-stop T-bars and safety
## perimeter markings. Pure geometry builder; TaxiPaving lifts it onto the
## site ramp via TaxiPavingSite.lift_overlay() so no line floats or clips.

const EDGE_INSET_INNER_M := 0.55
const EDGE_INSET_OUTER_M := 1.05
const EDGE_LINE_W := 0.24
const COVER_GROW_M := EDGE_INSET_OUTER_M + EDGE_LINE_W * 0.5 + 0.15
const JUNCTION_MOUTH_GROW_M := COVER_GROW_M
const DEFAULT_COVER_GROW_M := 0.35
const WHITE_UV := Vector2(11.5 / 32.0, 14.2 / 16.0)
const RED_UV := Vector2(31.5 / 32.0, 0.45 / 16.0)
const PAD_BORDER_INSET_M := 0.50
const PAD_BORDER_W := 0.30
const DASH_LEN_M := 2.4
const DASH_GAP_M := 2.4
const HOLD_DASH_LEN_M := 1.5
const HOLD_DASH_GAP_M := 1.5
const HOLD_DASH_INSET_M := 1.6
const STOP_BAR_W := 3.8
const STOP_BAR_D := 0.42
const STOP_TICK_W := 2.2
const STOP_TICK_D := 0.28
const STOP_TICK_OFFSETS := [-4.2, 3.8]

static var _material: Material = null


## Un-outlined toon material for flat markings painted onto paving.
static func material() -> Material:
	if _material == null:
		_material = preload("res://assets/materials/tp_atlas_simple_toon.tres").duplicate()
		_material.next_pass = null
	return _material


## Builds the overlay ArrayMesh for `strip_list`, `pad_list`, `holds`,
## `stand_pts`, and `runway_south_z` at `y = HEIGHT_M + LINE_LIFT_M`.
static func mesh_of(
	strip_list: Array[Dictionary],
	pad_list: Array[Rect2],
	holds: PackedVector3Array,
	stand_pts: PackedVector3Array,
	runway_south_z: float,
	mat: Material = null
) -> ArrayMesh:
	var out := ArrayMesh.new()
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var index := PackedInt32Array()
	var y := TaxiPaving.HEIGHT_M + TaxiPaving.LINE_LIFT_M

	_add_taxiway_edge_lines(strip_list, pad_list, runway_south_z, y, verts, normals, uvs, index)
	_add_hold_dashed_bars(holds, strip_list, runway_south_z, y, verts, normals, uvs, index)
	_add_stand_markings(stand_pts, strip_list, pad_list, y, verts, normals, uvs, index)
	_add_pad_safety_borders(
		pad_list, strip_list, stand_pts, runway_south_z, y, verts, normals, uvs, index
	)

	if index.is_empty():
		return out
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = index
	out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	out.surface_set_material(0, mat if mat != null else material())
	return out


static func _add_taxiway_edge_lines(
	strip_list: Array[Dictionary],
	pad_list: Array[Rect2],
	runway_south_z: float,
	y: float,
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	index: PackedInt32Array
) -> void:
	for strip in strip_list:
		if strip.has("quad"):
			continue
		var rect: Rect2 = strip["rect"]
		var across_x: bool = strip["across_x"]
		if across_x:
			for sign_x: float in [-1.0, 1.0]:
				var base_x := rect.position.x if sign_x < 0.0 else rect.end.x
				for inset: float in [EDGE_INSET_INNER_M, EDGE_INSET_OUTER_M]:
					var cx := base_x - sign_x * inset
					var spans := _uncovered_spans(
						rect.position.y,
						rect.end.y,
						cx,
						false,
						strip,
						strip_list,
						pad_list,
						runway_south_z
					)
					for span in spans:
						_add_rect(
							Rect2(cx - EDGE_LINE_W * 0.5, span.x, EDGE_LINE_W, span.y - span.x),
							y,
							TaxiPaving.MARKING_UV,
							verts,
							normals,
							uvs,
							index
						)
		else:
			for sign_z: float in [-1.0, 1.0]:
				var base_z := rect.position.y if sign_z < 0.0 else rect.end.y
				for inset: float in [EDGE_INSET_INNER_M, EDGE_INSET_OUTER_M]:
					var cz := base_z - sign_z * inset
					var spans := _uncovered_spans(
						rect.position.x,
						rect.end.x,
						cz,
						true,
						strip,
						strip_list,
						pad_list,
						runway_south_z
					)
					for span in spans:
						_add_rect(
							Rect2(span.x, cz - EDGE_LINE_W * 0.5, span.y - span.x, EDGE_LINE_W),
							y,
							TaxiPaving.MARKING_UV,
							verts,
							normals,
							uvs,
							index
						)


static func _uncovered_spans(
	from_s: float,
	to_s: float,
	fixed_coord: float,
	horizontal: bool,
	owner_strip: Dictionary,
	strip_list: Array[Dictionary],
	pad_list: Array[Rect2],
	runway_south_z: float
) -> Array[Vector2]:
	var intervals: Array[Vector2] = [Vector2(from_s, to_s)]
	var owner_rect: Rect2 = owner_strip["rect"]
	var owner_across: bool = owner_strip["across_x"]
	if not horizontal and runway_south_z > -INF:
		intervals = _subtract_interval(intervals, -INF, runway_south_z + 0.15)
	if horizontal and fixed_coord <= runway_south_z + 0.15:
		return []
	for other in strip_list:
		if other == owner_strip or other.has("quad"):
			continue
		var or_rect: Rect2 = other["rect"]
		var abuts := _rects_touch_or_overlap(owner_rect, or_rect, TaxiPaving.SAME_M)
		var perp_abut := abuts and (bool(other["across_x"]) != owner_across)
		var gx := (
			COVER_GROW_M if (abuts and (not horizontal or not perp_abut)) else DEFAULT_COVER_GROW_M
		)
		var gy := (
			COVER_GROW_M if (abuts and (horizontal or not perp_abut)) else DEFAULT_COVER_GROW_M
		)
		var r := Rect2(
			or_rect.position.x - gx,
			or_rect.position.y - gy,
			or_rect.size.x + 2.0 * gx,
			or_rect.size.y + 2.0 * gy
		)
		if horizontal:
			if fixed_coord >= r.position.y and fixed_coord <= r.end.y:
				intervals = _subtract_interval(intervals, r.position.x, r.end.x)
		else:
			if fixed_coord >= r.position.x and fixed_coord <= r.end.x:
				intervals = _subtract_interval(intervals, r.position.y, r.end.y)
	for pad in pad_list:
		var abuts := _rects_touch_or_overlap(owner_rect, pad, TaxiPaving.SAME_M)
		var grow := COVER_GROW_M if abuts else DEFAULT_COVER_GROW_M
		var pr := Rect2(
			pad.position.x - grow,
			pad.position.y - grow,
			pad.size.x + 2.0 * grow,
			pad.size.y + 2.0 * grow
		)
		if horizontal:
			if fixed_coord >= pr.position.y and fixed_coord <= pr.end.y:
				intervals = _subtract_interval(intervals, pr.position.x, pr.end.x)
		else:
			if fixed_coord >= pr.position.x and fixed_coord <= pr.end.x:
				intervals = _subtract_interval(intervals, pr.position.y, pr.end.y)
	return intervals


static func _rects_touch_or_overlap(a: Rect2, b: Rect2, tol: float) -> bool:
	return (
		b.position.x <= a.end.x + tol
		and b.end.x >= a.position.x - tol
		and b.position.y <= a.end.y + tol
		and b.end.y >= a.position.y - tol
	)


static func _subtract_interval(
	intervals: Array[Vector2], cut_a: float, cut_b: float
) -> Array[Vector2]:
	if cut_b <= cut_a:
		return intervals
	var out: Array[Vector2] = []
	for seg in intervals:
		if cut_b <= seg.x or cut_a >= seg.y:
			out.append(seg)
			continue
		if cut_a > seg.x + 0.25:
			out.append(Vector2(seg.x, cut_a))
		if cut_b < seg.y - 0.25:
			out.append(Vector2(cut_b, seg.y))
	return out


static func _add_hold_dashed_bars(
	holds: PackedVector3Array,
	strip_list: Array[Dictionary],
	runway_south_z: float,
	y: float,
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	index: PackedInt32Array
) -> void:
	var reach := TaxiPaving.HOLD_GAP_M * 0.5 + TaxiPaving.HOLD_LINE_M
	var step := HOLD_DASH_LEN_M + HOLD_DASH_GAP_M
	var half_w := TaxiPaving.WIDTH_M * 0.5 - HOLD_DASH_INSET_M
	for at in holds:
		var ew := _is_east_west_hold(strip_list, at)
		if ew:
			var hx := TaxiPaving.clamp_ew_hold_x(at.x, at, strip_list, reach)
			var dir := -1.0 if at.x < 0.0 else 1.0
			var bx := hx + dir * (reach + TaxiPaving.HOLD_GAP_M)
			var z := at.z - half_w
			while z + HOLD_DASH_LEN_M <= at.z + half_w + 0.05:
				_add_rect(
					Rect2(
						bx - TaxiPaving.HOLD_LINE_M * 0.5,
						z,
						TaxiPaving.HOLD_LINE_M,
						HOLD_DASH_LEN_M
					),
					y,
					TaxiPaving.MARKING_UV,
					verts,
					normals,
					uvs,
					index
				)
				z += step
		else:
			var z := TaxiPaving.clamp_ns_hold_z(at.z, at, runway_south_z, strip_list, reach)
			var bz := z - (reach + TaxiPaving.HOLD_GAP_M)
			if bz - TaxiPaving.HOLD_LINE_M * 0.5 <= runway_south_z + 0.05:
				bz = z + reach + TaxiPaving.HOLD_GAP_M
			var x := at.x - half_w
			while x + HOLD_DASH_LEN_M <= at.x + half_w + 0.05:
				_add_rect(
					Rect2(
						x,
						bz - TaxiPaving.HOLD_LINE_M * 0.5,
						HOLD_DASH_LEN_M,
						TaxiPaving.HOLD_LINE_M
					),
					y,
					TaxiPaving.MARKING_UV,
					verts,
					normals,
					uvs,
					index
				)
				x += step


static func _is_east_west_hold(strip_list: Array[Dictionary], at: Vector3) -> bool:
	var ew := false
	for strip in strip_list:
		if strip.has("quad"):
			continue
		var rect: Rect2 = strip["rect"]
		var centre := rect.get_center()
		if strip["across_x"]:
			var on_col := (
				at.z >= rect.position.y - TaxiPaving.SAME_M
				and at.z <= rect.end.y + TaxiPaving.SAME_M
			)
			if absf(at.x - centre.x) < TaxiPaving.SAME_M and on_col:
				return false
		elif absf(at.z - centre.y) < TaxiPaving.SAME_M:
			ew = ew or (at.x >= rect.position.x and at.x <= rect.end.x)
	return ew


static func _add_stand_markings(
	stand_pts: PackedVector3Array,
	strip_list: Array[Dictionary],
	pad_list: Array[Rect2],
	y: float,
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	index: PackedInt32Array
) -> void:
	for pt in stand_pts:
		var side_stand := _is_side_stand(pt, strip_list, pad_list)
		if side_stand:
			_add_rect(
				Rect2(pt.x - STOP_BAR_D * 0.5, pt.z - STOP_BAR_W * 0.5, STOP_BAR_D, STOP_BAR_W),
				y,
				TaxiPaving.MARKING_UV,
				verts,
				normals,
				uvs,
				index
			)
			for off: float in STOP_TICK_OFFSETS:
				_add_rect(
					Rect2(
						pt.x + off - STOP_TICK_D * 0.5,
						pt.z - STOP_TICK_W * 0.5,
						STOP_TICK_D,
						STOP_TICK_W
					),
					y,
					WHITE_UV,
					verts,
					normals,
					uvs,
					index
				)
		else:
			_add_rect(
				Rect2(pt.x - STOP_BAR_W * 0.5, pt.z - STOP_BAR_D * 0.5, STOP_BAR_W, STOP_BAR_D),
				y,
				TaxiPaving.MARKING_UV,
				verts,
				normals,
				uvs,
				index
			)
			for off: float in STOP_TICK_OFFSETS:
				_add_rect(
					Rect2(
						pt.x - STOP_TICK_W * 0.5,
						pt.z + off - STOP_TICK_D * 0.5,
						STOP_TICK_W,
						STOP_TICK_D
					),
					y,
					WHITE_UV,
					verts,
					normals,
					uvs,
					index
				)


static func _is_side_stand(
	pt: Vector3, strip_list: Array[Dictionary], pad_list: Array[Rect2]
) -> bool:
	for strip in strip_list:
		if strip.get("row", false):
			var r: Rect2 = (strip["rect"] as Rect2).grow(1.0)
			if r.has_point(Vector2(pt.x, pt.z)):
				return true
	for pad in pad_list:
		if pad.has_point(Vector2(pt.x, pt.z)):
			return pad.size.x > pad.size.y * 1.15
	return false


static func _add_pad_safety_borders(
	pad_list: Array[Rect2],
	strip_list: Array[Dictionary],
	stand_pts: PackedVector3Array,
	runway_south_z: float,
	y: float,
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	index: PackedInt32Array
) -> void:
	var pad_y := y - TaxiPaving.PAD_DROP_M
	for idx in pad_list.size():
		var pad := pad_list[idx]
		var wall := _pad_wall_edge(pad, strip_list, stand_pts)
		var edges: Array[Dictionary] = []
		if wall != "N":
			(
				edges
				. append(
					{
						"a": pad.position.x + PAD_BORDER_INSET_M,
						"b": pad.end.x - PAD_BORDER_INSET_M,
						"fixed": pad.position.y + PAD_BORDER_INSET_M,
						"horiz": true,
					}
				)
			)
		if wall != "S":
			(
				edges
				. append(
					{
						"a": pad.position.x + PAD_BORDER_INSET_M,
						"b": pad.end.x - PAD_BORDER_INSET_M,
						"fixed": pad.end.y - PAD_BORDER_INSET_M,
						"horiz": true,
					}
				)
			)
		if wall != "W":
			(
				edges
				. append(
					{
						"a": pad.position.y + PAD_BORDER_INSET_M,
						"b": pad.end.y - PAD_BORDER_INSET_M,
						"fixed": pad.position.x + PAD_BORDER_INSET_M,
						"horiz": false,
					}
				)
			)
		if wall != "E":
			(
				edges
				. append(
					{
						"a": pad.position.y + PAD_BORDER_INSET_M,
						"b": pad.end.y - PAD_BORDER_INSET_M,
						"fixed": pad.end.x - PAD_BORDER_INSET_M,
						"horiz": false,
					}
				)
			)
		for e in edges:
			var spans: Array[Vector2] = [Vector2(e["a"], e["b"])]
			var fixed: float = e["fixed"]
			var horiz: bool = e["horiz"]
			if not horiz and runway_south_z > -INF:
				spans = _subtract_interval(spans, -INF, runway_south_z + 0.15)
			for strip in strip_list:
				if strip.has("quad"):
					continue
				var sr: Rect2 = (strip["rect"] as Rect2).grow(0.3)
				if horiz and fixed >= sr.position.y and fixed <= sr.end.y:
					spans = _subtract_interval(spans, sr.position.x, sr.end.x)
				elif not horiz and fixed >= sr.position.x and fixed <= sr.end.x:
					spans = _subtract_interval(spans, sr.position.y, sr.end.y)
			for other_idx in pad_list.size():
				if other_idx == idx:
					continue
				var pr := pad_list[other_idx].grow(0.3)
				if horiz and fixed >= pr.position.y and fixed <= pr.end.y:
					spans = _subtract_interval(spans, pr.position.x, pr.end.x)
				elif not horiz and fixed >= pr.position.x and fixed <= pr.end.x:
					spans = _subtract_interval(spans, pr.position.y, pr.end.y)
			for span in spans:
				_add_dashed_segment(span.x, span.y, fixed, horiz, pad_y, verts, normals, uvs, index)


static func _pad_wall_edge(
	pad: Rect2, strip_list: Array[Dictionary], stand_pts: PackedVector3Array
) -> String:
	var reach := StandPlacement.NOSE_GAP_M + StandPlacement.NOSE_M
	for pt in stand_pts:
		if pad.has_point(Vector2(pt.x, pt.z)):
			if absf(pad.end.y - pt.z - reach) < 0.25:
				return "S"
			if absf(pad.end.x - pt.x - reach) < 0.25:
				return "E"
			if absf(pt.x - pad.position.x - reach) < 0.25:
				return "W"
	for strip in strip_list:
		if strip.has("quad"):
			continue
		var sr: Rect2 = strip["rect"]
		if strip.get("row", false):
			var cy := sr.get_center().y
			if cy >= pad.position.y and cy <= pad.end.y:
				if (
					not strip.get("east_cut", false)
					and absf(sr.end.x - pad.end.x) < 0.25
					and sr.position.x < pad.position.x + 1.0
				):
					return "E"
				if (
					not strip.get("west_cut", false)
					and absf(sr.position.x - pad.position.x) < 0.25
					and sr.end.x > pad.end.x - 1.0
				):
					return "W"
		elif strip["across_x"]:
			var cx := sr.get_center().x
			if cx >= pad.position.x and cx <= pad.end.x:
				if absf(sr.end.y - pad.end.y) < 0.25 and sr.position.y < pad.position.y + 1.0:
					return "S"
	return "S"


static func _add_dashed_segment(
	s0: float,
	s1: float,
	fixed: float,
	horiz: bool,
	y: float,
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	index: PackedInt32Array
) -> void:
	var cur := s0
	var toggle := 0
	while cur < s1 - 0.3:
		var end_s := minf(cur + DASH_LEN_M, s1)
		var uv := RED_UV if toggle % 2 == 0 else WHITE_UV
		if horiz:
			_add_rect(
				Rect2(cur, fixed - PAD_BORDER_W * 0.5, end_s - cur, PAD_BORDER_W),
				y,
				uv,
				verts,
				normals,
				uvs,
				index
			)
		else:
			_add_rect(
				Rect2(fixed - PAD_BORDER_W * 0.5, cur, PAD_BORDER_W, end_s - cur),
				y,
				uv,
				verts,
				normals,
				uvs,
				index
			)
		cur += DASH_LEN_M + DASH_GAP_M
		toggle += 1


static func _add_rect(
	rect: Rect2,
	y: float,
	uv: Vector2,
	verts: PackedVector3Array,
	normals: PackedVector3Array,
	uvs: PackedVector2Array,
	index: PackedInt32Array
) -> void:
	if rect.size.x <= 0.001 or rect.size.y <= 0.001:
		return
	var base := verts.size()
	verts.append(Vector3(rect.position.x, y, rect.position.y))
	verts.append(Vector3(rect.end.x, y, rect.position.y))
	verts.append(Vector3(rect.end.x, y, rect.end.y))
	verts.append(Vector3(rect.position.x, y, rect.end.y))
	for _i in 4:
		normals.append(Vector3.UP)
		uvs.append(uv)
	index.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
