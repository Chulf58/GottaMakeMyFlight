class_name RampPatrol
extends RefCounted
## Pure view-only airside apron patrol planner and deterministic sampler for
## idle StaffMember.Role.RAMP agents. Builds a closed loop of safe stand
## inspection checkpoints (clear of aircraft fuselages, wings, jet bridges,
## and terminal walls) and alternates smoothly between walking segments and
## stand-facing clipboard check pauses.

const PATROL_WALK_MPS := 1.85
const PAUSE_TICKS := 72
const STARBOARD_INNER_M := 3.8
const STARBOARD_MID_X_M := 7.8
const STARBOARD_OUTER_M := 11.8
const WALL_CLEAR_M := 2.0
const FORWARD_CLEAR_M := 4.8
const STAND_LOOK_M := 9.0
const DETOUR_CELL_M := 2.0
const DETOUR_MARGIN_M := 22.0
const FALLBACK_STANDOFF_M := 3.5
const FALLBACK_SPAN_M := 4.2
const FALLBACK_OUT_M := 2.5


## Builds the closed apron patrol loop for the current airport stands/grid.
static func build_loop(flight_sim: FlightSim, grid: BuildGrid, staff: StaffSim) -> Dictionary:
	var stands := _collect_stands(flight_sim)
	var points: Array[Dictionary] = []
	if stands.is_empty():
		points = _fallback_points(grid, staff)
	elif stands.size() == 1:
		points = _single_stand_points(stands[0], grid)
	else:
		points = _multi_stand_points(stands, grid)
	if points.is_empty():
		var origin := grid.origin if grid != null else Vector3.ZERO
		points = [{"pos": origin + Vector3(0.0, 0.0, -3.5), "face": origin, "pause": true}]
	return _compile_loop(points)


## Plans an obstacle-clear return polyline from a post-job exit position onto
## `target_pos` (or the nearest reachable loop checkpoint). Returns
## {"ok": bool, "points": Array[Vector3]}.
static func plan_return_path(
	from_pos: Vector3,
	target_pos: Vector3,
	flight_sim: FlightSim,
	grid: BuildGrid,
) -> Dictionary:
	var stands := _collect_stands(flight_sim)
	var excl := _stand_exclusion_rects(stands, grid)
	if _point_blocked(target_pos, excl, grid):
		return {"ok": false, "points": [] as Array[Vector3]}
	if not _segment_blocked(from_pos, target_pos, excl, grid):
		return {"ok": true, "points": [from_pos, target_pos]}
	var egress := _find_egress(from_pos, stands, excl, grid)
	if not bool(egress["ok"]):
		return {"ok": false, "points": [] as Array[Vector3]}
	var egress_pos: Vector3 = egress["pos"]
	var detour := _clear_detour(egress_pos, target_pos, excl, grid)
	if not bool(detour["ok"]):
		return {"ok": false, "points": [] as Array[Vector3]}
	var pts: Array[Vector3] = [from_pos]
	if Vector2(from_pos.x, from_pos.z).distance_to(Vector2(egress_pos.x, egress_pos.z)) > 0.05:
		pts.append(egress_pos)
	for mid_pos: Vector3 in detour["points"]:
		pts.append(mid_pos)
	pts.append(target_pos)
	return {"ok": true, "points": pts}


## Samples deterministic patrol pose at `sim_time` for `slot_idx`.
static func sample(loop: Dictionary, sim_time: float, slot_idx: int, grid: BuildGrid) -> Dictionary:
	var points: Array = loop.get("points", [])
	var legs: Array = loop.get("legs", [])
	var total_ticks := int(loop.get("total_ticks", 0))
	if points.is_empty():
		return {"pos": Vector3.ZERO, "yaw": 0.0, "clip": "idle", "speed": 1.0, "can_fidget": true}
	if total_ticks <= 0 or legs.is_empty():
		var p0: Dictionary = points[0]
		var pos0 := _ground_pos(grid, p0["pos"] as Vector3)
		return {
			"pos": pos0,
			"yaw": _yaw_toward(pos0, p0["face"]),
			"clip": "idle",
			"speed": 1.0,
			"can_fidget": true,
		}
	var phase := _slot_phase_ticks(loop, slot_idx)
	var t := fposmod(sim_time + float(phase), float(total_ticks))
	var acc := 0.0
	for i in legs.size():
		var leg: Dictionary = legs[i]
		var leg_total := float(leg["total"])
		if t < acc + leg_total or i == legs.size() - 1:
			return _sample_leg(points, leg, i, t - acc, grid)
		acc += leg_total
	return {"pos": Vector3.ZERO, "yaw": 0.0, "clip": "idle", "speed": 1.0, "can_fidget": true}


