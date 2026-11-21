class_name BaggageShuttle
extends RefCounted
## One automated baggage_cart trip from a bag room out to a parked plane's
## stand during LOAD_LEAD_TICKS (decision baggage-loop-completion-connect-
## gated-penalties-visible-wait). Plain data owned by BaggageSim; BaggageViews
## reads pose_at() and carrying_bags() to animate the cart.
##
## `driver_staff_id` is reserved for Tier-2 Ramp Agent staffing (board
## eddcd9cd) to bind a Ramp Agent driver/loader to the trip without rewriting
## the shuttle state machine.

enum Phase { OUTBOUND, UNLOADING, RETURNING }

## Travel timing bounds in sim ticks (20 ticks/s), keeping outbound + unload
## strictly inside LOAD_LEAD_TICKS (200 ticks) before doors close.
const MIN_TRAVEL_TICKS := 40
const MAX_TRAVEL_TICKS := 140
const UNLOAD_TICKS := 20
const TRAVEL_TICKS_PER_M := 3.0
## Starboard-forward loading offsets in a north-twin stand frame, clear of the
## wing, nose/propeller, and port passenger walk.
const SMALL_CARGO_OFFSET := Vector3(-2.6, 0.0, 5.8)
const LARGE_CARGO_OFFSET := Vector3(-5.0, 0.0, 1.5)
const FALLBACK_CARGO_OFFSET := Vector3(-3.5, 0.0, 6.5)
const ROUTE_PAD_CELLS := 4

var id := 0
var cart_id := 0
var flight := ""
var phase := Phase.OUTBOUND
var start_tick := 0
var arrive_tick := 0
var unload_tick := 0
var return_tick := 0
var origin_world := Vector3.ZERO
var origin_yaw := 0.0
var target_world := Vector3.ZERO
var target_yaw := 0.0
## Ordered world path points [origin_world, ..., target_world]; empty falls back
## to a direct [origin_world, target_world] segment.
var waypoints: Array[Vector3] = []
var bag_ids: Array[int] = []
## Staff member id assigned as driver/loader (0 = automated / unassigned).
var driver_staff_id := 0


func carrying_bags() -> bool:
	return phase == Phase.OUTBOUND or phase == Phase.UNLOADING


## Where the cart parks beside the plane at `stand` (StandPlacement): starboard
## forward fuselage, away from the port passenger walk and jet bridge.
static func cargo_point(stand: Dictionary, model_name := "") -> Vector3:
	var twin := StandPlacement.north_twin(stand)
	var at: Vector3
	if model_name != "" and PlaneClasses.self_taxis(model_name):
		at = StandPlacement.stand_point(twin) + SMALL_CARGO_OFFSET
	elif model_name != "" and PlaneModels.PLANES.has(model_name):
		at = StandPlacement.door_point(twin, model_name) + LARGE_CARGO_OFFSET
	else:
		at = StandPlacement.stand_point(twin) + FALLBACK_CARGO_OFFSET
	return StandPlacement.to_world(stand, at)


## Surface height under `point`: site paving/ramp height on a SiteGrid, else
## the test grid's origin height.
static func ground_y(grid: BuildGrid, point: Vector3) -> float:
	if grid is SiteGrid:
		return PlaneView.ground_height_at(point)
	return grid.origin.y if grid != null else 0.0


## Deterministic cart transform at integer sim `at_tick`.
func pose_at(at_tick: int, grid: BuildGrid) -> Transform3D:
	var pts: Array[Vector3] = waypoints if waypoints.size() >= 2 else [origin_world, target_world]
	var pos: Vector3
	var yaw := origin_yaw
	if phase == Phase.OUTBOUND:
		var span := maxi(1, arrive_tick - start_tick)
		var t := clampf(float(at_tick - start_tick) / float(span), 0.0, 1.0)
		var sample := _sample_path(pts, t, origin_yaw)
		pos = sample["pos"]
		yaw = _blend_yaw(origin_yaw, sample["yaw"], target_yaw, t)
	elif phase == Phase.UNLOADING:
		pos = target_world
		yaw = target_yaw
	else:
		var span := maxi(1, return_tick - unload_tick)
		var t := clampf(float(at_tick - unload_tick) / float(span), 0.0, 1.0)
		var rev := pts.duplicate()
		rev.reverse()
		var sample := _sample_path(rev, t, target_yaw)
		pos = sample["pos"]
		yaw = _blend_yaw(target_yaw, sample["yaw"], origin_yaw, t)
	pos.y = ground_y(grid, pos)
	return Transform3D(Basis(Vector3.UP, yaw), pos)


