class_name CorridorLane
extends RefCounted
## Purely visual wall-clamped right-hand corridor lane offset for walking
## passengers (decision passenger-walking-separation-wall-clamped-right-hand-
## corrido). Walkers moving along indoor corridor paths shift slightly to
## their right so opposite-direction walkers pass shoulder-to-shoulder instead
## of phasing through each other, strictly clamped against walls and obstacles
## and faded cleanly to zero at endpoints, turns, doorways, queues, stations,
## seats, scanners, and stalls. Never mutates sim state.

const LANE_OFFSET_M := 0.24
const CLEARANCE_M := 0.50
const TURN_BLEND_M := 2.4
const ENDPOINT_FADE_M := 2.4
const ACTIVITY_DELAY_M := 2.0
const DOOR_EASE_M := DoorSteer.EASE_M + ENDPOINT_FADE_M
const MAX_SLOPE := 0.11
const TAPER_STEP_M := 0.1
const TAPER_STEPS := 22
const MIN_PATH_MM := 2000

const WALK_STAGES: Array[Passenger.Stage] = [
	Passenger.Stage.TO_CHECKIN,
	Passenger.Stage.TO_SECURITY,
	Passenger.Stage.TO_GATE,
	Passenger.Stage.TO_EXIT,
]


## Desired right-hand corridor lateral offset in world space (x, 0, z) for
## `p` in `sim`, or Vector3.ZERO when standing, stationary, near a door/endpoint,
## or boxed in on the right.
static func target_offset(sim: PassengerSim, p: Passenger) -> Vector3:
	if _excluded(sim, p):
		return Vector3.ZERO
	var end_weight := _endpoint_weight(p)
	if end_weight <= 0.001:
		return Vector3.ZERO
	return _lateral_offset(sim.grid, p, end_weight)


static func _excluded(sim: PassengerSim, p: Passenger) -> bool:
	if sim == null or sim.grid == null or p == null:
		return true
	if not WALK_STAGES.has(p.stage) or not p.is_moving() or p.path.size() < 2:
		return true
	if p.collect_tick != 0 and sim.tick < p.collect_tick:
		return true
	return sim.files.waiters.ids().has(p.id)


static func _endpoint_weight(p: Passenger) -> float:
	var walked_mm := p.seg_mm
	for i in p.path_index:
		walked_mm += Passenger.segment_mm(p.path[i], p.path[i + 1])
	var left_mm := p.remaining_mm()
	if walked_mm + left_mm < MIN_PATH_MM:
		return 0.0
	var start_delay_m := (
		ACTIVITY_DELAY_M
		if p.shop_cooldown > 0 and p.shop_cooldown == p.stage_tick + ShopSim.BROWSE_COOLDOWN_TICKS
		else 0.0
	)
	return (
		smoothstep(start_delay_m, start_delay_m + ENDPOINT_FADE_M, walked_mm / 1000.0)
		* smoothstep(0.0, ENDPOINT_FADE_M, left_mm / 1000.0)
	)


static func _lateral_offset(
	grid: BuildGrid, p: Passenger, end_weight: float, door_weight := -1.0
) -> Vector3:
	var a := p.path[p.path_index]
	var b := p.path[p.path_index + 1]
	var dir := _seg_dir(a, b)
	var turn_scale := _corner_weight(p, a, b, dir)
	if turn_scale <= 0.001:
		return Vector3.ZERO
	var right := Vector2(-dir.y, dir.x)
	var pos_local := p.grid_position()
	var d_weight := _door_weight(grid, pos_local) if door_weight < 0.0 else door_weight
	var desired := LANE_OFFSET_M * minf(end_weight, minf(d_weight, turn_scale))
	if desired <= 0.001:
		return Vector3.ZERO
	var dist := _tapered_clamp(grid, pos_local, dir, right, desired)
	if dist <= 0.001:
		return Vector3.ZERO
	return Vector3(right.x * dist, 0.0, right.y * dist)


static func _corner_weight(p: Passenger, a: Vector2i, b: Vector2i, cur: Vector2) -> float:
	var weight := 1.0
	var seg_len := Passenger.segment_mm(a, b) / 1000.0
	var dist_back := p.seg_mm / 1000.0
	for i in range(p.path_index - 1, -1, -1):
		if dist_back >= TURN_BLEND_M:
			break
		if _seg_dir(p.path[i], p.path[i + 1]).dot(cur) < 0.99:
			weight = minf(weight, smoothstep(0.0, TURN_BLEND_M, dist_back))
			break
		dist_back += Passenger.segment_mm(p.path[i], p.path[i + 1]) / 1000.0
	var dist_fwd := seg_len - p.seg_mm / 1000.0
	for i in range(p.path_index + 1, p.path.size() - 1):
		if dist_fwd >= TURN_BLEND_M:
			break
		if _seg_dir(p.path[i], p.path[i + 1]).dot(cur) < 0.99:
			weight = minf(weight, smoothstep(0.0, TURN_BLEND_M, dist_fwd))
			break
		dist_fwd += Passenger.segment_mm(p.path[i], p.path[i + 1]) / 1000.0
	return weight