static func _sample_leg(
	points: Array, leg: Dictionary, idx: int, local_t: float, grid: BuildGrid
) -> Dictionary:
	var pause_ticks := float(leg["pause"])
	var walk_ticks := float(leg["walk"])
	var wp: Dictionary = points[idx]
	if local_t < pause_ticks or walk_ticks <= 0.0:
		var pos := _ground_pos(grid, wp["pos"] as Vector3)
		return {
			"pos": pos,
			"yaw": _yaw_toward(pos, wp["face"]),
			"clip": "idle",
			"speed": 1.0,
			"can_fidget": bool(wp.get("pause", true)),
		}
	var nxt: Dictionary = points[(idx + 1) % points.size()]
	var frac := clampf((local_t - pause_ticks) / walk_ticks, 0.0, 1.0)
	var a := wp["pos"] as Vector3
	var b := nxt["pos"] as Vector3
	var pos := _ground_pos(grid, a.lerp(b, frac))
	return {
		"pos": pos,
		"yaw": _yaw_toward(a, b),
		"clip": "walk",
		"speed": PATROL_WALK_MPS / StaffCharacters.CLIP_WALK_MPS[StaffMember.Role.RAMP],
		"can_fidget": false,
	}


static func _compile_loop(points: Array[Dictionary]) -> Dictionary:
	var legs: Array[Dictionary] = []
	var pause_starts: Array[int] = []
	var total_ticks := 0
	var count := points.size()
	for i in count:
		var wp := points[i]
		var nxt := points[(i + 1) % count]
		var pause_t := PAUSE_TICKS if bool(wp.get("pause", true)) else 0
		if pause_t > 0:
			pause_starts.append(total_ticks)
		var dist := (
			Vector2(
				(nxt["pos"] as Vector3).x - (wp["pos"] as Vector3).x,
				(nxt["pos"] as Vector3).z - (wp["pos"] as Vector3).z,
			)
			. length()
		)
		var walk_t := 0
		if dist >= 0.05:
			walk_t = maxi(1, roundi(dist * float(SimClock.TICK_RATE) / PATROL_WALK_MPS))
		var leg_t := pause_t + walk_t
		legs.append({"pause": pause_t, "walk": walk_t, "total": leg_t})
		total_ticks += leg_t
	return {
		"points": points,
		"legs": legs,
		"total_ticks": total_ticks,
		"pause_starts": pause_starts,
	}


static func _slot_phase_ticks(loop: Dictionary, slot_idx: int) -> int:
	if slot_idx <= 0:
		return 0
	var pause_starts: Array = loop.get("pause_starts", [])
	var total := int(loop.get("total_ticks", 0))
	if total <= 0:
		return 0
	var m := pause_starts.size()
	if m >= 2 and slot_idx < m:
		var order := _spread_order(m)
		return int(pause_starts[order[slot_idx]])
	var phases: Array[int] = []
	for k in slot_idx:
		if k < m and m >= 2:
			phases.append(int(pause_starts[_spread_order(m)[k]]))
		else:
			phases.append(_largest_gap_midpoint(phases, total))
	return _largest_gap_midpoint(phases, total)


static func _largest_gap_midpoint(phases: Array[int], total: int) -> int:
	if phases.is_empty():
		return 0
	var sorted := phases.duplicate()
	sorted.sort()
	var best_gap := -1
	var best_mid := 0
	for i in sorted.size():
		var cur := int(sorted[i])
		var nxt := int(sorted[(i + 1) % sorted.size()])
		var gap := (nxt - cur) if i + 1 < sorted.size() else (total - cur + nxt)
		if gap > best_gap:
			best_gap = gap
			@warning_ignore("integer_division")
			best_mid = (cur + gap / 2) % total
	return best_mid


static func _spread_order(count: int) -> Array[int]:
	var order: Array[int] = [0]
	var used := {0: true}
	var step := maxi(1, count / 2)
	while order.size() < count:
		var cand := (order[order.size() - 1] + step) % count
		while used.has(cand):
			cand = (cand + 1) % count
		order.append(cand)
		used[cand] = true
	return order