## Plans a world polyline [origin, ..., target] on the exterior apron without
## crossing terminal walls. If the cart sits inside an enclosed bag room with no
## exterior door/opening, exits straight through the room's nearest exterior
## wall face onto the apron, and keeps every subsequent apron segment wall-clear.
static func plan_route(grid: BuildGrid, origin: Vector3, target: Vector3) -> Array[Vector3]:
	var direct: Array[Vector3] = [origin, target]
	if grid == null or not segment_hits_wall(grid, origin, target):
		return direct
	var bounds := _search_bounds(grid, origin, target)
	var target_cell := _clamp_to_rect(grid.world_to_cell(target), bounds)
	var origin_cell := _clamp_to_rect(grid.world_to_cell(origin), bounds)
	var field := _apron_field(grid, bounds, target_cell)
	var dist_from_target: Dictionary = field["dist"]
	var apron_parent: Dictionary = field["parent"]
	# Case 1: origin is already on the connected exterior apron (or reaches target un-walled).
	if dist_from_target.has(origin_cell):
		var ext_cells := _trace_to_target(origin_cell, target_cell, apron_parent)
		return _build_apron_points(grid, origin, target, ext_cells, false)
	# Case 2: cart is inside a bag_room — prefer an exterior door/opening first,
	# else exit directly through the bag room's own exterior wall face.
	var room_id := grid.room_at(origin_cell)
	if room_id != 0:
		var room_rect: Rect2i = grid.get_room(room_id).get("rect", Rect2i())
		var room_route := _route_from_room(
			grid,
			origin,
			origin_cell,
			target,
			target_cell,
			room_rect,
			dist_from_target,
			apron_parent
		)
		if not room_route.is_empty():
			return room_route
	# Case 3: trapped inside manual/nested walls — 0-1 BFS out to nearest exterior cell.
	var escape := _escape_to_apron(grid, bounds, origin_cell, dist_from_target)
	if escape.is_empty():
		return direct
	var ext_entry: Vector2i = escape[escape.size() - 1]
	var apron_tail := _trace_to_target(ext_entry, target_cell, apron_parent)
	var pts: Array[Vector3] = [origin]
	for i in range(1, escape.size()):
		var w := grid.cell_to_world(escape[i])
		w.y = origin.y
		pts.append(w)
	var tail_pts := _build_apron_points(
		grid, grid.cell_to_world(ext_entry), target, apron_tail, true
	)
	for i in range(1, tail_pts.size()):
		pts.append(tail_pts[i])
	return pts


static func route_length(pts: Array[Vector3]) -> float:
	var total := 0.0
	for i in range(1, pts.size()):
		total += Vector2(pts[i].x - pts[i - 1].x, pts[i].z - pts[i - 1].z).length()
	return total


## True when segment `a -> b` crosses any grid wall edge (or clips a wall corner).
static func segment_hits_wall(
	grid: BuildGrid, a: Vector3, b: Vector3, allow_doors := false
) -> bool:
	if grid == null:
		return false
	var dist := Vector2(b.x - a.x, b.z - a.z).length()
	var steps := maxi(2, int(ceilf(dist / 0.25)))
	var prev := grid.world_to_cell(a)
	for i in range(1, steps + 1):
		var p := a.lerp(b, float(i) / float(steps))
		var cell := grid.world_to_cell(p)
		if cell == prev:
			continue
		if _step_walled(grid, prev, cell, allow_doors):
			return true
		prev = cell
	return false


