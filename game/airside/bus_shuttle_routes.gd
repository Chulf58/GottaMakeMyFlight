class_name BusShuttleRoutes
extends RefCounted
## Pose helpers and coarse 2 m apron BFS route planner for BusShuttleSim
## (decisions 710a78b4, 6d69da79, 94ae5894).

const STEP_M := 2.0
const BAND_MIN_Z := -269.0
const EXTRA_X_M := 16.0
const BUS_MID_Z := 0.67
const DOOR_LOCAL_X := -1.325
const DOOR_LOCAL_ZS: Array[float] = [6.907, 5.323, 3.557, 1.973]
const DOOR_MID_Z := 4.44
const STOP_CURB_GAP_M := 4.1
const ENTRY_STEP_OUT_M := 0.9
const CURB_EXIT_M := 0.30
const CURB_INNER_STEP_M := 1.32
const CURB_OUTER_STEP_M := 0.92
const STAIR_LANE_OFFSET_M := 0.22
const INNER_APPROACH_OUT_M := 0.75
const OUTER_APPROACH_OUT_M := 1.35
const SMALL_03A_OUT_M := 9.5
const SMALL_03A_AFT_M := -2.5
const TERM_PAD_M := 1.5
const SERVICE_BAND_DEPTH_M := 8.0


static func bay_pose_for(stand: Dictionary, site: SiteDefinition = null) -> Dictionary:
	var bay := BusBays.bay_rect(stand)
	if not bay.has_area():
		return {}
	var center := Vector3(bay.position.x + 0.5 * bay.size.x, 0.0, bay.position.y + 0.5 * bay.size.y)
	var yaw := 0.0
	match StandPlacement.side_of(stand):
		StandPlacement.NORTH:
			yaw = PI * 0.5
		StandPlacement.WEST:
			yaw = PI
		StandPlacement.EAST:
			yaw = 0.0
	var fwd := Vector3(sin(yaw), 0.0, cos(yaw))
	var gy := _ground_y(center, site)
	var origin := Vector3(center.x, gy, center.z) - fwd * BUS_MID_Z
	return {
		"origin": origin,
		"yaw": yaw,
		"forward": fwd,
		"bay": bay,
	}


static func stop_pose_for(stand: Dictionary, model: String, ground_y: float) -> Dictionary:
	if stand.is_empty():
		return {}
	if AirstairsPose.docks(model):
		var stair := AirstairsPose.pose_for(stand, model, ground_y)
		var entry: Vector3 = stair["bottom_entry"]
		var origin := Vector3(entry.x + DOOR_MID_Z, ground_y, entry.z + STOP_CURB_GAP_M)
		return {
			"origin": origin,
			"yaw": -PI * 0.5,
			"forward": Vector3(-1.0, 0.0, 0.0),
			"waypoints": _airstairs_waypoints(stair),
		}
	var at := StandPlacement.stand_point(stand)
	var gy := ground_y
	var door := JetBridgePose.plane_door(stand, model, gy)
	var raw_door: Vector3 = door["door"]
	var door_pos := Vector3(raw_door.x, gy, raw_door.z)
	var normal: Vector3 = door["normal"]
	var fwd_plane := StandPlacement.turn(stand, Vector3(0.0, 0.0, 1.0))
	var step_target := (
		door_pos
		+ normal * JetBridgePose.APRON_END_OUT_M
		- fwd_plane * JetBridgePose.APRON_END_AFT_M
	)
	var origin_03 := Vector3(at.x + SMALL_03A_OUT_M, gy, at.z + SMALL_03A_AFT_M)
	return {
		"origin": origin_03,
		"yaw": 0.0,
		"forward": Vector3(0.0, 0.0, 1.0),
		"waypoints": PackedVector3Array([step_target]),
	}