static func _collect_stands(flight_sim: FlightSim) -> Array[Dictionary]:
	if flight_sim == null:
		return []
	var by_key := {}
	var ordered: Array[Dictionary] = []
	var has_sources := (
		flight_sim.stand_source.is_valid() or flight_sim.remote_ground_source.is_valid()
	)
	if has_sources:
		var grounds := flight_sim.stand_grounds()
		var ids := grounds.keys()
		ids.sort_custom(BusGatePairing.remote_sort_less)
		for sid: Variant in ids:
			var g: Dictionary = grounds[sid]
			var s: Dictionary = g.get("stand", {})
			_append_unique_stand(
				s, String(g.get("max_class", PlaneClasses.MEDIUM)), by_key, ordered
			)
	if ordered.is_empty():
		for fid in flight_sim.flight_ids():
			var s := flight_sim.flight_stand(fid)
			_append_unique_stand(s, PlaneClasses.MEDIUM, by_key, ordered)
	ordered.sort_custom(_stand_perimeter_less)
	return ordered


static func _append_unique_stand(
	stand: Dictionary, max_class: String, by_key: Dictionary, out: Array[Dictionary]
) -> void:
	if not StandPlacement.is_stand(stand):
		return
	var key := (
		"%s:%d:%.2f:%.2f"
		% [
			StandPlacement.side_of(stand),
			int(stand["exit"]),
			float(stand["x"]),
			float(stand["wall_z"]),
		]
	)
	if by_key.has(key):
		return
	by_key[key] = true
	out.append({"stand": stand, "max_class": max_class})


static func _stand_perimeter_less(a: Dictionary, b: Dictionary) -> bool:
	var sa: Dictionary = a["stand"]
	var sb: Dictionary = b["stand"]
	var rank_a := _side_rank(StandPlacement.side_of(sa))
	var rank_b := _side_rank(StandPlacement.side_of(sb))
	if rank_a != rank_b:
		return rank_a < rank_b
	var side := StandPlacement.side_of(sa)
	if side == StandPlacement.WEST:
		return float(sa["wall_z"]) > float(sb["wall_z"])
	if side == StandPlacement.EAST:
		return float(sa["wall_z"]) < float(sb["wall_z"])
	return float(sa["x"]) < float(sb["x"])


static func _side_rank(side: String) -> int:
	if side == StandPlacement.WEST:
		return 0
	if side == StandPlacement.NORTH:
		return 1
	return 2


static func _single_stand_points(entry: Dictionary, grid: BuildGrid) -> Array[Dictionary]:
	var stand: Dictionary = entry["stand"]
	var twin := StandPlacement.north_twin(stand)
	var pt := StandPlacement.stand_point(twin)
	var wall_z := float(twin["wall_z"])
	var face := StandPlacement.to_world(stand, Vector3(pt.x, 0.0, wall_z - STAND_LOOK_M))
	var excl := _stand_exclusion_rects([entry], grid)
	var locals: Array[Vector3] = [
		Vector3(pt.x - STARBOARD_INNER_M, 0.0, wall_z - WALL_CLEAR_M),
		Vector3(pt.x - STARBOARD_MID_X_M, 0.0, wall_z - WALL_CLEAR_M),
		Vector3(pt.x - STARBOARD_OUTER_M, 0.0, wall_z - WALL_CLEAR_M),
		Vector3(pt.x - STARBOARD_OUTER_M, 0.0, wall_z - FORWARD_CLEAR_M),
		Vector3(pt.x - STARBOARD_MID_X_M, 0.0, wall_z - FORWARD_CLEAR_M),
		Vector3(pt.x - STARBOARD_INNER_M - 0.2, 0.0, wall_z - FORWARD_CLEAR_M),
	]
	var out: Array[Dictionary] = []
	for i in locals.size():
		var world := StandPlacement.to_world(stand, locals[i])
		if _point_blocked(world, excl, grid):
			continue
		if not out.is_empty() and _segment_blocked(out[out.size() - 1]["pos"], world, excl, grid):
			continue
		out.append({"pos": world, "face": face, "pause": true})
	while (
		out.size() >= 2 and _segment_blocked(out[out.size() - 1]["pos"], out[0]["pos"], excl, grid)
	):
		out.pop_back()
	if out.is_empty():
		var p0 := StandPlacement.to_world(stand, locals[0])
		if not _point_blocked(p0, excl, grid):
			out.append({"pos": p0, "face": face, "pause": true})
	return out