static func _step_walled(
	grid: BuildGrid, from_cell: Vector2i, to_cell: Vector2i, allow_doors := false
) -> bool:
	var diff := to_cell - from_cell
	if diff == Vector2i.ZERO:
		return false
	if absi(diff.x) + absi(diff.y) == 1:
		return _edge_walled(grid, from_cell, diff, allow_doors)
	if absi(diff.x) == 1 and absi(diff.y) == 1:
		var sx := Vector2i(diff.x, 0)
		var sy := Vector2i(0, diff.y)
		var via_x := (
			_edge_walled(grid, from_cell, sx, allow_doors)
			or _edge_walled(grid, from_cell + sx, sy, allow_doors)
		)
		var via_y := (
			_edge_walled(grid, from_cell, sy, allow_doors)
			or _edge_walled(grid, from_cell + sy, sx, allow_doors)
		)
		return via_x or via_y
	# Multi-cell jump safety fallback.
	var steps := maxi(absi(diff.x), absi(diff.y)) * 2
	var wa := grid.cell_to_world(from_cell)
	var wb := grid.cell_to_world(to_cell)
	var prev := from_cell
	for i in range(1, steps + 1):
		var c := grid.world_to_cell(wa.lerp(wb, float(i) / float(steps)))
		if c != prev:
			if _step_walled(grid, prev, c, allow_doors):
				return true
			prev = c
	return false


static func _edge_walled(
	grid: BuildGrid, cell: Vector2i, step: Vector2i, allow_doors := false
) -> bool:
	var side := BuildGrid.SIDE_STEP.find(step)
	if side < 0:
		return false
	if grid.in_bounds(cell):
		var kind := grid.wall_kind(cell, side)
		if kind != BuildGrid.WallKind.NONE and (not allow_doors or kind != BuildGrid.WallKind.DOOR):
			return true
	var other := cell + step
	var opp := (side + 2) % 4
	if grid.in_bounds(other):
		var kind2 := grid.wall_kind(other, opp)
		if (
			kind2 != BuildGrid.WallKind.NONE
			and (not allow_doors or kind2 != BuildGrid.WallKind.DOOR)
		):
			return true
	return false


static func _search_bounds(grid: BuildGrid, origin: Vector3, target: Vector3) -> Rect2i:
	var area := grid.flood_area()
	var co := grid.world_to_cell(origin)
	var ct := grid.world_to_cell(target)
	var merged := Rect2i(co, Vector2i.ONE).merge(Rect2i(ct, Vector2i.ONE))
	if area.size != Vector2i.ZERO:
		merged = merged.merge(area)
	return merged.grow(ROUTE_PAD_CELLS).intersection(Rect2i(Vector2i.ZERO, grid.size))


static func _clamp_to_rect(cell: Vector2i, rect: Rect2i) -> Vector2i:
	return Vector2i(
		clampi(cell.x, rect.position.x, rect.end.x - 1),
		clampi(cell.y, rect.position.y, rect.end.y - 1)
	)


static func _apron_field(grid: BuildGrid, bounds: Rect2i, target_cell: Vector2i) -> Dictionary:
	var filter_indoor := not grid.is_indoor(target_cell)
	var dist := {target_cell: 0}
	var parent := {}
	var frontier: Array[Vector2i] = [target_cell]
	while not frontier.is_empty():
		var best_idx := 0
		var best_cost: int = dist[frontier[0]]
		for i in range(1, frontier.size()):
			var c: int = dist[frontier[i]]
			if c < best_cost:
				best_cost = c
				best_idx = i
		var cur: Vector2i = frontier[best_idx]
		frontier.remove_at(best_idx)
		var d: int = dist[cur]
		for step in BuildGrid.SIDE_STEP:
			var nxt: Vector2i = cur + step
			if not bounds.has_point(nxt):
				continue
			if (filter_indoor and grid.is_indoor(nxt)) or _edge_walled(grid, cur, step, false):
				continue
			var step_cost := 4 if _touches_any_wall(grid, nxt) else 1
			var cand := d + step_cost
			if cand < int(dist.get(nxt, 1 << 29)):
				dist[nxt] = cand
				parent[nxt] = cur
				frontier.append(nxt)
	return {"dist": dist, "parent": parent}


static func _touches_any_wall(grid: BuildGrid, cell: Vector2i) -> bool:
	if not grid.in_bounds(cell):
		return false
	for side in 4:
		if grid.has_wall(cell, side):
			return true
	return false