static func bus_door_world(pose: Dictionary, door_idx: int) -> Vector3:
	if pose.is_empty():
		return Vector3.ZERO
	var idx := clampi(door_idx, 0, DOOR_LOCAL_ZS.size() - 1)
	var origin: Vector3 = pose["origin"]
	var yaw := float(pose["yaw"])
	var xf := Transform3D(Basis(Vector3.UP, yaw), origin)
	return xf * Vector3(DOOR_LOCAL_X, 0.0, DOOR_LOCAL_ZS[idx])


## Non-crossing unload walk from bus door `door_idx` (-X flank) out past the
## bus skirt and into two parallel airstairs lanes (or to 03a's apron target).
static func bus_unload_walk(stop_pose: Dictionary, door_idx: int) -> Array[Vector3]:
	var out: Array[Vector3] = []
	if stop_pose.is_empty():
		return out
	var idx := clampi(door_idx, 0, DOOR_LOCAL_ZS.size() - 1)
	var door_pos := bus_door_world(stop_pose, idx)
	var bus_out := (
		(Basis(Vector3.UP, float(stop_pose["yaw"])) * Vector3(-1.0, 0.0, 0.0)).normalized()
	)
	var start_pos := door_pos + bus_out * CURB_EXIT_M
	var inner := idx == 1 or idx == 2
	var step_m := CURB_INNER_STEP_M if inner else CURB_OUTER_STEP_M
	var curb_pt := start_pos + bus_out * step_m
	out.append(start_pos)
	out.append(curb_pt)
	var stair_pts: PackedVector3Array = stop_pose.get("waypoints", PackedVector3Array())
	if stair_pts.size() < 4:
		for pt in stair_pts:
			out.append(pt)
		return out
	var approach := stair_pts[0]
	var entry := stair_pts[1]
	var in_dir := Vector3(entry.x - approach.x, 0.0, entry.z - approach.z).normalized()
	var north_dir := in_dir.cross(Vector3.UP).normalized()
	var south_lane := idx <= 1
	var lane_off := (-north_dir if south_lane else north_dir) * STAIR_LANE_OFFSET_M
	var turn_out := INNER_APPROACH_OUT_M if south_lane else OUTER_APPROACH_OUT_M
	var turn_base := entry - in_dir * turn_out
	out.append(Vector3(turn_base.x, curb_pt.y, curb_pt.z))
	if not south_lane:
		out.append(turn_base + lane_off)
	out.append(approach + lane_off)
	for i in range(1, stair_pts.size()):
		out.append(stair_pts[i] + lane_off)
	return out


static func stair_waypoints_for(
	stand: Dictionary, model: String, ground_y: float
) -> PackedVector3Array:
	var stop := stop_pose_for(stand, model, ground_y)
	return stop.get("waypoints", PackedVector3Array())


static func route_length(points: PackedVector3Array) -> float:
	var total := 0.0
	for i in range(1, points.size()):
		total += Vector2(points[i].x - points[i - 1].x, points[i].z - points[i - 1].z).length()
	return total


static func plan_route(
	grid: BuildGrid,
	origin: Vector3,
	target: Vector3,
	regular_stands: Array[Dictionary],
	remote_stands: Dictionary,
	target_stand_id: String,
	target_model: String
) -> PackedVector3Array:
	if grid == null:
		return PackedVector3Array([origin, target])
	var site := (grid as SiteGrid).site if grid is SiteGrid else null
	var bounds := _search_bounds(grid)
	var cols := int(ceil(bounds.size.x / STEP_M)) + 1
	var rows := int(ceil(bounds.size.y / STEP_M)) + 1
	var start := _to_cell(origin, bounds, cols, rows)
	var goal := _to_cell(target, bounds, cols, rows)
	var term_rects := _terminal_rects(grid, site)
	var plane_rect := _plane_rect(remote_stands.get(target_stand_id, {}), target_model)
	var full_envelopes := _stand_envelopes(
		grid, site, regular_stands, remote_stands, target_stand_id, true
	)
	var swing_envelopes := _stand_envelopes(
		grid, site, regular_stands, remote_stands, target_stand_id, false
	)
	var tiers := [
		term_rects + full_envelopes + plane_rect,
		term_rects + swing_envelopes + plane_rect,
		term_rects + plane_rect,
	]
	for blocked: Array in tiers:
		var occ := _blocked_grid(bounds, cols, rows, start, goal, blocked, term_rects)
		var raw := _bfs(bounds, cols, rows, start, goal, origin, target, occ, site)
		if not raw.is_empty():
			return _simplify(raw, bounds, cols, rows, occ, origin, target)
	return PackedVector3Array([origin, target])