static func _multi_stand_points(stands: Array[Dictionary], grid: BuildGrid) -> Array[Dictionary]:
	var excl := _stand_exclusion_rects(stands, grid)
	var anchors: Array[Dictionary] = []
	for entry in stands:
		var stand: Dictionary = entry["stand"]
		var twin := StandPlacement.north_twin(stand)
		var pt := StandPlacement.stand_point(twin)
		var wall_z := float(twin["wall_z"])
		var face := StandPlacement.to_world(stand, Vector3(pt.x, 0.0, wall_z - STAND_LOOK_M))
		var p0 := StandPlacement.to_world(
			stand, Vector3(pt.x - STARBOARD_INNER_M, 0.0, wall_z - WALL_CLEAR_M)
		)
		if not _point_blocked(p0, excl, grid):
			anchors.append({"pos": p0, "face": face, "pause": true, "entry": entry})
	if anchors.size() < 2:
		return _single_stand_points(stands[0], grid)
	var built: Array[Dictionary] = [anchors[0]]
	var legs_between: Array[Array] = []
	for i in range(1, anchors.size()):
		var cur_anchor := built[built.size() - 1]
		var cand := anchors[i]
		var detour := _clear_detour(cur_anchor["pos"], cand["pos"], excl, grid)
		if bool(detour["ok"]):
			legs_between.append(detour["points"])
			built.append(cand)
	if built.size() >= 2:
		var close_detour := _clear_detour(
			built[built.size() - 1]["pos"], built[0]["pos"], excl, grid
		)
		if bool(close_detour["ok"]):
			var out: Array[Dictionary] = []
			for i in built.size():
				var cur := built[i]
				out.append({"pos": cur["pos"], "face": cur["face"], "pause": true})
				var mids: Array = (
					legs_between[i] if i < legs_between.size() else close_detour["points"]
				)
				var nxt := built[(i + 1) % built.size()]
				for mid_pos: Vector3 in mids:
					out.append({"pos": mid_pos, "face": nxt["pos"], "pause": false})
			return out
	return _single_stand_points(built[0]["entry"], grid)


static func _stand_exclusion_rects(stands: Array[Dictionary], grid: BuildGrid) -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for entry in stands:
		var stand: Dictionary = entry["stand"]
		var max_class := String(entry.get("max_class", PlaneClasses.MEDIUM))
		var twin := StandPlacement.north_twin(stand)
		var pt := StandPlacement.stand_point(twin)
		var wall_z := float(twin["wall_z"])
		var tail_z := _max_tail_z(pt, max_class) - 1.2
		var half_span := StandEnvelope.half_span(max_class) + 1.2
		var has_wall := int(stand.get("exit", 0)) != 0
		if not has_wall and grid != null:
			var behind := StandPlacement.to_world(
				stand, Vector3(float(twin["x"]), 0.0, wall_z + 1.5)
			)
			has_wall = grid.is_indoor(grid.world_to_cell(behind))
		var port_wall_x := pt.x + (5.2 if has_wall else 2.4)
		var nose_south := (wall_z + 2.0) if has_wall else (wall_z - 0.3)
		var local_rects: Array[Rect2] = [
			Rect2(pt.x - 2.4, tail_z, port_wall_x - (pt.x - 2.4), nose_south - tail_z),
			Rect2(pt.x - half_span, tail_z, 2.0 * half_span, (wall_z - 5.0) - tail_z),
		]
		if has_wall:
			local_rects.append(Rect2(pt.x - half_span, wall_z - 1.6, 2.0 * half_span, 60.0))
		for wr in StandPlacement.rects_to_world(stand, local_rects):
			rects.append(wr)
	return rects


static func _max_tail_z(stand_pt: Vector3, plane_class: String) -> float:
	var spec: Dictionary = PlaneClasses.CLASSES.get(
		plane_class, PlaneClasses.CLASSES[PlaneClasses.MEDIUM]
	)
	var models: Array = spec["models"]
	var min_z := stand_pt.z - StandPlacement.TAIL_M
	for model: String in models:
		var shape: Dictionary = PlaneModels.PLANES[model]
		var origin := stand_pt + PlaneClasses.stand_offset(model)
		min_z = minf(min_z, origin.z - float(shape["tail"]))
	return min_z