static func _trace_to_target(
	start_cell: Vector2i, target_cell: Vector2i, parent: Dictionary
) -> Array[Vector2i]:
	var path: Array[Vector2i] = [start_cell]
	var cur := start_cell
	while cur != target_cell and parent.has(cur):
		cur = parent[cur]
		path.append(cur)
	return path


static func _route_from_room(
	grid: BuildGrid,
	origin: Vector3,
	origin_cell: Vector2i,
	target: Vector3,
	target_cell: Vector2i,
	room_rect: Rect2i,
	dist_from_target: Dictionary,
	apron_parent: Dictionary,
) -> Array[Vector3]:
	if room_rect.size == Vector2i.ZERO:
		return []
	# First BFS within the bag room (without crossing interior walls) to find
	# either an open/door exit onto the apron or the nearest exterior wall face.
	var room_dist := {origin_cell: 0}
	var room_parent := {}
	var queue: Array[Vector2i] = [origin_cell]
	var head := 0
	while head < queue.size():
		var cur := queue[head]
		head += 1
		var d: int = room_dist[cur]
		for step in BuildGrid.SIDE_STEP:
			var nxt: Vector2i = cur + step
			if not room_rect.has_point(nxt) or room_dist.has(nxt):
				continue
			if _edge_walled(grid, cur, step, true):
				continue
			room_dist[nxt] = d + 1
			room_parent[nxt] = cur
			queue.append(nxt)
	var best_open := {}
	var best_walled := {}
	for cell: Vector2i in room_dist:
		for step in BuildGrid.SIDE_STEP:
			var ext: Vector2i = cell + step
			if room_rect.has_point(ext) or not dist_from_target.has(ext):
				continue
			var score: int = int(room_dist[cell]) + 1 + int(dist_from_target[ext])
			var door_open := not _edge_walled(grid, cell, step, true)
			if door_open:
				if best_open.is_empty() or score < int(best_open["score"]):
					best_open = {"inside": cell, "ext": ext, "score": score}
			else:
				if best_walled.is_empty() or score < int(best_walled["score"]):
					best_walled = {"inside": cell, "ext": ext, "score": score}
	var chosen := best_open if not best_open.is_empty() else best_walled
	if chosen.is_empty():
		return []
	var inside_cell: Vector2i = chosen["inside"]
	var ext_cell: Vector2i = chosen["ext"]
	var apron_cells := _trace_to_target(ext_cell, target_cell, apron_parent)
	var pts: Array[Vector3] = _room_waypoints(grid, origin, origin_cell, inside_cell, room_parent)
	var ext_pt := grid.cell_to_world(ext_cell)
	ext_pt.y = origin.y
	var apron_pts := _build_apron_points(grid, ext_pt, target, apron_cells, true)
	pts.append_array(apron_pts)
	return pts


static func _room_waypoints(
	grid: BuildGrid,
	origin: Vector3,
	origin_cell: Vector2i,
	inside_cell: Vector2i,
	room_parent: Dictionary,
) -> Array[Vector3]:
	if inside_cell == origin_cell:
		return [origin]
	var rev: Array[Vector2i] = []
	var walk := inside_cell
	while walk != origin_cell:
		rev.append(walk)
		walk = room_parent[walk]
	rev.append(origin_cell)
	rev.reverse()
	var raw: Array[Vector3] = [origin]
	for i in range(1, rev.size()):
		var w := grid.cell_to_world(rev[i])
		w.y = origin.y
		raw.append(w)
	var smoothed: Array[Vector3] = [raw[0]]
	var idx := 0
	while idx < raw.size() - 1:
		var furthest := idx + 1
		for cand in range(raw.size() - 1, idx, -1):
			if not segment_hits_wall(grid, raw[idx], raw[cand], true):
				furthest = cand
				break
		smoothed.append(raw[furthest])
		idx = furthest
	return smoothed