static func _airstairs_waypoints(stair: Dictionary) -> PackedVector3Array:
	var raw: PackedVector3Array = stair.get("waypoints", PackedVector3Array())
	if raw.is_empty():
		return raw
	var entry: Vector3 = raw[0]
	var normal: Vector3 = stair.get("normal", Vector3(1.0, 0.0, 0.0))
	var approach := entry + normal * ENTRY_STEP_OUT_M
	var out := PackedVector3Array([approach])
	for pt in raw:
		out.append(pt)
	return out


static func _ground_y(at: Vector3, site: SiteDefinition) -> float:
	if site != null:
		return PlaneView.ground_height_at(at)
	return at.y


static func _search_bounds(grid: BuildGrid) -> Rect2:
	var min_x := grid.origin.x - EXTRA_X_M
	var max_x := grid.origin.x + float(grid.size.x) + EXTRA_X_M
	var min_z := minf(BAND_MIN_Z, grid.origin.z)
	var max_z := grid.origin.z + float(grid.size.y)
	return Rect2(min_x, min_z, max_x - min_x, max_z - min_z)


static func _to_cell(pos: Vector3, bounds: Rect2, cols: int, rows: int) -> Vector2i:
	var cx := clampi(int(round((pos.x - bounds.position.x) / STEP_M)), 0, cols - 1)
	var cy := clampi(int(round((pos.z - bounds.position.y) / STEP_M)), 0, rows - 1)
	return Vector2i(cx, cy)


static func _cell_world(cell: Vector2i, bounds: Rect2, site: SiteDefinition) -> Vector3:
	var x := bounds.position.x + float(cell.x) * STEP_M
	var z := bounds.position.y + float(cell.y) * STEP_M
	var pt := Vector3(x, 0.0, z)
	pt.y = _ground_y(pt, site)
	return pt


static func _terminal_rects(grid: BuildGrid, site: SiteDefinition) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for y in grid.size.y:
		for x in grid.size.x:
			var c := Vector2i(x, y)
			if not _cell_blocks_bus(grid, site, c):
				continue
			var wx := grid.origin.x + float(x)
			var wz := grid.origin.z + float(y)
			var span := 1.0 + 2.0 * TERM_PAD_M
			out.append(Rect2(wx - TERM_PAD_M, wz - TERM_PAD_M, span, span))
	return out


static func _cell_blocks_bus(grid: BuildGrid, site: SiteDefinition, cell: Vector2i) -> bool:
	if grid.floor_at(cell) != BuildGrid.FLOOR_NONE:
		return true
	var obj := grid.object_at(cell)
	if obj != 0:
		var rec := grid.get_object(obj)
		if StringName(rec.get("def", &"")) != RemoteStands.STAND_ID:
			return true
	if site != null and site.is_obstacle(cell):
		return true
	for s in 4:
		if grid.has_wall(cell, s):
			return true
	return false


static func _stand_envelopes(
	grid: BuildGrid,
	site: SiteDefinition,
	regular_stands: Array[Dictionary],
	remote_stands: Dictionary,
	target_stand_id: String,
	include_way: bool
) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var service_south := grid.origin.z if site != null else BAND_MIN_Z + SERVICE_BAND_DEPTH_M
	for stand in regular_stands:
		_append_envelope_rects(out, stand, PlaneClasses.LARGE, include_way, true, service_south)
	for sid: String in remote_stands:
		if sid == target_stand_id:
			continue
		var stand: Dictionary = remote_stands[sid]
		var klass := RemoteStands.max_class(grid, site, stand)
		if klass != "":
			_append_envelope_rects(out, stand, klass, include_way, false, service_south)
	return out