static func _find_egress(
	from_pos: Vector3, stands: Array[Dictionary], excl: Array[Rect2], grid: BuildGrid
) -> Dictionary:
	if not _point_blocked(from_pos, excl, grid):
		return {"ok": true, "pos": from_pos}
	var cands: Array[Vector3] = []
	for entry in stands:
		var stand: Dictionary = entry["stand"]
		var twin := StandPlacement.north_twin(stand)
		var pt := StandPlacement.stand_point(twin)
		var wall_z := float(twin["wall_z"])
		for off in [
			Vector3(pt.x - STARBOARD_INNER_M, 0.0, wall_z - WALL_CLEAR_M),
			Vector3(pt.x - STARBOARD_MID_X_M, 0.0, wall_z - WALL_CLEAR_M),
			Vector3(pt.x - STARBOARD_INNER_M, 0.0, wall_z - FORWARD_CLEAR_M),
		]:
			cands.append(StandPlacement.to_world(stand, off))
	for r in [2.0, 4.0, 6.0]:
		for ang_i in 8:
			var ang := float(ang_i) * PI * 0.25
			cands.append(from_pos + Vector3(cos(ang) * r, 0.0, sin(ang) * r))
	var best_pos := Vector3.ZERO
	var best_d := INF
	var found := false
	for cand in cands:
		if _point_blocked(cand, excl, grid):
			continue
		if grid != null and BaggageShuttle.segment_hits_wall(grid, from_pos, cand):
			continue
		if _egress_crosses_core(from_pos, cand, stands):
			continue
		var d := Vector2(from_pos.x, from_pos.z).distance_to(Vector2(cand.x, cand.z))
		if d < best_d:
			best_d = d
			best_pos = cand
			found = true
	return {"ok": found, "pos": best_pos}


static func _egress_crosses_core(
	from_pos: Vector3, to_pos: Vector3, stands: Array[Dictionary]
) -> bool:
	var a := Vector2(from_pos.x, from_pos.z)
	var b := Vector2(to_pos.x, to_pos.z)
	for entry in stands:
		var stand: Dictionary = entry["stand"]
		var twin := StandPlacement.north_twin(stand)
		var pt := StandPlacement.stand_point(twin)
		var wall_z := float(twin["wall_z"])
		var core_local := Rect2(pt.x - 1.2, pt.z - StandPlacement.TAIL_M, 2.4, wall_z - pt.z)
		for wr in StandPlacement.rects_to_world(stand, [core_local]):
			if not wr.has_point(a) and _segment_hits_rect(a, b, wr):
				return true
	return false


static func _clear_detour(
	from: Vector3, to: Vector3, excl: Array[Rect2], grid: BuildGrid
) -> Dictionary:
	if not _segment_blocked(from, to, excl, grid):
		return {"ok": true, "points": [] as Array[Vector3]}
	var bounds := Rect2(Vector2(from.x, from.z), Vector2.ZERO).expand(Vector2(to.x, to.z))
	for r in excl:
		bounds = bounds.merge(r)
	bounds = bounds.grow(DETOUR_MARGIN_M)
	var cols := maxi(4, ceili(bounds.size.x / DETOUR_CELL_M) + 1)
	var rows := maxi(4, ceili(bounds.size.y / DETOUR_CELL_M) + 1)
	var start := _world_to_detour(bounds, from, cols, rows)
	var goal := _world_to_detour(bounds, to, cols, rows)
	var cfg := {
		"bounds": bounds,
		"cols": cols,
		"rows": rows,
		"start": start,
		"goal": goal,
		"from": from,
		"to": to,
	}
	var path_cells := _detour_bfs(cfg, excl, grid)
	if path_cells.size() < 2:
		return {"ok": false, "points": [] as Array[Vector3]}
	var pts: Array[Vector3] = [from]
	for k in range(1, path_cells.size() - 1):
		pts.append(_detour_to_world(bounds, path_cells[k]))
	pts.append(to)
	var smoothed := _smooth_detour(pts, excl, grid)
	for i in smoothed.size() - 1:
		if _segment_blocked(smoothed[i], smoothed[i + 1], excl, grid):
			return {"ok": false, "points": [] as Array[Vector3]}
	if smoothed.size() <= 2:
		return {"ok": true, "points": [] as Array[Vector3]}
	return {"ok": true, "points": smoothed.slice(1, smoothed.size() - 1)}