## Clamps `desired` strictly at `pos_local` and caps spatial slope both ahead
## and behind along `walk_dir` at MAX_SLOPE so approaching or passing any
## obstacle or wall corner stays within a walking step per tick.
static func _tapered_clamp(
	grid: BuildGrid, pos_local: Vector2, walk_dir: Vector2, offset_dir: Vector2, desired: float
) -> float:
	var under := Vector2i(floori(pos_local.x), floori(pos_local.y))
	var limit := _clamp_distance(pos_local, offset_dir, desired, _obstacles_near(grid, under))
	if walk_dir.length_squared() < 1e-6:
		return limit
	for k in range(-TAPER_STEPS, TAPER_STEPS + 1):
		if k == 0:
			continue
		var s := k * TAPER_STEP_M
		if absf(s) * MAX_SLOPE >= limit:
			continue
		var sample := pos_local + walk_dir * s
		var s_cell := Vector2i(floori(sample.x), floori(sample.y))
		var d_sample := _clamp_distance(sample, offset_dir, desired, _obstacles_near(grid, s_cell))
		limit = minf(limit, d_sample + absf(s) * MAX_SLOPE)
	return limit


static func _seg_dir(a: Vector2i, b: Vector2i) -> Vector2:
	return Vector2(b - a).normalized()


## Weight in [0, 1] fading smoothly to 0 near any entrance/exit door or
## interior door wall so DoorSteer and doorway frames are never fought.
static func _door_weight(grid: BuildGrid, pos_local: Vector2) -> float:
	var weight := 1.0
	var here := grid.origin + Vector3(pos_local.x, 0.0, pos_local.y)
	var under := Vector2i(floori(pos_local.x), floori(pos_local.y))
	var reach := ceili(maxf(DOOR_EASE_M, DoorSteer.LATERAL_M + ENDPOINT_FADE_M))
	var seen := {}
	for dy in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var cell := under + Vector2i(dx, dy)
			if not grid.in_bounds(cell):
				continue
			var id := grid.object_at(cell)
			if id != 0 and not seen.has(id):
				seen[id] = true
				var record := grid.get_object(id)
				if BuildCatalog.is_door(record["def"]):
					var step := DoorPlacement.back_step(record["facing"])
					var out := Vector2(step)
					var plane := (
						grid.cell_to_world(record["anchor"]) + Vector3(step.x, 0.0, step.y) * 0.5
					)
					var rel := Vector2(here.x - plane.x, here.z - plane.z)
					weight = minf(
						weight, _edge_door_weight(rel.dot(out), rel.dot(Vector2(out.y, -out.x)))
					)
			if grid.wall_kind(cell, BuildGrid.Side.NORTH) == BuildGrid.WallKind.DOOR:
				var n_w := _edge_door_weight(pos_local.y - cell.y, pos_local.x - (cell.x + 0.5))
				weight = minf(weight, n_w)
			if grid.wall_kind(cell, BuildGrid.Side.WEST) == BuildGrid.WallKind.DOOR:
				var w_w := _edge_door_weight(pos_local.x - cell.x, pos_local.y - (cell.y + 0.5))
				weight = minf(weight, w_w)
	return weight


static func _edge_door_weight(d_plane: float, d_axis: float) -> float:
	var plane_w := smoothstep(DoorSteer.EASE_M, DOOR_EASE_M, absf(d_plane))
	var axis_w := smoothstep(
		DoorSteer.LATERAL_M, DoorSteer.LATERAL_M + ENDPOINT_FADE_M, absf(d_axis)
	)
	return maxf(plane_w, axis_w)


## Grid-local obstacle boxes (solid/non-passenger cells, object footprints, and
## wall edges) within the 3x3 neighbourhood around `under`.
static func _obstacles_near(grid: BuildGrid, under: Vector2i) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var cell := under + Vector2i(dx, dy)
			if not grid.is_passenger_cell(cell) or grid.object_at(cell) != 0:
				out.append(Rect2(Vector2(cell), Vector2.ONE))
			if grid.wall_kind(cell, BuildGrid.Side.NORTH) != BuildGrid.WallKind.NONE:
				out.append(Rect2(Vector2(cell), Vector2(1.0, 0.0)))
			if grid.wall_kind(cell, BuildGrid.Side.WEST) != BuildGrid.WallKind.NONE:
				out.append(Rect2(Vector2(cell), Vector2(0.0, 1.0)))
			if dy == 1 and grid.wall_kind(cell, BuildGrid.Side.SOUTH) != BuildGrid.WallKind.NONE:
				out.append(Rect2(Vector2(cell.x, cell.y + 1), Vector2(1.0, 0.0)))
			if dx == 1 and grid.wall_kind(cell, BuildGrid.Side.EAST) != BuildGrid.WallKind.NONE:
				out.append(Rect2(Vector2(cell.x + 1, cell.y), Vector2(0.0, 1.0)))
	return out


static func _clamp_distance(
	pos: Vector2, right: Vector2, desired: float, obstacles: Array[Rect2]
) -> float:
	if _is_clear(pos, pos + right * desired, obstacles):
		return desired
	var lo := 0.0
	var hi := desired
	for i in 10:
		var mid := (lo + hi) * 0.5
		if _is_clear(pos, pos + right * mid, obstacles):
			lo = mid
		else:
			hi = mid
	return lo


static func _is_clear(origin: Vector2, candidate: Vector2, obstacles: Array[Rect2]) -> bool:
	for rect in obstacles:
		var limit := minf(CLEARANCE_M, _dist_to_rect(origin, rect))
		if _dist_to_rect(candidate, rect) < limit - 1e-4:
			return false
	return true


static func _dist_to_rect(pt: Vector2, rect: Rect2) -> float:
	var cx := clampf(pt.x, rect.position.x, rect.end.x)
	var cy := clampf(pt.y, rect.position.y, rect.end.y)
	return pt.distance_to(Vector2(cx, cy))