static func _append_envelope_rects(
	out: Array[Rect2],
	stand: Dictionary,
	klass: String,
	include_way: bool,
	is_regular: bool,
	service_south: float
) -> void:
	var parts := StandEnvelope.rects(stand, klass)
	if parts.is_empty():
		return
	out.append(parts[0])
	if is_regular:
		var twin := StandPlacement.north_twin(stand)
		var at := StandPlacement.stand_point(twin)
		var swing := StandEnvelope.radius(klass)
		var nose_gap := Rect2(
			at.x - swing, at.z + StandPlacement.NOSE_M, 2.0 * swing, StandPlacement.NOSE_GAP_M + 0.5
		)
		for r in StandPlacement.rects_to_world(stand, [nose_gap]):
			out.append(r)
	if include_way and parts.size() > 1:
		var way := parts[1]
		if is_regular and StandPlacement.side_of(stand) == StandPlacement.NORTH:
			var top := maxf(way.position.y, service_south)
			if way.end.y > top:
				out.append(Rect2(way.position.x, top, way.size.x, way.end.y - top))
		else:
			out.append(way)


static func _plane_rect(stand: Dictionary, model: String) -> Array[Rect2]:
	if stand.is_empty() or not PlaneModels.PLANES.has(model):
		return []
	var spec: Dictionary = PlaneModels.PLANES[model]
	var half_span := float(spec["half_span"])
	var nose := float(spec["nose"])
	var tail := float(spec["tail"])
	var doors: Array = spec["doors"]
	var port_x := absf(float((doors[0] as Vector3).x)) if not doors.is_empty() else 1.5
	var fuse_half := port_x + 0.4
	var at := StandPlacement.stand_point(stand) + PlaneClasses.stand_offset(model)
	var stop := stop_pose_for(stand, model, at.y)
	var stop_z := float((stop["origin"] as Vector3).z) if not stop.is_empty() else at.z + nose
	var z_min := at.z - tail - 0.8
	var out: Array[Rect2] = [Rect2(at.x - fuse_half, z_min, 2.0 * fuse_half, nose + tail + 1.6)]
	var wing_front := minf(at.z + nose * 0.45, stop_z - 1.8)
	if wing_front > z_min:
		out.append(Rect2(at.x - half_span - 0.8, z_min, 2.0 * half_span + 1.6, wing_front - z_min))
	return out


static func _blocked_grid(
	bounds: Rect2,
	cols: int,
	rows: int,
	start: Vector2i,
	goal: Vector2i,
	blocked: Array,
	hard_blocked: Array = []
) -> PackedByteArray:
	var grid := PackedByteArray()
	grid.resize(cols * rows)
	_mark_rects(grid, bounds, cols, rows, blocked, 1)
	var hard := PackedByteArray()
	hard.resize(cols * rows)
	_mark_rects(hard, bounds, cols, rows, hard_blocked, 1)
	grid[start.y * cols + start.x] = 0
	grid[goal.y * cols + goal.x] = 0
	_carve_curb_corridor(grid, hard, cols, rows, goal)
	return grid


static func _mark_rects(
	cells: PackedByteArray, bounds: Rect2, cols: int, rows: int, rects: Array, value: int
) -> void:
	for r: Rect2 in rects:
		var x0 := clampi(int(floor((r.position.x - bounds.position.x) / STEP_M)), 0, cols - 1)
		var x1 := clampi(int(ceil((r.end.x - bounds.position.x) / STEP_M)), 0, cols - 1)
		var y0 := clampi(int(floor((r.position.y - bounds.position.y) / STEP_M)), 0, rows - 1)
		var y1 := clampi(int(ceil((r.end.y - bounds.position.y) / STEP_M)), 0, rows - 1)
		for y in range(y0, y1 + 1):
			var row_off := y * cols
			var wz := bounds.position.y + float(y) * STEP_M
			for x in range(x0, x1 + 1):
				var wx := bounds.position.x + float(x) * STEP_M
				if r.has_point(Vector2(wx, wz)):
					cells[row_off + x] = value