static func _detour_bfs(
	cfg: Dictionary,
	excl: Array[Rect2],
	grid: BuildGrid,
) -> Array[Vector2i]:
	var start: Vector2i = cfg["start"]
	var goal: Vector2i = cfg["goal"]
	var cols: int = cfg["cols"]
	var rows: int = cfg["rows"]
	var visited := {start: true}
	var parent := {}
	var queue: Array[Vector2i] = [start]
	var head := 0
	var steps := [
		Vector2i(1, 0),
		Vector2i(-1, 0),
		Vector2i(0, 1),
		Vector2i(0, -1),
		Vector2i(1, 1),
		Vector2i(1, -1),
		Vector2i(-1, 1),
		Vector2i(-1, -1),
	]
	while head < queue.size():
		var cur := queue[head]
		head += 1
		if cur == goal:
			return _trace_detour(start, goal, parent)
		for d: Vector2i in steps:
			var nxt := cur + d
			if nxt.x < 0 or nxt.y < 0 or nxt.x >= cols or nxt.y >= rows or visited.has(nxt):
				continue
			if _detour_step_blocked(cfg, cur, nxt, excl, grid):
				continue
			visited[nxt] = true
			parent[nxt] = cur
			queue.append(nxt)
	return []


static func _detour_step_blocked(
	cfg: Dictionary, cur: Vector2i, nxt: Vector2i, excl: Array[Rect2], grid: BuildGrid
) -> bool:
	var bounds: Rect2 = cfg["bounds"]
	var start: Vector2i = cfg["start"]
	var goal: Vector2i = cfg["goal"]
	var a: Vector3 = cfg["from"] if cur == start else _detour_to_world(bounds, cur)
	var b: Vector3 = cfg["to"] if nxt == goal else _detour_to_world(bounds, nxt)
	if nxt != goal and _point_blocked(b, excl, grid):
		return true
	return _segment_blocked(a, b, excl, grid)


static func _trace_detour(start: Vector2i, goal: Vector2i, parent: Dictionary) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var cur := goal
	while cur != start and parent.has(cur):
		out.append(cur)
		cur = parent[cur]
	out.append(start)
	out.reverse()
	return out


static func _smooth_detour(
	pts: Array[Vector3], excl: Array[Rect2], grid: BuildGrid
) -> Array[Vector3]:
	var out: Array[Vector3] = [pts[0]]
	var i := 0
	while i < pts.size() - 1:
		var best := i + 1
		for j in range(pts.size() - 1, i + 1, -1):
			if not _segment_blocked(pts[i], pts[j], excl, grid):
				best = j
				break
		out.append(pts[best])
		i = best
	return out


static func _world_to_detour(bounds: Rect2, pos: Vector3, cols: int, rows: int) -> Vector2i:
	return Vector2i(
		clampi(roundi((pos.x - bounds.position.x) / DETOUR_CELL_M), 0, cols - 1),
		clampi(roundi((pos.z - bounds.position.y) / DETOUR_CELL_M), 0, rows - 1),
	)


static func _detour_to_world(bounds: Rect2, cell: Vector2i) -> Vector3:
	return Vector3(
		bounds.position.x + float(cell.x) * DETOUR_CELL_M,
		0.0,
		bounds.position.y + float(cell.y) * DETOUR_CELL_M,
	)


static func _point_blocked(pos: Vector3, excl: Array[Rect2], grid: BuildGrid) -> bool:
	if grid != null and grid.is_indoor(grid.world_to_cell(pos)):
		return true
	var p2 := Vector2(pos.x, pos.z)
	for r in excl:
		if r.has_point(p2):
			return true
	return false


static func _segment_blocked(a: Vector3, b: Vector3, excl: Array[Rect2], grid: BuildGrid) -> bool:
	if grid != null and BaggageShuttle.segment_hits_wall(grid, a, b):
		return true
	var a2 := Vector2(a.x, a.z)
	var b2 := Vector2(b.x, b.z)
	for r in excl:
		if _segment_hits_rect(a2, b2, r):
			return true
	return false