static func _escape_to_apron(
	grid: BuildGrid, bounds: Rect2i, origin_cell: Vector2i, dist_from_target: Dictionary
) -> Array[Vector2i]:
	var cost := {origin_cell: 0}
	var parent := {}
	var frontier: Array[Vector2i] = [origin_cell]
	var found := Vector2i(-1, -1)
	while not frontier.is_empty():
		var best_idx := 0
		var best_cost: int = cost[frontier[0]]
		for i in range(1, frontier.size()):
			var c: int = cost[frontier[i]]
			if c < best_cost:
				best_cost = c
				best_idx = i
		var cur: Vector2i = frontier[best_idx]
		frontier.remove_at(best_idx)
		if dist_from_target.has(cur):
			found = cur
			break
		var cur_cost: int = cost[cur]
		for step in BuildGrid.SIDE_STEP:
			var nxt: Vector2i = cur + step
			if not bounds.has_point(nxt):
				continue
			var step_cost := 1000 if _edge_walled(grid, cur, step, true) else 1
			var cand_cost := cur_cost + step_cost
			if cand_cost < int(cost.get(nxt, 1 << 29)):
				cost[nxt] = cand_cost
				parent[nxt] = cur
				frontier.append(nxt)
	if found == Vector2i(-1, -1):
		return []
	var rev: Array[Vector2i] = []
	var walk := found
	while walk != origin_cell:
		rev.append(walk)
		walk = parent[walk]
	rev.append(origin_cell)
	rev.reverse()
	return rev


static func _build_apron_points(
	grid: BuildGrid, start_world: Vector3, target: Vector3, cells: Array[Vector2i], keep_start: bool
) -> Array[Vector3]:
	var raw: Array[Vector3] = [start_world]
	for i in range(1, cells.size()):
		var w := grid.cell_to_world(cells[i])
		w.y = start_world.y
		raw.append(w)
	if Vector2(raw[raw.size() - 1].x - target.x, raw[raw.size() - 1].z - target.z).length() > 0.05:
		raw.append(target)
	var smoothed: Array[Vector3] = [raw[0]]
	var idx := 0
	while idx < raw.size() - 1:
		var furthest := idx + 1
		for cand in range(raw.size() - 1, idx, -1):
			if _apron_segment_clear(grid, raw[idx], raw[cand]):
				furthest = cand
				break
		smoothed.append(raw[furthest])
		idx = furthest
	if keep_start or smoothed.size() >= 2:
		return smoothed
	return [start_world, target]


static func _apron_segment_clear(grid: BuildGrid, a: Vector3, b: Vector3) -> bool:
	if segment_hits_wall(grid, a, b, false):
		return false
	var flat := Vector2(b.x - a.x, b.z - a.z)
	if flat.length_squared() <= 0.01:
		return true
	var perp := Vector2(-flat.y, flat.x).normalized() * 0.3
	var offset := Vector3(perp.x, 0.0, perp.y)
	return (
		not segment_hits_wall(grid, a + offset, b + offset, false)
		and not segment_hits_wall(grid, a - offset, b - offset, false)
	)


static func _sample_path(pts: Array[Vector3], t: float, fallback_yaw: float) -> Dictionary:
	var total := route_length(pts)
	if total <= 0.001:
		return {"pos": pts[0], "yaw": fallback_yaw}
	var want := clampf(t, 0.0, 1.0) * total
	var covered := 0.0
	for i in range(1, pts.size()):
		var a := pts[i - 1]
		var b := pts[i]
		var flat := Vector2(b.x - a.x, b.z - a.z)
		var seg := flat.length()
		if seg <= 0.0001:
			continue
		if covered + seg >= want or i == pts.size() - 1:
			var local_t := clampf((want - covered) / seg, 0.0, 1.0)
			return {"pos": a.lerp(b, local_t), "yaw": atan2(flat.x, flat.y)}
		covered += seg
	return {"pos": pts[pts.size() - 1], "yaw": fallback_yaw}


static func _blend_yaw(from_yaw: float, travel_yaw: float, to_yaw: float, t: float) -> float:
	if t < 0.15:
		return lerp_angle(from_yaw, travel_yaw, t / 0.15)
	if t > 0.85:
		return lerp_angle(travel_yaw, to_yaw, (t - 0.85) / 0.15)
	return travel_yaw