static func _carve_curb_corridor(
	grid: PackedByteArray, hard: PackedByteArray, cols: int, rows: int, goal: Vector2i
) -> void:
	for step: Vector2i in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]:
		var n := goal + step
		if n.x >= 0 and n.x < cols and n.y >= 0 and n.y < rows and grid[n.y * cols + n.x] == 0:
			return
	for dir: Vector2i in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]:
		var carved: Array[int] = []
		var cur := goal
		for _s in 6:
			cur += dir
			if cur.x < 0 or cur.x >= cols or cur.y < 0 or cur.y >= rows:
				break
			var idx := cur.y * cols + cur.x
			if hard[idx] != 0:
				break
			if grid[idx] == 0:
				for ci in carved:
					grid[ci] = 0
				return
			carved.append(idx)


static func _bfs(
	bounds: Rect2,
	cols: int,
	rows: int,
	start: Vector2i,
	goal: Vector2i,
	origin: Vector3,
	target: Vector3,
	occ: PackedByteArray,
	site: SiteDefinition
) -> PackedVector3Array:
	var parent := PackedInt32Array()
	parent.resize(cols * rows)
	parent.fill(-1)
	var start_i := start.y * cols + start.x
	var goal_i := goal.y * cols + goal.x
	parent[start_i] = start_i
	var queue: Array[int] = [start_i]
	var head := 0
	var found := false
	while head < queue.size():
		var cur := queue[head]
		head += 1
		if cur == goal_i:
			found = true
			break
		var cx := cur % cols
		var cy := cur / cols
		for step: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx := cx + step.x
			var ny := cy + step.y
			if nx < 0 or nx >= cols or ny < 0 or ny >= rows:
				continue
			var ni := ny * cols + nx
			if occ[ni] != 0 or parent[ni] != -1:
				continue
			parent[ni] = cur
			queue.append(ni)
	if not found:
		return PackedVector3Array()
	var rev: Array[Vector3] = [target]
	var cur := parent[goal_i]
	while cur != start_i:
		var cell := Vector2i(cur % cols, cur / cols)
		rev.append(_cell_world(cell, bounds, site))
		cur = parent[cur]
	rev.append(origin)
	rev.reverse()
	var out := PackedVector3Array()
	for pt in rev:
		out.append(pt)
	return out


static func _simplify(
	raw: PackedVector3Array,
	bounds: Rect2,
	cols: int,
	rows: int,
	occ: PackedByteArray,
	origin: Vector3,
	target: Vector3
) -> PackedVector3Array:
	if raw.size() <= 2:
		return raw
	var kept := PackedVector3Array([origin])
	var anchor := 0
	while anchor < raw.size() - 1:
		var far := raw.size() - 1
		while far > anchor + 1:
			if _segment_clear(raw[anchor], raw[far], bounds, cols, rows, occ):
				break
			far -= 1
		kept.append(raw[far])
		anchor = far
	kept[kept.size() - 1] = target
	return kept


static func _segment_clear(
	a: Vector3, b: Vector3, bounds: Rect2, cols: int, rows: int, occ: PackedByteArray
) -> bool:
	var dist := Vector2(b.x - a.x, b.z - a.z).length()
	var steps := maxi(1, int(ceil(dist / 1.0)))
	for i in range(1, steps):
		var t := float(i) / float(steps)
		var pt := Vector3(lerpf(a.x, b.x, t), 0.0, lerpf(a.z, b.z, t))
		var c := _to_cell(pt, bounds, cols, rows)
		if occ[c.y * cols + c.x] != 0:
			return false
	return true