static func _segment_hits_rect(a: Vector2, b: Vector2, rect: Rect2) -> bool:
	if rect.has_point(a) or rect.has_point(b):
		return true
	var min_x := minf(a.x, b.x)
	var max_x := maxf(a.x, b.x)
	var min_y := minf(a.y, b.y)
	var max_y := maxf(a.y, b.y)
	if max_x < rect.position.x or min_x > rect.end.x:
		return false
	if max_y < rect.position.y or min_y > rect.end.y:
		return false
	var d := b - a
	var t_min := 0.0
	var t_max := 1.0
	for axis in 2:
		var p := a[axis]
		var delta := d[axis]
		var lo := rect.position[axis]
		var hi := rect.end[axis]
		if absf(delta) < 1e-6:
			if p < lo or p > hi:
				return false
		else:
			var t1 := (lo - p) / delta
			var t2 := (hi - p) / delta
			if t1 > t2:
				var tmp := t1
				t1 = t2
				t2 = tmp
			t_min = maxf(t_min, t1)
			t_max = minf(t_max, t2)
			if t_min > t_max:
				return false
	return true


static func _fallback_points(grid: BuildGrid, staff: StaffSim) -> Array[Dictionary]:
	if grid != null and staff != null and staff.sim != null:
		var exit_pts := _exit_fallback_points(grid, staff.sim.layout.exits)
		if not exit_pts.is_empty():
			return exit_pts
	if grid != null:
		for obj_id in grid.object_ids():
			var rec := grid.get_object(obj_id)
			if StringName(rec.get("def", &"")) == BaggageSim.CART_DEF:
				var cart_w := grid.cell_to_world(rec["anchor"])
				return _validated_fallback_tri(
					grid,
					cart_w + Vector3(-2.0, 0.0, -2.0),
					Vector3(0.0, 0.0, -1.0),
					cart_w,
				)
		var base := grid.origin + Vector3(float(grid.size.x) * 0.5, 0.0, -3.5)
		return _validated_fallback_tri(
			grid, base, Vector3(0.0, 0.0, -1.0), base + Vector3(0.0, 0.0, -5.0)
		)
	return []


static func _exit_fallback_points(grid: BuildGrid, exits: Array) -> Array[Dictionary]:
	var chosen := {}
	for exit_id: int in exits:
		var rec := grid.get_object(exit_id)
		if rec.is_empty():
			continue
		var step := DoorPlacement.back_step(rec["facing"])
		var side := StandPlacement.side_of_step(step)
		if side == "":
			continue
		if chosen.is_empty() or side == StandPlacement.NORTH:
			chosen = {"rec": rec, "step": step}
			if side == StandPlacement.NORTH:
				break
	if chosen.is_empty():
		return []
	var step: Vector2i = chosen["step"]
	var door_cell: Vector2i = chosen["rec"]["anchor"]
	var door_w := grid.cell_to_world(door_cell)
	var out_dir := Vector3(float(step.x), 0.0, float(step.y))
	var anchor := door_w + out_dir * FALLBACK_STANDOFF_M
	var face := anchor + out_dir * 4.5
	return _validated_fallback_tri(grid, anchor, out_dir, face)


static func _validated_fallback_tri(
	grid: BuildGrid, anchor: Vector3, out_dir: Vector3, face: Vector3
) -> Array[Dictionary]:
	var tan_dir := Vector3(-out_dir.z, 0.0, out_dir.x)
	var cands: Array[Vector3] = [
		anchor,
		anchor + tan_dir * FALLBACK_SPAN_M,
		anchor + tan_dir * (FALLBACK_SPAN_M * 0.5) + out_dir * FALLBACK_OUT_M,
		anchor - tan_dir * FALLBACK_SPAN_M,
	]
	var out: Array[Dictionary] = []
	for cand in cands:
		if _fallback_point_blocked(grid, cand):
			continue
		if not out.is_empty() and _segment_blocked(out[out.size() - 1]["pos"], cand, [], grid):
			continue
		out.append({"pos": cand, "face": face, "pause": true})
		if out.size() >= 3:
			break
	while out.size() >= 2 and _segment_blocked(out[out.size() - 1]["pos"], out[0]["pos"], [], grid):
		out.pop_back()
	return out


static func _fallback_point_blocked(grid: BuildGrid, pos: Vector3) -> bool:
	if grid == null:
		return false
	if grid.is_indoor(grid.world_to_cell(pos)):
		return true
	var road_z := grid.origin.z + float(grid.size.y)
	return pos.z >= road_z - 1.5


static func _ground_pos(grid: BuildGrid, pos: Vector3) -> Vector3:
	return Vector3(pos.x, BaggageShuttle.ground_y(grid, pos), pos.z)


static func _yaw_toward(from: Vector3, target: Vector3) -> float:
	var delta := Vector2(target.x - from.x, target.z - from.z)
	if delta.length_squared() < 1e-6:
		return 0.0
	return atan2(delta.x, delta.y)
